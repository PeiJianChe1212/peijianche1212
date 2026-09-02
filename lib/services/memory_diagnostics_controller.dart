import '../models/character_settings.dart';
import '../models/chat_message.dart';
import '../models/event_memory.dart';
import '../models/legacy_memory_view.dart';
import '../models/memory_extraction_state.dart';
import '../models/memory_summary.dart';
import '../models/user_memory.dart';
import 'auto_memory_extraction_service.dart';
import 'character_settings_storage_service.dart';
import 'chat_storage_service.dart';
import 'legacy_memory_adapter.dart';
import 'memory2_storage_service.dart';
import 'memory_diagnostics_service.dart';
import 'memory_extraction_state_service.dart';

class MemoryDiagnosticsSnapshot {
  const MemoryDiagnosticsSnapshot({
    required this.characterId,
    required this.settings,
    required this.state,
    required this.unprocessedMessages,
    required this.events,
    required this.users,
    required this.legacy,
    required this.summary,
    required this.isRunning,
    required this.coolingDown,
  });
  final String characterId;
  final CharacterSettings settings;
  final MemoryExtractionState state;
  final List<ChatMessage> unprocessedMessages;
  final List<EventMemory> events;
  final List<UserMemory> users;
  final List<LegacyMemoryView> legacy;
  final MemorySummary summary;
  final bool isRunning;
  final bool coolingDown;
  int get unprocessedUserMessages =>
      unprocessedMessages.where((m) => m.role == 'user').length;
  bool get reachesThreshold =>
      unprocessedMessages.length >=
          AutoMemoryExtractionService.minimumMessages &&
      unprocessedUserMessages >=
          AutoMemoryExtractionService.minimumUserMessages;
}

class MemoryDiagnosticsController {
  const MemoryDiagnosticsController();

  Future<MemoryDiagnosticsSnapshot> read(
    String characterId, {
    DateTime? now,
  }) async {
    final state = await MemoryExtractionStateService(
      characterId: characterId,
    ).load();
    final messages =
        (await ChatStorageService(characterId: characterId).loadMessages())
            .where(
              (m) =>
                  (m.role == 'user' || m.role == 'assistant') &&
                  m.isVisibleInConversationContext &&
                  m.content.trim().isNotEmpty,
            )
            .toList();
    final unprocessed = _afterCursor(messages, state);
    final storage = Memory2StorageService(characterId: characterId);
    final settings = await CharacterSettingsStorageService(
      characterId: characterId,
    ).loadSettings();
    final failureAt = state.lastFailureAt;
    final current = now ?? DateTime.now();
    return MemoryDiagnosticsSnapshot(
      characterId: characterId,
      settings: settings,
      state: state,
      unprocessedMessages: unprocessed,
      events: await storage.loadEventMemories(),
      users: await storage.loadUserMemories(),
      legacy: await LegacyMemoryAdapter(
        characterId: characterId,
      ).loadReadOnlyViews(),
      summary: await storage.loadMemorySummary(),
      isRunning: AutoMemoryExtractionService.isRunning(characterId),
      coolingDown:
          failureAt != null &&
          current.difference(failureAt) <
              AutoMemoryExtractionService.failureCooldown,
    );
  }

  Future<AutoMemoryExtractionOutcome> checkAutoMemory(
    String characterId,
  ) async {
    final service = AutoMemoryExtractionService(characterId: characterId);
    try {
      return await service.maybeExtract();
    } finally {
      service.dispose();
    }
  }

  List<ChatMessage> _afterCursor(
    List<ChatMessage> messages,
    MemoryExtractionState state,
  ) {
    final id = state.lastProcessedMessageId;
    if (id != null) {
      final index = messages.indexWhere((m) => m.id == id);
      if (index >= 0) return messages.skip(index + 1).toList();
    }
    final at = state.lastProcessedAt;
    return at == null
        ? messages
        : messages.where((m) => m.createdAt.isAfter(at)).toList();
  }

  Duration effectiveAge(EventMemory event, DateTime now) {
    final reference =
        event.lastRecalledAt != null &&
            event.lastRecalledAt!.isAfter(event.createdAt)
        ? event.lastRecalledAt!
        : event.createdAt;
    final extension = Duration(days: (event.recallCount * 3).clamp(0, 30));
    final age = now.difference(reference) - extension;
    return age.isNegative ? Duration.zero : age;
  }

  int? daysToNextBoundary(EventMemory event, DateTime now) {
    if (event.isPinned || event.status == EventMemoryStatus.forgotten) {
      return null;
    }
    final age = effectiveAge(event, now).inDays;
    final boundary = switch (event.status) {
      EventMemoryStatus.active => 30,
      EventMemoryStatus.fading => 60,
      EventMemoryStatus.pendingForget => 90,
      EventMemoryStatus.forgotten => 90,
    };
    return (boundary - age).clamp(0, boundary);
  }

  MemoryExtractionReport? extraction(String id) =>
      MemoryDiagnosticsService.extractionFor(id);
  MemoryRetrieverReport? retriever(String id) =>
      MemoryDiagnosticsService.retrieverFor(id);
}
