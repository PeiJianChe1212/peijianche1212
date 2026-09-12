import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/ai/chat_model_provider.dart';
import 'package:peijianche_app/ai/model_hub.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_capability.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/group_chat.dart';
import 'package:peijianche_app/models/group_member.dart';
import 'package:peijianche_app/models/group_memory_event.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/group_character_voice.dart';
import 'package:peijianche_app/services/group_conversation_coordinator.dart';
import 'package:peijianche_app/services/group_participation_service.dart';
import 'package:peijianche_app/services/group_reply_target.dart';

/// 捕获最后一次模型请求，用于确认 prompt 里的回复目标与身份标签。
class _CapturingProvider implements ChatModelProvider {
  final List<String> prompts = [];
  String reply = '好的。';

  @override
  String get providerName => 'capturing';

  @override
  Set<AiCapability> get capabilities => {AiCapability.chat};

  @override
  bool supports(AiCapability capability) => capabilities.contains(capability);

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int maxTokens,
    double? topP,
    bool acceptStructuredReasoningFallback = false,
  }) async {
    prompts.add(
      messages
          .map((message) => '[${message['role']}]${message['content']}')
          .join('\n=====\n'),
    );
    return reply;
  }
}

class _CapturingHub extends ModelHub {
  _CapturingHub(this.provider);

  final ChatModelProvider provider;

  @override
  Future<ChatModelProvider> chatProvider({ApiSettings? settings}) async =>
      provider;
}

