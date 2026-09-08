import 'package:http/http.dart' as http;

import 'provider_transport.dart';

class HttpProviderTransport implements ProviderTransport {
  HttpProviderTransport({http.Client? client})
    : client = client ?? http.Client(),
      ownsClient = client == null;

  final http.Client client;
  final bool ownsClient;

  @override
  Future<ProviderTransportResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    required Duration timeout,
  }) async {
    final response = await client
        .post(uri, headers: headers, body: body)
        .timeout(timeout);
    return ProviderTransportResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
    );
  }

  void dispose() {
    if (ownsClient) client.close();
  }
}
