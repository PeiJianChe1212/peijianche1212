import 'dart:async';

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
import 'explicit_remember_intent.dart';
import 'memory_content_boundary.dart';

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
  explicitEmpty,
}

enum MemoryReprocessingOutcome {
  success,
  empty,
  invalidRange,
  sourceUnavailable,
  failed,
  alreadyRunning,
}

class AutoMemoryExtractionService {
  /// Dispatch only after every reply segment was saved; never await extraction
  /// on the chat path. The factory keeps this boundary testable offline.
  static void afterReplySaved({
    required String characterId,
    required bool replyPersisted,
    required String? userMessageId,
    AutoMemoryExtractionService Function()? factory,
  }) {
    if (!replyPersisted) return;
    unawaited(() async {
      AutoMemoryExtractionService? service;
      try {
        service =
            factory?.call() ??
            AutoMemoryExtractionService(characterId: characterId);
        await service.maybeExtract(explicitMessageId: userMessageId);
      } catch (_) {
        // Includes setup/disposal failures, which must not escape into chat.
      } finally {
        try {
          service?.dispose();
        } catch (_) {
          // Background cleanup is also isolated from the saved reply.
        }
      }
    }());
  }

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
  // Two ordinary minimum batches; the existing extractor still emits <=6 events
  // and <=10 user facts in one 900-token response. Reject, never silently truncate.
  static const int reprocessingMessageLimit = minimumMessages * 2;
  static const int reprocessingCharacterLimit = 12000;
  static const int reprocessingSelectionLimit = 100;
  static final Set<String> _runningCharacters = <String>{};
  static final Map<String, Completer<void>> _runningCompletion = {};
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

  Future<AutoMemoryExtractionOutcome> maybeExtract({
    DateTime? now,
    String? explicitMessageId,
    bool retryExplicit = false,
  }) async {
    final time = now ?? DateTime.now();
    // A reply-bound request must not disappear behind an in-flight batch.
    // Waiting shares the existing role lock; it does not retry a model call.
    while (explicitMessageId != null &&
        _runningCharacters.contains(characterId)) {
      final running = _runningCompletion[characterId];
      if (running == null) return AutoMemoryExtractionOutcome.alreadyRunning;
      await running.future;
    }
    if (_deletingCharacters.contains(characterId) ||
        !_runningCharacters.add(characterId)) {
      _log('skip=alreadyRunning');
      _report(time, 'skipped');
      return AutoMemoryExtractionOutcome.alreadyRunning;
    }
    final completion = Completer<void>();
    _runningCompletion[characterId] = completion;

    MemoryExtractionState? state;
    String? terminalMessageId;
    List<ChatMessage> unprocessed = const [];
    ExplicitRememberIntent? explicit;
    try {
      final settings = await _settingsLoader();
      state = await _stateService.loadStrict();
      final allMessages = (await _messagesLoader())
          .where(_isEligible)
          .toList(growable: false);
      final userMessages = allMessages.where((m) => m.role == 'user').toList();
      final explicitSource = explicitMessageId == null
          ? (userMessages.isEmpty ? null : userMessages.last)
          : userMessages.where((m) => m.id == explicitMessageId).firstOrNull;
      explicit = explicitSource == null
          ? null
          : ExplicitRememberIntent.detect(explicitSource);
      if (explicit != null) {
        final previous = state.explicitAttempts[explicit.messageId];
        if (previous != null && (!retryExplicit || previous == 'success')) {
          return AutoMemoryExtractionOutcome.insufficientMessages;
        }
        unprocessed = explicit.window(allMessages);
        // Persist attempt before dispatch: crashes/failures never loop automatically.
        state = state.copyWith(
          explicitAttempts: {
            ...state.explicitAttempts,
            explicit.messageId: 'attempted',
          },
        );
        await _stateService.save(state);
      } else {
        if (retryExplicit) {
          return AutoMemoryExtractionOutcome.insufficientMessages;
        }
        if (!settings.autoMemoryEnabled) {
          return AutoMemoryExtractionOutcome.disabled;
        }
        unprocessed = _afterCursor(allMessages, state);
      }
      if (explicit == null &&
          (unprocessed.isEmpty ||
              unprocessed.length < minimumMessages ||
              unprocessed.where((item) => item.role == 'user').length <
                  minimumUserMessages)) {
        _log('skip=threshold batchCount=${unprocessed.length}');
        _report(time, 'skipped', messages: unprocessed);
        return AutoMemoryExtractionOutcome.insufficientMessages;
      }

      terminalMessageId = unprocessed.last.id;
      final failedAt = state.lastFailureAt;
      if (explicit == null &&
          state.lastFailedMessageId == terminalMessageId &&
          failedAt != null &&
          time.difference(failedAt) < failureCooldown) {
        _log('skip=cooldown batchCount=${unprocessed.length}');
        _report(time, 'skipped', messages: unprocessed);
        return AutoMemoryExtractionOutcome.coolingDown;
      }

      final extraction = await _extractMessages(
        unprocessed,
        settings,
        explicitTarget: explicit?.target,
      );
      final result = extraction.result;
      final legacy = extraction.legacy;
      final allowedIds = unprocessed.map((m) => m.id).toSet();
      final explicitUsers = result.userMemories
          .where(
            (m) =>
                m.sourceMessageIds.isNotEmpty &&
                m.sourceMessageIds.every(allowedIds.contains),
          )
          .take(1)
          .toList();
      final explicitEvents = result.eventMemories
          .where(
            (m) =>
                m.sourceMessageIds.isNotEmpty &&
                m.sourceMessageIds.every(allowedIds.contains),
          )
          .take(1)
          .toList();
      final toApply = explicit == null
          ? result
          : MemoryExtractionResult(
              userMemories: explicitUsers,
              eventMemories: explicitUsers.isEmpty ? explicitEvents : const [],
            );
      final applied = await Memory2Engine(storage: _storage).apply(
        toApply,
        legacyViews: legacy,
        now: time,
        explicitRemember: explicit != null,
        sourceMessages: unprocessed,
      );
      if (explicit != null) {
        final formed =
            applied.addedEvents + applied.addedUsers + applied.updatedUsers > 0;
        await _stateService.save(
          state.copyWith(
            explicitAttempts: {
              ...state.explicitAttempts,
              explicit.messageId: formed ? 'success' : 'empty',
            },
          ),
        );
        _report(
          time,
          formed ? 'explicitSuccess' : 'explicitEmpty',
          messages: unprocessed,
          eventWritten: applied.addedEvents,
          userCreated: applied.addedUsers,
          userUpdated: applied.updatedUsers,
        );
        return formed
            ? AutoMemoryExtractionOutcome.success
            : AutoMemoryExtractionOutcome.explicitEmpty;
      }
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
              explicitAttempts: explicit == null
                  ? null
                  : {...state.explicitAttempts, explicit.messageId: 'failed'},
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
      _runningCompletion.remove(characterId);
      completion.complete();
    }
  }

