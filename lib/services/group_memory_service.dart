import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/event_memory.dart';
import '../models/group_memory_event.dart';
import '../models/group_message.dart';
import '../models/memory_extraction_state.dart';
import 'character_registry_service.dart';
import 'group_memory_extractor.dart';
import 'group_memory_storage_service.dart';
import 'group_message_storage_service.dart';

typedef GroupMemoryMessageLoader = Future<List<GroupMessage>> Function(
  String groupId,
);
typedef GroupMemorySenderNameLoader = Future<Map<String, String>> Function(
  String groupId,
);
typedef GroupMemoryLogger = void Function(String message);

enum GroupMemoryExtractionOutcome {
  insufficientMessages,
  alreadyRunning,
  coolingDown,
  success,
  empty,
  failed,
}

class GroupMemoryRetrievalResult {
  const GroupMemoryRetrievalResult({
    this.events = const [],
    this.contextText = '',
  });

  final List<GroupMemoryEvent> events;
  final String contextText;

  bool get isEmpty => events.isEmpty || contextText.trim().isEmpty;

  static const GroupMemoryRetrievalResult none =
      GroupMemoryRetrievalResult();
}

/// Lightweight group event memory: extraction, de-duplication, and retrieval.
///
/// Boundaries:
/// - reads only group chat messages for this [groupId]
/// - writes only to the group-scoped Memory 2.0 shaped file
/// - never reads or writes CharacterUserProfile / CharacterArchive / private
///   character Memory 2.0
class GroupMemoryService {
  GroupMemoryService({
    required this.groupId,
    this.groupName = '',
    GroupMemoryStorageService? storage,
    GroupMemoryExtractor? extractor,
    GroupMemoryMessageLoader? messagesLoader,
    GroupMemorySenderNameLoader? namesLoader,
    GroupMemoryLogger? logger,
    DateTime Function()? clock,
    this.minimumMessages = defaultMinimumMessages,
  }) : _storage =
           storage ?? GroupMemoryStorageService(groupId: groupId),
       _extractor = extractor ?? const GroupMemoryExtractor(),
       _messagesLoader =
           messagesLoader ??
           ((id) => GroupMessageStorageService(groupId: id).loadMessages()),
       _namesLoader = namesLoader ?? _defaultSenderNames,
       _logger = logger ?? debugPrint,
       _clock = clock ?? DateTime.now;

  /// Batch gate: a segment must accumulate this many new messages first.
  static const int defaultMinimumMessages = 6;
  static const Duration failureCooldown = Duration(minutes: 10);
  static const int maximumRetrievedEvents = 2;
  static const int retrievedItemCharacters = 200;
  static const int retrievedContextCharacters = 600;
  static const double minimumRetrievalScore = 0.14;

  static final Set<String> _runningGroups = <String>{};
  static final Map<String, Completer<void>> _runningCompletion = {};

  final String groupId;
  final String groupName;
  final int minimumMessages;
  final GroupMemoryStorageService _storage;
  final GroupMemoryExtractor _extractor;
  final GroupMemoryMessageLoader _messagesLoader;
  final GroupMemorySenderNameLoader _namesLoader;
  final GroupMemoryLogger _logger;
  final DateTime Function() _clock;

  static bool isRunning(String groupId) => _runningGroups.contains(groupId);

  /// Fire-and-forget hook for the chat path. Never awaited by the UI and never
  /// allowed to throw into message persistence.
  static void dispatchAfterMessagesSaved({
    required String groupId,
    String groupName = '',
    GroupMemoryService Function()? factory,
  }) {
    if (groupId.trim().isEmpty) return;
    unawaited(() async {
      try {
        final service =
            factory?.call() ??
            GroupMemoryService(groupId: groupId, groupName: groupName);
        await service.maybeExtract();
      } catch (_) {
        // Extraction is optional context; failures stay off the chat path.
      }
    }());
  }

  Future<GroupMemoryExtractionOutcome> maybeExtract({DateTime? now}) async {
    final time = now ?? _clock();
    if (!_runningGroups.add(groupId)) {
      _log('skip=alreadyRunning');
      return GroupMemoryExtractionOutcome.alreadyRunning;
    }
    final completion = Completer<void>();
    _runningCompletion[groupId] = completion;
    var state = await _storage.loadState();
    String? terminalMessageId;
    var unprocessed = const <GroupMessage>[];
    try {
      final messages = (await _messagesLoader(
        groupId,
      )).where(_isEligible).toList(growable: false);
      unprocessed = _afterCursor(messages, state);
      if (unprocessed.length < minimumMessages) {
        _log('skip=threshold batchCount=${unprocessed.length}');
        return GroupMemoryExtractionOutcome.insufficientMessages;
      }
      terminalMessageId = unprocessed.last.id;
      final failedAt = state.lastFailureAt;
      if (state.lastFailedMessageId == terminalMessageId &&
          failedAt != null &&
          time.difference(failedAt) < failureCooldown) {
        _log('skip=cooldown batchCount=${unprocessed.length}');
        return GroupMemoryExtractionOutcome.coolingDown;
      }

      final names = await _namesLoader(groupId);
      final events = _extractor.extract(
        groupId: groupId,
        groupName: groupName,
        messages: unprocessed,
        senderNames: names,
        now: time,
      );
      final added = await _storage.appendEvents(events, now: time);
      // Cursor advances even for 0 extracted events: a trivial chat segment must
      // never be re-summarized, and "nothing worth remembering" is a valid result.
      await _storage.saveState(
        state.copyWith(
          lastProcessedMessageId: terminalMessageId,
          lastProcessedAt: unprocessed.last.createdAt,
          lastSuccessfulExtractionAt: time,
          clearFailure: true,
        ),
      );
      _log(
        'success batchCount=${unprocessed.length} candidates=${events.length} added=$added',
      );
      return added > 0
          ? GroupMemoryExtractionOutcome.success
          : GroupMemoryExtractionOutcome.empty;
    } catch (error) {
      if (terminalMessageId != null) {
        try {
          state = state.copyWith(
            lastFailureAt: time,
            lastFailedMessageId: terminalMessageId,
          );
          await _storage.saveState(state);
        } catch (_) {
          // Per-group extraction failure must not escape into the chat path.
        }
      }
      _log('failed errorType=${error.runtimeType}');
      return GroupMemoryExtractionOutcome.failed;
    } finally {
      _runningGroups.remove(groupId);
      _runningCompletion.remove(groupId);
      if (!completion.isCompleted) completion.complete();
    }
  }

