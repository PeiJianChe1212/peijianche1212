import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/ai/chat_model_provider.dart';
import 'package:peijianche_app/ai/model_hub.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_capability.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_archive.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/group_chat.dart';
import 'package:peijianche_app/models/group_member.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/services/character_archive_storage_service.dart';
import 'package:peijianche_app/services/character_profile_storage_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/group_conversation_coordinator.dart';

/// 捕获最后一次模型请求的 system prompt 内容。
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

/// Phase G3.3 targeted coverage: Character Voice 数据化，防止不同角色说成同一个 AI。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('group_g33_test_');
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

  GroupChat groupFor(List<AiCharacter> members) => GroupChat(
    id: 'group_g33',
    name: '测试群',
    createdAt: DateTime.utc(2026, 8, 1),
    lastActiveAt: DateTime.utc(2026, 8, 1),
    members: [
      for (final item in members)
        GroupMember(
          groupId: 'group_g33',
          characterId: item.id,
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
    ],
  );

  GroupMessage userMessage(String content) => GroupMessage(
    id: 'm1',
    groupId: 'group_g33',
    senderType: GroupSenderType.user,
    senderId: 'user',
    content: content,
    createdAt: DateTime.utc(2026, 8, 21, 9),
  );

  Future<(_CapturingProvider, String)> promptFor({
    required AiCharacter speaker,
    required List<AiCharacter> members,
    String content = '今晚吃什么？',
  }) async {
    final provider = _CapturingProvider();
    final coordinator = GroupConversationCoordinator(
      modelHub: _CapturingHub(provider),
    );
    await coordinator.generateStep(
      group: groupFor(members),
      step: GroupReplyStep(characterId: speaker.id, replyCount: 1),
      messages: [userMessage(content)],
    );
    expect(provider.prompts, isNotEmpty, reason: '必须发起模型请求');
    return (provider, provider.prompts.last);
  }

  Future<void> saveSettings(
    String id,
    String name, {
    String exampleDialogues = '',
    String replyLength = 'standard',
  }) async {
    await CharacterSettingsStorageService(characterId: id).saveSettings(
      CharacterSettings.genericDefaults().copyWith(
        characterName: name,
        exampleDialogues: exampleDialogues,
        replyLength: replyLength,
      ),
    );
  }

  test(
    'A 的 speakingStyle 进入 A prompt，B 的 speakingStyle 不进入 A prompt',
    () async {
      final a = character('char_a', '甲');
      final b = character('char_b', '乙');
      await CharacterRegistryService().saveCharacters([a, b]);
      await saveSettings('char_a', '甲');
      await saveSettings('char_b', '乙');

      await CharacterProfileStorageService(characterId: 'char_a').save(
        const CharacterProfile(
          characterId: 'char_a',
          name: '甲',
          speakingStyle: '甲专属表达：短句、爱反问、结尾用波浪号~',
        ),
      );
      await CharacterProfileStorageService(characterId: 'char_b').save(
        const CharacterProfile(
          characterId: 'char_b',
          name: '乙',
          speakingStyle: '乙专属表达：长句、文言腔、从不用 emoji',
        ),
      );

      final (_, promptA) = await promptFor(speaker: a, members: [a, b]);
      expect(promptA.contains('甲专属表达：短句、爱反问、结尾用波浪号~'), isTrue);
      expect(promptA.contains('乙专属表达：长句、文言腔、从不用 emoji'), isFalse);

      final (_, promptB) = await promptFor(speaker: b, members: [a, b]);
      expect(promptB.contains('乙专属表达：长句、文言腔、从不用 emoji'), isTrue);
      expect(promptB.contains('甲专属表达：短句、爱反问、结尾用波浪号~'), isFalse);
    },
  );

  test('expressionProfile / Archive 表达资料只进入对应角色 prompt', () async {
    final a = character('char_a', '甲');
    final b = character('char_b', '乙');
    await CharacterRegistryService().saveCharacters([a, b]);
    await saveSettings('char_a', '甲');
    await saveSettings('char_b', '乙');

    await CharacterProfileStorageService(characterId: 'char_a').save(
      const CharacterProfile(
        characterId: 'char_a',
        name: '甲',
        identity: '甲的身份',
        personalityTags: '甲的性格标签',
        personalityDescription: '甲说话前会先想一遍',
      ),
    );
    await CharacterArchiveStorageService(characterId: 'char_a').save(
      const CharacterArchive(
        characterId: 'char_a',
        values: {
          'languageHabits': '甲常用省略句',
          'commonExpressions': '好的吧',
          'chatPace': '甲回复节奏偏慢',
          'expressionTraits': '甲喜欢用省略号',
        },
      ),
    );
    await CharacterArchiveStorageService(characterId: 'char_b').save(
      const CharacterArchive(
        characterId: 'char_b',
        values: {'languageHabits': '乙只用短促的问句'},
      ),
    );

    final (_, promptA) = await promptFor(speaker: a, members: [a, b]);
    expect(promptA.contains('甲的性格标签'), isTrue);
    expect(promptA.contains('甲常用省略句'), isTrue);
    expect(promptA.contains('甲回复节奏偏慢'), isTrue);
    expect(promptA.contains('甲喜欢用省略号'), isTrue);
    expect(promptA.contains('乙只用短促的问句'), isFalse);

    final (_, promptB) = await promptFor(speaker: b, members: [a, b]);
    expect(promptB.contains('乙只用短促的问句'), isTrue);
    expect(promptB.contains('甲常用省略句'), isFalse);
    expect(promptB.contains('甲的性格标签'), isFalse);
  });

  test('styleExamples 只取少量代表样本，不全部灌入，也不串角色', () async {
    final a = character('char_a', '甲');
    final b = character('char_b', '乙');
    await CharacterRegistryService().saveCharacters([a, b]);
    await saveSettings(
      'char_a',
      '甲',
      exampleDialogues: [
        '甲：甲例句一',
        '甲：甲例句二',
        '甲：甲例句三',
        '甲：甲例句四',
        '甲：甲例句五',
        '甲：甲例句六',
      ].join('\n'),
    );
    await saveSettings('char_b', '乙', exampleDialogues: '乙：乙专属样本句');

    final (_, promptA) = await promptFor(speaker: a, members: [a, b]);
    expect(promptA.contains('【语言风格样本'), isTrue);
    expect(promptA.contains('甲例句一'), isTrue);
    expect(promptA.contains('甲例句三'), isTrue);
    // 只取 3 条：第四条起不进 prompt
    expect(promptA.contains('甲例句四'), isFalse);
    expect(promptA.contains('甲例句五'), isFalse);
    expect(promptA.contains('甲例句六'), isFalse);
    // 不把 B 的样本给 A
    expect(promptA.contains('乙专属样本句'), isFalse);

    final (_, promptB) = await promptFor(speaker: b, members: [a, b]);
    expect(promptB.contains('乙专属样本句'), isTrue);
    expect(promptB.contains('甲例句一'), isFalse);
  });

  test('没有 CharacterProfile 的旧角色仍能正常生成（fallback 不抛错）', () async {
    final old = character('char_old', '老角色');
    final other = character('char_other', '另一个');
    await CharacterRegistryService().saveCharacters([old, other]);
    await saveSettings('char_old', '老角色');
    await saveSettings('char_other', '另一个');

    final (provider, prompt) = await promptFor(
      speaker: old,
      members: [old, other],
    );
    // 仍然正常发起一次生成请求，并带上了角色身份
    expect(provider.prompts, hasLength(1));
    expect(prompt.contains('角色本名：老角色'), isTrue);
    // 没有任何表达数据时，不输出空的 Character Voice 标题
    expect(prompt.contains('【Character Voice'), isFalse);
  });

  test('普通非 Reborn 角色拥有完整 Character Voice', () async {
    final plain = character('char_plain', '普通角色', persona: '一个爱吐槽的人');
    final other = character('char_other', '另一个');
    await CharacterRegistryService().saveCharacters([plain, other]);
    await saveSettings('char_plain', '普通角色');
    await saveSettings('char_other', '另一个');
    await CharacterProfileStorageService(characterId: 'char_plain').save(
      const CharacterProfile(
        characterId: 'char_plain',
        name: '普通角色',
        speakingStyle: '普通角色专属：爱吐槽、句子短、常用「哈？」',
      ),
    );

    final (_, prompt) = await promptFor(
      speaker: plain,
      members: [plain, other],
    );
    expect(prompt.contains('【Character Voice'), isTrue);
    expect(prompt.contains('普通角色专属：爱吐槽、句子短、常用「哈？」'), isTrue);
    // persona 未出现在 coreProfile 时作为语义补充进入
    expect(prompt.contains('一个爱吐槽的人'), isTrue);
  });

  test('Reborn 硬编码不再覆盖角色自己的表达数据，仅作无数据兜底', () async {
    final jiang = character('char_jiang', '江逾白');
    final other = character('char_other', '另一个');
    await CharacterRegistryService().saveCharacters([jiang, other]);
    await saveSettings('char_jiang', '江逾白');
    await saveSettings('char_other', '另一个');
    await CharacterProfileStorageService(characterId: 'char_jiang').save(
      const CharacterProfile(
        characterId: 'char_jiang',
        name: '江逾白',
        speakingStyle: '江逾白本人数据：语速快、爱用半句话结尾',
      ),
    );

    final (_, withOwnData) = await promptFor(
      speaker: jiang,
      members: [jiang, other],
    );
    expect(withOwnData.contains('江逾白本人数据：语速快、爱用半句话结尾'), isTrue);
    expect(withOwnData.contains('毒舌但无恶意'), isFalse, reason: '硬编码不得覆盖角色自己的表达数据');

    // 没有自己表达数据时，Reborn 口径只作为兜底
    final lin = character('char_lin', '林屿');
    final other2 = character('char_other2', '另一个');
    await CharacterRegistryService().saveCharacters([lin, other2]);
    await saveSettings('char_lin', '林屿');
    await saveSettings('char_other2', '另一个');
    final (_, fallback) = await promptFor(speaker: lin, members: [lin, other2]);
    expect(fallback.contains('群聊语言'), isTrue, reason: '无数据时回落到 Reborn 口径');
  });

  test('群聊通用规则只负责场景，不强制统一人格', () async {
    final a = character('char_a', '甲');
    final b = character('char_b', '乙');
    await CharacterRegistryService().saveCharacters([a, b]);
    await saveSettings('char_a', '甲');
    await saveSettings('char_b', '乙');

    final (_, prompt) = await promptFor(speaker: a, members: [a, b]);
    // 旧的「口语、自然、短」一刀切人格约束不再出现
    expect(prompt.contains('口语、自然、短'), isFalse);
    // 场景规则明确把表达方式交回角色自己
    expect(prompt.contains('以本角色自己的表达习惯为准'), isTrue);
    expect(prompt.contains('群聊规则只负责场景，不塑造人格'), isTrue);
    // 多人场景边界仍在
    expect(prompt.contains('不能替其他成员或用户说话'), isTrue);
  });

  test('G3.1 speaker identity 不回退：A 生成时看得到 B 的发言身份', () async {
    final a = character('char_a', '甲');
    final b = character('char_b', '乙');
    await CharacterRegistryService().saveCharacters([a, b]);
    await saveSettings('char_a', '甲');
    await saveSettings('char_b', '乙');

    final provider = _CapturingProvider();
    final coordinator = GroupConversationCoordinator(
      modelHub: _CapturingHub(provider),
    );
    await coordinator.generateStep(
      group: groupFor([a, b]),
      step: const GroupReplyStep(characterId: 'char_a', replyCount: 1),
      messages: [
        userMessage('今晚吃什么？'),
        GroupMessage(
          id: 'm2',
          groupId: 'group_g33',
          senderType: GroupSenderType.character,
          senderId: 'char_b',
          content: '火锅吧。',
          createdAt: DateTime.utc(2026, 8, 21, 9, 1),
        ),
      ],
    );
    final prompt = provider.prompts.last;
    expect(prompt.contains('乙(char_b)：火锅吧。'), isTrue);
    expect(prompt.contains('用户：火锅吧。'), isFalse);
    expect(prompt.contains('用户：今晚吃什么？'), isTrue);
  });

  test('不新增模型调用：单次 generateStep 只请求一次模型', () async {
    final a = character('char_a', '甲');
    final b = character('char_b', '乙');
    await CharacterRegistryService().saveCharacters([a, b]);
    await saveSettings('char_a', '甲');
    await saveSettings('char_b', '乙');

    final (provider, _) = await promptFor(speaker: a, members: [a, b]);
    expect(provider.prompts, hasLength(1));
  });

  test('schema/storage 不变化：表达数据不新增持久化字段', () {
    final profileKeys = const CharacterProfile(
      characterId: 'x',
    ).toJson().keys.toSet();
    expect(profileKeys.contains('speakingStyle'), isTrue);
    expect(profileKeys.contains('expressionProfile'), isFalse);
    expect(profileKeys.contains('styleExamples'), isFalse);

    final settingsKeys = CharacterSettings.genericDefaults()
        .toJson()
        .keys
        .toSet();
    expect(settingsKeys, {
      'characterName',
      'remark',
      'relation',
      'birthday',
      'anniversary',
      'introduction',
      'userCallName',
      'coreProfile',
      'behaviorStyle',
      'forbiddenRules',
      'exampleDialogues',
      'conversationMode',
      'temperature',
      'replyLength',
      'initiative',
      'intimacy',
      'tsundere',
      'proactiveEnabled',
      'lateNightMessages',
      'maxProactivePerDay',
      'autoMemoryEnabled',
    });
  });
}
