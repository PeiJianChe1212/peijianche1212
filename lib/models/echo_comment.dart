enum EchoCommentAuthorType {
  user,
  character,
  system,
}

enum EchoCommentSourceType {
  manualUser,
  manualCharacterDebug,
  autoCharacter,
  autoReply,
  relationshipTriggered,
  lifeEventTriggered,
  legacy,
}

class EchoComment {
  const EchoComment({
    required this.id,
    required this.echoId,
    required this.authorType,
    required this.content,
    required this.createdAt,
    this.authorId = '',
    this.authorNameSnapshot = '',
    this.authorAvatarSnapshot = '',
    this.replyToCommentId,
    this.replyToAuthorId = '',
    this.replyToAuthorNameSnapshot = '',
    this.sourceType = EchoCommentSourceType.legacy,
    this.relatedLifeEventId = '',
    this.relatedRelationshipId = '',
    this.isDeleted = false,
    this.metadata = const {},
  });

  final String id;
  final String echoId;
  final EchoCommentAuthorType authorType;
  final String authorId;
  final String authorNameSnapshot;
  final String authorAvatarSnapshot;
  final String content;
  final DateTime createdAt;
  final String? replyToCommentId;
  final String replyToAuthorId;
  final String replyToAuthorNameSnapshot;
  final EchoCommentSourceType sourceType;
  final String relatedLifeEventId;
  final String relatedRelationshipId;
  final bool isDeleted;
  final Map<String, dynamic> metadata;

  bool get hasCharacterIdentity =>
      authorType == EchoCommentAuthorType.character &&
      authorId.trim().isNotEmpty;

  EchoComment copyWith({
    String? echoId,
    String? authorId,
    String? authorNameSnapshot,
    String? authorAvatarSnapshot,
    String? content,
    DateTime? createdAt,
    String? replyToCommentId,
    bool clearReplyToCommentId = false,
    String? replyToAuthorId,
    String? replyToAuthorNameSnapshot,
    EchoCommentSourceType? sourceType,
    String? relatedLifeEventId,
    String? relatedRelationshipId,
    bool? isDeleted,
    Map<String, dynamic>? metadata,
  }) {
    return EchoComment(
      id: id,
      echoId: echoId ?? this.echoId,
      authorType: authorType,
      authorId: authorId ?? this.authorId,
      authorNameSnapshot: authorNameSnapshot ?? this.authorNameSnapshot,
      authorAvatarSnapshot:
          authorAvatarSnapshot ?? this.authorAvatarSnapshot,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      replyToCommentId: clearReplyToCommentId
          ? null
          : (replyToCommentId ?? this.replyToCommentId),
      replyToAuthorId: replyToAuthorId ?? this.replyToAuthorId,
      replyToAuthorNameSnapshot:
          replyToAuthorNameSnapshot ?? this.replyToAuthorNameSnapshot,
      sourceType: sourceType ?? this.sourceType,
      relatedLifeEventId: relatedLifeEventId ?? this.relatedLifeEventId,
      relatedRelationshipId:
          relatedRelationshipId ?? this.relatedRelationshipId,
      isDeleted: isDeleted ?? this.isDeleted,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'commentId': id,
        'echoId': echoId,
        'authorType': authorType.name,
        'authorId': authorId,
        'authorNameSnapshot': authorNameSnapshot,
        'authorAvatarSnapshot': authorAvatarSnapshot,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'replyToCommentId': replyToCommentId,
        'replyToAuthorId': replyToAuthorId,
        'replyToAuthorNameSnapshot': replyToAuthorNameSnapshot,
        'sourceType': sourceType.name,
        'relatedLifeEventId': relatedLifeEventId,
        'relatedRelationshipId': relatedRelationshipId,
        'isDeleted': isDeleted,
        'metadata': metadata,
      };

  factory EchoComment.fromJson(
    Map<dynamic, dynamic> json, {
    String fallbackEchoId = '',
  }) {
    final legacyAuthorType = json['authorType']?.toString();
    final rawMetadata = json['metadata'];
    final metadata = rawMetadata is Map
        ? rawMetadata.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    final legacySharedExperienceId =
        json['sourceSharedExperienceId']?.toString() ?? '';
    if (legacySharedExperienceId.isNotEmpty) {
      metadata.putIfAbsent(
        'sourceSharedExperienceId',
        () => legacySharedExperienceId,
      );
    }
    return EchoComment(
      id: json['commentId']?.toString() ?? json['id']?.toString() ?? '',
      echoId: json['echoId']?.toString() ?? fallbackEchoId,
      authorType: EchoCommentAuthorType.values.firstWhere(
        (value) => value.name == legacyAuthorType,
        orElse: () => EchoCommentAuthorType.user,
      ),
      authorId:
          json['authorId']?.toString() ?? json['characterId']?.toString() ?? '',
      authorNameSnapshot: json['authorNameSnapshot']?.toString() ??
          json['characterName']?.toString() ??
          '',
      authorAvatarSnapshot: json['authorAvatarSnapshot']?.toString() ??
          json['characterAvatarPath']?.toString() ??
          '',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      replyToCommentId: json['replyToCommentId']?.toString(),
      replyToAuthorId: json['replyToAuthorId']?.toString() ?? '',
      replyToAuthorNameSnapshot:
          json['replyToAuthorNameSnapshot']?.toString() ?? '',
      sourceType: EchoCommentSourceType.values.firstWhere(
        (value) => value.name == json['sourceType']?.toString(),
        orElse: () => EchoCommentSourceType.legacy,
      ),
      relatedLifeEventId: json['relatedLifeEventId']?.toString() ?? '',
      relatedRelationshipId:
          json['relatedRelationshipId']?.toString() ?? '',
      isDeleted: json['isDeleted'] == true,
      metadata: metadata,
    );
  }
}
