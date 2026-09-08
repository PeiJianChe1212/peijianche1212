import '../models/character_settings.dart';
import '../models/character_user_profile.dart';
import '../models/event_memory.dart';
import '../models/legacy_memory_view.dart';
import '../models/memory_source_type.dart';
import '../models/memory_summary.dart';
import '../models/user_memory.dart';
import 'character_settings_storage_service.dart';
import 'character_user_profile_storage_service.dart';
import 'event_memory_lifecycle_service.dart';
import 'legacy_memory_adapter.dart';
import 'memory2_storage_service.dart';
import 'legacy_memory_migration_service.dart';
import 'memory2_mutation_coordinator.dart';
import 'auto_memory_extraction_service.dart';
import 'chat_storage_service.dart';
import 'memory_extraction_state_service.dart';
import 'memory_source_resolver.dart';
import '../models/chat_message.dart';
import 'memory_review_service.dart';

class MemoryCenterSnapshot {
  const MemoryCenterSnapshot({
    required this.events,
    required this.userMemories,
    required this.summary,
    required this.characterUserProfile,
    required this.settings,
    required this.legacy,
    this.lifecycleRefreshSucceeded = true,
    this.migratedLegacyIds = const {},
    this.legacyPendingCount = 0,
  });

  final List<EventMemory> events;
  final List<UserMemory> userMemories;
  final MemorySummary summary;
  final CharacterUserProfile characterUserProfile;
  final CharacterSettings settings;
  final List<LegacyMemoryView> legacy;
  final bool lifecycleRefreshSucceeded;
  final Set<String> migratedLegacyIds;
  final int legacyPendingCount;
}

class MemoryCenterController {
  MemoryCenterController({
    required this.characterId,
    Memory2StorageService? storage,
    EventMemoryLifecycleService? lifecycle,
    CharacterUserProfileStorageService? profileStorage,
    CharacterSettingsStorageService? settingsStorage,
    LegacyMemoryAdapter? legacyAdapter,
    this.explicitServiceFactory,
    this.extractionState,
    this.messagesLoader,
  }) : storage = storage ?? Memory2StorageService(characterId: characterId),
       lifecycle =
           lifecycle ?? EventMemoryLifecycleService(characterId: characterId),
       profileStorage =
           profileStorage ??
           CharacterUserProfileStorageService(characterId: characterId),
       settingsStorage =
           settingsStorage ??
           CharacterSettingsStorageService(characterId: characterId),
       legacyAdapter =
           legacyAdapter ?? LegacyMemoryAdapter(characterId: characterId);

  final String characterId;
  final Memory2StorageService storage;
  final EventMemoryLifecycleService lifecycle;
  final CharacterUserProfileStorageService profileStorage;
  final CharacterSettingsStorageService settingsStorage;
  final LegacyMemoryAdapter legacyAdapter;
  final AutoMemoryExtractionService Function()? explicitServiceFactory;
  final MemoryExtractionStateService? extractionState;
  final AutoMemoryMessagesLoader? messagesLoader;

  Future<List<ResolvedMemorySource>> resolveSources(List<String> ids) =>
      MemorySourceResolver(
        characterId: characterId,
        messagesLoader: messagesLoader,
      ).resolve(ids);

  Future<List<ChatMessage>> loadReprocessingMessages() async {
    final messages =
        await (messagesLoader ??
            ChatStorageService(characterId: characterId).loadMessages)();
    return messages
        .where(
          (m) =>
              m.isVisibleInConversationContext &&
              (m.role == 'user' || m.role == 'assistant') &&
              (m.content.trim().isNotEmpty || m.type == MessageType.image),
        )
        .toList()
        .reversed
        .take(AutoMemoryExtractionService.reprocessingSelectionLimit)
        .toList()
        .reversed
        .toList();
  }

  Future<MemoryReprocessingOutcome> reprocessMessages(List<String> ids) async {
    final service =
        explicitServiceFactory?.call() ??
        AutoMemoryExtractionService(characterId: characterId);
    try {
      return await service.reprocess(ids);
    } finally {
      service.dispose();
    }
  }

  Future<List<({String messageId, String content, String outcome})>>
  loadExplicitFailures() async {
    final state =
        await (extractionState ??
                MemoryExtractionStateService(characterId: characterId))
            .loadStrict();
    final messages =
        await (messagesLoader ??
            ChatStorageService(characterId: characterId).loadMessages)();
    return state.explicitAttempts.entries
        .where((e) => e.value != 'success')
        .map((e) {
          final source = messages
              .where((m) => m.id == e.key && m.isVisibleInConversationContext)
              .firstOrNull;
          return (
            messageId: e.key,
            content: source?.content ?? '',
            outcome: e.value,
          );
        })
        .toList();
  }

