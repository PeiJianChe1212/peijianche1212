import 'memory_source_type.dart';

enum EventMemoryStatus {
  active,
  fading,
  pendingForget,
  forgotten;

  static EventMemoryStatus fromJson(dynamic value) {
    final name = value?.toString();
    return EventMemoryStatus.values.firstWhere(
      (item) => item.name == name,
      orElse: () => EventMemoryStatus.active,
    );
  }
}

class EventMemory {
  EventMemory({
    required this.id,
    required this.characterId,
    required this.content,
    this.occurredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.sourceMessageIds = const [],
    this.status = EventMemoryStatus.active,
    this.lastRecalledAt,
    this.recallCount = 0,
    this.isPinned = false,
    this.sourceType = MemorySourceType.manual,
    this.legacySourceId,
    this.metadata = const {},
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  final String characterId;
  final String content;
  final DateTime? occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> sourceMessageIds;
  final EventMemoryStatus status;
  final DateTime? lastRecalledAt;
  final int recallCount;
  final bool isPinned;
  final MemorySourceType sourceType;
  final String? legacySourceId;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'id': id,
    'characterId': characterId,
    'content': content,
    'occurredAt': occurredAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'sourceMessageIds': sourceMessageIds,
    'status': status.name,
    'lastRecalledAt': lastRecalledAt?.toIso8601String(),
    'recallCount': recallCount,
    'isPinned': isPinned,
    'sourceType': sourceType.name,
    'legacySourceId': legacySourceId,
    'metadata': metadata,
  };

  factory EventMemory.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    final createdAt = _date(json['createdAt']) ?? now;
    return EventMemory(
      id: _text(json['id']),
      characterId: _text(json['characterId']),
      content: _text(json['content']),
      occurredAt: _date(json['occurredAt']),
      createdAt: createdAt,
      updatedAt: _date(json['updatedAt']) ?? createdAt,
      sourceMessageIds: _stringList(json['sourceMessageIds']),
      status: EventMemoryStatus.fromJson(json['status']),
      lastRecalledAt: _date(json['lastRecalledAt']),
      recallCount: _nonNegativeInt(json['recallCount']),
      isPinned: json['isPinned'] == true,
      sourceType: MemorySourceType.fromJson(json['sourceType']),
      legacySourceId: _nullableText(json['legacySourceId']),
      metadata: _metadata(json['metadata']),
    );
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';
  static String? _nullableText(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '');

  static int _nonNegativeInt(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return (parsed ?? 0).clamp(0, 1 << 31).toInt();
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map(_text).where((item) => item.isNotEmpty).toSet().toList();
  }

  static Map<String, dynamic> _metadata(dynamic value) {
    if (value is! Map) return const {};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
