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
  }) {
    final roll = _hash('$characterId|${now.hour}|moment') % 100;
    return roll < activeShareChance(recentUserMessages);
  }

  int _hash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 37 + unit) & 0x7fffffff;
    }
    return hash;
  }
}
