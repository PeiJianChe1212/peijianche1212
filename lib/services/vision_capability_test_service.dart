import 'dart:convert';
import 'dart:typed_data';

import '../models/api_settings.dart';
import '../models/vision_settings.dart';
import 'vision_router.dart';

class VisionCapabilityTestService {
  VisionCapabilityTestService({VisionRouter? router})
    : _router = router ?? VisionRouter();

  final VisionRouter _router;

  // A normal-sized local PNG avoids providers rejecting a tiny placeholder
  // before the request reaches the model's actual image-input capability.
  static final Uint8List testImageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACQSURBVHhe7dChEQAwDIDA7r9u7ypi0gXYAMQbJOfdWbMGUDRpAEWTBlA0aQBFkwZQNGkARZMGUDRpAEWTBlA0aQBFkwZQNGkARZMGUDRpAEWTBlA0aQBFkwZQNGkARZMGUDRpAEWTBlA0aQBFkwZQNGkARZMGUDRpAEWTBlA0aQBFkwZQNGkARZMGUDSRD5j9J4gjowbsZHIAAAAASUVORK5CYII=',
  );

  Future<String> test({
    required VisionSettings visionSettings,
    required ApiSettings chatSettings,
  }) async {
    final adapter = _router.resolve(
      visionSettings: visionSettings,
      chatSettings: chatSettings,
    );
    return adapter.understandImageBytes(
      bytes: testImageBytes,
      mimeType: 'image/png',
      instruction: '请简短描述图片中的主要内容。',
      maxTokens: 80,
    );
  }
}
