class WorldTickState {
  const WorldTickState({
    required this.lastTickAt,
    required this.lastForegroundAt,
    required this.sequence,
  });

  final DateTime? lastTickAt;
  final DateTime? lastForegroundAt;
  final int sequence;

  WorldTickState copyWith({
    DateTime? lastTickAt,
    bool clearLastTickAt = false,
    DateTime? lastForegroundAt,
    bool clearLastForegroundAt = false,
    int? sequence,
  }) {
    return WorldTickState(
      lastTickAt: clearLastTickAt ? null : (lastTickAt ?? this.lastTickAt),
      lastForegroundAt: clearLastForegroundAt
          ? null
          : (lastForegroundAt ?? this.lastForegroundAt),
      sequence: sequence ?? this.sequence,
    );
  }

  Map<String, dynamic> toJson() => {
        'lastTickAt': lastTickAt?.toIso8601String(),
        'lastForegroundAt': lastForegroundAt?.toIso8601String(),
        'sequence': sequence,
      };

  factory WorldTickState.fromJson(Map<dynamic, dynamic> json) {
    return WorldTickState(
      lastTickAt: DateTime.tryParse(json['lastTickAt']?.toString() ?? ''),
      lastForegroundAt:
          DateTime.tryParse(json['lastForegroundAt']?.toString() ?? ''),
      sequence: int.tryParse(json['sequence']?.toString() ?? '') ?? 0,
    );
  }

  factory WorldTickState.initial() => const WorldTickState(
        lastTickAt: null,
        lastForegroundAt: null,
        sequence: 0,
      );
}

class CharacterTickSnapshot {
  const CharacterTickSnapshot({
    required this.characterId,
    required this.availableLifeEvents,
    required this.pendingLifeEvents,
    this.nextPendingAt,
    this.decisionsCompleted = 0,
    this.decisionsInterrupted = 0,
  });

  final String characterId;
  final int availableLifeEvents;
  final int pendingLifeEvents;
  final DateTime? nextPendingAt;
  final int decisionsCompleted;
  final int decisionsInterrupted;
}

class WorldTickReport {
  const WorldTickReport({
    required this.executed,
    required this.tickAt,
    required this.elapsed,
    required this.crossedDayBoundary,
    required this.crossedTimePeriod,
    required this.characterSnapshots,
    this.previousTickAt,
    this.worldEffectsCreated = 0,
    this.worldEffectsRefreshed = 0,
    this.worldEffectsEnded = 0,
    this.worldStatesEnded = 0,
  });

  final bool executed;
  final DateTime tickAt;
  final DateTime? previousTickAt;
  final Duration elapsed;
  final bool crossedDayBoundary;
  final bool crossedTimePeriod;
  final List<CharacterTickSnapshot> characterSnapshots;
  final int worldEffectsCreated;
  final int worldEffectsRefreshed;
  final int worldEffectsEnded;
  final int worldStatesEnded;

  int get totalWorldChanges =>
      worldEffectsCreated +
      worldEffectsRefreshed +
      worldEffectsEnded +
      worldStatesEnded;

  int get totalAvailableLifeEvents => characterSnapshots.fold(
        0,
        (total, item) => total + item.availableLifeEvents,
      );

  int get totalPendingLifeEvents => characterSnapshots.fold(
        0,
        (total, item) => total + item.pendingLifeEvents,
      );

  int get totalDecisionsCompleted => characterSnapshots.fold(
        0,
        (total, item) => total + item.decisionsCompleted,
      );

  int get totalDecisionsInterrupted => characterSnapshots.fold(
        0,
        (total, item) => total + item.decisionsInterrupted,
      );
}
