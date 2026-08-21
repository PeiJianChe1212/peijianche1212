import 'dart:typed_data';

abstract class VisionAdapter {
  String get adapterName;

  Future<String> understandImageBytes({
    required Uint8List bytes,
    required String mimeType,
    required String instruction,
    String? systemPrompt,
    int maxTokens = 900,
  });

  Future<String> understandImagePath({
    required String imagePath,
    required String instruction,
    String? systemPrompt,
    int maxTokens = 900,
  });
}

enum VisionErrorKind {
  invalidApiKey,
  permissionDenied,
  modelUnavailable,
  unsupportedImageInput,
  incompatibleProtocol,
  networkUnavailable,
  timeout,
  invalidImage,
  requestFailed,
}

class VisionException implements Exception {
  const VisionException(this.kind, this.userMessage);

  final VisionErrorKind kind;
  final String userMessage;

  @override
  String toString() => userMessage;
}
