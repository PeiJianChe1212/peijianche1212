enum SharedExperienceType {
  encounter,
  conversation,
  cooperation,
  help,
  celebration,
  travel,
  dailyLife,
  tension,
  other,
}

extension SharedExperienceTypeText on SharedExperienceType {
  String get label => switch (this) {
        SharedExperienceType.encounter => '偶遇',
        SharedExperienceType.conversation => '交流',
        SharedExperienceType.cooperation => '合作',
        SharedExperienceType.help => '互相帮助',
        SharedExperienceType.celebration => '共同庆祝',
        SharedExperienceType.travel => '共同出行',
        SharedExperienceType.dailyLife => '日常相处',
        SharedExperienceType.tension => '轻微不愉快',
        SharedExperienceType.other => '共同经历',
      };
}

class SharedExperience {
  const SharedExperience({
    required this.id,
    required this.participantIds,
    required this.participantNames,
    required this.type,
    required this.summary,
    required this.occurredAt,
    required this.createdAt,
    this.sourceLifeEventId = '',
    this.decisionId = '',
    this.location = '',
    this.importance = 1,
    this.detail = '',
    this.relationshipOpportunityId = '',
  });

  final String id;
  final List<String> participantIds;
  final List<String> participantNames;
  final SharedExperienceType type;
  final String summary;
  final String detail;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String sourceLifeEventId;
  final String decisionId;
  final String location;
  final int importance;
  final String relationshipOpportunityId;

  bool containsParticipant(String characterId) =>
      participantIds.contains(characterId);

  bool containsPair(String firstId, String secondId) =>
      participantIds.contains(firstId) && participantIds.contains(secondId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'participantIds': participantIds,
        'participantNames': participantNames,
        'type': type.name,
        'summary': summary,
        'detail': detail,
        'occurredAt': occurredAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'sourceLifeEventId': sourceLifeEventId,
        'decisionId': decisionId,
        'location': location,
        'importance': importance,
        'relationshipOpportunityId': relationshipOpportunityId,
      };

  factory SharedExperience.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    return SharedExperience(
      id: _text(json['id']).isEmpty
          ? 'shared_experience_${now.microsecondsSinceEpoch}'
          : _text(json['id']),
      participantIds: _stringList(json['participantIds']),
      participantNames: _stringList(json['participantNames']),
      type: SharedExperienceType.values.firstWhere(
        (item) => item.name == _text(json['type']),
        orElse: () => SharedExperienceType.other,
      ),
      summary: _text(json['summary']),
      detail: _text(json['detail']),
      occurredAt: DateTime.tryParse(_text(json['occurredAt'])) ?? now,
      createdAt: DateTime.tryParse(_text(json['createdAt'])) ?? now,
      sourceLifeEventId: _text(json['sourceLifeEventId']),
      decisionId: _text(json['decisionId']),
      location: _text(json['location']),
      importance: _readImportance(json['importance']),
      relationshipOpportunityId:
          _text(json['relationshipOpportunityId']),
    );
  }

  static String buildId({
    required String sourceLifeEventId,
    required String firstId,
    required String secondId,
  }) {
    final ids = [firstId.trim(), secondId.trim()]..sort();
    final source = sourceLifeEventId.trim();
    if (source.isNotEmpty) {
      return 'shared_${source}_${ids[0]}__${ids[1]}';
    }
    return 'shared_${DateTime.now().microsecondsSinceEpoch}_${ids[0]}__${ids[1]}';
  }

  static int _readImportance(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return (parsed ?? 1).clamp(1, 3);
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(_text)
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }
}
