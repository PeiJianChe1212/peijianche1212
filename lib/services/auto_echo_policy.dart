import '../models/relationship_growth_behavior.dart';

class EchoActivityPattern {
  const EchoActivityPattern({
    required this.preferredStartHour,
    required this.preferredEndHour,
    required this.quietCycleDays,
  });

  final int preferredStartHour;
  final int preferredEndHour;
  final int quietCycleDays;

  bool containsHour(int hour) {
    if (preferredStartHour <= preferredEndHour) {
      return hour >= preferredStartHour && hour <= preferredEndHour;
    }
    return hour >= preferredStartHour || hour <= preferredEndHour;
  }
}

class AutoEchoPolicy {
  const AutoEchoPolicy();

  int guaranteeDays(String characterId, DateTime? lastPublishedAt) =>
      1 + _hash('$characterId|${lastPublishedAt?.day ?? 0}') % 3;

  bool isDailyDue({
    required String characterId,
    required DateTime now,
    required DateTime? lastPublishedAt,
  }) {
    if (lastPublishedAt == null) return true;
    return now.difference(lastPublishedAt) >=
        Duration(days: guaranteeDays(characterId, lastPublishedAt));
  }

  EchoActivityPattern activityPattern(
    String characterId, {
    int recentUserMessages = 0,
  }) {
    final seed = _hash('$characterId|activity-pattern');
    final start = 7 + seed % 8;
    final span = recentUserMessages >= 20 ? 12 : 8 + (seed ~/ 11) % 4;
    return EchoActivityPattern(
      preferredStartHour: start,
      preferredEndHour: (start + span) % 24,
      quietCycleDays: 2 + (seed ~/ 29) % 4,
    );
  }

  bool isPreferredActiveTime({
    required String characterId,
    required DateTime now,
    int recentUserMessages = 0,
  }) => activityPattern(
    characterId,
    recentUserMessages: recentUserMessages,
  ).containsHour(now.hour);

  bool isQuietCycle({required String characterId, required DateTime now}) {
    final pattern = activityPattern(characterId);
    final day = now.difference(DateTime(2024)).inDays;
    return (day + _hash(characterId)) % pattern.quietCycleDays == 0;
  }

  DateTime distributedCreatedAt({
    required String characterId,
    required DateTime now,
    required String trigger,
    int recentUserMessages = 0,
    bool offlineReturn = false,
  }) {
    if (trigger == 'initial') return now;
    final seed = _hash(
      '$characterId|${now.year}-${now.month}-${now.day}|$trigger|time',
    );
    final maxMinutes = offlineReturn
        ? 30 * 60
        : recentUserMessages >= 20
        ? 90
        : isPreferredActiveTime(
            characterId: characterId,
            now: now,
            recentUserMessages: recentUserMessages,
          )
        ? 180
        : 12 * 60;
    final offset = 2 + seed % maxMinutes;
    return now.subtract(Duration(minutes: offset));
  }

  int activeShareChance(int recentUserMessages) {
    if (recentUserMessages >= 100) return 85;
    if (recentUserMessages >= 40) return 60;
    if (recentUserMessages >= 10) return 38;
    return 20;
  }

  bool shouldTryMoment({
    required String characterId,
    required DateTime now,
    required int recentUserMessages,
    int relationshipLevel = 1,
  }) {
    if (isQuietCycle(characterId: characterId, now: now) &&
        recentUserMessages < 10) {
      return false;
    }
    final activeModifier =
        isPreferredActiveTime(
          characterId: characterId,
          now: now,
          recentUserMessages: recentUserMessages,
        )
        ? 12
        : -8;
    final growthModifier = RelationshipGrowthBehavior.forLevel(
      relationshipLevel,
    ).shareChanceModifier;
    final chance =
        (activeShareChance(recentUserMessages) +
                activeModifier +
                growthModifier)
            .clamp(5, 92);
    final roll = _hash('$characterId|${now.hour}|moment') % 100;
    return roll < chance;
  }

  int _hash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 37 + unit) & 0x7fffffff;
    }
    return hash;
  }
}
