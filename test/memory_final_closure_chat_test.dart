import 'dart:async';
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
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_retrieval_result.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/services/api_settings_storage_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/deepseek_service.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/ai/providers/openai_compatible_chat_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('memory_final_closure_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => documents.path);
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
        id: 'role-final',
        characterName: '测试角色',
        remark: '',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await CharacterRegistryService().setActiveCharacter('role-final');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('retriever failure still sends one normal provider request', () async {
    var requests = 0;
    final service = DeepSeekService(
      client: MockClient((request) async {
        requests++;
        return _response('正常回复');
      }),
      memory2RetrieverFactory: (_) => _ThrowingRetriever(),
    );
    addTearDown(service.dispose);

    expect(await _send(service), '正常回复');
    expect(requests, 1);
  });

  test('recall persistence that never completes does not block chat', () async {
    final recallGate = Completer<void>();
    var requests = 0;
    late _HangingRecallRetriever retriever;
    final service = DeepSeekService(
      client: MockClient((request) async {
        requests++;
        return _response('记得');
      }),
      memory2RetrieverFactory: (_) {
        retriever = _HangingRecallRetriever(recallGate);
        return retriever;
      },
    );
    addTearDown(() {
      if (!recallGate.isCompleted) recallGate.complete();
      service.dispose();
    });

    expect(await _send(service), '记得');
    expect(requests, 1);
    expect(retriever.recordCalls, 1);
    expect(retriever.capturedIds, contains('event-final'));
  });

  test('empty content with reasoning and length finish reason fails in provider',
      () async {
    var requests = 0;
    final service = DeepSeekService(
      client: MockClient((request) async {
        requests++;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {'content': '', 'reasoning_content': '内部推理'},
                'finish_reason': 'length',
              },
            ],
          })),
          200,
        );
      }),
    );
    addTearDown(service.dispose);

    await expectLater(
      _send(service),
      throwsA(isA<ChatEmptyResponseException>()),
    );
    expect(requests, 1);
  });

  test('malformed JSON and HTTP errors reach caller without fake reply', () async {
    var malformedRequests = 0;
    final malformed = DeepSeekService(
      client: MockClient((request) async {
        malformedRequests++;
        return http.Response.bytes(utf8.encode('not-json'), 200);
      }),
    );
    addTearDown(malformed.dispose);
    await expectLater(
      _send(malformed),
      throwsA(isA<FormatException>()),
    );
    expect(malformedRequests, 1);

    var failedRequests = 0;
    final failed = DeepSeekService(
      client: MockClient((request) async {
        failedRequests++;
        return http.Response.bytes(utf8.encode('{"error":"no"}'), 503);
      }),
    );
    addTearDown(failed.dispose);
    await expectLater(_send(failed), throwsA(isA<Exception>()));
    expect(failedRequests, 1);
  });
}

Future<String> _send(DeepSeekService service) => service.sendMessage(
      messages: [ChatMessage(role: 'user', content: '你好')],
      conversationMode: 'basic',
      temperature: 0.7,
      replyLength: 'standard',
      initiative: 0.5,
      intimacy: 0.5,
      tsundere: 0.5,
      characterId: 'role-final',
    );

http.Response _response(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      })),
      200,
    );

class _ThrowingRetriever implements Memory2RetrieverGateway {
  @override
  Future<MemoryRetrievalResult> retrieve({
    required String currentMessage,
    List<ChatMessage> recentMessages = const [],
    required DateTime now,
  }) async => throw StateError('retriever failed');

  @override
  Future<void> recordInjectedEvents(
    Iterable<String> eventIds, {
    required DateTime now,
  }) async {}
}

class _HangingRecallRetriever implements Memory2RetrieverGateway {
  _HangingRecallRetriever(this.gate);
  final Completer<void> gate;
  int recordCalls = 0;
  final List<String> capturedIds = <String>[];

  @override
  Future<MemoryRetrievalResult> retrieve({
    required String currentMessage,
    List<ChatMessage> recentMessages = const [],
    required DateTime now,
  }) async => MemoryRetrievalResult(
        selectedEventMemories: [
          EventMemory(
            id: 'event-final',
            characterId: 'role-final',
            content: '封板测试事件',
          ),
        ],
        memorySummary: const MemorySummary(characterId: 'role-final'),
        contextText: '【共同经历】\n- 封板测试事件',
        diagnostics: const MemoryRetrievalDiagnostics(
          eventCandidates: 1,
          userCandidates: 0,
          legacyCandidates: 0,
          recallIntent: true,
          lifecycleRefreshSucceeded: true,
        ),
      );

  @override
  Future<void> recordInjectedEvents(
    Iterable<String> eventIds, {
    required DateTime now,
  }) {
    recordCalls++;
    capturedIds.addAll(eventIds);
    return gate.future;
  }
}
