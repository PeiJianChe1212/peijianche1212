enum EchoCommentInteractionTone {
  neutral,
  support,
  concern,
  celebration,
  invitation,
}

class EchoCommentInteraction {
  const EchoCommentInteraction({
    required this.id,
    required this.echoId,
    required this.commentId,
    required this.actorId,
    required this.targetId,
    required this.summary,
    required this.tone,
    required this.importance,
    required this.createdAt,
    this.parentCommentId = '',
    this.relatedLifeEventId = '',
    this.relatedRelationshipId = '',
    this.futureCandidateId = '',
    this.metadata = const {},
  });

  final String id;
  final String echoId;
  final String commentId;
  final String parentCommentId;
  final String actorId;
  final String targetId;
  final String summary;
  final EchoCommentInteractionTone tone;
  final int importance;
  final DateTime createdAt;
  final String relatedLifeEventId;
  final String relatedRelationshipId;
  final String futureCandidateId;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'id': id,
        'echoId': echoId,
        'commentId': commentId,
        'parentCommentId': parentCommentId,
        'actorId': actorId,
        'targetId': targetId,
        'summary': summary,
        'tone': tone.name,
        'importance': importance,
        'createdAt': createdAt.toIso8601String(),
        'relatedLifeEventId': relatedLifeEventId,
        'relatedRelationshipId': relatedRelationshipId,
        'futureCandidateId': futureCandidateId,
        'metadata': metadata,
      };

  factory EchoCommentInteraction.fromJson(Map<dynamic, dynamic> json) {
    final rawMetadata = json['metadata'];
    return EchoCommentInteraction(
      id: json['id']?.toString() ?? '',
      echoId: json['echoId']?.toString() ?? '',
      commentId: json['commentId']?.toString() ?? '',
      parentCommentId: json['parentCommentId']?.toString() ?? '',
      actorId: json['actorId']?.toString() ?? '',
      targetId: json['targetId']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      tone: EchoCommentInteractionTone.values.firstWhere(
        (item) => item.name == json['tone']?.toString(),
        orElse: () => EchoCommentInteractionTone.neutral,
      ),
      importance: (int.tryParse(json['importance']?.toString() ?? '') ?? 0)
          .clamp(0, 100)
          .toInt(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      relatedLifeEventId: json['relatedLifeEventId']?.toString() ?? '',
      relatedRelationshipId:
          json['relatedRelationshipId']?.toString() ?? '',
      futureCandidateId: json['futureCandidateId']?.toString() ?? '',
      metadata: rawMetadata is Map
          ? rawMetadata.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const {},
    );
  }
}

class EchoLifeOpportunityCandidate {
  const EchoLifeOpportunityCandidate({
    required this.id,
    required this.characterIdA,
    required this.characterIdB,
    required this.reason,
    required this.suggestedActivity,
    required this.createdAt,
    required this.expiresAt,
    required this.sourceInteractionId,
  });

  final String id;
  final String characterIdA;
  final String characterIdB;
  final String reason;
  final String suggestedActivity;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String sourceInteractionId;

  bool isForPair(String firstId, String secondId) =>
      (characterIdA == firstId && characterIdB == secondId) ||
      (characterIdA == secondId && characterIdB == firstId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterIdA': characterIdA,
        'characterIdB': characterIdB,
        'reason': reason,
        'suggestedActivity': suggestedActivity,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'sourceInteractionId': sourceInteractionId,
      };

  factory EchoLifeOpportunityCandidate.fromJson(Map<dynamic, dynamic> json) {
    return EchoLifeOpportunityCandidate(
      id: json['id']?.toString() ?? '',
      characterIdA: json['characterIdA']?.toString() ?? '',
      characterIdB: json['characterIdB']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      suggestedActivity: json['suggestedActivity']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
      sourceInteractionId: json['sourceInteractionId']?.toString() ?? '',
    );
  }
}
