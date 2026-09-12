import 'dart:convert';

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/character_archive.dart';
import '../models/character_user_profile.dart';
import '../models/group_chat.dart';
import '../models/group_message.dart';
import '../models/group_user_profile.dart';
import '../context_builder/context_build_result.dart';
import '../prompt_composer/prompt_composer.dart';
import '../prompt_composer/prompt_context.dart';
import 'character_archive_storage_service.dart';
import 'character_profile_storage_service.dart';
import 'character_registry_service.dart';
import 'character_settings_storage_service.dart';
import 'character_user_profile_storage_service.dart';
import 'context_builder.dart';
import '../conversation/conversation_engine.dart';
import '../conversation/chat_reply_sanitizer.dart';
import 'group_user_profile_storage_service.dart';
import 'group_participation_service.dart';
import 'group_character_voice.dart';
import 'group_memory_service.dart';
import 'group_reply_target.dart';
import 'memory2_chat_context_builder.dart';
import 'memory2_retriever.dart';
import 'prompt_builder.dart';
import 'reborn_group_profile_service.dart';

class GroupReplyStep {
  const GroupReplyStep({
    required this.characterId,
    this.replyCount = 1,
    this.intent = '',
    this.reasons = const [],
    this.plannerTargetId,
  });

  final String characterId;
  final int replyCount;
  final String intent;

  /// planner 同一次调用里可选给出的回复目标（user / 角色ID / group）。
  /// 仅存在于内存，不写入 storage；最终目标由 GroupReplyTargetResolver 决定。
  final String? plannerTargetId;

  /// 轻量可解释标签（mentioned / topic_relevant / cooldown …）。
  /// 仅存在于内存，不写入 storage。
  final List<String> reasons;
}

class GroupReplyPlan {
  const GroupReplyPlan({required this.steps, this.participation = const []});

  final List<GroupReplyStep> steps;

  /// 本地预筛结果，供测试与调试观察，不进入 storage。
  final List<GroupParticipation> participation;
}

class GroupGeneratedReply {
  const GroupGeneratedReply({
    required this.characterId,
    required this.messages,
  });

  final String characterId;
  final List<String> messages;
}

/// 群聊第二批核心：先决定谁说，再让角色按顺序逐个生成。
class GroupConversationCoordinator {
  GroupConversationCoordinator({ModelHub? modelHub})
    : _modelHub = modelHub ?? ModelHub();

  final ModelHub _modelHub;
  final GroupParticipationService _participation =
      const GroupParticipationService();
  final GroupReplyTargetResolver _replyTargets =
      const GroupReplyTargetResolver();

  /// 本地预筛最多送几个候选给 planner（不改变 planner 的硬上限）。
  static const int _maxCandidates = 4;

