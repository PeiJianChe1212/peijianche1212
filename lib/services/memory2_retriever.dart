import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/event_memory.dart';
import '../models/legacy_memory_view.dart';
import '../models/memory_retrieval_result.dart';
import '../models/user_memory.dart';
import 'event_memory_lifecycle_service.dart';
import 'legacy_memory_adapter.dart';
import 'memory2_storage_service.dart';
import 'memory_diagnostics_service.dart';
import 'legacy_memory_migration_service.dart';
import 'user_memory_key_aliases.dart';

typedef Memory2LegacyViewLoader = Future<List<LegacyMemoryView>> Function();
typedef Memory2RetrieverLogger = void Function(String message);

abstract interface class Memory2RetrieverGateway {
  Future<MemoryRetrievalResult> retrieve({
    required String currentMessage,
    List<ChatMessage> recentMessages,
    required DateTime now,
  });

  Future<void> recordInjectedEvents(
    Iterable<String> eventIds, {
    required DateTime now,
  });
}

class Memory2Retriever implements Memory2RetrieverGateway {
  Memory2Retriever({
    required this.characterId,
    Memory2StorageService? storage,
    EventMemoryLifecycleService? lifecycle,
    Memory2LegacyViewLoader? legacyLoader,
    Memory2RetrieverLogger? logger,
  }) : _storage = storage ?? Memory2StorageService(characterId: characterId),
       _lifecycle =
           lifecycle ?? EventMemoryLifecycleService(characterId: characterId),
       _legacyLoader =
           legacyLoader ??
           LegacyMemoryAdapter(characterId: characterId).loadReadOnlyViews,
       _logger = logger ?? debugPrint;

  static const int maximumUserMemories = 4;
  static const int maximumHistoricalUserMemories = 2;
  static const int maximumEventMemories = 3;
  static const int recentQueryMessages = 4;
  static const int summaryCharacters = 1200;
  static const int userItemCharacters = 180;
  static const int eventItemCharacters = 240;
  static const int legacyItemCharacters = 180;
  static const int totalContextCharacters = 2600;

  final String characterId;
  final Memory2StorageService _storage;
  final EventMemoryLifecycleService _lifecycle;
  final Memory2LegacyViewLoader _legacyLoader;
  final Memory2RetrieverLogger _logger;

  @override
  Future<MemoryRetrievalResult> retrieve({
    required String currentMessage,
    List<ChatMessage> recentMessages = const [],
    required DateTime now,
  }) async {
    var refreshSucceeded = true;
    try {
      await _lifecycle.refresh(now: now);
    } catch (error) {
      refreshSucceeded = false;
      _log('refreshFailed errorType=${error.runtimeType}');
    }

    try {
      final events = await _storage.loadEventMemories();
      final users = await _storage.loadUserMemories();
      final summary = await _storage.loadMemorySummary();
      final legacy = await _legacyLoader();
      final migratedLegacyIds = await LegacyMemoryMigrationService(
        characterId: characterId,
        storage: _storage,
        fileProvider: _storage.fileProvider,
      ).migratedSourceIds(events, users);
      final recallIntent = _hasRecallIntent(currentMessage);
      final query = _querySignals(currentMessage, recentMessages);
      final historicalScores = _hasHistoricalUserIntent(currentMessage)
          ? (users
                .where((m) => m.status == UserMemoryStatus.superseded)
                .map(
                  (m) => _Scored<UserMemory>(m, _userScore(m, currentMessage)),
                )
                .where((m) => m.score >= 0.18)
                .toList()
              ..sort(_compareUsers))
          : <_Scored<UserMemory>>[];
      final allEventScores = events.map((item) {
        final relevance = _relevance(item.content, query);
        return _Scored<EventMemory>(
          item,
          _eventScore(item, relevance.combined, recallIntent),
          currentContribution: relevance.current,
          contextContribution: relevance.context,
        );
      }).toList();
      final eventScores =
          allEventScores
              .where(
                (item) =>
                    item.value.status != EventMemoryStatus.forgotten &&
                    _eventEligible(item.value, item.score, recallIntent),
              )
              .toList()
            ..sort(_compareEvents);
      final userScores =
          users
              .where((item) => item.status == UserMemoryStatus.active)
              .map((item) {
                final relevance = _relevance(
                  item.displayText,
                  query,
                  user: item,
                );
                return _Scored<UserMemory>(
                  item,
                  relevance.combined,
                  currentContribution: relevance.current,
                  contextContribution: relevance.context,
                );
              })
              .where((item) => item.score >= 0.14)
              .toList()
            ..sort(_compareUsers);
      final legacyScores =
          legacy
              .where(
                (item) =>
                    !item.legacyArchived &&
                    !migratedLegacyIds.contains(item.legacySourceId) &&
                    item.kind != LegacyMemoryKind.legacyUnclassified,
              )
              .map((item) {
                final relevance = _relevance(item.content, query);
                return _Scored<LegacyMemoryView>(
                  item,
                  relevance.combined,
                  currentContribution: relevance.current,
                  contextContribution: relevance.context,
                );
              })
              .where((item) => item.score >= 0.18)
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));

