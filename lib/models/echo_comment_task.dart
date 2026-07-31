enum EchoCommentTaskStatus {
  pending,
  published,
  skipped,
  failed,
}

class EchoCommentTask {
  const EchoCommentTask({
    required this.id,
    required this.echoId,
    required this.echoOwnerId,
    required this.commenterId,
    required this.scheduledAt,
    required this.createdAt,
    this.status = EchoCommentTaskStatus.pending,
    this.publishedAt,
    this.attempts = 0,
    this.skipReason = '',
    this.lastError = '',
    this.triggerReason = '',
  });

  final String id;
  final String echoId;
  final String echoOwnerId;
  final String commenterId;
  final DateTime scheduledAt;
  final DateTime createdAt;
  final EchoCommentTaskStatus status;
  final DateTime? publishedAt;
  final int attempts;
  final String skipReason;
  final String lastError;
  final String triggerReason;

  EchoCommentTask copyWith({
    DateTime? scheduledAt,
    EchoCommentTaskStatus? status,
    DateTime? publishedAt,
    bool clearPublishedAt = false,
    int? attempts,
    String? skipReason,
    String? lastError,
    String? triggerReason,
  }) {
    return EchoCommentTask(
      id: id,
      echoId: echoId,
      echoOwnerId: echoOwnerId,
      commenterId: commenterId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      createdAt: createdAt,
      status: status ?? this.status,
      publishedAt:
          clearPublishedAt ? null : (publishedAt ?? this.publishedAt),
      attempts: attempts ?? this.attempts,
      skipReason: skipReason ?? this.skipReason,
      lastError: lastError ?? this.lastError,
      triggerReason: triggerReason ?? this.triggerReason,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'echoId': echoId,
        'echoOwnerId': echoOwnerId,
        'commenterId': commenterId,
        'scheduledAt': scheduledAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'publishedAt': publishedAt?.toIso8601String(),
        'attempts': attempts,
        'skipReason': skipReason,
        'lastError': lastError,
        'triggerReason': triggerReason,
      };

  factory EchoCommentTask.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    return EchoCommentTask(
      id: json['id']?.toString() ?? '',
      echoId: json['echoId']?.toString() ?? '',
      echoOwnerId: json['echoOwnerId']?.toString() ?? '',
      commenterId: json['commenterId']?.toString() ?? '',
      scheduledAt:
          DateTime.tryParse(json['scheduledAt']?.toString() ?? '') ?? now,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      status: EchoCommentTaskStatus.values.firstWhere(
        (item) => item.name == json['status']?.toString(),
        orElse: () => EchoCommentTaskStatus.pending,
      ),
      publishedAt:
          DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
      skipReason: json['skipReason']?.toString() ?? '',
      lastError: json['lastError']?.toString() ?? '',
      triggerReason: json['triggerReason']?.toString() ?? '',
    );
  }
}