  Future<GroupReplyPlan> createPlan({
    required GroupChat group,
    required List<GroupMessage> messages,
  }) async {
    final registry = await CharacterRegistryService().loadCharacters();
    final members = registry
        .where((item) => group.memberCharacterIds.contains(item.id))
        .toList(growable: false);
    if (members.isEmpty) return const GroupReplyPlan(steps: []);

    final latest = messages.isEmpty ? null : messages.last;
    // 本轮只能由用户发言触发：角色消息不会自动开启又一轮互聊。
    if (latest == null || !_replyTargets.isTurnTrigger(latest)) {
      return const GroupReplyPlan(steps: []);
    }

    // 本地 Participation 预筛：先定候选，再交给 planner 决定最终发言者。
    final participation = _participation.evaluate(
      group: group,
      members: members,
      messages: messages,
    );
    final candidates = participation
        .where((item) => item.allowed)
        .take(_maxCandidates)
        .toList(growable: false);
    if (candidates.isEmpty) {
      // 没有合适候选时允许本轮无人追加回复。
      return GroupReplyPlan(steps: const [], participation: participation);
    }
    final candidateIds = candidates.map((item) => item.characterId).toSet();
    final candidateText = candidates
        .map((item) {
          final character = members.firstWhere(
            (member) => member.id == item.characterId,
          );
          final tags = item.reasons.isEmpty
              ? ''
              : '｜${item.reasons.join(',')}';
          return '- ${character.id}｜${character.displayName}｜'
              '${_shortPersona(character)}$tags';
        })
        .join('\n');

    try {
      final provider = await _modelHub.chatProvider();
      final recent = _recentTranscript(messages, registry, limit: 14);
      final rebornPlanner = RebornGroupProfileService.plannerContext(members);
      final mentioned = latest.mentionedMemberIds;
      final mentionedText = mentioned.isEmpty
          ? '无明确@对象'
          : mentioned
                .map((id) {
                  if (id == 'user') return '用户';
                  for (final item in members) {
                    if (item.id == id) return '${item.displayName}(${item.id})';
                  }
                  return id;
                })
                .join('、');
      final repliedMessage = _findMessage(messages, latest.replyToMessageId);
      final replyText = repliedMessage == null
          ? '无引用消息'
          : '${_senderName(repliedMessage, registry)}：${repliedMessage.content}';
      final prompt =
          '''
你是 PeiLink 群聊调度器，只负责安排发言，不负责代替角色说话。

【群聊原则】
1. 默认只选1至2人，绝不能因为群里人多就全员回复。
2. 内容明显指向某个角色时优先选该角色；存在明确@对象时，被@角色必须优先进入第一步，除非@全体。
3. 可以安排后一个角色接前一个角色的话，但总消息数最多6条。
4. 最多4名角色参与；同一角色最多连续3条。
5. 简单问候通常1人即可；明确问全体时可2至4人。
6. 允许0人回复，但用户刚主动发言时通常至少1人回应。
7. 不要固定按成员顺序轮流发言。
8. 禁止争风吃醋、集体恋爱脑、恶意攻击。
9. 只能从【本地候选】中选择；候选之外的角色本轮不要选择。
10. 普通消息倾向1至2人，只有明确的多人话题才考虑3人。
11. 候选里已经标记 recently_active / cooldown / already_answered 的角色，
    除非被@或确实需要补充，否则优先不选。

【本地候选（按参与优先级排序）】
$candidateText

$rebornPlanner

【本轮明确@对象】
$mentionedText

【本轮引用消息】
$replyText

【最近群聊】
$recent

请只输出JSON：
{"steps":[{"characterId":"角色ID","replyCount":1,"intent":"这一位为什么参与以及接什么话","targetSpeakerId":"可选：user / 其他角色ID / group"}]}
replyCount只能是1到3。steps最多4项，总replyCount最多6。
targetSpeakerId 是可选项：只在这一位明显是在接某人的话时给出，不确定就省略。
''';
      final raw = await provider.complete(
        messages: [
          {'role': 'system', 'content': prompt},
        ],
        temperature: 0.35,
        maxTokens: 420,
        topP: 0.75,
      );
      // 只接受本地候选内的选择：planner 不能在候选之外点名。
      final parsed = _parsePlan(
        raw,
        candidateIds,
        reasonsById: {
          for (final item in participation) item.characterId: item.reasons,
        },
      );
      if (parsed.steps.isNotEmpty) {
        return _prioritizeMentioned(
          GroupReplyPlan(steps: parsed.steps, participation: participation),
          latest,
          candidateIds,
          participation: participation,
        );
      }
      // Planner 明确给出 0 人时尊重沉默；越界或解析失败才走本地兜底。
      if (RegExp(r'"steps"\s*:\s*\[\s*\]').hasMatch(raw)) {
        return GroupReplyPlan(steps: const [], participation: participation);
      }
    } catch (_) {
      // 使用最相关单角色兜底，不让模型失败变成全员出场。
    }

    final fallback = candidates.first;
    return GroupReplyPlan(
      steps: [
        GroupReplyStep(
          characterId: fallback.characterId,
          replyCount: 1,
          intent: '回应用户最新消息',
          reasons: fallback.reasons,
        ),
      ],
      participation: participation,
    );
  }

