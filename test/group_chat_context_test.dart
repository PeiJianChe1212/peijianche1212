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
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/group_chat.dart';
import 'package:peijianche_app/models/group_member.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/models/group_user_profile.dart';
import 'package:peijianche_app/services/character_archive_storage_service.dart';
import 'package:peijianche_app/services/character_profile_storage_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/character_user_profile_storage_service.dart';
import 'package:peijianche_app/services/group_conversation_coordinator.dart';
import 'package:peijianche_app/services/group_user_profile_storage_service.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('group_ctx_test_');
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

  AiCharacter character(String id, String name) => AiCharacter(
    id: id,
    characterName: name,
    remark: '',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  GroupChat group(List<AiCharacter> members) => GroupChat(
    id: 'group_ctx',
    name: '测试群',
    createdAt: DateTime.utc(2026, 8, 1),
    lastActiveAt: DateTime.utc(2026, 8, 1),
    members: [
      for (final item in members)
        GroupMember(
          groupId: 'group_ctx',
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
    int minute,
  ) => GroupMessage(
    id: id,
    groupId: 'group_ctx',
    senderType: type,
    senderId: senderId,
    content: content,
    createdAt: DateTime.utc(2026, 8, 21, 9, minute),
  );

  Future<String> promptFor({
    required AiCharacter speaker,
    required List<AiCharacter> members,
    required List<GroupMessage> messages,
  }) async {
    final provider = _CapturingProvider();
    final coordinator = GroupConversationCoordinator(
      modelHub: _CapturingHub(provider),
    );
    await coordinator.generateStep(
      group: group(members),
      step: GroupReplyStep(characterId: speaker.id, replyCount: 1),
      messages: messages,
    );
    expect(provider.prompts, isNotEmpty, reason: '必须发起模型请求');
    return provider.prompts.last;
  }

  test('transcript 保留真实发言者身份，不把其他角色伪装成用户', () async {
    final q = character('q', 'q');
    final w = character('w', 'w');
    await CharacterRegistryService().saveCharacters([q, w]);

    final prompt = await promptFor(
      speaker: w,
      members: [q, w],
      messages: [
        message('m1', GroupSenderType.user, 'user', '今晚吃什么？', 0),
        message('m2', GroupSenderType.character, 'q', '火锅。', 1),
        message('m3', GroupSenderType.system, 'system', 'q 加入了群聊', 2),
      ],
    );

    // 角色 q 的发言带 speaker 标签，而不是被当成用户
    expect(prompt.contains('q(q)：火锅。'), isTrue);
    expect(prompt.contains('用户：火锅。'), isFalse);
    expect(prompt.contains('用户：今晚吃什么？'), isTrue);
    // system 语义保留
    expect(prompt.contains('系统：q 加入了群聊'), isTrue);
    // 当前发言角色自己的历史发言标为"我"（assistant）
    expect(prompt.contains('q(q)：火锅。'), isTrue);
    expect(prompt.contains('用户：火锅。'), isFalse);
  });

  test('C 生成时能看到 用户 + A + B 的发言', () async {
    final a = character('a', 'a');
    final b = character('b', 'b');
    final c = character('c', 'c');
    await CharacterRegistryService().saveCharacters([a, b, c]);

    final prompt = await promptFor(
      speaker: c,
      members: [a, b, c],
      messages: [
        message('m1', GroupSenderType.user, 'user', '今晚吃什么？', 0),
        message('m2', GroupSenderType.character, 'a', '火锅。', 1),
        message('m3', GroupSenderType.character, 'b', '你昨天不是才吃过？', 2),
      ],
    );

    expect(prompt.contains('用户：今晚吃什么？'), isTrue);
    expect(prompt.contains('a(a)：火锅。'), isTrue);
    expect(prompt.contains('b(b)：你昨天不是才吃过？'), isTrue);
    expect(prompt.contains('用户：火锅。'), isFalse);
    expect(prompt.contains('用户：你昨天不是才吃过？'), isFalse);
  });

  test('注入当前角色的 CharacterProfile / Archive / 私人用户认知 / 群公开身份', () async {
    final a = character('a', 'a');
    final b = character('b', 'b');
    await CharacterRegistryService().saveCharacters([a, b]);
    await CharacterSettingsStorageService(characterId: 'a').saveSettings(
      CharacterSettings.genericDefaults().copyWith(characterName: 'a'),
    );

    await CharacterProfileStorageService(characterId: 'a').save(
      CharacterProfile(
        characterId: 'a',
        personalityTags: '沉稳',
        personalityDescription: 'A 的专属性格描述',
        speakingStyle: 'A 专属说话风格：短句',
        occupation: 'A 的职业',
      ),
    );
    await CharacterArchiveStorageService(characterId: 'a').save(
      CharacterArchive(
        characterId: 'a',
        values: const {'speakingStyle': 'A 的档案表达风格'},
      ),
    );
    await CharacterUserProfileStorageService(characterId: 'a').save(
      const CharacterUserProfile(
        characterId: 'a',
        userName: '念念',
        callName: '老婆',
        personaDescription: 'A 眼里的用户是妻子',
      ),
    );
    await CharacterUserProfileStorageService(characterId: 'b').save(
      const CharacterUserProfile(
        characterId: 'b',
        userName: '小念',
        personaDescription: 'B 眼里的用户只是同事',
      ),
    );
    await GroupUserProfileStorageService(groupId: 'group_ctx').save(
      const GroupUserProfile(
        groupId: 'group_ctx',
        displayName: '群里的念念',
        selfDescription: '和大家认识很久的朋友',
      ),
    );

    final promptA = await promptFor(
      speaker: a,
      members: [a, b],
      messages: [message('m1', GroupSenderType.user, 'user', '晚上好', 0)],
    );
    expect(promptA.contains('A 的专属性格描述'), isTrue);
    expect(promptA.contains('A 专属说话风格：短句'), isTrue);
    expect(promptA.contains('A 的档案表达风格'), isTrue);
    expect(promptA.contains('群里的念念'), isTrue);
    expect(promptA.contains('和大家认识很久的朋友'), isTrue);
    expect(promptA.contains('A 眼里的用户是妻子'), isTrue);
    // 不读取其他角色的私人用户认知
    expect(promptA.contains('B 眼里的用户只是同事'), isFalse);

    final promptB = await promptFor(
      speaker: b,
      members: [a, b],
      messages: [message('m1', GroupSenderType.user, 'user', '晚上好', 0)],
    );
    expect(promptB.contains('B 眼里的用户只是同事'), isTrue);
    expect(promptB.contains('A 眼里的用户是妻子'), isFalse);
    expect(promptB.contains('A 的专属性格描述'), isFalse);
  });

  test('关系层保持中性，不自动加入嫉妒/争抢/敌对规则', () async {
    final a = character('a', 'a');
    final b = character('b', 'b');
    await CharacterRegistryService().saveCharacters([a, b]);
    await CharacterSettingsStorageService(characterId: 'a').saveSettings(
      CharacterSettings.genericDefaults().copyWith(
        characterName: 'a',
        relation: '恋人',
      ),
    );
    await CharacterSettingsStorageService(characterId: 'b').saveSettings(
      CharacterSettings.genericDefaults().copyWith(
        characterName: 'b',
        relation: '伴侣',
      ),
    );
    await GroupUserProfileStorageService(
      groupId: 'group_ctx',
    ).save(const GroupUserProfile(groupId: 'group_ctx', displayName: '念念'));

    final prompt = await promptFor(
      speaker: a,
      members: [a, b],
      messages: [message('m1', GroupSenderType.user, 'user', '在吗', 0)],
    );
    expect(prompt.contains('你与用户的关系：恋人'), isTrue);
    // 关系数据本身不制造竞争语义
    expect(prompt.contains('同一时间只选择'), isFalse);
    expect(prompt.contains('没有人比你更重要'), isFalse);
    expect(prompt.contains('排他'), isFalse);
  });
}
