import 'package:flutter/foundation.dart';

import '../models/character_settings.dart';
import '../models/chat_message.dart';
import '../models/legacy_memory_view.dart';
import '../models/memory_extraction_state.dart';
import '../models/memory_extraction_result.dart';
import 'character_settings_storage_service.dart';
import 'chat_storage_service.dart';
import 'legacy_memory_adapter.dart';
import 'memory2_engine.dart';
import 'memory2_extractor.dart';
import 'memory2_storage_service.dart';
import 'memory_extraction_state_service.dart';
import 'memory_diagnostics_service.dart';
import 'user_profile_storage_service.dart';

typedef AutoMemoryMessagesLoader = Future<List<ChatMessage>> Function();
typedef AutoMemorySettingsLoader = Future<CharacterSettings> Function();
typedef AutoMemoryUserNameLoader = Future<String> Function();
typedef AutoMemoryLegacyLoader = Future<List<LegacyMemoryView>> Function();
typedef AutoMemoryLogger = void Function(String message);

enum AutoMemoryExtractionOutcome {
  disabled,
  insufficientMessages,
  alreadyRunning,
  coolingDown,
  success,
  failed,
}

class AutoMemoryExtractionService {
  AutoMemoryExtractionService({
    required this.characterId,
    Memory2ExtractionGateway? gateway,
    Memory2StorageService? storage,
    MemoryExtractionStateService? stateService,
    AutoMemoryMessagesLoader? messagesLoader,
    AutoMemorySettingsLoader? settingsLoader,
    AutoMemoryUserNameLoader? userNameLoader,
    AutoMemoryLegacyLoader? legacyLoader,
    AutoMemoryLogger? logger,
  }) : _gateway = gateway ?? Memory2ModelExtractor(),
       _ownsGateway = gateway == null,
       _storage = storage ?? Memory2StorageService(characterId: characterId),
       _stateService =
           stateService ??
           MemoryExtractionStateService(characterId: characterId),
       _messagesLoader =
           messagesLoader ??
           ChatStorageService(characterId: characterId).loadMessages,
       _settingsLoader =
           settingsLoader ??
           CharacterSettingsStorageService(
             characterId: characterId,
           ).loadSettings,
       _userNameLoader = userNameLoader ?? _defaultUserName,
       _legacyLoader =
           legacyLoader ??
           LegacyMemoryAdapter(characterId: characterId).loadReadOnlyViews,
       _logger = logger ?? debugPrint;

  static const int minimumMessages = 8;
  static const int minimumUserMessages = 3;
  static const Duration failureCooldown = Duration(minutes: 10);
  static const int hintLimit = 5;
  static final Set<String> _runningCharacters = <String>{};
  static final Set<String> _deletingCharacters = <String>{};
  static bool isRunning(String characterId) =>
      _runningCharacters.contains(characterId);

  /// Blocks new extraction before any asynchronous deletion work starts.
  static Future<void> duringCharacterDeletion(
    String characterId,
    Future<void> Function() action,
  ) async {
    if (isRunning(characterId) || !_deletingCharacters.add(characterId)) {
      throw StateError('记忆整理或角色删除尚未结束，请稍后重试。');
    }
    try {
      await action();
    } finally {
      _deletingCharacters.remove(characterId);
    }
  }

  final String characterId;
  final Memory2ExtractionGateway _gateway;
  final bool _ownsGateway;
  final Memory2StorageService _storage;
  final MemoryExtractionStateService _stateService;
  final AutoMemoryMessagesLoader _messagesLoader;
  final AutoMemorySettingsLoader _settingsLoader;
  final AutoMemoryUserNameLoader _userNameLoader;
  final AutoMemoryLegacyLoader _legacyLoader;
  final AutoMemoryLogger _logger;