  Future<GroupGeneratedReply?> generateStep({
    required GroupChat group,
    required GroupReplyStep step,
    required List<GroupMessage> messages,
  }) async {
    final registry = await CharacterRegistryService().loadCharacters();
    AiCharacter? character;
    for (final item in registry) {
      if (item.id == step.characterId) {
        character = item;
        break;
      }
    }
    if (character == null) return null;
    final selectedCharacter = character;

    try {
      final settings = await CharacterSettingsStorageService(
        characterId: selectedCharacter.id,
      ).loadSettings();
      final provider = await _modelHub.chatProvider();
      final transcript = _recentTranscript(messages, registry, limit: 18);
      final latest = _latestUserMessage(messages);
      final quoted = _findMessage(messages, latest?.replyToMessageId);
      final quotedContext = quoted == null
          ? '本轮没有引用消息。'
          : '本轮用户正在引用回复${_senderName(quoted, registry)}的消息：${quoted.content}';
      final mentionContext = latest?.mentionedMemberIds.isEmpty ?? true
          ? '本轮没有明确@对象。'
          : '本轮明确@了：${latest!.mentionedMemberIds.map((id) => id == 'user' ? '用户' : registry.where((item) => item.id == id).map((item) => item.displayName).join()).where((name) => name.isNotEmpty).join('、')}。';
      final groupMembers = registry
          .where((item) => group.memberCharacterIds.contains(item.id))
          .toList(growable: false);
      final otherMembers = registry
          .where(
            (item) =>
                group.memberCharacterIds.contains(item.id) &&
                item.id != character!.id,
          )
          .map((item) => '${item.id}=${item.displayName}')
          .join('、');

      final relationshipContext = RebornGroupProfileService.relationshipContext(
        groupMembers,
      );
      final socialProtocol = RebornGroupProfileService.socialProtocol(
        groupMembers,
      );
      final esportsRules = RebornGroupProfileService.esportsRules(groupMembers);
      final conversationEngine = ConversationEngine.build(
        messages: _conversationMessages(messages, selectedCharacter.id, registry: registry),
        conversationMode: 'basic',
      );

      // —— 身份 / 人格 / 记忆补齐（只读，仅当前发言角色）——
      final characterProfile = await CharacterProfileStorageService(
        characterId: selectedCharacter.id,
      ).load(character: selectedCharacter, legacySettings: settings);
      CharacterArchive? characterArchive;
      try {
        characterArchive = await CharacterArchiveStorageService(
          characterId: selectedCharacter.id,
        ).load();
      } catch (_) {
        characterArchive = null;
      }
      CharacterUserProfile characterUserProfile;
      try {
        characterUserProfile = await CharacterUserProfileStorageService(
          characterId: selectedCharacter.id,
        ).load();
      } catch (_) {
        characterUserProfile = CharacterUserProfile(
          characterId: selectedCharacter.id,
        );
      }
      GroupUserProfile groupUserProfile = GroupUserProfile(
        groupId: group.id,
      );
      try {
        groupUserProfile = await GroupUserProfileStorageService(
          groupId: group.id,
        ).loadResolved();
      } catch (_) {
        // 旧群无身份文件时保持空值，由上层 fallback 处理。
      }

      // Memory 2.0 只读检索：查询基于用户当前消息 + 最近群聊上下文。
      var memoryPrompt = '';
      try {
        final retriever = Memory2Retriever(characterId: selectedCharacter.id);
        final retrieval = await retriever.retrieve(
          currentMessage: latest?.content ?? '',
          recentMessages: _conversationMessages(
            messages,
            selectedCharacter.id,
            registry: registry,
          ),
          now: DateTime.now(),
        );
        memoryPrompt = Memory2ChatContextBuilder.build(
          retrieval: retrieval,
          characterUserProfile: characterUserProfile,
        );
      } catch (_) {
        // 记忆是可选上下文，失败不影响群聊回复。
        memoryPrompt = '';
      }

      // G3.4 群聊共同经历：与本角色的私聊 Memory 分开检索、分开标注。
      var groupMemoryPrompt = '';
      try {
        final groupMemory = await GroupMemoryService(
          groupId: group.id,
          groupName: group.name,
        ).retrieve(
          currentMessage: latest?.content ?? '',
          participantIds: group.memberCharacterIds,
          now: DateTime.now(),
        );
        groupMemoryPrompt = groupMemory.contextText;
      } catch (_) {
        // 群聊记忆同样是可选上下文。
        groupMemoryPrompt = '';
      }

      // G3.5 本轮回复目标：纯本地推导（mention / 上一位发言者 / participation
      // reason / planner 可选提示），不新增模型调用，也不写入 storage。
      final registryNames = <String, String>{
        for (final item in registry) item.id: item.displayName,
      };
      final replyTarget = _replyTargets.resolve(
        speakerCharacterId: selectedCharacter.id,
        speakerName: selectedCharacter.displayName,
        messages: messages,
        participationReasons: step.reasons,
        plannerTargetId: step.plannerTargetId,
      );
      final replyTargetContext = _replyTargetContext(
        target: replyTarget,
        messages: messages,
        latestUser: latest,
        names: registryNames,
      );

      final groupIdentityContext = _groupIdentityContext(
        groupUserProfile: groupUserProfile,
        characterUserProfile: characterUserProfile,
        relation: settings.relation.trim().isEmpty
            ? selectedCharacter.relationship.trim()
            : settings.relation.trim(),
      );

      // —— G3.3 Character Voice：只读取当前角色自己的表达数据 ——
      // Reborn 专项口径只作为「角色完全没有自己的表达数据」时的兜底，
      // 不再默认覆盖角色自己的 speakingStyle / Archive 表达字段。
      final characterVoice = GroupCharacterVoice.build(
        character: selectedCharacter,
        profile: characterProfile,
        archive: characterArchive,
        settings: settings,
      );
      final rebornVoiceFallback = characterVoice.isEmpty
          ? RebornGroupProfileService.speechProfile(selectedCharacter)
          : '';
      final styleExamples = PromptBuilder.buildStyleExamplesPrompt(
        settings,
        maxExamples: 3,
      );

      final system = ContextBuilder.build(
        task: ContextTask.groupChat,
        settings: settings,
        characterProfile: characterProfile,
        characterArchive: characterArchive,
        relevantMemory: memoryPrompt,
        styleExamples: styleExamples,
        taskRules:
            '''
你正在真实的多人群聊“${group.name}”中发言。
你只能扮演${selectedCharacter.displayName}，不能替其他成员或用户说话。
$quotedContext
$mentionContext
$replyTargetContext
$groupMemoryPrompt
群聊共同经历是群里公开发生过的事件，可以自然接话，但不能当成你和用户的私聊记忆，也不要替其他成员宣称他们私下知道的事。
如果需要点名某人，请使用群内真实名称写成“@名字”，不要虚构不存在的成员。
先看清最近消息，只回应【本轮回复目标】指的那个人或全群，不要对每个人各说一遍。
群聊接话允许非常短（例如“确实。”“我不同意。”“那倒也是。”），回复长度只是你平时的说话倾向，不是硬性要求。
回复要像真实的手机群聊：先自然接住别人的话，长度、语气和用词以本角色自己的表达习惯为准（多数情况不需要长篇，但不要为了显得简短就丢掉角色个性）。禁止用（）、()、[]、【】或 *动作* 输出独立动作、心理或舞台标签，也不写旁白、分析或角色名标签。状态或行为只能自然融进聊天正文。
不要重复别人已经说过的话，不要做圆桌式总结，不要强行把话题绕回恋爱。
禁止争风吃醋、威胁用户、要求用户只能选择你。
普通聊天不要长篇说教；比赛、训练和专业话题才可以明显认真。
本次最多输出${step.replyCount}条消息。若输出多条，用换行分隔，每行是一条完整气泡。
不要故意把一句完整的话切碎，也不要超过3行。
只输出消息正文。

【群聊规则只负责场景，不塑造人格】
以上规则只规定多人聊天的场景与边界，不统一角色的语气、句长、用词、标点或 emoji 习惯。
每个成员都应该像不同的人聊天，不要套用同一种聊天机器人腔。

$characterVoice
$rebornVoiceFallback
$esportsRules
''',
        dynamicState:
            '本轮参与原因：${step.intent}\n'
            '本轮回复目标：${replyTarget.describe(registryNames)}\n'
            '群内其他成员：$otherMembers',
        recentConversation: transcript,
        relationshipContext: relationshipContext,
        socialProtocol: socialProtocol,
        groupIdentityContext: groupIdentityContext,
      );
      final modelContext = PromptComposer(
        baseContext: ContextBuildResult(
          messages: [
            {'role': 'system', 'content': system},
          ],
          systemPrompt: system,
        ),
      ).addContext(PromptContext.chatFlow(conversationEngine.prompt)).compose();
      final raw = await provider.complete(
        messages: modelContext.messages,
        temperature: settings.temperature.clamp(0.62, 0.86).toDouble(),
        maxTokens: 260,
        topP: 0.88,
      );
      final lines = _cleanLines(raw, step.replyCount);
      if (lines.isEmpty) return null;
      return GroupGeneratedReply(
        characterId: selectedCharacter.id,
        messages: lines,
      );
    } catch (_) {
      return null;
    }
  }

