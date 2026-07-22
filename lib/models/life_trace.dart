class LifeTrace {
  const LifeTrace({
    required this.id,
    required this.kind,
    required this.title,
    required this.emoji,
    required this.detail,
    required this.occurredAt,
  });

  final String id;
  final String kind;
  final String title;
  final String emoji;
  final String detail;
  final DateTime occurredAt;

  factory LifeTrace.fromJson(Map<dynamic, dynamic> json) {
    return LifeTrace(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'life',
      title: json['title']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '·',
      detail: json['detail']?.toString() ?? '',
      occurredAt:
          DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'emoji': emoji,
    'detail': detail,
    'occurredAt': occurredAt.toIso8601String(),
  };
}
