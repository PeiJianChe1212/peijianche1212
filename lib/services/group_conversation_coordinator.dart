import 'dart:convert';
import 'dart:math';

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/group_chat.dart';
import '../models/group_message.dart';
import '../context_builder/context_build_result.dart';
import '../prompt_composer/prompt_composer.dart';
import '../prompt_composer/prompt_context.dart';
import 'character_registry_service.dart';
import 'character_settings_storage_service.dart';
import 'context_builder.dart';
import '../conversation/conversation_engine.dart';
import '../conversation/chat_reply_sanitizer.dart';
import 'reborn_group_profile_service.dart';

class GroupReplyStep {
  const GroupReplyStep({
    required this.characterId,
    this.replyCount = 1,
    this.intent = '',
  });

  final String characterId;
  final int replyCount;
  final String intent;
}

class GroupReplyPlan {
  const GroupReplyPlan({required this.steps});

  final List<GroupReplyStep> steps;
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
  final Random _random = Random();

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
    if (latest == null || latest.senderType != GroupSenderType.user) {
      return const GroupReplyPlan(steps: []);
    }

    try {
      final provider = await _modelHub.chatProvider();
      final memberText = members
          .map(
            (item) => '- ${item.id}｜${item.displayName}｜${_shortPersona(item)}',
          )
          .join('\n');
      final recent = _recentTranscript(messages, registry, limit: 14);
      final rebornPlanner = RebornGroupProfileService.plannerContext(members);
      final mentioned = latest.mentionedMemberIds;
      final mentionedText = mentioned.isEmpty
          ? '无明确@对象'
          : mentioned
                .map((id) {
                  if (id == 'user') return '林念念';
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

【群成员】
$memberText

$rebornPlanner

【本轮明确@对象】
$mentionedText

【本轮引用消息】
$replyText

【最近群聊】
$recent

请只输出JSON：
{"steps":[{"characterId":"角色ID","replyCount":1,"intent":"这一位为什么参与以及接什么话"}]}
replyCount只能是1到3。steps最多4项，总replyCount最多6。
''';
      final raw = await provider.complete(
        messages: [
          {'role': 'system', 'content': prompt},
        ],
        temperature: 0.35,
        maxTokens: 420,
        topP: 0.75,
      );
      final parsed = _parsePlan(raw, members.map((e) => e.id).toSet());
      if (parsed.steps.isNotEmpty) {
        return _prioritizeMentioned(
          parsed,
          latest,
          members.map((item) => item.id).toSet(),
        );
      }
    } catch (_) {
      // 使用最相关单角色兜底，不让模型失败变成全员出场。
    }

    return GroupReplyPlan(
      steps: [
        GroupReplyStep(
          characterId: _fallbackCharacter(
            latest.content,
            members,
            mentionedIds: latest.mentionedMemberIds,
          ).id,
          replyCount: 1,
          intent: '回应用户最新消息',
        ),
      ],
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
          : '本轮明确@了：${latest!.mentionedMemberIds.map((id) => id == 'user' ? '林念念' : registry.where((item) => item.id == id).map((item) => item.displayName).join()).where((name) => name.isNotEmpty).join('、')}。';
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
      final speechProfile = RebornGroupProfileService.speechProfile(
        selectedCharacter,
      );
      final conversationEngine = ConversationEngine.build(
        messages: _conversationMessages(messages, selectedCharacter.id),
        conversationMode: 'basic',
      );

      final system = ContextBuilder.build(
        task: ContextTask.groupChat,
        settings: settings,
        taskRules:
            '''
你正在真实的多人群聊“${group.name}”中发言。
你只能扮演${selectedCharacter.displayName}，不能替其他成员或用户说话。
$quotedContext
$mentionContext
如果需要点名某人，请使用群内真实名称写成“@名字”，不要虚构不存在的成员。
先看清最近消息，允许接用户，也允许接刚刚说话的其他角色。
回复要像手机群聊，口语、自然、短。禁止用（）、()、[]、【】或 *动作* 输出独立动作、心理或舞台标签，也不写旁白、分析或角色名标签。状态或行为只能自然融进聊天正文。
不要重复别人已经说过的话，不要做圆桌式总结，不要强行把话题绕回恋爱。
禁止争风吃醋、威胁用户、要求用户只能选择你。
普通聊天不要长篇说教；比赛、训练和专业话题才可以明显认真。
本次最多输出${step.replyCount}条消息。若输出多条，用换行分隔，每行是一条完整气泡。
不要故意把一句完整的话切碎，也不要超过3行。
只输出消息正文。

$speechProfile
$esportsRules
''',
        dynamicState: '本轮参与原因：${step.intent}\n群内其他成员：$otherMembers',
        recentConversation: transcript,
        relationshipContext: relationshipContext,
        socialProtocol: socialProtocol,
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
    return GroupReplyPlan(steps: ordered);
  }

  GroupMessage? _latestUserMessage(List<GroupMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].senderType == GroupSenderType.user) {
        return messages[index];
      }
    }
    return null;
  }

  GroupReplyPlan _parsePlan(String raw, Set<String> allowedIds) {
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
          ),
        );
        total += count;
      }
      return GroupReplyPlan(steps: steps);
    } catch (_) {
      return const GroupReplyPlan(steps: []);
    }
  }

  AiCharacter _fallbackCharacter(
    String content,
    List<AiCharacter> members, {
    List<String> mentionedIds = const [],
  }) {
    for (final id in mentionedIds) {
      for (final member in members) {
        if (member.id == id) return member;
      }
    }
    final normalized = content.toLowerCase();
    for (final member in members) {
      final names = [
        member.characterName,
        member.remark,
      ].where((value) => value.trim().isNotEmpty);
      if (names.any((name) => normalized.contains(name.toLowerCase()))) {
        return member;
      }
    }
    return members[_random.nextInt(members.length)];
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
          final sender = switch (message.senderType) {
            GroupSenderType.user => '林念念',
            GroupSenderType.character => names[message.senderId] ?? '未知成员',
            GroupSenderType.system => '系统',
          };
          final mention = message.mentionedMemberIds.isEmpty
              ? ''
              : ' [@${message.mentionedMemberIds.map((id) => id == 'user' ? '林念念' : names[id] ?? id).join('、')}]';
          final reply = message.replyToMessageId == null
              ? ''
              : ' [引用:${message.replyToMessageId}]';
          return '$sender：${message.content}$mention$reply';
        })
        .join('\n');
  }

  GroupMessage? _findMessage(List<GroupMessage> messages, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final message in messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  String _senderName(GroupMessage message, List<AiCharacter> registry) {
    if (message.senderType == GroupSenderType.user) return '林念念';
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
    String speakingCharacterId,
  ) {
    final selected = messages.length <= 18
        ? messages
        : messages.sublist(messages.length - 18);
    return selected
        .map(
          (message) => ChatMessage(
            role: message.senderType == GroupSenderType.user
                ? 'user'
                : message.senderId == speakingCharacterId
                ? 'assistant'
                : 'user',
            content: message.content,
          ),
        )
        .toList(growable: false);
  }
}