  GroupReplyPlan _prioritizeMentioned(
    GroupReplyPlan plan,
    GroupMessage latest,
    Set<String> allowedIds,
    {
    List<GroupParticipation> participation = const [],
  }
  ) {
    final isMentioningAll =
        latest.content.contains('@全体成员') || latest.content.contains('@所有人');
    if (isMentioningAll || latest.mentionedMemberIds.isEmpty) return plan;

    final targetIds = latest.mentionedMemberIds
        .where(allowedIds.contains)
        .take(4)
        .toList(growable: false);
    if (targetIds.isEmpty) return plan;

    final byId = <String, GroupReplyStep>{
      for (final step in plan.steps) step.characterId: step,
    };
    final ordered = <GroupReplyStep>[];
    var total = 0;
    for (final id in targetIds) {
      final step =
          byId.remove(id) ??
        GroupReplyStep(
            characterId: id,
            replyCount: 1,
            intent: '用户明确@了该角色，优先直接回应',
            reasons: const ['mentioned'],
          );
      if (total + step.replyCount > 6) break;
      ordered.add(step);
      total += step.replyCount;
    }
    for (final step in plan.steps) {
      if (!byId.containsKey(step.characterId) || ordered.length >= 4) continue;
      if (total + step.replyCount > 6) break;
      ordered.add(step);
      total += step.replyCount;
      byId.remove(step.characterId);
    }
    return GroupReplyPlan(steps: ordered, participation: participation);
  }

