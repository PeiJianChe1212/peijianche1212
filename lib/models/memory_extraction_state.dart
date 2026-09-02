class MemoryExtractionState {
  const MemoryExtractionState({
    required this.characterId,
    this.lastProcessedMessageId,
    this.lastProcessedAt,
    this.lastSuccessfulExtractionAt,
    this.lastFailureAt,
    this.lastFailedMessageId,
  });

  final String characterId;
  final String? lastProcessedMessageId;
  final DateTime? lastProcessedAt;
  final DateTime? lastSuccessfulExtractionAt;
  final DateTime? lastFailureAt;
  final String? lastFailedMessageId;

  MemoryExtractionState copyWith({
    String? lastProcessedMessageId,
    DateTime? lastProcessedAt,
    DateTime? lastSuccessfulExtractionAt,
    DateTime? lastFailureAt,
    String? lastFailedMessageId,
    bool clearFailure = false,
  }) => MemoryExtractionState(
    characterId: characterId,
    lastProcessedMessageId:
        lastProcessedMessageId ?? this.lastProcessedMessageId,
    lastProcessedAt: lastProcessedAt ?? this.lastProcessedAt,
    lastSuccessfulExtractionAt:
        lastSuccessfulExtractionAt ?? this.lastSuccessfulExtractionAt,
    lastFailureAt: clearFailure ? null : lastFailureAt ?? this.lastFailureAt,
    lastFailedMessageId: clearFailure
        ? null
        : lastFailedMessageId ?? this.lastFailedMessageId,
  );

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'lastProcessedMessageId': lastProcessedMessageId,
    'lastProcessedAt': lastProcessedAt?.toIso8601String(),
    'lastSuccessfulExtractionAt': lastSuccessfulExtractionAt
        ?.toIso8601String(),
    'lastFailureAt': lastFailureAt?.toIso8601String(),
    'lastFailedMessageId': lastFailedMessageId,
  };

  factory MemoryExtractionState.fromJson(
    Map<dynamic, dynamic> json, {
    required String characterId,
  }) => MemoryExtractionState(
    characterId: characterId,
    lastProcessedMessageId: _nullableText(json['lastProcessedMessageId']),
    lastProcessedAt: _date(json['lastProcessedAt']),
    lastSuccessfulExtractionAt: _date(json['lastSuccessfulExtractionAt']),
    lastFailureAt: _date(json['lastFailureAt']),
    lastFailedMessageId: _nullableText(json['lastFailedMessageId']),
  );

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '');
}
