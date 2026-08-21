import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/ai/image_generation/image_generation_adapter.dart';
import 'package:peijianche_app/ai/image_generation/openai_compatible_image_adapter.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/image_generation_settings.dart';
import 'package:peijianche_app/models/vision_settings.dart';
import 'package:peijianche_app/services/image_generation_capability_test_service.dart';
import 'package:peijianche_app/services/image_generation_router.dart';

void main() {
  const chat = ApiSettings(
    provider: AIProvider.openai,
    apiKey: 'chat-key',
    baseUrl: 'https://api.openai.com/v1',
    model: 'chat-model',
  );
  const vision = VisionSettings(
    usageMode: VisionUsageMode.separateVisionModel,
    provider: VisionProvider.openai,
    apiKey: 'vision-key',
    model: 'vision-model',
  );

  test('ImageGenerationSettings saves and restores', () {
    const settings = ImageGenerationSettings(
      provider: ImageGenerationProvider.openai,
      apiKey: 'image-key',
      baseUrl: 'https://api.openai.com/v1',
      model: 'image-model',
      capabilityStatus: ImageGenerationCapabilityStatus.supported,
    );
    final restored = ImageGenerationSettingsCodec.decode(
      ImageGenerationSettingsCodec.encode(settings),
      legacySettings: chat,
    );
    expect(restored.provider, ImageGenerationProvider.openai);
    expect(restored.apiKey, 'image-key');
    expect(restored.model, 'image-model');
    expect(
      restored.capabilityStatus,
      ImageGenerationCapabilityStatus.supported,
    );
  });

  test('legacy Volcengine image configuration migrates intact', () {
    const legacy = ApiSettings(
      apiKey: 'legacy-chat-key',
      imageApiKey: 'legacy-image-key',
      imageBaseUrl: 'https://ark.example/api/v3/images/generations',
      imageModel: 'ep-image',
    );
    final migrated = ImageGenerationSettingsCodec.decode(
      {},
      legacySettings: legacy,
    );
    expect(migrated.provider, ImageGenerationProvider.volcengine);
    expect(migrated.apiKey, 'legacy-image-key');
    expect(migrated.baseUrl, legacy.imageBaseUrl);
    expect(migrated.model, 'ep-image');
  });

  test(
    'Images endpoint normalization handles roots and complete endpoints',
    () {
      for (final value in [
        'https://example.com/v1',
        'https://example.com/v1/',
        'https://example.com/v1/images/generations',
        'https://example.com/v1/chat/completions',
        'https://example.com/v1/responses',
        'https://example.com/v1/models',
      ]) {
        expect(
          ImageGenerationEndpointResolver.generationsUrl(value),
          'https://example.com/v1/images/generations',
        );
      }
    },
  );

  test('manual model remains when discovery fails', () {
    const settings = ImageGenerationSettings(model: 'manual-image-model');
    const discoveryError = '模型列表获取失败';
    expect(discoveryError, isNotEmpty);
    expect(settings.model, 'manual-image-model');
  });

  test('independent image key ignores chat key changes', () {
    const settings = ImageGenerationSettings(apiKey: 'independent-image-key');
    expect(
      settings.effectiveApiKey(chatSettings: chat, visionSettings: vision),
      'independent-image-key',
    );
    expect(
      settings.effectiveApiKey(
        chatSettings: chat.copyWith(apiKey: 'new-chat-key'),
        visionSettings: vision,
      ),
      'independent-image-key',
    );
  });

  test('key references read the selected existing Provider key', () {
    const fromChat = ImageGenerationSettings(
      provider: ImageGenerationProvider.openai,
      apiKeySource: ImageApiKeySource.chat,
    );
    const fromVision = ImageGenerationSettings(
      provider: ImageGenerationProvider.openai,
      apiKeySource: ImageApiKeySource.vision,
    );
    expect(
      fromChat.effectiveApiKey(chatSettings: chat, visionSettings: vision),
      'chat-key',
    );
    expect(
      fromVision.effectiveApiKey(chatSettings: chat, visionSettings: vision),
      'vision-key',
    );
  });

  test('key reference never sends a key to a different Provider', () {
    const settings = ImageGenerationSettings(
      provider: ImageGenerationProvider.volcengine,
      apiKeySource: ImageApiKeySource.chat,
    );
    expect(
      settings.effectiveApiKey(chatSettings: chat, visionSettings: vision),
      isEmpty,
    );
  });

  test('Provider drafts can remain isolated', () {
    final drafts = <ImageGenerationProvider, ImageGenerationSettings>{
      ImageGenerationProvider.openai: const ImageGenerationSettings(
        provider: ImageGenerationProvider.openai,
        apiKey: 'openai-image-key',
        model: 'openai-image-model',
      ),
      ImageGenerationProvider.custom: const ImageGenerationSettings(
        provider: ImageGenerationProvider.custom,
        apiKey: 'custom-image-key',
        baseUrl: 'https://relay.example/v1',
        model: 'custom-image-model',
      ),
    };
    expect(drafts[ImageGenerationProvider.openai]?.apiKey, 'openai-image-key');
    expect(drafts[ImageGenerationProvider.custom]?.model, 'custom-image-model');
  });

  test('URL image result parses into common payload', () {
    final payload = OpenAiCompatibleImageAdapter.parseResponse(
      '{"data":[{"url":"https://cdn.example/image.png","revised_prompt":"clean"}]}',
    );
    expect(payload.url, 'https://cdn.example/image.png');
    expect(payload.bytes, isNull);
    expect(payload.revisedPrompt, 'clean');
  });

  test('Base64 image result parses into common payload', () {
    final payload = OpenAiCompatibleImageAdapter.parseResponse(
      jsonEncode({
        'data': [
          {
            'b64_json': base64Encode([1, 2, 3, 4]),
          },
        ],
      }),
    );
    expect(payload.url, isNull);
    expect(payload.bytes, Uint8List.fromList([1, 2, 3, 4]));
  });

  test('configuration changes can clear capability status', () {
    const settings = ImageGenerationSettings(
      model: 'old-model',
      capabilityStatus: ImageGenerationCapabilityStatus.supported,
    );
    final changed = settings.copyWith(
      model: 'new-model',
      clearCapabilityStatus: true,
    );
    expect(changed.capabilityStatus, ImageGenerationCapabilityStatus.untested);
  });

  test('Router selects adapter with normalized endpoint', () {
    late _FakeImageAdapter adapter;
    final router = ImageGenerationRouter(
      adapterFactory:
          ({
            required provider,
            required apiKey,
            required endpointUrl,
            required model,
          }) {
            adapter = _FakeImageAdapter(provider, apiKey, endpointUrl, model);
            return adapter;
          },
    );
    router.resolve(
      settings: const ImageGenerationSettings(
        provider: ImageGenerationProvider.custom,
        apiKey: 'custom-key',
        baseUrl: 'https://relay.example/v1/chat/completions',
        model: 'custom-model',
      ),
      chatSettings: chat,
      visionSettings: vision,
    );
    expect(adapter.provider, ImageGenerationProvider.custom);
    expect(adapter.endpointUrl, 'https://relay.example/v1/images/generations');
    expect(adapter.apiKey, 'custom-key');
  });

  test(
    'Capability test generates without accepting a chat record or directory',
    () async {
      final adapter = _FakeImageAdapter(
        ImageGenerationProvider.openai,
        'key',
        'url',
        'model',
      );
      final service = ImageGenerationCapabilityTestService(
        router: ImageGenerationRouter(
          adapterFactory:
              ({
                required provider,
                required apiKey,
                required endpointUrl,
                required model,
              }) => adapter,
        ),
      );
      final result = await service.test(
        settings: const ImageGenerationSettings(
          provider: ImageGenerationProvider.openai,
          apiKey: 'key',
          baseUrl: 'https://api.openai.com/v1',
          model: 'model',
        ),
        chatSettings: chat,
        visionSettings: vision,
      );
      expect(result.bytes, isNotEmpty);
      expect(adapter.lastPrompt, '一颗蓝色圆球，纯白背景。');
    },
  );

  test('API error never exposes the API key', () async {
    const key = 'never-expose-image-key';
    final adapter = OpenAiCompatibleImageAdapter(
      adapterName: 'test',
      apiKey: key,
      endpointUrl: 'https://example.test/v1/images/generations',
      model: 'image-model',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'invalid $key'},
          }),
          401,
        ),
      ),
    );
    expect(
      () => adapter.generate(prompt: 'test'),
      throwsA(
        isA<ImageGenerationException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(key)),
        ),
      ),
    );
  });
}

class _FakeImageAdapter implements ImageGenerationAdapter {
  _FakeImageAdapter(this.provider, this.apiKey, this.endpointUrl, this.model);

  final ImageGenerationProvider provider;
  final String apiKey;
  final String endpointUrl;
  final String model;
  String? lastPrompt;

  @override
  String get adapterName => provider.label;

  @override
  Future<GeneratedImagePayload> generate({
    required String prompt,
    int width = 1024,
    int height = 1024,
  }) async {
    lastPrompt = prompt;
    return GeneratedImagePayload(bytes: Uint8List.fromList([1, 2, 3]));
  }
}