  GroupMessage? _latestUserMessage(List<GroupMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].senderType == GroupSenderType.user) {
        return messages[index];
      }
    }
    return null;
  }

  GroupReplyPlan _parsePlan(
    String raw,
    Set<String> allowedIds, {
    Map<String, List<String>> reasonsById = const {},
  }) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return const GroupReplyPlan(steps: []);
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! Map || decoded['steps'] is! List) {
        return const GroupReplyPlan(steps: []);
      }
      final steps = <GroupReplyStep>[];
      var total = 0;
      for (final item in decoded['steps'] as List) {
        if (item is! Map) continue;
        final id = item['characterId']?.toString() ?? '';
        if (!allowedIds.contains(id)) continue;
        var count = int.tryParse(item['replyCount']?.toString() ?? '') ?? 1;
        count = count.clamp(1, 3).toInt();
        if (total + count > 6 || steps.length >= 4) break;
        steps.add(
          GroupReplyStep(
            characterId: id,
            replyCount: count,
            intent: item['intent']?.toString() ?? '',
            reasons: reasonsById[id] ?? const [],
            plannerTargetId: item['targetSpeakerId']?.toString(),
          ),
        );
        total += count;
      }
      return GroupReplyPlan(steps: steps);
    } catch (_) {
      return const GroupReplyPlan(steps: []);
    }
  }

  String _recentTranscript(
    List<GroupMessage> messages,
    List<AiCharacter> registry, {
    required int limit,
  }) {
    final names = <String, String>{
      for (final item in registry) item.id: item.displayName,
    };
    final selected = messages.length <= limit
        ? messages
        : messages.sublist(messages.length - limit);
    return selected
        .map((message) {
          final mention = message.mentionedMemberIds.isEmpty
              ? ''
              : ' [@${message.mentionedMemberIds.map((id) => id == 'user' ? '用户' : names[id] ?? id).join('、')}]';
          final reply = message.replyToMessageId == null
              ? ''
              : ' [引用:${message.replyToMessageId}]';
          return '${speakerLabel(message, names)}：${message.content}$mention$reply';
        })
        .join('\n');
  }

  /// G3.5 回复目标上下文：告诉当前角色“你正在回应谁”。
  String _replyTargetContext({
    required GroupReplyTarget target,
    required List<GroupMessage> messages,
    required GroupMessage? latestUser,
    required Map<String, String> names,
  }) {
    final targetLabel = target.describe(names);
    final quoted = _quotedTargetLine(
      _lastMessageFromTarget(messages, target, latestUser),
    );
    switch (target.type) {
      case GroupReplyTargetType.character:
        return '【本轮回复目标】$targetLabel\n'
            '【对方最近一句】$quoted\n'
            '你正在接$targetLabel的话：直接回应他/她刚才说的，不需要重新完整回答用户最初的问题。'
            '可以简短回应、反驳、补充、吐槽或认可，不需要总结整个对话。';
      case GroupReplyTargetType.group:
        return '【本轮回复目标】全群（开放发言）\n'
            '【可接的最近一句】$quoted\n'
            '你可以对全群补充自己的观点，不需要假装对某个人说；只说你自己想说的，不必回应每一个人。';
      case GroupReplyTargetType.user:
        return '【本轮回复目标】用户\n'
            '【用户最近一句】$quoted\n'
            '你正在回应用户：接着刚才的对话往下说，不要复述用户的原问题，也不要复述别人已经说过的话。';
    }
  }

  String _quotedTargetLine(GroupMessage? message) {
    final text = message?.content.trim() ?? '';
    if (text.isEmpty) return '（没有更多上下文）';
    return text.length <= 120 ? text : '${text.substring(0, 120)}…';
  }

  GroupMessage? _lastMessageFromTarget(
    List<GroupMessage> messages,
    GroupReplyTarget target,
    GroupMessage? latestUser,
  ) {
    if (target.isUser) return latestUser;
    if (target.isGroup) {
      for (var index = messages.length - 1; index >= 0; index--) {
        if (messages[index].senderType != GroupSenderType.system) {
          return messages[index];
        }
      }
      return null;
    }
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.senderType == GroupSenderType.character &&
          message.senderId == target.characterId) {
        return message;
      }
    }
    return null;
  }

  GroupMessage? _findMessage(List<GroupMessage> messages, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final message in messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  String _senderName(GroupMessage message, List<AiCharacter> registry) {
    if (message.senderType == GroupSenderType.user) return '用户';
    if (message.senderType == GroupSenderType.system) return '系统';
    for (final character in registry) {
      if (character.id == message.senderId) return character.displayName;
    }
    return '群成员';
  }

  String _shortPersona(AiCharacter character) {
    final raw = '${character.introduction}\n${character.persona}'.trim();
    if (raw.isEmpty) return '按其独立人设自然发言';
    return raw.length <= 120 ? raw : '${raw.substring(0, 120)}…';
  }

  List<String> _cleanLines(String raw, int maxCount) {
    final cleaned = ChatReplySanitizer.clean(raw)
        .replaceAll(RegExp(r'^```(?:json|text)?', multiLine: true), '')
        .replaceAll('```', '')
        .trim();
    if (cleaned.isEmpty) return const [];
    final lines = cleaned
        .split(RegExp(r'\n+'))
        .map(
          (line) => line
              .replaceFirst(RegExp(r'^[-•]\s*'), '')
              .replaceFirst(RegExp(r'^\d+[.、]\s*'), '')
              .replaceFirst(RegExp(r'^[^：:]{1,12}[：:]\s*'), '')
              .trim(),
        )
        .where((line) => line.isNotEmpty)
        .take(maxCount.clamp(1, 3).toInt())
        .toList();
    return lines;
  }

  List<ChatMessage> _conversationMessages(
    List<GroupMessage> messages,
    String speakingCharacterId, {
    List<AiCharacter> registry = const [],
  }
  ) {
    final names = <String, String>{
      for (final item in registry) item.id: item.displayName,
    };
    final selected = messages.length <= 18
        ? messages
        : messages.sublist(messages.length - 18);
    return selected
        .map(
          (message) {
            // API 只支持 user/assistant/system 三种 role，因此把真实发言者
            // 身份写进 content 标签，避免其他角色被误当成"用户说的话"。
            final isSelf = message.senderId == speakingCharacterId &&
                message.senderType == GroupSenderType.character;
            final role = message.senderType == GroupSenderType.system
                ? 'system'
                : isSelf
                ? 'assistant'
                : 'user';
            return ChatMessage(
              role: role,
              content: '${speakerLabel(message, names)}：${message.content}',
            );
          },
        )
        .toList(growable: false);
  }

  /// 稳定身份标签：user / character(senderId) / system，不依赖 displayName 反推。
  /// 公开为静态方法，便于定向测试确认 G3.1 speaker identity 不回退。
  static String speakerLabel(GroupMessage message, Map<String, String> names) {
    switch (message.senderType) {
      case GroupSenderType.user:
        return '用户';
      case GroupSenderType.system:
        return '系统';
      case GroupSenderType.character:
        final id = message.senderId.trim();
        final name = names[id]?.trim() ?? '';
        return name.isEmpty ? id : '$name($id)';
    }
  }

  /// 群聊身份层：群公开身份 + 当前角色私人视角 + 该角色与用户的关系。
  ///
  /// 三层同时存在、互不覆盖；未知关系保持中性，不推导竞争/敌对语义。
  String _groupIdentityContext({
    required GroupUserProfile groupUserProfile,
    required CharacterUserProfile characterUserProfile,
    required String relation,
  }) {
    final sections = <String>[];
    final groupName = groupUserProfile.displayName.trim();
    final groupSelf = groupUserProfile.selfDescription.trim();
    if (groupName.isNotEmpty || groupSelf.isNotEmpty) {
      sections.add(
        [
          '【本群公开身份｜群里所有人都能看到】',
          if (groupName.isNotEmpty) '群内昵称：$groupName',
          if (groupSelf.isNotEmpty) '群内身份说明：$groupSelf',
        ].join('\n'),
      );
    }

    final privateLines = <String>[
      if (characterUserProfile.userName.trim().isNotEmpty)
        '你对用户的称呼：${characterUserProfile.userName.trim()}',
      if (characterUserProfile.callName.trim().isNotEmpty)
        '你平时叫用户：${characterUserProfile.callName.trim()}',
      if (relation.isNotEmpty) '你与用户的关系：$relation',
      if (characterUserProfile.effectiveDescription.trim().isNotEmpty)
        '你私下知道的用户信息：${characterUserProfile.effectiveDescription.trim()}',
    ];
    if (privateLines.isNotEmpty) {
      sections.add(
        [
          '【你私人的用户认知｜只有你自己知道，其他群成员不知道】',
          ...privateLines,
          '群里其他角色对用户可能有完全不同的认知，只按你自己了解的来理解和称呼用户。',
        ].join('\n'),
      );
    }
    return sections.join('\n\n');
  }
}
