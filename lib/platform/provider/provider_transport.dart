import 'dart:typed_data';

class ProviderTransportResponse {
  const ProviderTransportResponse({
    required this.statusCode,
    required this.bodyBytes,
  });
  final int statusCode;
  final Uint8List bodyBytes;
}

abstract interface class ProviderTransport {
  Future<ProviderTransportResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    required Duration timeout,
  });
}
