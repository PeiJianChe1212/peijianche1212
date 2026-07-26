enum RelationshipOpportunityType {
  encounter,
  conversation,
  cooperation,
  help,
  sharedRoutine,
  celebration,
}

extension RelationshipOpportunityTypeText on RelationshipOpportunityType {
  String get label => switch (this) {
        RelationshipOpportunityType.encounter => '自然碰面',
        RelationshipOpportunityType.conversation => '顺势交流',
        RelationshipOpportunityType.cooperation => '共同处理事情',
        RelationshipOpportunityType.help => '提供帮助',
        RelationshipOpportunityType.sharedRoutine => '共享日常',
        RelationshipOpportunityType.celebration => '共同庆祝',
      };
}

class RelationshipOpportunity {
  const RelationshipOpportunity({
    required this.id,
    required this.currentCharacterId,
    required this.otherCharacterId,
    required this.otherCharacterName,
    required this.type,
    required this.reason,
    required this.score,
    required this.createdAt,
    required this.expiresAt,
    this.suggestedActivity = '',
    this.suggestedLocation = '',
    this.worldEventIds = const [],
  });

  final String id;
  final String currentCharacterId;
  final String otherCharacterId;
  final String otherCharacterName;
  final RelationshipOpportunityType type;
  final String reason;
  final int score;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String suggestedActivity;
  final String suggestedLocation;
  final List<String> worldEventIds;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'currentCharacterId': currentCharacterId,
        'otherCharacterId': otherCharacterId,
        'otherCharacterName': otherCharacterName,
        'type': type.name,
        'reason': reason,
        'score': score,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'suggestedActivity': suggestedActivity,
        'suggestedLocation': suggestedLocation,
        'worldEventIds': worldEventIds,
      };
}
