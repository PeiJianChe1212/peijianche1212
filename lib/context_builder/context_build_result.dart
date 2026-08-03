class ContextBuildResult {
  const ContextBuildResult({
    required this.messages,
    required this.systemPrompt,
  });

  final List<Map<String, dynamic>> messages;
  final String systemPrompt;
}