      final built = _buildBudgetedContext(
        summaryText: summary.effectiveText,
        users: userScores,
        events: eventScores,
        legacy: legacyScores,
        history: historicalScores,
        allUsers: users,
      );
      _log(
        'retrieved eventCandidates=${eventScores.length} '
        'userCandidates=${userScores.length} '
        'legacyCandidates=${legacyScores.length} '
        'selectedEvents=${built.events.length} '
        'selectedUsers=${built.users.length} '
        'selectedLegacy=${built.legacy.length}',
      );
      _recordDiagnostics(
        now: now,
        currentMessage: currentMessage,
        recallIntent: recallIntent,
        events: events,
        allEventScores: allEventScores,
        eventScores: eventScores,
        selectedEvents: built.events,
        userCandidates: userScores.length,
        legacyCandidates: legacyScores.length,
        selectedUsers: built.users.length,
        selectedLegacy: built.legacy.length,
        summaryInjected: summary.effectiveText.trim().isNotEmpty,
        contextCharacters: built.text.length,
      );
      return MemoryRetrievalResult(
        selectedUserMemories: built.users,
        selectedHistoricalUserMemories: built.history,
        selectedEventMemories: built.events,
        selectedLegacyMemories: built.legacy,
        memorySummary: summary,
        contextText: built.text,
        diagnostics: MemoryRetrievalDiagnostics(
          eventCandidates: eventScores.length,
          userCandidates: userScores.length,
          legacyCandidates: legacyScores.length,
          recallIntent: recallIntent,
          lifecycleRefreshSucceeded: refreshSucceeded,
        ),
      );
    } catch (error) {
      _log('retrievalFailed errorType=${error.runtimeType}');
      final summary = await _storage.loadMemorySummary();
      return MemoryRetrievalResult(
        memorySummary: summary,
        diagnostics: MemoryRetrievalDiagnostics(
          eventCandidates: 0,
          userCandidates: 0,
          legacyCandidates: 0,
          recallIntent: _hasRecallIntent(currentMessage),
          lifecycleRefreshSucceeded: refreshSucceeded,
        ),
      );
    }
  }

  @override
  Future<void> recordInjectedEvents(
    Iterable<String> eventIds, {
    required DateTime now,
  }) async {
    for (final id in eventIds.toSet()) {
      try {
        final success = await _lifecycle.markRecalled(id, now: now);
        MemoryDiagnosticsService.recordRecall(
          characterId: characterId,
          success: success,
        );
      } catch (error) {
        MemoryDiagnosticsService.recordRecall(
          characterId: characterId,
          success: false,
        );
        _log('recallWriteFailed eventId=$id errorType=${error.runtimeType}');
      }
    }
  }

  void _recordDiagnostics({
    required DateTime now,
    required String currentMessage,
    required bool recallIntent,
    required List<EventMemory> events,
    required List<_Scored<EventMemory>> allEventScores,
    required List<_Scored<EventMemory>> eventScores,
    required List<EventMemory> selectedEvents,
    required int userCandidates,
    required int legacyCandidates,
    required int selectedUsers,
    required int selectedLegacy,
    required bool summaryInjected,
    required int contextCharacters,
  }) {
    if (!MemoryDiagnosticsService.enabled) return;
    final eligibleIds = eventScores.map((e) => e.value.id).toList();
    final selectedIds = selectedEvents.map((e) => e.id).toSet();
    final items = events
        .map((event) {
          _Scored<EventMemory>? scored;
          for (final candidate in allEventScores) {
            if (candidate.value.id == event.id) {
              scored = candidate;
              break;
            }
          }
          final relevance = scored == null
              ? _relevance(
                  event.content,
                  _querySignals(currentMessage, const []),
                )
              : _RelevanceScore(
                  current: scored.currentContribution,
                  context: scored.contextContribution,
                );
          final score =
              scored?.score ??
              _eventScore(event, relevance.combined, recallIntent);
          MemoryDiagnosticReason reason;
          if (event.status == EventMemoryStatus.forgotten) {
            reason = MemoryDiagnosticReason.forgotten;
          } else if (!_eventEligible(event, score, recallIntent)) {
            reason = event.status == EventMemoryStatus.pendingForget
                ? MemoryDiagnosticReason.pendingThreshold
                : MemoryDiagnosticReason.lowRelevance;
          } else if (selectedIds.contains(event.id)) {
            reason = MemoryDiagnosticReason.selected;
          } else {
            final rank = eligibleIds.indexOf(event.id);
            reason = rank >= maximumEventMemories
                ? MemoryDiagnosticReason.maxCount
                : MemoryDiagnosticReason.budgetTrimmed;
          }
          return MemoryRetrieverItemReport(
            id: event.id,
            status: event.status.name,
            score: score,
            reason: reason,
            currentQueryContribution: relevance.current,
            contextExpansionContribution: relevance.context,
          );
        })
        .toList(growable: false);
    MemoryDiagnosticsService.recordRetriever(
      MemoryRetrieverReport(
        characterId: characterId,
        createdAt: now,
        queryLength: currentMessage.trim().length,
        recallIntent: recallIntent,
        eventCandidates: eventScores.length,
        userCandidates: userCandidates,
        legacyCandidates: legacyCandidates,
        eventItems: items,
        selectedEventCount: selectedEvents.length,
        selectedUserCount: selectedUsers,
        legacyFallbackCount: selectedLegacy,
        summaryInjected: summaryInjected,
        contextCharacters: contextCharacters,
      ),
    );
  }

  bool _eventEligible(EventMemory memory, double score, bool recallIntent) {
    if (memory.status == EventMemoryStatus.pendingForget) {
      return score >= (recallIntent ? 0.38 : 0.48);
    }
    return score >= (recallIntent ? 0.12 : 0.18);
  }

  double _eventScore(EventMemory memory, double relevance, bool recallIntent) {
    var value = relevance;
    if (memory.status == EventMemoryStatus.fading) value *= 0.94;
    if (memory.isPinned) value += 0.03;
    if (recallIntent) value += 0.06;
    return value.clamp(0, 1).toDouble();
  }

  int _compareEvents(_Scored<EventMemory> a, _Scored<EventMemory> b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final aTime = a.value.lastRecalledAt ?? a.value.createdAt;
    final bTime = b.value.lastRecalledAt ?? b.value.createdAt;
    return bTime.compareTo(aTime);
  }

  int _compareUsers(_Scored<UserMemory> a, _Scored<UserMemory> b) {
    final score = b.score.compareTo(a.score);
    return score != 0 ? score : b.value.updatedAt.compareTo(a.value.updatedAt);
  }

  _BuiltContext _buildBudgetedContext({
    required String summaryText,
    required List<_Scored<UserMemory>> users,
    required List<_Scored<EventMemory>> events,
    required List<_Scored<LegacyMemoryView>> legacy,
    required List<_Scored<UserMemory>> history,
    required List<UserMemory> allUsers,
  }) {
    final sections = <String>[];
    final selectedUsers = <UserMemory>[];
    final selectedEvents = <EventMemory>[];
    final selectedLegacy = <LegacyMemoryView>[];
    final selectedHistory = <UserMemory>[];
    var remaining = totalContextCharacters;

    void addSection(String title, List<String> lines) {
      if (lines.isEmpty) return;
      final text = '【$title】\n${lines.join('\n')}';
      if (text.length > remaining) return;
      sections.add(text);
      remaining -= text.length + 2;
    }

    final summary = _truncate(summaryText, summaryCharacters);
    addSection('长期记忆汇总', summary.isEmpty ? const [] : [summary]);

    final userLines = <String>[];
    for (final scored in users.take(maximumUserMemories)) {
      final line =
          '- ${_truncate(scored.value.displayText, userItemCharacters)}';
      if (!_fits('关于用户的记忆', userLines, line, remaining)) break;
      userLines.add(line);
      selectedUsers.add(scored.value);
    }
    addSection('关于用户的记忆', userLines);

    final historyLines = <String>[];
    const historyTitle = '过去的用户事实｜仅回答过去，当前事实优先';
    for (final scored in history.take(maximumHistoricalUserMemories)) {
      final current = _currentVersion(scored.value, allUsers);
      final line =
          '- 过去：${_truncate(scored.value.displayText, userItemCharacters)}'
          '${current == null ? '；当前状态未知' : '；当前：${_truncate(current.displayText, userItemCharacters)}'}';
      if (!_fits(historyTitle, historyLines, line, remaining)) break;
      historyLines.add(line);
      selectedHistory.add(scored.value);
    }
    addSection(historyTitle, historyLines);

    final eventLines = <String>[];
    for (final scored in events.take(maximumEventMemories)) {
      final line = '- ${_truncate(scored.value.content, eventItemCharacters)}';
      if (!_fits('相关共同经历', eventLines, line, remaining)) break;
      eventLines.add(line);
      selectedEvents.add(scored.value);
    }
    addSection('相关共同经历', eventLines);

    final selectedNormalized = <String>{
      ...selectedUsers.map((item) => _normalize(item.displayText)),
      ...selectedEvents.map((item) => _normalize(item.content)),
    };
    final legacyLines = <String>[];
    var legacyUsers = 0;
    var legacyEvents = 0;
    for (final scored in legacy) {
      if ((scored.value.kind == LegacyMemoryKind.user &&
              selectedUsers.length + legacyUsers >= maximumUserMemories) ||
          (scored.value.kind == LegacyMemoryKind.event &&
              selectedEvents.length + legacyEvents >= maximumEventMemories)) {
        continue;
      }
      final normalized = _normalize(scored.value.content);
      if (selectedNormalized.any(
        (item) =>
            item == normalized ||
            item.contains(normalized) ||
            normalized.contains(item),
      )) {
        continue;
      }
      final line = '- ${_truncate(scored.value.content, legacyItemCharacters)}';
      if (!_fits('旧记忆兼容', legacyLines, line, remaining)) break;
      legacyLines.add(line);
      selectedLegacy.add(scored.value);
      selectedNormalized.add(normalized);
      if (scored.value.kind == LegacyMemoryKind.user) legacyUsers++;
      if (scored.value.kind == LegacyMemoryKind.event) legacyEvents++;
    }
    addSection('旧记忆兼容', legacyLines);
    return _BuiltContext(
      text: sections.join('\n\n'),
      users: selectedUsers,
      events: selectedEvents,
      legacy: selectedLegacy,
      history: selectedHistory,
    );
  }

  bool _fits(String title, List<String> lines, String next, int remaining) =>
      '【$title】\n${[...lines, next].join('\n')}'.length <= remaining;

  UserMemory? _currentVersion(UserMemory historical, List<UserMemory> users) {
    var next = historical.supersededById;
    final visited = <String>{historical.id};
    while (next != null && visited.add(next)) {
      final item = users.where((m) => m.id == next).firstOrNull;
      if (item == null) break;
      if (item.status == UserMemoryStatus.active) return item;
      next = item.supersededById;
    }
    return users
        .where(
          (m) => m.status == UserMemoryStatus.active && m.key == historical.key,
        )
        .firstOrNull;
  }

  _QuerySignals _querySignals(String current, List<ChatMessage> recent) {
    final cleaned = _withoutRecallPhrases(current).trim();
    final context = recent.reversed
        .where((item) => item.content.trim().isNotEmpty)
        .take(recentQueryMessages)
        .map((item) => item.content)
        .toList(growable: false);
    return _QuerySignals(
      current: cleaned,
      context: context,
      allowContextExpansion: _isAmbiguousCurrentMessage(current, cleaned),
    );
  }

  double _userScore(UserMemory user, String query) {
    final lexical = _score(user.displayText, query);
    final alias = UserMemoryKeyAliases.relevance(user.key, query);
    return lexical > alias ? lexical : alias;
  }

  _RelevanceScore _relevance(
    String candidate,
    _QuerySignals query, {
    UserMemory? user,
  }) {
    double score(String text) =>
        user == null ? _score(candidate, text) : _userScore(user, text);
    final current = score(query.current);
    if (!query.allowContextExpansion) {
      return _RelevanceScore(current: current, context: 0);
    }
    const weights = <double>[0.30, 0.14, 0.08, 0.04];
    var context = 0.0;
    for (
      var index = 0;
      index < query.context.length && index < weights.length;
      index++
    ) {
      final contribution = score(query.context[index]) * weights[index];
      if (contribution > context) context = contribution;
    }
    return _RelevanceScore(current: current, context: context);
  }

  bool _isAmbiguousCurrentMessage(String original, String cleaned) {
    if (_normalize(cleaned).isEmpty) return true;
    if (RegExp(
      r'^(你)?(觉得|认为|看)(怎么样|如何|呢)|^(然后呢|继续|what do you think|how about that)[？?。.!！]*$',
      caseSensitive: false,
    ).hasMatch(cleaned.trim())) {
      return true;
    }
    final hasReference = RegExp(
      r'那个|那件|那盆|那次|它|这个|这件|哪儿|哪里|放哪|what about it|where was it',
      caseSensitive: false,
    ).hasMatch(original);
    if (!hasReference) return false;
    final residual = cleaned.toLowerCase().replaceAll(
      RegExp(
        r'那个|那件|那盆|那次|它|这个|这件|哪儿|哪里|放哪|最后|还|了|吗|呢|在|到|是|的|what about it|where was it',
        caseSensitive: false,
      ),
      '',
    );
    return _normalize(residual).length <= 4;
  }

  double _score(String candidate, String query) {
    final scores = <double>[_scoreSingle(candidate, query)];
    for (final part in query.split(RegExp(r'\s+'))) {
      final word = part.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (word.length > 1 && !_stopWords.contains(word)) {
        scores.add(_scoreSingle(candidate, word));
      }
    }
    return scores.reduce((left, right) => left > right ? left : right);
  }

  double _scoreSingle(String candidate, String query) {
    final a = _normalize(candidate);
    final b = _normalize(query);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.contains(b) || b.contains(a)) return 1;
    final candidateTokens = _tokens(a);
    final queryTokens = _tokens(b);
    if (candidateTokens.isEmpty || queryTokens.isEmpty) return 0;
    final overlap = candidateTokens.intersection(queryTokens).length;
    final denominator = candidateTokens.length < queryTokens.length
        ? candidateTokens.length
        : queryTokens.length;
    return overlap / denominator;
  }

  Set<String> _tokens(String value) {
    final result = <String>{};
    for (final word in RegExp(r'[a-z0-9]+').allMatches(value)) {
      if (word.group(0) case final text?
          when text.length > 1 && !_stopWords.contains(text)) {
        result.add(text);
      }
    }
    final chinese = value.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
    for (var index = 0; index + 1 < chinese.length; index++) {
      final token = chinese.substring(index, index + 2);
      if (!_stopTokens.contains(token)) result.add(token);
    }
    return result;
  }

  bool _hasRecallIntent(String value) {
    final lower = value.toLowerCase();
    return const <String>[
      '还记得',
      '记不记得',
      '上次',
      '之前',
      '那次',
      '以前跟你说过',
      'remember',
      'last time',
      'before',
    ].any(lower.contains);
  }

  bool _hasHistoricalUserIntent(String value) =>
      RegExp(
        r'(以前|过去|之前|原来).{0,20}(喜欢|偏好|习惯|喝|吃|工作|是不是)|我.{0,6}(以前|过去|之前).{0,16}(什么|怎样|如何)|used to',
        caseSensitive: false,
      ).hasMatch(value) &&
      !RegExp(r'不用回忆|别提过去|不要回忆').hasMatch(value);

  String _withoutRecallPhrases(String value) {
    var result = value.toLowerCase();
    for (final phrase in const <String>[
      '还记得',
      '记不记得',
      '上次',
      '之前',
      '那次',
      '我以前跟你说过',
      'remember',
      'last time',
      'before',
    ]) {
      result = result.replaceAll(phrase, ' ');
    }
    result = result.replaceAll(RegExp(r'那件|这个|那个|吗'), ' ');
    return result;
  }

  String _normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r"[\s，。！？、,.!?~～“”'‘’（）()\[\]【】:_：-]"),
    '',
  );

  String _truncate(String value, int maximum) {
    final clean = value.trim();
    if (clean.length <= maximum) return clean;
    return '${clean.substring(0, maximum - 1).trimRight()}…';
  }

  void _log(String detail) =>
      _logger('Memory2Retriever characterId=$characterId $detail');

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
    '时候',
    '什么',
    '怎么',
    '一个',
    '已经',
    '还是',
  };

  static const Set<String> _stopWords = <String>{
    'and',
    'are',
    'but',
    'for',
    'from',
    'have',
    'not',
    'that',
    'the',
    'this',
    'was',
    'were',
    'what',
    'where',
    'with',
    'you',
    'your',
  };
}

class _Scored<T> {
  const _Scored(
    this.value,
    this.score, {
    this.currentContribution = 0,
    this.contextContribution = 0,
  });
  final T value;
  final double score;
  final double currentContribution;
  final double contextContribution;
}

class _QuerySignals {
  const _QuerySignals({
    required this.current,
    required this.context,
    required this.allowContextExpansion,
  });
  final String current;
  final List<String> context;
  final bool allowContextExpansion;
}

class _RelevanceScore {
  const _RelevanceScore({required this.current, required this.context});
  final double current;
  final double context;
  double get combined => current > context ? current : context;
}

class _BuiltContext {
  const _BuiltContext({
    required this.text,
    required this.users,
    required this.events,
    required this.legacy,
    required this.history,
  });
  final String text;
  final List<UserMemory> users;
  final List<EventMemory> events;
  final List<LegacyMemoryView> legacy;
  final List<UserMemory> history;
}
