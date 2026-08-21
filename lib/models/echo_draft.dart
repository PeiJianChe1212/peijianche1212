import 'echo_image_intent.dart';

class EchoDraft {
  const EchoDraft({
    required this.content,
    required this.momentSummary,
    required this.shouldAttachImage,
    required this.imageScene,
    required this.imagePrompt,
    required this.imageIntent,
  });

  final String content;
  final String momentSummary;
  final bool shouldAttachImage;
  final String imageScene;
  final String imagePrompt;
  final EchoImageIntent imageIntent;
}
