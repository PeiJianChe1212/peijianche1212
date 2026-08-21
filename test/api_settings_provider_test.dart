import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/api_settings_form_state.dart';
import 'package:peijianche_app/ai/model_hub.dart';
import 'package:peijianche_app/ai/providers/openai_compatible_chat_provider.dart';

void main() {
  test('OpenAI base URL resolves to chat completions endpoint', () {
    const settings = ApiSettings(
      provider: AIProvider.openai,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5-mini',
    );
    expect(
      settings.chatCompletionsUrl,
      'https://api.openai.com/v1/chat/completions',
    );
  });

  test('custom provider preserves its complete endpoint', () {
    const settings = ApiSettings(
      provider: AIProvider.custom,
      baseUrl: 'http://localhost:1234/v1/chat/completions',
      model: 'local-model',
    );
    expect(settings.chatCompletionsUrl, settings.baseUrl);
  });

  test('DeepSeek official base URL resolves to chat completions endpoint', () {
    const settings = ApiSettings(
      provider: AIProvider.deepseek,
      baseUrl: 'https://api.deepseek.com/v1',
    );
    expect(
      settings.chatCompletionsUrl,
      'https://api.deepseek.com/v1/chat/completions',
    );
  });

  test('models URL normalizes compatible endpoint variants', () {
    expect(
      ApiEndpointResolver.modelsUrl('https://example.com/v1'),
      'https://example.com/v1/models',
    );
    expect(
      ApiEndpointResolver.modelsUrl('https://example.com/v1/chat/completions/'),
      'https://example.com/v1/models',
    );
    expect(
      ApiEndpointResolver.modelsUrl('https://example.com/v1/responses'),
      'https://example.com/v1/models',
    );
    expect(
      ApiEndpointResolver.modelsUrl('https://example.com/v1/models'),
      'https://example.com/v1/models',
    );
  });

  test('legacy provider labels migrate to enum values', () {
    expect(AIProviderDetails.fromStored('豆包 / 火山方舟'), AIProvider.volcengine);
    expect(AIProviderDetails.fromStored('OpenAI'), AIProvider.openai);
  });

  test('provider drafts remain isolated while switching providers', () {
    final drafts = ProviderDraftStore()
      ..save(
        AIProvider.openai,
        const ProviderSettingsDraft(
          apiKey: 'openai-key',
          baseUrl: 'https://api.openai.com/v1',
          model: 'openai-model',
        ),
      )
      ..save(
        AIProvider.custom,
        const ProviderSettingsDraft(
          apiKey: 'custom-key',
          baseUrl: 'https://relay.example/v1',
          model: 'relay-model',
        ),
      );

    expect(drafts.forProvider(AIProvider.openai)?.apiKey, 'openai-key');
    expect(drafts.forProvider(AIProvider.custom)?.model, 'relay-model');
  });

  test('quick configuration excludes custom and Volcengine discovery', () {
    expect(quickApiProviders, [
      AIProvider.deepseek,
      AIProvider.openai,
      AIProvider.volcengine,
    ]);
    expect(AIProvider.custom.isQuickProvider, isFalse);
    expect(AIProvider.deepseek.supportsModelDiscovery, isTrue);
    expect(AIProvider.openai.supportsModelDiscovery, isTrue);
    expect(AIProvider.volcengine.supportsModelDiscovery, isFalse);
    expect(AIProvider.volcengine.requiresEndpointId, isTrue);
  });

  test(
    'ModelHub uses the exact settings supplied by the current request',
    () async {
      const settings = ApiSettings(
        provider: AIProvider.volcengine,
        apiKey: 'test-key',
        baseUrl: 'https://example.invalid/chat/completions',
        model: 'request-scoped-model',
      );

      final provider = await ModelHub().chatProvider(settings: settings);
      expect(provider, isA<OpenAiCompatibleChatProvider>());
      final compatible = provider as OpenAiCompatibleChatProvider;
      expect(compatible.settings.provider, AIProvider.volcengine);
      expect(compatible.settings.model, 'request-scoped-model');
    },
  );

  test('Chat provider errors never expose the API key', () async {
    const key = 'never-log-chat-key';
    final provider = OpenAiCompatibleChatProvider(
      settings: const ApiSettings(
        provider: AIProvider.custom,
        apiKey: key,
        baseUrl: 'https://relay.example/v1',
        model: 'custom-model',
      ),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'authorization rejected for $key'},
          }),
          400,
        ),
      ),
    );
    await expectLater(
      provider.complete(
        messages: const [
          {'role': 'user', 'content': 'test'},
        ],
        temperature: 0,
        maxTokens: 10,
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          allOf(isNot(contains(key)), contains('••••')),
        ),
      ),
    );
  });

  test('compatible provider reads segmented message content', () async {
    final provider = OpenAiCompatibleChatProvider(
      settings: const ApiSettings(
        provider: AIProvider.deepseek,
        apiKey: 'test-key',
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'deepseek-chat',
      ),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': [
                    {'type': 'text', 'text': '{"shouldShare":true}'},
                  ],
                },
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
        ),
      ),
    );

    final result = await provider.complete(
      messages: const [
        {'role': 'user', 'content': 'test'},
      ],
      temperature: 0,
      maxTokens: 100,
    );

    expect(result, '{"shouldShare":true}');
  });

  test(
    'reasoning without final content is classified as an empty response',
    () async {
      final provider = OpenAiCompatibleChatProvider(
        settings: const ApiSettings(
          provider: AIProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-reasoner',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': null,
                    'reasoning_content': 'internal reasoning only',
                  },
                  'finish_reason': 'length',
                },
              ],
            }),
            200,
          ),
        ),
      );

      await expectLater(
        provider.complete(
          messages: const [
            {'role': 'user', 'content': 'test'},
          ],
          temperature: 0,
          maxTokens: 100,
        ),
        throwsA(
          isA<ChatEmptyResponseException>()
              .having((error) => error.finishReason, 'finish reason', 'length')
              .having(
                (error) => error.hasReasoningContent,
                'reasoning presence',
                isTrue,
              ),
        ),
      );
    },
  );

  test(
    'structured calls may recover complete JSON from reasoning content',
    () async {
      final provider = OpenAiCompatibleChatProvider(
        settings: const ApiSettings(
          provider: AIProvider.deepseek,
          apiKey: 'test-key',
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-reasoner',
        ),
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '',
                      'reasoning_content': '完成判断。\n{"shouldShare":false}',
                    },
                    'finish_reason': 'stop',
                  },
                ],
              }),
            ),
            200,
          ),
        ),
      );

      final result = await provider.complete(
        messages: const [
          {'role': 'user', 'content': 'test'},
        ],
        temperature: 0,
        maxTokens: 100,
        acceptStructuredReasoningFallback: true,
      );

      expect(result, '{"shouldShare":false}');
    },
  );
}
