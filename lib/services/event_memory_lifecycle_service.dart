import '../models/event_memory.dart';
import 'memory2_mutation_coordinator.dart';
import 'memory2_storage_service.dart';

class EventMemoryLifecycleService {
  EventMemoryLifecycleService({
    required this.characterId,
    Memory2StorageService? storage,
  }) : storage = storage ?? Memory2StorageService(characterId: characterId);

  static const Duration activePeriod = Duration(days: 30);
  static const Duration fadingPeriod = Duration(days: 30);
  static const Duration pendingForgetPeriod = Duration(days: 30);
  static const Duration recallExtension = Duration(days: 3);
  static const Duration maximumRecallExtension = Duration(days: 30);

  final String characterId;
  final Memory2StorageService storage;

  EventMemoryStatus evaluateStatus(EventMemory memory, DateTime now) {
    if (memory.isPinned) return EventMemoryStatus.active;
    final reference = _referenceTime(memory);
    final extensionDays = (memory.recallCount * recallExtension.inDays).clamp(
      0,
      maximumRecallExtension.inDays,
    );
    final effectiveAge =
        now.difference(reference) - Duration(days: extensionDays);
    if (effectiveAge.isNegative || effectiveAge < activePeriod) {
      return EventMemoryStatus.active;
    }
    if (effectiveAge < activePeriod + fadingPeriod) {
      return EventMemoryStatus.fading;
    }
    if (effectiveAge < activePeriod + fadingPeriod + pendingForgetPeriod) {
      return EventMemoryStatus.pendingForget;
    }
    return EventMemoryStatus.forgotten;
  }

  Future<int> refresh({required DateTime now}) =>
      Memory2MutationCoordinator.runExclusive(characterId, () async {
        final memories = await storage.loadEventMemories();
        var changed = 0;
        final updated = memories
            .map((memory) {
              final status = evaluateStatus(memory, now);
              if (status == memory.status) return memory;
              changed++;
              return _copy(memory, status: status, updatedAt: now);
            })
            .toList(growable: false);
        if (changed > 0) await storage.saveEventMemories(updated);
        return changed;
      });

  Future<bool> markRecalled(String id, {required DateTime now}) =>
      Memory2MutationCoordinator.runExclusive(characterId, () async {
        final memories = await storage.loadEventMemories();
        final index = memories.indexWhere((item) => item.id == id);
        if (index < 0) return false;
        final memory = memories[index];
        if (memory.status == EventMemoryStatus.forgotten ||
            evaluateStatus(memory, now) == EventMemoryStatus.forgotten) {
          return false;
        }
        memories[index] = _copy(
          memory,
          status: EventMemoryStatus.active,
          lastRecalledAt: now,
          recallCount: memory.recallCount + 1,
          updatedAt: now,
        );
        await storage.saveEventMemories(memories);
        return true;
      });

  Future<bool> setPinned(
    String id, {
    required bool isPinned,
    required DateTime now,
  }) => Memory2MutationCoordinator.runExclusive(characterId, () async {
    final memories = await storage.loadEventMemories();
    final index = memories.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    final memory = memories[index];
    final provisional = _copy(
      memory,
      isPinned: isPinned,
      status: isPinned ? EventMemoryStatus.active : memory.status,
      updatedAt: now,
    );
    memories[index] = isPinned
        ? provisional
        : _copy(provisional, status: evaluateStatus(provisional, now));
    await storage.saveEventMemories(memories);
    return true;
  });

  Future<bool> restore(String id, {required DateTime now}) =>
      Memory2MutationCoordinator.runExclusive(characterId, () async {
        final memories = await storage.loadEventMemories();
        final index = memories.indexWhere((item) => item.id == id);
        if (index < 0) return false;
        memories[index] = _copy(
          memories[index],
          status: EventMemoryStatus.active,
          lastRecalledAt: now,
          updatedAt: now,
        );
        await storage.saveEventMemories(memories);
        return true;
      });

  DateTime _referenceTime(EventMemory memory) {
    final recalled = memory.lastRecalledAt;
    if (recalled == null || recalled.isBefore(memory.createdAt)) {
      return memory.createdAt;
    }
    return recalled;
  }

  EventMemory _copy(
    EventMemory memory, {
    EventMemoryStatus? status,
    DateTime? updatedAt,
    DateTime? lastRecalledAt,
    int? recallCount,
    bool? isPinned,
  }) => EventMemory(
    id: memory.id,
    characterId: memory.characterId,
    content: memory.content,
    occurredAt: memory.occurredAt,
    createdAt: memory.createdAt,
    updatedAt: updatedAt ?? memory.updatedAt,
    sourceMessageIds: memory.sourceMessageIds,
    status: status ?? memory.status,
    lastRecalledAt: lastRecalledAt ?? memory.lastRecalledAt,
    recallCount: recallCount ?? memory.recallCount,
    isPinned: isPinned ?? memory.isPinned,
    sourceType: memory.sourceType,
    legacySourceId: memory.legacySourceId,
    metadata: memory.metadata,
  );
}