  /// Relevance retrieval for the current group turn: a small top-K with a hard
  /// character budget. Returns nothing when the query carries no signal.
  Future<GroupMemoryRetrievalResult> retrieve({
    required String currentMessage,
    List<String> participantIds = const [],
    int limit = maximumRetrievedEvents,
    DateTime? now,
  }) async {
    final query = currentMessage.trim();
    if (query.isEmpty) return GroupMemoryRetrievalResult.none;
    final events = (await _storage.loadEvents())
        .where(
          (item) =>
              item.status != EventMemoryStatus.forgotten &&
              item.content.trim().isNotEmpty,
        )
        .map((item) => MapEntry(item, _score(item.content, query)))
        .where((entry) => entry.value >= minimumRetrievalScore)
        .toList()
      ..sort((a, b) {
        final score = b.value.compareTo(a.value);
        if (score != 0) return score;
        final aTime = a.key.occurredAt ?? a.key.createdAt;
        final bTime = b.key.occurredAt ?? b.key.createdAt;
        return bTime.compareTo(aTime);
      });
    final selected = events
        .take(limit.clamp(1, maximumRetrievedEvents).toInt())
        .map((entry) => entry.key)
        .toList(growable: false);
    return GroupMemoryRetrievalResult(
      events: selected,
      contextText: buildPrompt(groupName: groupName, events: selected),
    );
  }

  /// Labels group memories explicitly as public group history so the model does
  /// not mistake them for a private chat memory with the user.
  static String buildPrompt({
    required String groupName,
    required List<GroupMemoryEvent> events,
  }) {
    if (events.isEmpty) return '';
    final lines = <String>[];
    var remaining = retrievedContextCharacters;
    for (final event in events.take(maximumRetrievedEvents)) {
      final text = event.content.trim();
      if (text.isEmpty) continue;
      final line = text.length <= retrievedItemCharacters
          ? text
          : '${text.substring(0, retrievedItemCharacters - 1).trimRight()}…';
      if (line.length + 2 > remaining) break;
      lines.add('- $line');
      remaining -= line.length + 3;
    }
    if (lines.isEmpty) return '';
    final name = groupName.trim().isEmpty ? '本群' : groupName.trim();
    return '【群聊共同经历｜$name 内公开发生过，不是任何人的私聊记忆】\n'
        '${lines.join('\n')}';
  }

  List<GroupMessage> _afterCursor(
    List<GroupMessage> messages,
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

  bool _isEligible(GroupMessage message) =>
      message.senderType != GroupSenderType.system &&
      message.status != GroupMessageStatus.failed &&
      message.content.trim().isNotEmpty;

  double _score(String candidate, String query) {
    final a = _normalize(candidate);
    final b = _normalize(query);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.contains(b) || b.contains(a)) return 1;
    final candidateTokens = _tokens(a);
    final queryTokens = _tokens(b);
    if (candidateTokens.isEmpty || queryTokens.isEmpty) return 0;
    final denominator = candidateTokens.length < queryTokens.length
        ? candidateTokens.length
        : queryTokens.length;
    return candidateTokens.intersection(queryTokens).length / denominator;
  }

  Set<String> _tokens(String value) {
    final result = <String>{};
    for (final word in RegExp(r'[a-z0-9]+').allMatches(value)) {
      final text = word.group(0)!;
      if (text.length > 1) result.add(text);
    }
    final chinese = value.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
    for (var index = 0; index + 1 < chinese.length; index++) {
      final token = chinese.substring(index, index + 2);
      if (!_stopTokens.contains(token)) result.add(token);
    }
    return result;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(
        RegExp(r"[\s，。！？、：；~～“”‘’()（）\[\]【】《》_\-]+"),
        '',
      );

  void _log(String detail) =>
      _logger('GroupMemoryExtraction groupId=$groupId $detail');

  static Future<Map<String, String>> _defaultSenderNames(String groupId) async {
    try {
      final characters = await CharacterRegistryService().loadCharacters();
      return {
        for (final character in characters)
          if (character.id.trim().isNotEmpty)
            character.id: character.displayName.trim(),
      };
    } catch (_) {
      return const {};
    }
  }

  static const Set<String> _stopTokens = <String>{
    '用户',
    '角色',
    '这个',
    '那个',
    '之前',
    '上次',
    '记得',
    '我们',
    '你们',
    '他们',
    '事情',
    '什么',
    '怎么',
    '一个',
    '已经',
    '还是',
    '自己',
    '现在',
  };
}