/// Phase G3.5 targeted coverage: reply target + speaker identity chain.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('group_g35_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      if (await documents.exists()) await documents.delete(recursive: true);
    } catch (_) {}
  });

  AiCharacter character(String id, String name, {String relationship = ''}) =>
      AiCharacter(
        id: id,
        characterName: name,
        remark: '',
        relationship: relationship,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  AiCharacter a = character('char_a', '阿澈');
  AiCharacter b = character('char_b', '小满');
  AiCharacter c = character('char_c', '阿越');

  GroupChat groupFor(
    List<AiCharacter> members, {
    String relationshipLabel = '',
    Set<String> noInitiative = const {},
  }) => GroupChat(
    id: 'group_g35',
    name: '测试群',
    createdAt: DateTime.utc(2026, 8, 1),
    lastActiveAt: DateTime.utc(2026, 8, 1),
    members: [
      for (final item in members)
        GroupMember(
          groupId: 'group_g35',
          characterId: item.id,
          joinedAt: DateTime.utc(2026, 8, 1),
          relationshipLabel: relationshipLabel,
          allowInitiative: !noInitiative.contains(item.id),
        ),
    ],
  );

  GroupMessage userMessage(
    String content, {
    String id = 'u1',
    List<String> mentions = const [],
    DateTime? at,
  }) => GroupMessage(
    id: id,
    groupId: 'group_g35',
    senderType: GroupSenderType.user,
    senderId: 'user',
    content: content,
    mentionedMemberIds: mentions,
    createdAt: at ?? DateTime.utc(2026, 8, 21, 9),
  );

  GroupMessage memberMessage(
    String senderId,
    String content, {
    required String id,
    DateTime? at,
  }) => GroupMessage(
    id: id,
    groupId: 'group_g35',
    senderType: GroupSenderType.character,
    senderId: senderId,
    content: content,
    createdAt: at ?? DateTime.utc(2026, 8, 21, 9, 1),
  );

  const resolver = GroupReplyTargetResolver();

  Future<void> seedCharacters(List<AiCharacter> members) async {
    await CharacterRegistryService().saveCharacters(members);
    for (final item in members) {
      await CharacterSettingsStorageService(characterId: item.id).saveSettings(
        CharacterSettings.genericDefaults().copyWith(
          characterName: item.characterName,
        ),
      );
    }
  }

  Future<String> promptFor({
    required AiCharacter speaker,
    required List<AiCharacter> members,
    required List<GroupMessage> messages,
    GroupReplyStep? step,
    String plannerReply = '好的。',
  }) async {
    await seedCharacters(members);
    final provider = _CapturingProvider()..reply = plannerReply;
    final coordinator = GroupConversationCoordinator(
      modelHub: _CapturingHub(provider),
    );
    await coordinator.generateStep(
      group: groupFor(members),
      step: step ?? GroupReplyStep(characterId: speaker.id, replyCount: 1),
      messages: messages,
    );
    expect(provider.prompts, isNotEmpty, reason: '必须发起一次生成请求');
    return provider.prompts.last;
  }

  test('场景1：用户发言后 B 能看到 A，并把回复目标指向 A', () async {
    final messages = [
      userMessage('今晚吃什么？'),
      memberMessage('char_a', '火锅吧。', id: 'a1'),
    ];
    final target = resolver.resolve(
      speakerCharacterId: 'char_b',
      speakerName: '小满',
      messages: messages,
    );
    expect(target.type, GroupReplyTargetType.character);
    expect(target.characterId, 'char_a');

    final prompt = await promptFor(
      speaker: b,
      members: [a, b],
      messages: messages,
    );
    expect(prompt.contains('【本轮回复目标】阿澈(char_a)'), isTrue);
    expect(prompt.contains('你正在接阿澈(char_a)的话'), isTrue);
    // B 知道 A 刚说过什么（speaker identity + 连续上下文）。
    expect(prompt.contains('阿澈(char_a)：火锅吧。'), isTrue);
  });

  test('场景2：用户 @A 时 A 的回复目标是用户', () async {
    final messages = [
      userMessage('@阿澈 今晚吃什么？', mentions: ['char_a']),
    ];
    final target = resolver.resolve(
      speakerCharacterId: 'char_a',
      speakerName: '阿澈',
      messages: messages,
      participationReasons: const ['mentioned'],
    );
    expect(target.type, GroupReplyTargetType.user);

    final prompt = await promptFor(
      speaker: a,
      members: [a, b],
      messages: messages,
      step: const GroupReplyStep(
        characterId: 'char_a',
        replyCount: 1,
        reasons: ['mentioned'],
      ),
    );
    expect(prompt.contains('【本轮回复目标】用户'), isTrue);
  });

  test('场景3：A 明确点名 B 时 B 优先回应 A', () async {
    final messages = [
      userMessage('今晚吃什么？'),
      memberMessage('char_a', '小满，你昨天不是刚吃过火锅？', id: 'a1'),
    ];
    final target = resolver.resolve(
      speakerCharacterId: 'char_b',
      speakerName: '小满',
      messages: messages,
    );
    expect(target.type, GroupReplyTargetType.character);
    expect(target.characterId, 'char_a');
  });

  test('场景4：A 只是补充观点时 B 不强制回应 A', () async {
    const longOpinion =
        '我个人觉得今晚可以就近找一家川菜馆子，点两个家常菜就挺好，主要是别弄得太麻烦，吃完还要收拾桌子。';
    final messages = [
      userMessage('今晚吃什么？'),
      memberMessage('char_a', longOpinion, id: 'a1'),
    ];
    final target = resolver.resolve(
      speakerCharacterId: 'char_b',
      speakerName: '小满',
      messages: messages,
      participationReasons: const ['topic_relevant'],
    );
    expect(target.isCharacter, isFalse, reason: '上一句只是长陈述，不强制回应 A');
    expect(target.type, GroupReplyTargetType.group);

    final prompt = await promptFor(
      speaker: b,
      members: [a, b],
      messages: messages,
      step: const GroupReplyStep(
        characterId: 'char_b',
        replyCount: 1,
        reasons: ['topic_relevant'],
      ),
    );
    expect(prompt.contains('【本轮回复目标】全群'), isTrue);
    expect(prompt.contains('【本轮回复目标】阿澈(char_a)'), isFalse);
  });

  test('场景5：C 没有补充价值时 G3.2 允许沉默', () {
    final answered = [
      userMessage('今晚吃什么？'),
      memberMessage('char_a', '火锅吧。', id: 'a1'),
      memberMessage('char_b', '我投烧烤。', id: 'b1'),
    ];
    // 软信号：已经有人答过之后，未被点名的成员会带上 already_answered，
    // 排序下沉，交给 planner 决定是否真的沉默（G3.2 不设分数阈值）。
    final soft = const GroupParticipationService().evaluate(
      group: groupFor([a, b, c]),
      members: [a, b, c],
      messages: answered,
    );
    expect(
      soft.firstWhere((item) => item.characterId == 'char_c').reasons,
      contains('already_answered'),
    );

    // 硬门控：没有补充价值也不主动参与的成员 allowed=false，直接不进候选。
    final gated = const GroupParticipationService().evaluate(
      group: groupFor([a, b, c], noInitiative: const {'char_c'}),
      members: [a, b, c],
      messages: answered,
    );
    final cGated = gated.firstWhere((item) => item.characterId == 'char_c');
    expect(cGated.allowed, isFalse);
    expect(cGated.reasons, contains('initiative_disabled'));

    // 被 @ 时仍然进入候选，硬门控不会误伤被点名的成员。
    final mentioned = const GroupParticipationService().evaluate(
      group: groupFor([a, b, c], noInitiative: const {'char_c'}),
      members: [a, b, c],
      messages: [userMessage('@阿越 今晚吃什么？', mentions: ['char_c'])],
    );
    expect(
      mentioned.firstWhere((item) => item.characterId == 'char_c').allowed,
      isTrue,
    );
  });

  test('场景6：A 生成失败后 B 不会引用不存在的目标', () async {
    // A 失败 => transcript 里没有 A 的消息；planner 提示的 A 目标必须被丢弃。
    final messages = [userMessage('今晚吃什么？')];
    final target = resolver.resolve(
      speakerCharacterId: 'char_b',
      speakerName: '小满',
      messages: messages,
      plannerTargetId: 'char_a',
    );
    expect(target.type, GroupReplyTargetType.user);

    final prompt = await promptFor(
      speaker: b,
      members: [a, b],
      messages: messages,
      step: const GroupReplyStep(
        characterId: 'char_b',
        replyCount: 1,
        plannerTargetId: 'char_a',
      ),
    );
    expect(prompt.contains('【本轮回复目标】用户'), isTrue);
    expect(prompt.contains('【本轮回复目标】阿澈(char_a)'), isFalse);
  });

  test('场景7：多角色与用户都是特殊关系也不会自动产生吃醋/争抢', () async {
    final aLover = character('char_a', '阿澈', relationship: '恋人');
    final bLover = character('char_b', '小满', relationship: '恋人');
    final messages = [
      userMessage('今晚吃什么？'),
      memberMessage('char_a', '火锅吧。', id: 'a1'),
    ];

    final neutral = resolver.resolve(
      speakerCharacterId: 'char_b',
      speakerName: '小满',
      messages: messages,
    );
    final special = resolver.resolve(
      speakerCharacterId: 'char_b',
      speakerName: '小满',
      messages: messages,
    );
    expect(special, neutral, reason: '目标只由上下文决定，与关系无关');
    expect(GroupReplyTargetType.values, hasLength(3));

    final prompt = await promptFor(
      speaker: bLover,
      members: [aLover, bLover],
      messages: messages,
    );
    // 现有护栏仍然是“禁止”，不是自动触发。
    expect(prompt.contains('禁止争风吃醋'), isTrue);
    expect(prompt.contains('【本轮回复目标】阿澈(char_a)'), isTrue);
  });

  test('场景8：本轮结束后不会自动开启第二轮角色互聊', () async {
    final userTurn = [userMessage('今晚吃什么？')];
    final characterLast = [
      userMessage('今晚吃什么？'),
      memberMessage('char_a', '火锅吧。', id: 'a1'),
    ];
    expect(resolver.isTurnTrigger(userTurn.last), isTrue);
    expect(resolver.isTurnTrigger(characterLast.last), isFalse);
    expect(resolver.isTurnTrigger(null), isFalse);

    await seedCharacters([a, b]);
    // planner 即使想点名，角色结尾的 transcript 也不会开启新一轮。
    final provider = _CapturingProvider()
      ..reply = '{"steps":[{"characterId":"char_b","replyCount":1,"intent":"接话"}]}';
    final coordinator = GroupConversationCoordinator(
      modelHub: _CapturingHub(provider),
    );
    final plan = await coordinator.createPlan(
      group: groupFor([a, b]),
      messages: characterLast,
    );
    expect(plan.steps, isEmpty);
    expect(provider.prompts, isEmpty, reason: '角色结尾时不应调用 planner');
  });

  test('场景9：G3.1 speaker identity 不回退', () {
    const names = {'char_a': '阿澈', 'char_b': '小满'};
    expect(
      GroupConversationCoordinator.speakerLabel(userMessage('在吗'), names),
      '用户',
    );
    expect(
      GroupConversationCoordinator.speakerLabel(
        memberMessage('char_a', '火锅吧。', id: 'a1'),
        names,
      ),
      '阿澈(char_a)',
    );
    expect(
      GroupConversationCoordinator.speakerLabel(
        GroupMessage(
          id: 's1',
          groupId: 'group_g35',
          senderType: GroupSenderType.system,
          senderId: 'system',
          content: '系统提示',
        ),
        names,
      ),
      '系统',
    );
    expect(
      GroupConversationCoordinator.speakerLabel(
        memberMessage('char_b', '我投烧烤。', id: 'b1'),
        names,
      ),
      isNot('用户'),
    );
  });

  test('场景10：G3.2 participation 不回退', () {
    final participation = const GroupParticipationService().evaluate(
      group: groupFor([a, b]),
      members: [a, b],
      messages: [
        userMessage('@阿澈 今晚吃什么？', mentions: ['char_a']),
      ],
    );
    final aEntry = participation.firstWhere(
      (item) => item.characterId == 'char_a',
    );
    expect(aEntry.mentioned, isTrue);
    expect(aEntry.allowed, isTrue);
    expect(aEntry.reasons, contains('mentioned'));

    final addressed = const GroupParticipationService().evaluate(
      group: groupFor([a, b]),
      members: [a, b],
      messages: [
        userMessage('今晚吃什么？'),
        memberMessage('char_a', '小满，你昨天不是刚吃过火锅？', id: 'a1'),
      ],
    );
    final bEntry = addressed.firstWhere(
      (item) => item.characterId == 'char_b',
    );
    expect(bEntry.reasons, contains('addressed_by_member'));
  });

  test('场景11：G3.3 Character Voice 不回退', () {
    final voice = GroupCharacterVoice.build(
      character: a,
      profile: const CharacterProfile(
        characterId: 'char_a',
        name: '阿澈',
        speakingStyle: '阿澈专属表达：短句、爱反问、结尾用波浪号~',
      ),
    );
    expect(voice.isNotEmpty, isTrue);
    expect(voice.contains('阿澈专属表达：短句、爱反问、结尾用波浪号~'), isTrue);
  });

  test('场景12：G3.4 群聊记忆 speaker/participants 不回退', () {
    final event = GroupMemoryEvent(
      id: 'g1_event_1',
      groupId: 'group_g35',
      groupName: '测试群',
      content: '阿澈说：小满，你昨天不是刚吃过火锅？',
      speakerIds: const ['char_a'],
      participants: const ['char_a', 'char_b'],
      sourceMessageIds: const ['a1'],
    );
    final restored = GroupMemoryEvent.tryFromEventMemory(
      event.toEventMemory(),
      fallbackGroupId: 'group_g35',
    );
    expect(restored, isNotNull);
    expect(restored!.groupId, 'group_g35');
    expect(restored.speakerIds, ['char_a']);
    expect(restored.participants, containsAll(['char_a', 'char_b']));
    expect(restored.content.contains('阿澈说'), isTrue);
  });
}
