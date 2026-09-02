import '../config/peilink_runtime.dart';

enum MemoryDiagnosticReason {
  lowRelevance,
  forgotten,
  pendingThreshold,
  duplicate,
  budgetTrimmed,
  maxCount,
  selected,
}

class MemoryExtractionReport {
  const MemoryExtractionReport({
    required this.characterId,
    required this.triggeredAt,
    required this.result,
    this.batchMessageCount = 0,
    this.userMessageCount = 0,
    this.firstMessageId,
    this.lastMessageId,
    this.providerName = 'configuredChatProvider',
    this.eventCandidateCount = 0,
    this.userCandidateCount = 0,
    this.eventWrittenCount = 0,
    this.userCreatedCount = 0,
    this.userUpdatedCount = 0,
    this.eventDeduplicatedCount = 0,
    this.failureType,
    this.rawResponseShape,
    this.parseOutcome,
    this.cursorAdvanced = false,
    this.eventTexts = const [],
    this.userTexts = const [],
  });
  final String characterId;
  final DateTime triggeredAt;
  final String result;
  final int batchMessageCount;
  final int userMessageCount;
  final String? firstMessageId;
  final String? lastMessageId;
  final String providerName;
  final int eventCandidateCount;
  final int userCandidateCount;
  final int eventWrittenCount;
  final int userCreatedCount;
  final int userUpdatedCount;
  final int eventDeduplicatedCount;
  final String? failureType;
  final String? rawResponseShape;
  final String? parseOutcome;
  final bool cursorAdvanced;
  final List<String> eventTexts;
  final List<String> userTexts;
}

class MemoryRetrieverItemReport {
  const MemoryRetrieverItemReport({
    required this.id,
    required this.status,
    required this.score,
    required this.reason,
    this.currentQueryContribution = 0,
    this.contextExpansionContribution = 0,
  });
  final String id;
  final String status;
  final double score;
  final MemoryDiagnosticReason reason;
  final double currentQueryContribution;
  final double contextExpansionContribution;
}

class MemoryRetrieverReport {
  const MemoryRetrieverReport({
    required this.characterId,
    required this.createdAt,
    required this.queryLength,
    required this.recallIntent,
    required this.eventCandidates,
    required this.userCandidates,
    required this.legacyCandidates,
    required this.eventItems,
    required this.selectedEventCount,
    required this.selectedUserCount,
    required this.legacyFallbackCount,
    required this.summaryInjected,
    required this.contextCharacters,
    this.characterUserProfileInjected = false,
    this.injectedEventIds = const [],
    this.recallSuccessCount = 0,
    this.recallFailureCount = 0,
  });
  final String characterId;
  final DateTime createdAt;
  final int queryLength;
  final bool recallIntent;
  final int eventCandidates;
  final int userCandidates;
  final int legacyCandidates;
  final List<MemoryRetrieverItemReport> eventItems;
  final int selectedEventCount;
  final int selectedUserCount;
  final int legacyFallbackCount;
  final bool summaryInjected;
  final bool characterUserProfileInjected;
  final int contextCharacters;
  final List<String> injectedEventIds;
  final int recallSuccessCount;
  final int recallFailureCount;

  MemoryRetrieverReport copyWith({
    bool? characterUserProfileInjected,
    List<String>? injectedEventIds,
    int? recallSuccessCount,
    int? recallFailureCount,
  }) => MemoryRetrieverReport(
    characterId: characterId,
    createdAt: createdAt,
    queryLength: queryLength,
    recallIntent: recallIntent,
    eventCandidates: eventCandidates,
    userCandidates: userCandidates,
    legacyCandidates: legacyCandidates,
    eventItems: eventItems,
    selectedEventCount: selectedEventCount,
    selectedUserCount: selectedUserCount,
    legacyFallbackCount: legacyFallbackCount,
    summaryInjected: summaryInjected,
    characterUserProfileInjected:
        characterUserProfileInjected ?? this.characterUserProfileInjected,
    contextCharacters: contextCharacters,
    injectedEventIds: injectedEventIds ?? this.injectedEventIds,
    recallSuccessCount: recallSuccessCount ?? this.recallSuccessCount,
    recallFailureCount: recallFailureCount ?? this.recallFailureCount,
  );
}

class MemoryDiagnosticsService {
  MemoryDiagnosticsService._();
  static const int capacity = 10;
  static final List<MemoryExtractionReport> _extractions = [];
  static final List<MemoryRetrieverReport> _retrievers = [];
  static bool? debugEnabledOverride;
  static bool get enabled =>
      debugEnabledOverride ?? PeiLinkRuntime.developerToolsEnabled;
  static List<MemoryExtractionReport> get extractionReports =>
      List.unmodifiable(_extractions);
  static List<MemoryRetrieverReport> get retrieverReports =>
      List.unmodifiable(_retrievers);
  static MemoryExtractionReport? extractionFor(String characterId) =>
      _latest(_extractions.where((e) => e.characterId == characterId));
  static MemoryRetrieverReport? retrieverFor(String characterId) =>
      _latest(_retrievers.where((e) => e.characterId == characterId));

  static T? _latest<T>(Iterable<T> values) =>
      values.isEmpty ? null : values.last;
  static void recordExtraction(MemoryExtractionReport report) {
    if (!enabled) return;
    _append(_extractions, report);
  }

  static void recordRetriever(MemoryRetrieverReport report) {
    if (!enabled) return;
    _append(_retrievers, report);
  }

  static void recordPromptInjection({
    required String characterId,
    required List<String> eventIds,
    required bool characterUserProfileInjected,
  }) {
    if (!enabled) return;
    final index = _retrievers.lastIndexWhere(
      (e) => e.characterId == characterId,
    );
    if (index < 0) return;
    _retrievers[index] = _retrievers[index].copyWith(
      injectedEventIds: List.unmodifiable(eventIds),
      characterUserProfileInjected: characterUserProfileInjected,
    );
  }

  static void recordRecall({
    required String characterId,
    required bool success,
  }) {
    if (!enabled) return;
    final index = _retrievers.lastIndexWhere(
      (e) => e.characterId == characterId,
    );
    if (index < 0) return;
    final old = _retrievers[index];
    _retrievers[index] = old.copyWith(
      recallSuccessCount: old.recallSuccessCount + (success ? 1 : 0),
      recallFailureCount: old.recallFailureCount + (success ? 0 : 1),
    );
  }

  static void clearForTests() {
    _extractions.clear();
    _retrievers.clear();
  }

  static void _append<T>(List<T> target, T value) {
    target.add(value);
    if (target.length > capacity) {
      target.removeRange(0, target.length - capacity);
    }
  }
}
