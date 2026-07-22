import 'ai_model_provider.dart';

class GeneratedImage {
  const GeneratedImage({
    required this.url,
    this.revisedPrompt,
  });

  final String url;
  final String? revisedPrompt;
}

abstract class ImageModelProvider extends AiModelProvider {
  Future<GeneratedImage> generate({
    required String prompt,
    String? negativePrompt,
    int width = 1024,
    int height = 1024,
  });
}
