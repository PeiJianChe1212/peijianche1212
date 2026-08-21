import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peijianche_app/models/api_settings.dart';
import 'package:peijianche_app/services/model_discovery_service.dart';

void main() {
  test('custom discovery uses normalized models URL and parses models', () async {
    late Uri requestedUri;
    late String authorization;
    final service = ModelDiscoveryService(
      client: MockClient((request) async {
        requestedUri = request.url;
        authorization = request.headers['authorization'] ?? '';
        return http.Response(
          '{"data":[{"id":"chat-b"},{"id":"text-embedding-3-small"},{"id":"chat-a"}]}',
          200,
        );
      }),
    );

    final models = await service.discover(
      provider: AIProvider.custom,
      apiKey: 'secret-test-key',
      baseUrl: 'https://example.com/v1/chat/completions',
    );

    expect(requestedUri.toString(), 'https://example.com/v1/models');
    expect(authorization, 'Bearer secret-test-key');
    expect(models.map((model) => model.id), ['chat-a', 'chat-b']);
  });

  test('cache is scoped by provider, URL, and API key', () async {
    var calls = 0;
    final service = ModelDiscoveryService(
      client: MockClient((request) async {
        calls++;
        return http.Response('{"data":[{"id":"chat-model"}]}', 200);
      }),
    );

    for (var index = 0; index < 2; index++) {
      await service.discover(
        provider: AIProvider.custom,
        apiKey: 'key-a',
        baseUrl: 'https://example.com/v1',
      );
    }
    await service.discover(
      provider: AIProvider.custom,
      apiKey: 'key-b',
      baseUrl: 'https://example.com/v1',
    );
    expect(calls, 2);
  });

  test('DeepSeek falls back when models endpoint fails', () async {
    final service = ModelDiscoveryService(
      client: MockClient((request) async => http.Response('unavailable', 503)),
    );
    final models = await service.discover(
      provider: AIProvider.deepseek,
      apiKey: 'not-logged',
      baseUrl: AIProvider.deepseek.officialBaseUrl,
    );
    expect(models.map((model) => model.id), [
      'deepseek-chat',
      'deepseek-reasoner',
    ]);
  });

  test('Volcengine preserves manual Endpoint ID fallback', () async {
    final service = ModelDiscoveryService(
      client: MockClient((request) async => http.Response('{}', 200)),
    );
    expect(
      () => service.discover(
        provider: AIProvider.volcengine,
        apiKey: 'secret',
        baseUrl: AIProvider.volcengine.officialBaseUrl,
      ),
      throwsA(
        isA<ModelDiscoveryException>().having(
          (error) => error.kind,
          'kind',
          ModelDiscoveryErrorKind.unsupported,
        ),
      ),
    );
  });

  test('errors never include the API key', () async {
    const apiKey = 'never-print-this-key';
    final service = ModelDiscoveryService(
      client: MockClient((request) async => http.Response('denied', 401)),
    );
    try {
      await service.discover(
        provider: AIProvider.openai,
        apiKey: apiKey,
        baseUrl: AIProvider.openai.officialBaseUrl,
      );
      fail('expected an error');
    } on ModelDiscoveryException catch (error) {
      expect(error.toString(), isNot(contains(apiKey)));
    }
  });
}
