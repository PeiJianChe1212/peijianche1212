import '../ai/image_generation/image_generation_adapter.dart';
import '../models/api_settings.dart';
import '../models/image_generation_settings.dart';
import '../models/vision_settings.dart';
import 'image_generation_router.dart';

class ImageGenerationCapabilityTestService {
  ImageGenerationCapabilityTestService({ImageGenerationRouter? router})
    : _router = router ?? ImageGenerationRouter();

  final ImageGenerationRouter _router;

  Future<GeneratedImagePayload> test({
    required ImageGenerationSettings settings,
    required ApiSettings chatSettings,
    required VisionSettings visionSettings,
  }) {
    final adapter = _router.resolve(
      settings: settings,
      chatSettings: chatSettings,
      visionSettings: visionSettings,
    );
    return adapter.generate(prompt: '一颗蓝色圆球，纯白背景。', width: 1024, height: 1024);
  }
}
