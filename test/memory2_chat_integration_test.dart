import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_retrieval_result.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/services/api_settings_storage_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/deepseek_service.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/services/user_profile_storage_service.dart';

class _FakeRetriever implements Memory2RetrieverGateway {
  _FakeRetriever(this.result, {this.throwOnRecall = false});

  final MemoryRetrievalResult result;
  final bool throwOnRecall;
  final List<String> recalled = <String>[];

  @override
  Future<MemoryRetrievalResult> retrieve({
    required String currentMessage,
    List<ChatMessage> recentMessages = const [],
    required DateTime now,
  }) async => result;

  @override
  Future<void> recordInjectedEvents(
    Iterable<String> eventIds, {
    required DateTime now,
  }) async {
    recalled.addAll(eventIds);
    if (throwOnRecall) throw StateError('fake recall write failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('memory2_chat_');
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
    await UserProfileStorageService().saveProfile(
      const UserProfile(identity: '全局资料认为用户来自北方'),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test(
    'formal single-chat request contains Memory2 and hard user profile',
    () async {
      late Map<String, dynamic> requestBody;
      final event = EventMemory(
        id: 'event-1',
        characterId: 'role-a',
        content: '用户曾给角色看过蓝色裙子',
      );
      final retriever = _FakeRetriever(
        MemoryRetrievalResult(
          selectedEventMemories: [event],
          memorySummary: const MemorySummary(characterId: 'role-a'),
          contextText:
              '【关于用户的记忆】\n- 用户来自南方\n\n'
              '【相关共同经历】\n- 用户曾给角色看过蓝色裙子',
          diagnostics: const MemoryRetrievalDiagnostics(
            eventCandidates: 1,
            userCandidates: 0,
            legacyCandidates: 0,
            recallIntent: true,
            lifecycleRefreshSucceeded: true,
          ),
        ),
        throwOnRecall: true,
      );
      final service = DeepSeekService(
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '当然记得，那条蓝色裙子很适合你。'},
                  },
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        memory2RetrieverFactory: (_) => retriever,
        characterUserProfileLoader: (_) async => const CharacterUserProfile(
          characterId: 'role-a',
          personaDescription: '用户明确设定自己来自海边小城',
        ),
      );
      addTearDown(service.dispose);

      final reply = await service.sendMessage(
        messages: [ChatMessage(role: 'user', content: '还记得那条裙子吗？')],
        conversationMode: 'basic',
        temperature: 0.7,
        replyLength: 'standard',
        initiative: 0.5,
        intimacy: 0.5,
        tsundere: 0.5,
        characterId: 'role-a',
      );

      final messages = requestBody['messages'] as List;
      final system = (messages.first as Map)['content'].toString();
      expect(reply, contains('蓝色裙子'));
      expect(system, contains('【Memory 2.0｜仅作为已知事实，不得扩写】'));
      expect(system, contains('用户曾给角色看过蓝色裙子'));
      expect(system, contains('全局资料认为用户来自北方'));
      expect(system, contains('用户来自南方'));
      expect(system, contains('用户明确设定自己来自海边小城'));
      expect(
        system.indexOf('全局资料认为用户来自北方'),
        lessThan(system.indexOf('用户来自南方')),
      );
      expect(
        system.indexOf('用户来自南方'),
        lessThan(system.indexOf('用户明确设定自己来自海边小城')),
      );
      expect(system, isNot(contains('角色对用户的称呼：未填写')));
      for (
        var attempt = 0;
        attempt < 100 && retriever.recalled.isEmpty;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(retriever.recalled, ['event-1']);
    },
  );

  test(
    'empty Memory2 result keeps formal chat working without empty headings',
    () async {
      late String systemPrompt;
      final retriever = _FakeRetriever(
        MemoryRetrievalResult(
          memorySummary: const MemorySummary(characterId: 'role-a'),
          diagnostics: const MemoryRetrievalDiagnostics(
            eventCandidates: 0,
            userCandidates: 0,
            legacyCandidates: 0,
            recallIntent: false,
            lifecycleRefreshSucceeded: true,
          ),
        ),
      );
      final service = DeepSeekService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          final messages = body['messages'] as List;
          systemPrompt = (messages.first as Map)['content'].toString();
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '我在，怎么了？'},
                  },
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        memory2RetrieverFactory: (_) => retriever,
        characterUserProfileLoader: (_) async =>
            const CharacterUserProfile(characterId: 'role-a'),
      );
      addTearDown(service.dispose);

      expect(
        await service.sendMessage(
          messages: [ChatMessage(role: 'user', content: '在吗？')],
          conversationMode: 'basic',
          temperature: 0.7,
          replyLength: 'standard',
          initiative: 0.5,
          intimacy: 0.5,
          tsundere: 0.5,
          characterId: 'role-a',
        ),
        isNotEmpty,
      );
      expect(systemPrompt, isNot(contains('【Memory 2.0')));
      expect(systemPrompt, isNot(contains('【长期记忆汇总】')));
    },
  );
}
