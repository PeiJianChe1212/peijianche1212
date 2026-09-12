import 'event_memory.dart';
import 'memory_source_type.dart';

/// A group-scoped, speaker-attributed long-term event.
///
/// Storage reuses the Memory 2.0 row shape ([EventMemory]) so no new memory
/// schema is introduced. The group scope lives in `metadata` instead of a new
/// column, and [characterId] carries a `group:<groupId>` scope marker so group
/// rows can never be mistaken for a character's private Memory 2.0 rows.
class GroupMemoryEvent {
  GroupMemoryEvent({
    required this.id,
    required this.groupId,
    required this.content,
    this.groupName = '',
    this.speakerIds = const [],
    this.participants = const [],
    this.occurredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.sourceMessageIds = const [],
    this.status = EventMemoryStatus.active,
    this.isPinned = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  static const String scopeMarker = 'group_chat';
  static const String _scopePrefix = 'group:';

  final String id;
  final String groupId;
  final String groupName;
  final String content;
  final List<String> speakerIds;
  final List<String> participants;
  final DateTime? occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> sourceMessageIds;
  final EventMemoryStatus status;
  final bool isPinned;

  bool belongsTo(String group) => groupId == group;

  GroupMemoryEvent copyWith({
    String? groupName,
    String? content,
    List<String>? speakerIds,
    List<String>? participants,
    List<String>? sourceMessageIds,
    DateTime? updatedAt,
    EventMemoryStatus? status,
    bool? isPinned,
  }) => GroupMemoryEvent(
    id: id,
    groupId: groupId,
    groupName: groupName ?? this.groupName,
    content: content ?? this.content,
    speakerIds: speakerIds ?? this.speakerIds,
    participants: participants ?? this.participants,
    occurredAt: occurredAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sourceMessageIds: sourceMessageIds ?? this.sourceMessageIds,
    status: status ?? this.status,
    isPinned: isPinned ?? this.isPinned,
  );

  /// Serializes through the Memory 2.0 row shape; no new schema fields.
  EventMemory toEventMemory() => EventMemory(
    id: id,
    characterId: '$_scopePrefix$groupId',
    content: content,
    occurredAt: occurredAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    sourceMessageIds: sourceMessageIds,
    status: status,
    isPinned: isPinned,
    sourceType: MemorySourceType.automatic,
    metadata: {
      'scope': scopeMarker,
      'groupId': groupId,
      if (groupName.trim().isNotEmpty) 'groupName': groupName,
      if (speakerIds.isNotEmpty) 'speakerIds': speakerIds,
      if (participants.isNotEmpty) 'participants': participants,
    },
  );

  /// Reads a group row back. Returns null for character-private Memory 2.0 rows
  /// or malformed rows, so a group reader can never pull in private memory.
  static GroupMemoryEvent? tryFromEventMemory(
    EventMemory memory, {
    String fallbackGroupId = '',
  }) {
    final metadata = memory.metadata;
    final scope = metadata['scope']?.toString().trim() ?? '';
    final rawGroupId = metadata['groupId']?.toString().trim() ?? '';
    final characterScope = memory.characterId.startsWith(_scopePrefix)
        ? memory.characterId.substring(_scopePrefix.length)
        : '';
    final groupId = rawGroupId.isNotEmpty
        ? rawGroupId
        : (scope.isEmpty && characterScope.isNotEmpty
              ? characterScope
              : fallbackGroupId);
    if (groupId.isEmpty || memory.content.trim().isEmpty) return null;
    if (scope.isNotEmpty && scope != scopeMarker && rawGroupId.isEmpty) {
      return null;
    }
    return GroupMemoryEvent(
      id: memory.id,
      groupId: groupId,
      groupName: metadata['groupName']?.toString().trim() ?? '',
      content: memory.content,
      speakerIds: _stringList(metadata['speakerIds']),
      participants: _stringList(metadata['participants']),
      occurredAt: memory.occurredAt,
      createdAt: memory.createdAt,
      updatedAt: memory.updatedAt,
      sourceMessageIds: memory.sourceMessageIds,
      status: memory.status,
      isPinned: memory.isPinned,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
}