  Future<AutoMemoryExtractionOutcome> retryExplicit(String messageId) async {
    final service =
        explicitServiceFactory?.call() ??
        AutoMemoryExtractionService(characterId: characterId);
    try {
      return await service.maybeExtract(
        explicitMessageId: messageId,
        retryExplicit: true,
      );
    } finally {
      service.dispose();
    }
  }

  Future<MemoryCenterSnapshot> load({DateTime? now}) async {
    var refreshSucceeded = true;
    try {
      await lifecycle.refresh(now: now ?? DateTime.now());
    } catch (_) {
      refreshSucceeded = false;
    }
    final results = await Future.wait<Object>([
      storage.loadEventMemories(),
      storage.loadUserMemories(),
      storage.loadMemorySummary(),
      profileStorage.load(),
      settingsStorage.loadSettings(),
      legacyAdapter.loadReadOnlyViews(),
      _loadLegacyPendingCount(),
    ]);
    return MemoryCenterSnapshot(
      events: results[0] as List<EventMemory>,
      userMemories: results[1] as List<UserMemory>,
      summary: results[2] as MemorySummary,
      characterUserProfile: results[3] as CharacterUserProfile,
      settings: results[4] as CharacterSettings,
      legacy: results[5] as List<LegacyMemoryView>,
      legacyPendingCount: results[6] as int,
      lifecycleRefreshSucceeded: refreshSucceeded,
      migratedLegacyIds:
          await LegacyMemoryMigrationService(
            characterId: characterId,
            storage: storage,
            fileProvider: storage.fileProvider,
          ).migratedSourceIds(
            results[0] as List<EventMemory>,
            results[1] as List<UserMemory>,
          ),
    );
  }

