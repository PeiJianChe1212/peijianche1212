import 'memory_source_type.dart';

enum LegacyMemoryKind { event, user, legacyUnclassified }

/// Read-only Memory 2.0 view of an item that still belongs to memories.json.
///
/// `legacyArchived` is intentionally separate from EventMemoryStatus.forgotten:
/// old manual archiving does not prove that a memory was forgotten.
class LegacyMemoryView {
  const LegacyMemoryView({
    required this.id,
    required this.characterId,
    required this.legacySourceId,
    required this.kind,
    required this.content,
    required this.category,
    required this.createdAt,
    required this.isPinned,
    required this.legacyArchived,
    this.sourceType = MemorySourceType.legacy,
  });

  final String id;
  final String characterId;
  final String legacySourceId;
  final LegacyMemoryKind kind;
  final String content;
  final String category;
  final DateTime createdAt;
  final bool isPinned;
  final bool legacyArchived;
  final MemorySourceType sourceType;

  /// Legacy creation time is not treated as the event occurrence time.
  DateTime? get occurredAt => null;
}
