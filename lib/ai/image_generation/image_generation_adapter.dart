import 'dart:typed_data';

class GeneratedImagePayload {
  const GeneratedImagePayload({this.url, this.bytes, this.revisedPrompt});

  final String? url;
  final Uint8List? bytes;
  final String? revisedPrompt;

  bool get isValid =>
      (url?.trim().isNotEmpty ?? false) || (bytes?.isNotEmpty ?? false);
}

abstract class ImageGenerationAdapter {
  String get adapterName;

  Future<GeneratedImagePayload> generate({
    required String prompt,
    int width = 1024,
    int height = 1024,
  });
}

enum ImageGenerationErrorKind {
  invalidApiKey,
  modelUnavailable,
  unsupportedGeneration,
  incompatibleProtocol,
  networkUnavailable,
  timeout,
  invalidResult,
  requestFailed,
}

class ImageGenerationException implements Exception {
  const ImageGenerationException(this.kind, this.userMessage);

  final ImageGenerationErrorKind kind;
  final String userMessage;

  @override
  String toString() => userMessage;
}
