import '../models/event_memory.dart';
import '../models/legacy_memory_view.dart';
import '../models/memory_extraction_result.dart';
import '../models/memory_source_type.dart';
import '../models/user_memory.dart';
import 'memory2_storage_service.dart';
import 'memory2_mutation_coordinator.dart';

class Memory2ApplyResult {
  const Memory2ApplyResult({
    required this.addedEvents,
    required this.addedUsers,
    required this.updatedUsers,
  });

  final int addedEvents;
  final int addedUsers;
  final int updatedUsers;
}

class Memory2Engine {
  const Memory2Engine({required this.storage});

  final Memory2StorageService storage;

  Future<Memory2ApplyResult> apply(
    MemoryExtractionResult extracted, {
    required List<LegacyMemoryView> legacyViews,
    DateTime? now,
  }) => Memory2MutationCoordinator.runExclusive(
    storage.characterId,
    () => _applyUnlocked(extracted, legacyViews: legacyViews, now: now),
  );

  Future<Memory2ApplyResult> _applyUnlocked(
    MemoryExtractionResult extracted, {
    required List<LegacyMemoryView> legacyViews,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final events = await storage.loadEventMemoriesStrict();
    final users = await storage.loadUserMemoriesStrict();
    var addedEvents = 0;
    var addedUsers = 0;
    var updatedUsers = 0;

    final batchEvents = _deduplicateEventBatch(extracted.eventMemories);
    for (var index = 0; index < batchEvents.length; index++) {
      final candidate = batchEvents[index];
      final duplicateIndex = events.indexWhere(
        (item) => _sameEvent(
          item.content,
          item.sourceMessageIds,
          candidate.content,
          candidate.sourceMessageIds,
        ),
      );
      final duplicatesLegacy = legacyViews
          .where((item) => item.kind == LegacyMemoryKind.event)
          .any((item) => _similarText(item.content, candidate.content));
      if (duplicatesLegacy) continue;
      if (duplicateIndex >= 0) {
        final existing = events[duplicateIndex];
        final mergedSources = _mergeIds(
          existing.sourceMessageIds,
          candidate.sourceMessageIds,
        );
        if (mergedSources.length != existing.sourceMessageIds.length) {
          events[duplicateIndex] = EventMemory(
            id: existing.id,
            characterId: existing.characterId,
            content: existing.content,
            occurredAt: existing.occurredAt ?? candidate.occurredAt,
            createdAt: existing.createdAt,
            updatedAt: time,
            sourceMessageIds: mergedSources,
            status: existing.status,
            lastRecalledAt: existing.lastRecalledAt,
            recallCount: existing.recallCount,
            isPinned: existing.isPinned,
            sourceType: existing.sourceType,
            legacySourceId: existing.legacySourceId,
            metadata: existing.metadata,
          );
        }
        continue;
      }
      events.add(
        EventMemory(
          id: 'event_${time.microsecondsSinceEpoch}_$index',
          characterId: storage.characterId,
          content: candidate.content,
          occurredAt: candidate.occurredAt,
          createdAt: time,
          updatedAt: time,
          sourceMessageIds: candidate.sourceMessageIds,
          sourceType: MemorySourceType.automatic,
        ),
      );
      addedEvents++;
    }

    for (var index = 0; index < extracted.userMemories.length; index++) {
      final candidate = extracted.userMemories[index];
      final normalizedKey = _normalize(candidate.key);
      if (normalizedKey.isEmpty) continue;
      final legacyDuplicate = legacyViews
          .where((item) => item.kind == LegacyMemoryKind.user)
          .any(
            (item) => _similarText(
              item.content,
              '${candidate.key}${candidate.value}',
            ),
          );
      if (legacyDuplicate) continue;
      final existingIndex = users.indexWhere(
        (item) =>
            item.status == UserMemoryStatus.active &&
            _normalize(item.key) == normalizedKey,
      );
      if (existingIndex < 0) {
        users.add(
          UserMemory(
            id: 'user_memory_${time.microsecondsSinceEpoch}_$index',
            characterId: storage.characterId,
            key: candidate.key,
            value: candidate.value,
            createdAt: time,
            updatedAt: time,
            sourceMessageIds: candidate.sourceMessageIds,
            sourceType: MemorySourceType.automatic,
          ),
        );
        addedUsers++;
        continue;
      }

      final existing = users[existingIndex];
      final sameValue =
          _normalize(existing.value) == _normalize(candidate.value);
      final mergedSources = _mergeIds(
        existing.sourceMessageIds,
        candidate.sourceMessageIds,
      );
      if ((existing.userConfirmed || existing.isPinned) && !sameValue) {
        continue;
      }
      users[existingIndex] = UserMemory(
        id: existing.id,
        characterId: existing.characterId,
        key: candidate.key,
        value: sameValue ? existing.value : candidate.value,
        createdAt: existing.createdAt,
        updatedAt: time,
        sourceMessageIds: mergedSources,
        status: existing.status,
        supersededById: existing.supersededById,
        mergedFromIds: existing.mergedFromIds,
        isPinned: existing.isPinned,
        userConfirmed: existing.userConfirmed,
        sourceType: existing.sourceType,
        legacySourceId: existing.legacySourceId,
      );
      updatedUsers++;
    }

    await storage.saveEventMemories(events);
    await storage.saveUserMemories(users);
    return Memory2ApplyResult(
      addedEvents: addedEvents,
      addedUsers: addedUsers,
      updatedUsers: updatedUsers,
    );
  }

  List<ExtractedEventMemory> _deduplicateEventBatch(
    List<ExtractedEventMemory> items,
  ) {
    final result = <ExtractedEventMemory>[];
    for (final item in items) {
      final index = result.indexWhere(
        (old) => _sameEvent(
          old.content,
          old.sourceMessageIds,
          item.content,
          item.sourceMessageIds,
        ),
      );
      if (index < 0) {
        result.add(item);
        continue;
      }
      final old = result[index];
      result[index] = ExtractedEventMemory(
        content: item.content.length > old.content.length
            ? item.content
            : old.content,
        sourceMessageIds: _mergeIds(
          old.sourceMessageIds,
          item.sourceMessageIds,
        ),
        occurredAt: old.occurredAt ?? item.occurredAt,
      );
    }
    return result;
  }

  bool _sameEvent(
    String firstContent,
    List<String> firstSources,
    String secondContent,
    List<String> secondSources,
  ) =>
      firstSources.toSet().intersection(secondSources.toSet()).isNotEmpty ||
      _similarText(firstContent, secondContent);

  bool _similarText(String first, String second) {
    final a = _normalize(first);
    final b = _normalize(second);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final left = a.split('').toSet();
    final right = b.split('').toSet();
    final union = left.union(right).length;
    return union > 0 && left.intersection(right).length / union >= 0.82;
  }

  List<String> _mergeIds(List<String> first, List<String> second) =>
      {...first, ...second}.where((item) => item.trim().isNotEmpty).toList();

  String _normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r"[\s，。！？、,.!?~～“”'‘’（）()\[\]【】:_：-]"),
    '',
  );
}
