import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/activity_status.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/services/api_settings_storage_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/character_user_profile_storage_service.dart';
import 'package:peijianche_app/services/deepseek_service.dart';
import 'package:peijianche_app/services/proactive_message_generation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('profile_ctx_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => documents.path);
    FlutterSecureStorage.setMockInitialValues({});
    await ApiSettingsStorageService().saveSettings(
      const ApiSettings(
        provider: AIProvider.custom,
        apiKey: 'fake-key',
        baseUrl: 'https://example.invalid/v1/chat/completions',
        model: 'fake-model',
      ),
    );
    await CharacterRegistryService().saveAllCharacters([
      AiCharacter(
        id: 'role-a',
        characterName: '测试角色',
        remark: '',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await CharacterRegistryService().setActiveCharacter('role-a');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('主动消息注入当前角色的 CharacterUserProfile', () async {
    await CharacterUserProfileStorageService(characterId: 'role-a').save(
      const CharacterUserProfile(
        characterId: 'role-a',
        userName: '主动消息用户',
        gender: '女',
        personaDescription: '只有这个角色知道用户喜欢深夜写作。',
      ),
    );

    late String systemPrompt;
    final service = ProactiveMessageGenerationService(
      characterId: 'role-a',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final messages = body['messages'] as List;
        systemPrompt = (messages.first as Map)['content'].toString();
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {'message': {'content': '这么晚还在写吗？记得休息。'}},
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final settings = await CharacterSettingsStorageService(
      characterId: 'role-a',
    ).loadSettings();

    final result = await service.generate(
      settings: settings,
      activity: const ActivityStatus(
        id: 'working',
        label: '工作中',
        emoji: '',
        detail: '在写代码',
        promptGuidance: '',
      ),
      now: DateTime(2026, 9, 11, 22, 0),
      slot: '夜间',
      messages: const [],
      recentProactiveMessages: const [],
      fallbackMessage: '在吗？',
    );

    expect(result.content, isNotEmpty);
    expect(systemPrompt, contains('用户姓名：主动消息用户'));
    expect(systemPrompt, contains('性别：女'));
    expect(systemPrompt, contains('只有这个角色知道用户喜欢深夜写作。'));
  });

  test('图片随图消息注入当前角色的 CharacterUserProfile', () async {
    late String systemPrompt;
    final service = DeepSeekService(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final messages = body['messages'] as List;
        systemPrompt = (messages.first as Map)['content'].toString();
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {'message': {'content': '给你画了一只猫。'}},
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      characterUserProfileLoader: (id) async => const CharacterUserProfile(
        characterId: 'role-a',
        userName: '图片消息用户',
        gender: '男',
        personaDescription: '这个角色知道用户养了一只橘猫。',
      ),
    );
    addTearDown(service.dispose);

    final caption = await service.composeImageMessage(
      userRequest: '画一只猫',
      characterId: 'role-a',
    );

    expect(caption, isNotEmpty);
    expect(systemPrompt, contains('用户姓名：图片消息用户'));
    expect(systemPrompt, contains('性别：男'));
    expect(systemPrompt, contains('这个角色知道用户养了一只橘猫。'));
  });

  test('图片随图消息不传 characterId 时回退到活跃角色', () async {
    late String systemPrompt;
    final service = DeepSeekService(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final messages = body['messages'] as List;
        systemPrompt = (messages.first as Map)['content'].toString();
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {'message': {'content': '给你。'}},
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      characterUserProfileLoader: (id) async {
        expect(id, 'role-a');
        return const CharacterUserProfile(
          characterId: 'role-a',
          userName: '活跃角色用户',
          personaDescription: '活跃角色的设定。',
        );
      },
    );
    addTearDown(service.dispose);

    await service.composeImageMessage(userRequest: '画点东西');
    expect(systemPrompt, contains('活跃角色用户'));
  });
}
