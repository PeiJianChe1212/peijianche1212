class TodayEvent {
  const TodayEvent({
    required this.id,
    required this.activityId,
    this.kind = 'activity',
    required this.title,
    required this.emoji,
    required this.story,
    required this.occurredAt,
  });

  final String id;
  final String activityId;
  final String kind;
  final String title;
  final String emoji;
  final String story;
  final DateTime occurredAt;

  factory TodayEvent.fromJson(Map<dynamic, dynamic> json) {
    return TodayEvent(
      id: json['id']?.toString() ?? '',
      activityId: json['activityId']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'activity',
      title: json['title']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      story: json['story']?.toString() ?? '',
      occurredAt:
          DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'activityId': activityId,
    'kind': kind,
    'title': title,
    'emoji': emoji,
    'story': story,
    'occurredAt': occurredAt.toIso8601String(),
  };
}