  Future<int> _loadLegacyPendingCount() async {
    try {
      return (await MemoryReviewService(
        characterId: characterId,
      ).loadItems()).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> addEvent(String content, {bool isPinned = false}) async {
    final now = DateTime.now();
    await storage.upsertEventMemory(
      EventMemory(
        id: _id('event', now),
        characterId: characterId,
        content: content.trim(),
        createdAt: now,
        updatedAt: now,
        isPinned: isPinned,
        sourceType: MemorySourceType.manual,
      ),
    );
  }

  Future<void> setEventPinned(EventMemory item, bool pinned) =>
      lifecycle.setPinned(item.id, isPinned: pinned, now: DateTime.now());

  Future<void> restoreEvent(EventMemory item) =>
      lifecycle.restore(item.id, now: DateTime.now());

  Future<void> deleteEvent(EventMemory item) =>
      storage.deleteEventMemory(item.id);

  Future<void> addUserMemory(String key, String value) async {
    final now = DateTime.now();
    await storage.upsertUserMemory(
      UserMemory(
        id: _id('user', now),
        characterId: characterId,
        key: key.trim(),
        value: value.trim(),
        createdAt: now,
        updatedAt: now,
        userConfirmed: true,
        sourceType: MemorySourceType.manual,
      ),
    );
  }

  Future<void> updateUserMemory(
    UserMemory item, {
    required String key,
    required String value,
  }) => Memory2MutationCoordinator.runExclusive(characterId, () async {
    final items = await storage.loadUserMemoriesStrict();
    final index = items.indexWhere((m) => m.id == item.id);
    if (index < 0 || items[index].status != UserMemoryStatus.active) return;
    final latest = items[index];
    final now = DateTime.now();
    if (latest.key == key.trim() && latest.value == value.trim()) {
      items[index] = UserMemory.fromJson({
        ...latest.toJson(),
        'userConfirmed': true,
      });
    } else {
      final newId = _id('user', now);
      items[index] = UserMemory.fromJson({
        ...latest.toJson(),
        'status': 'superseded',
        'supersededById': newId,
        'updatedAt': now.toIso8601String(),
      });
      items.add(
        UserMemory(
          id: newId,
          characterId: characterId,
          key: key.trim(),
          value: value.trim(),
          createdAt: now,
          updatedAt: now,
          mergedFromIds: [latest.id],
          isPinned: latest.isPinned,
          userConfirmed: true,
          sourceType: MemorySourceType.manual,
        ),
      );
    }
    await storage.saveUserMemories(items);
  });

  Future<void> setUserMemoryPinned(UserMemory item, bool pinned) => _mutateUser(
    item.id,
    (item) => UserMemory(
      id: item.id,
      characterId: characterId,
      key: item.key,
      value: item.value,
      createdAt: item.createdAt,
      updatedAt: DateTime.now(),
      sourceMessageIds: item.sourceMessageIds,
      status: item.status,
      supersededById: item.supersededById,
      mergedFromIds: item.mergedFromIds,
      isPinned: pinned,
      userConfirmed: item.userConfirmed,
      sourceType: item.sourceType,
      legacySourceId: item.legacySourceId,
    ),
  );

  Future<void> deleteUserMemory(UserMemory item) =>
      storage.deleteUserMemory(item.id);

  Future<void> _mutateUser(String id, UserMemory Function(UserMemory) update) =>
      Memory2MutationCoordinator.runExclusive(characterId, () async {
        final items = await storage.loadUserMemoriesStrict();
        var index = items.indexWhere((item) => item.id == id);
        final visited = <String>{};
        while (index >= 0 &&
            items[index].status == UserMemoryStatus.superseded) {
          if (!visited.add(items[index].id)) return;
          final next = items[index].supersededById;
          index = items.indexWhere((item) => item.id == next);
        }
        if (index < 0) return;
        if (items[index].status != UserMemoryStatus.active) return;
        items[index] = update(items[index]);
        await storage.saveUserMemories(items);
      });

  Future<void> _mutateSummary(MemorySummary Function(MemorySummary) update) =>
      Memory2MutationCoordinator.runExclusive(characterId, () async {
        final latest = await storage.loadMemorySummaryStrict();
        await storage.saveMemorySummary(update(latest));
      });

  Future<void> saveUserEditedSummary(MemorySummary current, String text) =>
      _mutateSummary(
        (current) => MemorySummary(
          characterId: characterId,
          generatedText: current.generatedText,
          userEditedText: text.trim(),
          generatedAt: current.generatedAt,
          editedAt: DateTime.now(),
          sourceRevision: current.sourceRevision,
        ),
      );

  Future<void> saveGeneratedSummary(
    MemorySummary current,
    String text, {
    bool replaceUserEdit = false,
  }) => _mutateSummary((latest) {
    if (replaceUserEdit && latest.userEditedText != current.userEditedText) {
      throw StateError('记忆汇总已被编辑，请重新预览后确认。');
    }
    return MemorySummary(
      characterId: characterId,
      generatedText: text.trim(),
      userEditedText: replaceUserEdit ? '' : latest.userEditedText,
      generatedAt: DateTime.now(),
      editedAt: latest.editedAt,
      sourceRevision: latest.sourceRevision + 1,
    );
  });

  Future<void> clearSummary() =>
      _mutateSummary((_) => MemorySummary(characterId: characterId));

  Future<void> setAutoMemoryEnabled(CharacterSettings current, bool enabled) =>
      settingsStorage.saveSettings(
        current.copyWith(autoMemoryEnabled: enabled),
      );

  String buildCopyText(MemoryCenterSnapshot snapshot) {
    String clean(String value) => value.trim();
    final profile = snapshot.characterUserProfile;
    final profileLines = <String>[
      if (clean(profile.userName).isNotEmpty) '我的称呼：${clean(profile.userName)}',
      if (clean(profile.gender).isNotEmpty) '性别：${clean(profile.gender)}',
      if (clean(profile.effectiveDescription).isNotEmpty)
        clean(profile.effectiveDescription),
    ];
    final users = snapshot.userMemories
        .where((item) => item.status == UserMemoryStatus.active)
        .map((item) => item.displayText)
        .where((item) => item.trim().isNotEmpty);
    final events = snapshot.events
        .where((item) => item.status != EventMemoryStatus.forgotten)
        .map((item) => '- ${item.content.trim()}')
        .where((item) => item != '- ');
    final legacy = snapshot.legacy
        .where(
          (item) =>
              !item.legacyArchived &&
              !snapshot.migratedLegacyIds.contains(item.legacySourceId),
        )
        .map((item) => '- ${item.content.trim()}')
        .where((item) => item != '- ');
    final sections = <String>[];
    final about = [...profileLines, ...users];
    if (about.isNotEmpty) sections.add('[Ta 心中的我]\n${about.join('\n')}');
    if (snapshot.summary.effectiveText.isNotEmpty) {
      sections.add('[记忆汇总]\n${snapshot.summary.effectiveText}');
    }
    if (events.isNotEmpty) sections.add('[经历过的事]\n${events.join('\n')}');
    if (legacy.isNotEmpty) sections.add('[旧记忆]\n${legacy.join('\n')}');
    return sections.join('\n\n');
  }

  String _id(String prefix, DateTime now) =>
      '${prefix}_${now.microsecondsSinceEpoch}';
}
