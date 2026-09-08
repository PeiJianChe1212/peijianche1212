class MemoryExtractionState {
  const MemoryExtractionState({
    required this.characterId,
    this.lastProcessedMessageId,
    this.lastProcessedAt,
    this.lastSuccessfulExtractionAt,
    this.lastFailureAt,
    this.lastFailedMessageId,
    this.explicitAttempts = const {},
  });

  final String characterId;
  final String? lastProcessedMessageId;
  final DateTime? lastProcessedAt;
  final DateTime? lastSuccessfulExtractionAt;
  final DateTime? lastFailureAt;
  final String? lastFailedMessageId;
  // Per-source execution outcomes, not candidates or review records.
  final Map<String, String> explicitAttempts;

  MemoryExtractionState copyWith({
    String? lastProcessedMessageId,
    DateTime? lastProcessedAt,
    DateTime? lastSuccessfulExtractionAt,
    DateTime? lastFailureAt,
    String? lastFailedMessageId,
    bool clearFailure = false,
    Map<String, String>? explicitAttempts,
  }) => MemoryExtractionState(
    characterId: characterId,
    explicitAttempts: explicitAttempts ?? this.explicitAttempts,
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
    'explicitAttempts': explicitAttempts,
    'lastProcessedMessageId': lastProcessedMessageId,
    'lastProcessedAt': lastProcessedAt?.toIso8601String(),
    'lastSuccessfulExtractionAt': lastSuccessfulExtractionAt?.toIso8601String(),
    'lastFailureAt': lastFailureAt?.toIso8601String(),
    'lastFailedMessageId': lastFailedMessageId,
  };

  factory MemoryExtractionState.fromJson(
    Map<dynamic, dynamic> json, {
    required String characterId,
  }) => MemoryExtractionState(
    characterId: characterId,
    explicitAttempts: (json['explicitAttempts'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
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