  /// User initiated, independent of both ordinary cursor and explicit attempts.
  Future<MemoryReprocessingOutcome> reprocess(List<String> messageIds) async {
    final ids = messageIds.toSet();
    if (ids.isEmpty ||
        ids.length != messageIds.length ||
        ids.length > reprocessingMessageLimit) {
      return MemoryReprocessingOutcome.invalidRange;
    }
    if (_deletingCharacters.contains(characterId) ||
        !_runningCharacters.add(characterId)) {
      return MemoryReprocessingOutcome.alreadyRunning;
    }
    final completion = Completer<void>();
    _runningCompletion[characterId] = completion;
    try {
      final messages = (await _messagesLoader())
          .where((m) => ids.contains(m.id) && _isEligible(m))
          .toList();
      if (messages.length != ids.length) {
        return MemoryReprocessingOutcome.sourceUnavailable;
      }
      final characters = messages.fold<int>(
        0,
        (sum, m) => sum + MemoryContentBoundary.sourceCharacters(m),
      );
      if (characters > reprocessingCharacterLimit) {
        return MemoryReprocessingOutcome.invalidRange;
      }
      final extraction = await _extractMessages(
        messages,
        await _settingsLoader(),
      );
      final result = extraction.result;
      _log(
        'reprocessing count=${messages.length} parseOutcome=${result.parseOutcome == 'success' ? 'success' : 'completed'}',
      );
      if (result.eventMemories.isEmpty && result.userMemories.isEmpty) {
        return MemoryReprocessingOutcome.empty;
      }
      await Memory2Engine(storage: _storage).apply(
        result,
        legacyViews: extraction.legacy,
        sourceMessages: messages,
        historicalReprocessing: true,
      );
      return MemoryReprocessingOutcome.success;
    } catch (error) {
      _log('reprocessingFailed errorType=${error.runtimeType}');
      return MemoryReprocessingOutcome.failed;
    } finally {
      _runningCharacters.remove(characterId);
      _runningCompletion.remove(characterId);
      completion.complete();
    }
  }

  Future<({MemoryExtractionResult result, List<LegacyMemoryView> legacy})>
  _extractMessages(
    List<ChatMessage> messages,
    CharacterSettings settings, {
    String? explicitTarget,
  }) async {
    final events = await _storage.loadEventMemoriesStrict();
    final users = await _storage.loadUserMemoriesStrict();
    final legacy = await _legacyLoader();
    final result = await _gateway.extract(
      Memory2ExtractionRequest(
        characterName: settings.characterName,
        userName: await _userNameLoader(),
        messages: messages,
        explicitTarget: explicitTarget,
        existingEventHints: events.reversed
            .take(hintLimit)
            .map((m) => m.content)
            .toList(),
        existingUserHints: users.reversed
            .where((m) => m.status.name == 'active')
            .take(40)
            .map((m) => '[id=${m.id}] ${m.key}：${m.value}')
            .toList(),
        legacyHints: legacy.reversed
            .where((m) => !m.legacyArchived)
            .take(hintLimit)
            .map((m) => m.content)
            .toList(),
      ),
    );
    return (
      result: MemoryContentBoundary.grounded(result, messages),
      legacy: legacy,
    );
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
      (message.content.trim().isNotEmpty ||
          (message.type == MessageType.image &&
              (message.metadata['visionDescription']
                      ?.toString()
                      .trim()
                      .isNotEmpty ??
                  false)));

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
