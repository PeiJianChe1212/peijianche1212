enum MemoryExtractionRawResponseShape {
  pureJson,
  fencedJson,
  wrappedJson,
  invalid,
}

class ExtractedEventMemory {
  const ExtractedEventMemory({
    required this.content,
    this.sourceMessageIds = const [],
    this.occurredAt,
  });

  final String content;
  final List<String> sourceMessageIds;
  final DateTime? occurredAt;
}

class ExtractedUserMemory {
  const ExtractedUserMemory({
    required this.key,
    required this.value,
    this.sourceMessageIds = const [],
  });

  final String key;
  final String value;
  final List<String> sourceMessageIds;
}

class MemoryExtractionResult {
  const MemoryExtractionResult({
    this.eventMemories = const [],
    this.userMemories = const [],
    this.rawResponseShape,
    this.parseOutcome,
  });

  final List<ExtractedEventMemory> eventMemories;
  final List<ExtractedUserMemory> userMemories;
  final MemoryExtractionRawResponseShape? rawResponseShape;
  final String? parseOutcome;
}

class MemoryExtractionParseException implements Exception {
  const MemoryExtractionParseException(this.message, {required this.shape});

  final String message;
  final MemoryExtractionRawResponseShape shape;

  @override
  String toString() => 'MemoryExtractionParseException: $message';
}
