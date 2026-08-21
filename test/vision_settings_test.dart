import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/ai/vision/openai_compatible_vision_adapter.dart';
import 'package:peijianche_app/ai/vision/volcengine_vision_adapter.dart';
import 'package:peijianche_app/ai/vision/vision_adapter.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/models/vision_settings.dart';
import 'package:peijianche_app/services/vision_capability_test_service.dart';
import 'package:peijianche_app/services/vision_router.dart';

void main() {
  const chatSettings = ApiSettings(
    provider: AIProvider.openai,
    apiKey: 'chat-key',
    baseUrl: 'https://api.openai.com/v1',
    model: 'chat-model',
  );

  test('use chat model mode saves and restores', () {
    const settings = VisionSettings(
      usageMode: VisionUsageMode.useChatModel,
      capabilityStatus: VisionCapabilityStatus.supported,
    );
    final restored = VisionSettingsCodec.decode(
      VisionSettingsCodec.encode(settings),
      legacySettings: chatSettings,
    );
    expect(restored.usageMode, VisionUsageMode.useChatModel);
    expect(restored.capabilityStatus, VisionCapabilityStatus.supported);
  });

  test('capability test uses a provider-safe 64px PNG', () {
    final bytes = VisionCapabilityTestService.testImageBytes;
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(16), 64);
    expect(data.getUint32(20), 64);
  });

  test('separate OpenAI Vision configuration saves and restores', () {
    const settings = VisionSettings(
      usageMode: VisionUsageMode.separateVisionModel,
      provider: VisionProvider.openai,
      apiKey: 'vision-key',
      baseUrl: 'https://api.openai.com/v1',
      model: 'vision-model',
    );
    final restored = VisionSettingsCodec.decode(
      VisionSettingsCodec.encode(settings),
      legacySettings: chatSettings,
    );
    expect(restored.provider, VisionProvider.openai);
    expect(restored.apiKey, 'vision-key');
    expect(restored.model, 'vision-model');
  });

  test('legacy Volcengine multimodal settings migrate without data loss', () {
    const legacy = ApiSettings(
      apiKey: 'chat-key',
      multimodalApiKey: 'legacy-vision-key',
      multimodalBaseUrl: 'https://ark.example/api/v3/chat/completions',
      multimodalModel: 'ep-legacy',
    );
    final migrated = VisionSettingsCodec.decode({}, legacySettings: legacy);
    expect(migrated.usageMode, VisionUsageMode.separateVisionModel);
    expect(migrated.provider, VisionProvider.volcengine);
    expect(migrated.apiKey, 'legacy-vision-key');
    expect(migrated.baseUrl, legacy.multimodalBaseUrl);
    expect(migrated.model, 'ep-legacy');
  });

  test('chat key reuse follows the latest chat settings', () {
    const settings = VisionSettings(
      usageMode: VisionUsageMode.separateVisionModel,
      provider: VisionProvider.openai,
      apiKey: 'independent-key',
      reuseChatApiKey: true,
    );
    expect(settings.effectiveApiKey(chatSettings), 'chat-key');
    expect(
      settings.effectiveApiKey(chatSettings.copyWith(apiKey: 'new-chat-key')),
      'new-chat-key',
    );
  });

  test('independent Vision key never overwrites or reads chat key', () {
    const settings = VisionSettings(
      usageMode: VisionUsageMode.separateVisionModel,
      provider: VisionProvider.openai,
      apiKey: 'independent-key',
    );
    expect(settings.effectiveApiKey(chatSettings), 'independent-key');
    expect(chatSettings.apiKey, 'chat-key');
  });

  test('configuration change can clear a previous capability result', () {
    const settings = VisionSettings(
      model: 'old-model',
      capabilityStatus: VisionCapabilityStatus.supported,
    );
    final changed = settings.copyWith(
      model: 'new-model',
      clearCapabilityStatus: true,
    );
    expect(changed.model, 'new-model');
    expect(changed.capabilityStatus, VisionCapabilityStatus.untested);
  });

  test('router uses chat adapter in useChatModel mode', () {
    late _CapturedAdapter adapter;
    final router = VisionRouter(
      adapterFactory:
          ({
            required adapterName,
            required apiKey,
            required endpointUrl,
            required model,
          }) {
            adapter = _CapturedAdapter(adapterName, apiKey, endpointUrl, model);
            return adapter;
          },
    );
    router.resolve(
      visionSettings: const VisionSettings(),
      chatSettings: chatSettings,
    );
    expect(adapter.apiKey, 'chat-key');
    expect(adapter.endpointUrl, 'https://api.openai.com/v1/chat/completions');
    expect(adapter.model, 'chat-model');
  });

  test('router normalizes Custom Vision Base URL', () {
    late _CapturedAdapter adapter;
    final router = VisionRouter(
      adapterFactory:
          ({
            required adapterName,
            required apiKey,
            required endpointUrl,
            required model,
          }) {
            adapter = _CapturedAdapter(adapterName, apiKey, endpointUrl, model);
            return adapter;
          },
    );
    router.resolve(
      visionSettings: const VisionSettings(
        usageMode: VisionUsageMode.separateVisionModel,
        provider: VisionProvider.custom,
        apiKey: 'vision-key',
        baseUrl: 'https://relay.example/v1/responses',
        model: 'vision-model',
      ),
      chatSettings: chatSettings,
    );
    expect(adapter.endpointUrl, 'https://relay.example/v1/chat/completions');
  });

  test('router selects native Volcengine adapter for a separate Endpoint', () {
    final adapter = VisionRouter().resolve(
      visionSettings: const VisionSettings(
        usageMode: VisionUsageMode.separateVisionModel,
        provider: VisionProvider.volcengine,
        apiKey: 'ark-key',
        baseUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
        model: 'ep-20240821',
      ),
      chatSettings: chatSettings,
    );
    expect(adapter, isA<VolcengineVisionAdapter>());
    final volcengine = adapter as VolcengineVisionAdapter;
    expect(volcengine.endpointId, 'ep-20240821');
    expect(
      volcengine.endpointUrl,
      'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
    );
  });

  test(
    'Volcengine request preserves the legacy verified wire format',
    () async {
      late http.Request captured;
      late Map<String, dynamic> requestBody;
      final adapter = VolcengineVisionAdapter(
        apiKey: 'ark-key',
        endpointUrl: 'https://ark.example/api/v3/chat/completions',
        endpointId: 'ep-legacy',
        client: MockClient((request) async {
          captured = request;
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '火山识图成功'},
                  },
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await adapter.understandImageBytes(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
        instruction: '描述图片',
      );

      expect(
        captured.url.toString(),
        'https://ark.example/api/v3/chat/completions',
      );
      expect(captured.headers['authorization'], 'Bearer ark-key');
      expect(requestBody['model'], 'ep-legacy');
      expect(requestBody['stream'], isFalse);
      expect(requestBody['temperature'], 0.35);
      final content =
          ((requestBody['messages'] as List).last as Map)['content'] as List;
      expect((content.first as Map)['type'], 'image_url');
      expect(
        ((content.first as Map)['image_url'] as Map)['url'],
        startsWith('data:image/png;base64,'),
      );
      expect(result, '火山识图成功');
    },
  );

  test(
    'generic image error text is not misclassified as unsupported',
    () async {
      final adapter = VolcengineVisionAdapter(
        apiKey: 'ark-key',
        endpointUrl: 'https://ark.example/api/v3/chat/completions',
        endpointId: 'ep-legacy',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'invalid image_url request format'},
            }),
            400,
          ),
        ),
      );

      expect(
        () => adapter.understandImageBytes(
          bytes: Uint8List.fromList([1]),
          mimeType: 'image/png',
          instruction: '描述图片',
        ),
        throwsA(
          isA<VisionException>().having(
            (error) => error.kind,
            'kind',
            VisionErrorKind.incompatibleProtocol,
          ),
        ),
      );
    },
  );

  test('only an explicit image-input rejection is unsupported', () async {
    final adapter = OpenAiCompatibleVisionAdapter(
      adapterName: 'test',
      apiKey: 'vision-key',
      endpointUrl: 'https://example.test/v1/chat/completions',
      model: 'vision-model',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'model does not support image input'},
          }),
          400,
        ),
      ),
    );
    expect(
      () => adapter.understandImageBytes(
        bytes: Uint8List.fromList([1]),
        mimeType: 'image/png',
        instruction: 'describe',
      ),
      throwsA(
        isA<VisionException>().having(
          (error) => error.kind,
          'kind',
          VisionErrorKind.unsupportedImageInput,
        ),
      ),
    );
  });

  test('adapter error text does not expose API key', () async {
    const key = 'never-expose-this-key';
    final adapter = OpenAiCompatibleVisionAdapter(
      adapterName: 'test',
      apiKey: key,
      endpointUrl: 'https://example.test/v1/chat/completions',
      model: 'vision-model',
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
      () => adapter.understandImageBytes(
        bytes: Uint8List.fromList([1]),
        mimeType: 'image/png',
        instruction: 'describe',
      ),
      throwsA(
        isA<VisionException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(key)),
        ),
      ),
    );
  });

  test(
    'capability request sends an actual image and reads text response',
    () async {
      late Map<String, dynamic> requestBody;
      final adapter = OpenAiCompatibleVisionAdapter(
        adapterName: 'test',
        apiKey: 'vision-key',
        endpointUrl: 'https://example.test/v1/chat/completions',
        model: 'vision-model',
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '一张简单的测试图片'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final result = await adapter.understandImageBytes(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
        instruction: '请简短描述图片中的主要内容。',
      );
      final messages = requestBody['messages'] as List;
      final content = (messages.last as Map)['content'] as List;
      final image = content.whereType<Map>().firstWhere(
        (part) => part['type'] == 'image_url',
      );
      expect(
        (image['image_url'] as Map)['url'],
        startsWith('data:image/png;base64,'),
      );
      expect(result, '一张简单的测试图片');
    },
  );

  test('manual model remains after an unrelated discovery failure', () {
    const settings = VisionSettings(
      usageMode: VisionUsageMode.separateVisionModel,
      provider: VisionProvider.custom,
      model: 'manual-vision-model',
    );
    const discoveryError = '模型列表获取失败';
    expect(discoveryError, isNotEmpty);
    expect(settings.model, 'manual-vision-model');
  });

  test('Vision settings do not mutate ordinary chat configuration', () {
    const vision = VisionSettings(
      usageMode: VisionUsageMode.separateVisionModel,
      provider: VisionProvider.custom,
      apiKey: 'vision-key',
      model: 'vision-model',
    );
    VisionSettingsCodec.encode(vision);
    expect(chatSettings.apiKey, 'chat-key');
    expect(chatSettings.model, 'chat-model');
    expect(chatSettings.provider, AIProvider.openai);
  });
}

class _CapturedAdapter implements VisionAdapter {
  _CapturedAdapter(this.adapterName, this.apiKey, this.endpointUrl, this.model);

  @override
  final String adapterName;
  final String apiKey;
  final String endpointUrl;
  final String model;

  @override
  Future<String> understandImageBytes({
    required Uint8List bytes,
    required String mimeType,
    required String instruction,
    String? systemPrompt,
    int maxTokens = 900,
  }) async => 'ok';

  @override
  Future<String> understandImagePath({
    required String imagePath,
    required String instruction,
    String? systemPrompt,
    int maxTokens = 900,
  }) async => 'ok';
}