  Future<AutoMemoryExtractionOutcome> maybeExtract({DateTime? now}) async {
    final time = now ?? DateTime.now();
    if (_deletingCharacters.contains(characterId) ||
        !_runningCharacters.add(characterId)) {
      _log('skip=alreadyRunning');
      _report(time, 'skipped');
      return AutoMemoryExtractionOutcome.alreadyRunning;
    }

    MemoryExtractionState? state;
    String? terminalMessageId;
    List<ChatMessage> unprocessed = const [];
    try {
      final settings = await _settingsLoader();
      if (!settings.autoMemoryEnabled) {
        _log('skip=disabled');
        _report(time, 'skipped');
        return AutoMemoryExtractionOutcome.disabled;
      }

      state = await _stateService.loadStrict();
      final allMessages = (await _messagesLoader())
          .where(_isEligible)
          .toList(growable: false);
      unprocessed = _afterCursor(allMessages, state);
      if (unprocessed.isEmpty ||
          unprocessed.length < minimumMessages ||
          unprocessed.where((item) => item.role == 'user').length <
              minimumUserMessages) {
        _log('skip=threshold batchCount=${unprocessed.length}');
        _report(time, 'skipped', messages: unprocessed);
        return AutoMemoryExtractionOutcome.insufficientMessages;
      }

      terminalMessageId = unprocessed.last.id;
      final failedAt = state.lastFailureAt;
      if (state.lastFailedMessageId == terminalMessageId &&
          failedAt != null &&
          time.difference(failedAt) < failureCooldown) {
        _log('skip=cooldown batchCount=${unprocessed.length}');
        _report(time, 'skipped', messages: unprocessed);
        return AutoMemoryExtractionOutcome.coolingDown;
      }

      final events = await _storage.loadEventMemoriesStrict();
      final users = await _storage.loadUserMemoriesStrict();
      final legacy = await _legacyLoader();
      final result = await _gateway.extract(
        Memory2ExtractionRequest(
          characterName: settings.characterName,
          userName: await _userNameLoader(),
          messages: unprocessed,
          existingEventHints: events.reversed
              .take(hintLimit)
              .map((item) => item.content)
              .toList(growable: false),
          existingUserHints: users.reversed
              .where((item) => item.status.name == 'active')
              .take(hintLimit)
              .map((item) => '${item.key}：${item.value}')
              .toList(growable: false),
          legacyHints: legacy.reversed
              .where((item) => !item.legacyArchived)
              .take(hintLimit)
              .map((item) => item.content)
              .toList(growable: false),
        ),
      );
      final applied = await Memory2Engine(
        storage: _storage,
      ).apply(result, legacyViews: legacy, now: time);
      await _stateService.save(
        state.copyWith(
          lastProcessedMessageId: terminalMessageId,
          lastProcessedAt: unprocessed.last.createdAt,
          lastSuccessfulExtractionAt: time,
          clearFailure: true,
        ),
      );
      _log(
        'success batchCount=${unprocessed.length} '
        'eventCount=${result.eventMemories.length} '
        'userCount=${result.userMemories.length} '
        'addedEvents=${applied.addedEvents} '
        'addedUsers=${applied.addedUsers} updatedUsers=${applied.updatedUsers}',
      );
      _report(
        time,
        result.eventMemories.isEmpty && result.userMemories.isEmpty
            ? 'empty'
            : 'success',
        messages: unprocessed,
        eventCandidates: result.eventMemories.length,
        userCandidates: result.userMemories.length,
        eventWritten: applied.addedEvents,
        userCreated: applied.addedUsers,
        userUpdated: applied.updatedUsers,
        eventTexts: result.eventMemories.map((e) => e.content).toList(),
        userTexts: result.userMemories
            .map((e) => '${e.key}：${e.value}')
            .toList(),
        rawResponseShape: result.rawResponseShape?.name,
        parseOutcome: result.parseOutcome,
        cursorAdvanced: true,
      );
      return AutoMemoryExtractionOutcome.success;
    } catch (error) {
      if (state != null && terminalMessageId != null) {
        try {
          await _stateService.save(
            state.copyWith(
              lastFailureAt: time,
              lastFailedMessageId: terminalMessageId,
            ),
          );
        } catch (_) {
          // The extraction failure is already isolated from the chat flow.
        }
      }
      _log('failed errorType=${error.runtimeType}');
      _report(
        time,
        'failed',
        messages: unprocessed,
        failureType: error.runtimeType.toString(),
        rawResponseShape: error is MemoryExtractionParseException
            ? error.shape.name
            : null,
        parseOutcome: error is MemoryExtractionParseException
            ? 'rejected: ${error.message}'
            : 'failed',
      );
      return AutoMemoryExtractionOutcome.failed;
    } finally {
      _runningCharacters.remove(characterId);
    }
  }

  List<ChatMessage> _afterCursor(
    List<ChatMessage> messages,
    MemoryExtractionState state,
  ) {
    final cursorId = state.lastProcessedMessageId;
    if (cursorId != null) {
      final index = messages.indexWhere((item) => item.id == cursorId);
      if (index >= 0) return messages.skip(index + 1).toList(growable: false);
    }
    final cursorTime = state.lastProcessedAt;
    if (cursorTime == null) return messages;
    return messages
        .where((item) => item.createdAt.isAfter(cursorTime))
        .toList(growable: false);
  }

  bool _isEligible(ChatMessage message) =>
      (message.role == 'user' || message.role == 'assistant') &&
      message.isVisibleInConversationContext &&
      message.content.trim().isNotEmpty;

  void _log(String detail) =>
      _logger('Memory2Extraction characterId=$characterId $detail');

  void _report(
    DateTime at,
    String result, {
    List<ChatMessage> messages = const [],
    int eventCandidates = 0,
    int userCandidates = 0,
    int eventWritten = 0,
    int userCreated = 0,
    int userUpdated = 0,
    String? failureType,
    String? rawResponseShape,
    String? parseOutcome,
    bool cursorAdvanced = false,
    List<String> eventTexts = const [],
    List<String> userTexts = const [],
  }) => MemoryDiagnosticsService.recordExtraction(
    MemoryExtractionReport(
      characterId: characterId,
      triggeredAt: at,
      result: result,
      batchMessageCount: messages.length,
      userMessageCount: messages.where((m) => m.role == 'user').length,
      firstMessageId: messages.isEmpty ? null : messages.first.id,
      lastMessageId: messages.isEmpty ? null : messages.last.id,
      eventCandidateCount: eventCandidates,
      userCandidateCount: userCandidates,
      eventWrittenCount: eventWritten,
      userCreatedCount: userCreated,
      userUpdatedCount: userUpdated,
      eventDeduplicatedCount: (eventCandidates - eventWritten).clamp(
        0,
        1 << 31,
      ),
      failureType: failureType,
      rawResponseShape: rawResponseShape,
      parseOutcome: parseOutcome,
      cursorAdvanced: cursorAdvanced,
      eventTexts: eventTexts,
      userTexts: userTexts,
    ),
  );

  void dispose() {
    if (_ownsGateway && _gateway is Memory2ModelExtractor) {
      _gateway.dispose();
    }
  }

  static Future<String> _defaultUserName() async {
    final value = (await UserProfileStorageService().loadProfile()).nickname;
    return value.trim().isEmpty || value == '未设置' ? '用户' : value.trim();
  }
}
