import 'event_memory.dart';
import 'legacy_memory_view.dart';
import 'memory_summary.dart';
import 'user_memory.dart';

class MemoryRetrievalDiagnostics {
  const MemoryRetrievalDiagnostics({
    required this.eventCandidates,
    required this.userCandidates,
    required this.legacyCandidates,
    required this.recallIntent,
    required this.lifecycleRefreshSucceeded,
  });

  final int eventCandidates;
  final int userCandidates;
  final int legacyCandidates;
  final bool recallIntent;
  final bool lifecycleRefreshSucceeded;
}

class MemoryRetrievalResult {
  const MemoryRetrievalResult({
    this.selectedUserMemories = const [],
    this.selectedEventMemories = const [],
    this.selectedLegacyMemories = const [],
    required this.memorySummary,
    this.contextText = '',
    required this.diagnostics,
  });

  final List<UserMemory> selectedUserMemories;
  final List<EventMemory> selectedEventMemories;
  final List<LegacyMemoryView> selectedLegacyMemories;
  final MemorySummary memorySummary;
  final String contextText;
  final MemoryRetrievalDiagnostics diagnostics;

  List<String> get injectedEventIds =>
      selectedEventMemories.map((item) => item.id).toList(growable: false);
}
