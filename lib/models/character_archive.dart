class CharacterArchive {
  const CharacterArchive({required this.characterId, this.values = const {}});

  final String characterId;
  final Map<String, String> values;

  static const fieldKeys = <String>[
    'likes',
    'dislikes',
    'favoriteFood',
    'favoriteColor',
    'favoriteMusic',
    'collections',
    'smallHabits',
    'inLove',
    'trueAffection',
    'whenUnhappy',
    'whenAngry',
    'whenJealous',
    'whenAfraid',
    'whenVulnerable',
    'lifeGoal',
    'futureView',
    'moneyView',
    'loveView',
    'importantPrinciples',
    'frequentPlaces',
    'friends',
    'workPartners',
    'livingHabits',
    'dailyState',
    'era',
    'socialEnvironment',
    'importantPlaces',
    'rolePosition',
    'currentState',
    'languageHabits',
    'commonExpressions',
    'speakingStyle',
    'chatPace',
    'expressionTraits',
    'childhoodExperience',
    'adolescence',
    'turningPoints',
    'influentialPeople',
    'lifeExperience',
  ];

  String value(String key) => values[key] ?? '';

  CharacterArchive merge(Map<String, String> updates) => CharacterArchive(
    characterId: characterId,
    values: {...values, ...updates},
  );

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'values': values,
  };

  factory CharacterArchive.fromJson(Map<dynamic, dynamic> json, String id) {
    final rawValues = json['values'];
    final values = <String, String>{};
    if (rawValues is Map) {
      for (final entry in rawValues.entries) {
        values[entry.key.toString()] = entry.value?.toString().trim() ?? '';
      }
    }
    return CharacterArchive(characterId: id, values: values);
  }
}
