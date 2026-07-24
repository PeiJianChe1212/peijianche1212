class EchoDraft {
  const EchoDraft({
    required this.content,
    required this.momentSummary,
    required this.shouldAttachImage,
    required this.imageScene,
  });

  final String content;
  final String momentSummary;
  final bool shouldAttachImage;
  final String imageScene;
}
