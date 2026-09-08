import '../models/event_memory.dart';
import '../models/chat_message.dart';
import '../models/legacy_memory_view.dart';
import '../models/memory_extraction_result.dart';
import '../models/memory_source_type.dart';
import '../models/user_memory.dart';
import 'memory2_storage_service.dart';
import 'memory2_mutation_coordinator.dart';
import 'explicit_remember_intent.dart';

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
    bool explicitRemember = false,
    List<ChatMessage> sourceMessages = const [],
    bool historicalReprocessing = false,
  }) => Memory2MutationCoordinator.runExclusive(
    storage.characterId,
    () => _applyUnlocked(
      extracted,
      legacyViews: legacyViews,
      now: now,
      explicitRemember: explicitRemember,
      sourceMessages: sourceMessages,
      historicalReprocessing: historicalReprocessing,
    ),
  );

  Future<Memory2ApplyResult> _applyUnlocked(
    MemoryExtractionResult extracted, {
    required List<LegacyMemoryView> legacyViews,
    DateTime? now,
    bool explicitRemember = false,
    List<ChatMessage> sourceMessages = const [],
    bool historicalReprocessing = false,
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
      if (duplicatesLegacy && !explicitRemember) continue;
      if (duplicateIndex >= 0) {
        final existing = events[duplicateIndex];
        final mergedSources = _mergeIds(
          existing.sourceMessageIds,
          candidate.sourceMessageIds,
        );
        if (explicitRemember ||
            mergedSources.length != existing.sourceMessageIds.length) {
          events[duplicateIndex] = EventMemory(
            id: existing.id,
            characterId: existing.characterId,
            content: existing.content,
            occurredAt: existing.occurredAt ?? candidate.occurredAt,
            createdAt: existing.createdAt,
            updatedAt: time,
            sourceMessageIds: mergedSources,
            status: explicitRemember
                ? EventMemoryStatus.active
                : existing.status,
            lastRecalledAt: existing.lastRecalledAt,
            recallCount: existing.recallCount,
            isPinned: existing.isPinned || explicitRemember,
            sourceType: existing.sourceType,
            legacySourceId: existing.legacySourceId,
            metadata: existing.metadata,
          );
        }
        if (explicitRemember) addedEvents++;
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
          isPinned: explicitRemember,
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
      if (legacyDuplicate && !explicitRemember) continue;
      final existingIndex = users.indexWhere(
        (item) =>
            item.status == UserMemoryStatus.active &&
            _normalize(item.key) == normalizedKey,
      );
      if (existingIndex < 0) {
        if (candidate.supersedesId != null) continue;
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
            userConfirmed: explicitRemember,
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
      if (!sameValue) {
        // Model intent alone is insufficient: require exact user evidence.
        final evidence = candidate.changeEvidence.trim();
        final validChange =
            candidate.supersedesId == existing.id &&
            evidence.isNotEmpty &&
            ExplicitRememberIntent.isChangeEvidence(evidence) &&
            sourceMessages.any(
              (m) =>
                  m.role == 'user' &&
                  m.isVisibleInConversationContext &&
                  candidate.sourceMessageIds.contains(m.id) &&
                  (!historicalReprocessing ||
                      m.createdAt.isAfter(existing.createdAt)) &&
                  ExplicitRememberIntent.containsDirectChange(
                    m.content,
                    evidence,
                  ),
            );
        if (!validChange) continue;
        final newId =
            'user_memory_${time.microsecondsSinceEpoch}_${index}_${users.length}';
        users[existingIndex] = UserMemory.fromJson({
          ...existing.toJson(),
          'status': UserMemoryStatus.superseded.name,
          'supersededById': newId,
          'updatedAt': time.toIso8601String(),
        });
        users.add(
          UserMemory(
            id: newId,
            characterId: storage.characterId,
            key: candidate.key,
            value: candidate.value,
            createdAt: time,
            updatedAt: time,
            sourceMessageIds: candidate.sourceMessageIds,
            mergedFromIds: [existing.id],
            sourceType: MemorySourceType.automatic,
            userConfirmed: existing.userConfirmed || explicitRemember,
            isPinned: existing.isPinned,
          ),
        );
        updatedUsers++;
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
        userConfirmed: existing.userConfirmed || explicitRemember,
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
