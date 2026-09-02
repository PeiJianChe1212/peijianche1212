class MemorySummary {
  const MemorySummary({
    required this.characterId,
    this.generatedText = '',
    this.userEditedText = '',
    this.generatedAt,
    this.editedAt,
    this.sourceRevision = 0,
  });

  final String characterId;
  final String generatedText;
  final String userEditedText;
  final DateTime? generatedAt;
  final DateTime? editedAt;
  final int sourceRevision;

  String get effectiveText => userEditedText.trim().isNotEmpty
      ? userEditedText.trim()
      : generatedText.trim();

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'generatedText': generatedText,
    'userEditedText': userEditedText,
    'generatedAt': generatedAt?.toIso8601String(),
    'editedAt': editedAt?.toIso8601String(),
    'sourceRevision': sourceRevision,
  };

  factory MemorySummary.fromJson(Map<dynamic, dynamic> json) => MemorySummary(
    characterId: json['characterId']?.toString().trim() ?? '',
    generatedText: json['generatedText']?.toString().trim() ?? '',
    userEditedText: json['userEditedText']?.toString().trim() ?? '',
    generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
    editedAt: DateTime.tryParse(json['editedAt']?.toString() ?? ''),
    sourceRevision: _revision(json['sourceRevision']),
  );

  static int _revision(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return (parsed ?? 0).clamp(0, 1 << 31).toInt();
  }
}
