import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/ai/chat_model_provider.dart';
import 'package:peijianche_app/ai/model_hub.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_capability.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/group_chat.dart';
import 'package:peijianche_app/models/group_member.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/group_conversation_coordinator.dart';
import 'package:peijianche_app/services/group_participation_service.dart';

class _FakeProvider implements ChatModelProvider {
  _FakeProvider(this.reply);

  final String reply;
  int calls = 0;
  final List<String> prompts = [];

  @override
  String get providerName => 'fake';

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
    calls++;
    prompts.add(messages.map((m) => m['content'].toString()).join('\n'));
    return reply;
  }
}

class _FakeHub extends ModelHub {
  _FakeHub(this.provider);

  final ChatModelProvider provider;

  @override
  Future<ChatModelProvider> chatProvider({ApiSettings? settings}) async =>
      provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('group_participation_');
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

  AiCharacter character(String id, String name, {String persona = ''}) =>
      AiCharacter(
        id: id,
        characterName: name,
        remark: '',
        persona: persona,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  GroupChat chat(
    List<AiCharacter> members, {
    Map<String, GroupMember>? memberMeta,
  }) => GroupChat(
    id: 'g',
    name: '测试群',
    createdAt: DateTime.utc(2026, 8, 1),
    lastActiveAt: DateTime.utc(2026, 8, 1),
    members: [
      for (final item in members)
        memberMeta?[item.id] ??
            GroupMember(
              groupId: 'g',
              characterId: item.id,
              joinedAt: DateTime.utc(2026, 8, 1),
            ),
    ],
  );

  GroupMessage message(
    String id,
    GroupSenderType type,
    String senderId,
    String content,
    int minute, {
    List<String> mentions = const [],
  }) => GroupMessage(
    id: id,
    groupId: 'g',
    senderType: type,
    senderId: senderId,
    content: content,
    mentionedMemberIds: mentions,
    createdAt: DateTime.utc(2026, 8, 21, 9, minute),
  );

  final now = DateTime.utc(2026, 8, 21, 9, 30);
  const service = GroupParticipationService();

  GroupParticipation scoreOf(
    List<GroupParticipation> all,
    String id,
  ) => all.firstWhere((item) => item.characterId == id);

  test('@ 角色是最高优先级强触发', () {
    final a = character('a', '阿澈');
    final b = character('b', '沈砚');
    final all = service.evaluate(
      group: chat([a, b]),
      members: [a, b],
      messages: [
        message('m1', GroupSenderType.user, 'user', '@沈砚 在吗', 0, mentions: ['b']),
      ],
      now: now,
    );
    expect(all.first.characterId, 'b');
    expect(scoreOf(all, 'b').reasons, contains('mentioned'));
    expect(scoreOf(all, 'b').mentioned, isTrue);
  });

  test('直接点名（无 @）也会被优先', () {
    final a = character('a', '阿澈');
    final b = character('b', '沈砚');
    final all = service.evaluate(
      group: chat([a, b]),
      members: [a, b],
      messages: [
        message('m1', GroupSenderType.user, 'user', '沈砚，你怎么看', 0),
      ],
      now: now,
    );
    expect(all.first.characterId, 'b');
    expect(scoreOf(all, 'b').reasons, contains('directly_addressed'));
  });

  test('刚刚连续发言的角色降权，久未参与的升权', () {
    final a = character('a', '阿澈');
    final b = character('b', '沈砚');
    final members = chat([
      a,
      b,
    ], memberMeta: {
      'a': GroupMember(
        groupId: 'g',
        characterId: 'a',
        joinedAt: DateTime.utc(2026, 8, 1),
        lastSpokeAt: now.subtract(const Duration(minutes: 2)),
        activityLevel: 0.9,
      ),
      'b': GroupMember(
        groupId: 'g',
        characterId: 'b',
        joinedAt: DateTime.utc(2026, 8, 1),
        lastSpokeAt: now.subtract(const Duration(hours: 3)),
        activityLevel: 0.9,
      ),
    });
    final all = service.evaluate(
      group: members,
      members: [a, b],
      messages: [
        message('m1', GroupSenderType.character, 'a', '刚才那条是我说的', 0),
        message('m2', GroupSenderType.character, 'a', '再补一句', 1),
        message('m3', GroupSenderType.user, 'user', '随便聊聊', 2),
      ],
      now: now,
    );
    final aScore = scoreOf(all, 'a');
    final bScore = scoreOf(all, 'b');
    expect(aScore.reasons, contains('cooldown'));
    expect(aScore.reasons, contains('recently_active'));
    expect(bScore.reasons, contains('long_absent'));
    expect(bScore.score, greaterThan(aScore.score));
  });

  test('activityLevel 参与评分', () {
    final low = character('low', '低活跃');
    final high = character('high', '高活跃');
    final all = service.evaluate(
      group: chat([low, high], memberMeta: {
        'low': GroupMember(
          groupId: 'g',
          characterId: 'low',
          joinedAt: DateTime.utc(2026, 8, 1),
          activityLevel: 0.1,
        ),
        'high': GroupMember(
          groupId: 'g',
          characterId: 'high',
          joinedAt: DateTime.utc(2026, 8, 1),
          activityLevel: 0.95,
        ),
      }),
      members: [low, high],
      messages: [message('m1', GroupSenderType.user, 'user', '在吗', 0)],
      now: now,
    );
    expect(scoreOf(all, 'high').score, greaterThan(scoreOf(all, 'low').score));
    expect(scoreOf(all, 'high').reasons, contains('high_activity'));
    expect(scoreOf(all, 'low').reasons, contains('low_activity'));
  });

  test('allowInitiative=false 时不因弱触发成为候选，但被 @ 仍可回应', () {
    final a = character('a', '阿澈');
    final quiet = character('quiet', '安静的');
    final meta = {
      'quiet': GroupMember(
        groupId: 'g',
        characterId: 'quiet',
        joinedAt: DateTime.utc(2026, 8, 1),
        allowInitiative: false,
        activityLevel: 1.0,
      ),
    };
    final weak = service.evaluate(
      group: chat([a, quiet], memberMeta: meta),
      members: [a, quiet],
      messages: [message('m1', GroupSenderType.user, 'user', '大家好', 0)],
      now: now,
    );
    expect(scoreOf(weak, 'quiet').allowed, isFalse);
    expect(scoreOf(weak, 'quiet').reasons, contains('initiative_disabled'));

    final strong = service.evaluate(
      group: chat([a, quiet], memberMeta: meta),
      members: [a, quiet],
      messages: [
        message('m1', GroupSenderType.user, 'user', '@安静的 说两句', 0,
            mentions: ['quiet']),
      ],
      now: now,
    );
    expect(scoreOf(strong, 'quiet').allowed, isTrue);
  });

  test('话题相关的角色得分更高', () {
    final cook = character('cook', '小厨', persona: '喜欢做饭、料理和甜点');
    final gamer = character('gamer', '小游', persona: '沉迷游戏和电竞');
    final all = service.evaluate(
      group: chat([cook, gamer]),
      members: [cook, gamer],
      messages: [
        message('m1', GroupSenderType.user, 'user', '晚饭想做个甜点，有什么建议', 0),
      ],
      now: now,
    );
    expect(scoreOf(all, 'cook').reasons, contains('topic_relevant'));
    expect(scoreOf(all, 'cook').score, greaterThan(scoreOf(all, 'gamer').score));
  });

  test('其他角色已充分回答后，未被 @ 的角色降权', () {
    final a = character('a', '阿澈');
    final b = character('b', '沈砚');
    final all = service.evaluate(
      group: chat([a, b]),
      members: [a, b],
      messages: [
        message('m1', GroupSenderType.user, 'user', '今晚吃什么', 0),
        message('m2', GroupSenderType.character, 'a', '火锅。', 1),
        message('m3', GroupSenderType.character, 'a', '不过要早点去排队。', 2),
      ],
      now: now,
    );
    expect(scoreOf(all, 'b').reasons, contains('already_answered'));
  });

  test('createPlan：@ 优先 + planner 仍存在 + 只调用一次模型', () async {
    final a = character('a', '阿澈');
    final b = character('b', '沈砚');
    await CharacterRegistryService().saveCharacters([a, b]);

    final provider = _FakeProvider(
      '{"steps":[{"characterId":"a","replyCount":1,"intent":"先接一句"}]}',
    );
    final coordinator = GroupConversationCoordinator(
      modelHub: _FakeHub(provider),
    );
    final group = chat([a, b]);
    final plan = await coordinator.createPlan(
      group: group,
      messages: [
        message('m1', GroupSenderType.user, 'user', '@沈砚 今晚吃什么', 0,
            mentions: ['b']),
      ],
    );

    expect(provider.calls, 1, reason: '一次 planner，而不是每个角色一次 YES/NO');
    expect(provider.prompts.single.contains('群聊调度器'), isTrue);
    expect(provider.prompts.single.contains('【本地候选'), isTrue);
    // 被 @ 的角色进入第一步
    expect(plan.steps.first.characterId, 'b');
    expect(plan.steps.first.reasons, contains('mentioned'));
    expect(plan.participation, isNotEmpty);
  });

  test('createPlan：planner 给出 0 人时允许本轮沉默', () async {
    final a = character('a', '阿澈');
    final b = character('b', '沈砚');
    await CharacterRegistryService().saveCharacters([a, b]);
    final provider = _FakeProvider('{"steps":[]}');
    final coordinator = GroupConversationCoordinator(
      modelHub: _FakeHub(provider),
    );
    final plan = await coordinator.createPlan(
      group: chat([a, b]),
      messages: [message('m1', GroupSenderType.user, 'user', '嗯', 0)],
    );
    expect(plan.steps, isEmpty);
  });

  test('createPlan：planner 失败时本地最高分候选保底 1 人', () async {
    final a = character('a', '阿澈');
    final b = character('b', '沈砚');
    await CharacterRegistryService().saveCharacters([a, b]);
    final provider = _FakeProvider('不是 JSON');
    final coordinator = GroupConversationCoordinator(
      modelHub: _FakeHub(provider),
    );
    final plan = await coordinator.createPlan(
      group: chat([a, b]),
      messages: [
        message('m1', GroupSenderType.user, 'user', '阿澈在吗', 0),
      ],
    );
    expect(plan.steps, hasLength(1));
    expect(plan.steps.single.characterId, 'a');
  });

  test('createPlan：未被 @ 且 allowInitiative=false 的角色不进候选', () async {
    final a = character('a', '阿澈');
    final quiet = character('quiet', '安静的');
    await CharacterRegistryService().saveCharacters([a, quiet]);
    final provider = _FakeProvider(
      '{"steps":[{"characterId":"quiet","replyCount":1,"intent":"插话"}]}',
    );
    final coordinator = GroupConversationCoordinator(
      modelHub: _FakeHub(provider),
    );
    final plan = await coordinator.createPlan(
      group: chat([a, quiet], memberMeta: {
        'quiet': GroupMember(
          groupId: 'g',
          characterId: 'quiet',
          joinedAt: DateTime.utc(2026, 8, 1),
          allowInitiative: false,
        ),
      }),
      messages: [message('m1', GroupSenderType.user, 'user', '随便聊聊', 0)],
    );
    expect(
      plan.steps.map((step) => step.characterId),
      isNot(contains('quiet')),
    );
    // 候选名单里该角色被标记为不可用
    final quietScore = plan.participation.firstWhere(
      (item) => item.characterId == 'quiet',
    );
    expect(quietScore.allowed, isFalse);
  });
}
