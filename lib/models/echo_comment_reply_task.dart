enum EchoCommentReplyTaskStatus {
  pending,
  published,
  skipped,
  failed,
}

class EchoCommentReplyTask {
  const EchoCommentReplyTask({
    required this.id,
    required this.echoId,
    required this.echoOwnerId,
    required this.parentCommentId,
    required this.publisherId,
    required this.scheduledAt,
    required this.createdAt,
    this.status = EchoCommentReplyTaskStatus.pending,
    this.publishedAt,
    this.attempts = 0,
    this.skipReason = '',
    this.lastError = '',
  });

  final String id;
  final String echoId;
  final String echoOwnerId;
  final String parentCommentId;
  final String publisherId;
  final DateTime scheduledAt;
  final DateTime createdAt;
  final EchoCommentReplyTaskStatus status;
  final DateTime? publishedAt;
  final int attempts;
  final String skipReason;
  final String lastError;

  EchoCommentReplyTask copyWith({
    DateTime? scheduledAt,
    EchoCommentReplyTaskStatus? status,
    DateTime? publishedAt,
    int? attempts,
    String? skipReason,
    String? lastError,
  }) {
    return EchoCommentReplyTask(
      id: id,
      echoId: echoId,
      echoOwnerId: echoOwnerId,
      parentCommentId: parentCommentId,
      publisherId: publisherId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      createdAt: createdAt,
      status: status ?? this.status,
      publishedAt: publishedAt ?? this.publishedAt,
      attempts: attempts ?? this.attempts,
      skipReason: skipReason ?? this.skipReason,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'echoId': echoId,
        'echoOwnerId': echoOwnerId,
        'parentCommentId': parentCommentId,
        'publisherId': publisherId,
        'scheduledAt': scheduledAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'publishedAt': publishedAt?.toIso8601String(),
        'attempts': attempts,
        'skipReason': skipReason,
        'lastError': lastError,
      };

  factory EchoCommentReplyTask.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    return EchoCommentReplyTask(
      id: json['id']?.toString() ?? '',
      echoId: json['echoId']?.toString() ?? '',
      echoOwnerId: json['echoOwnerId']?.toString() ?? '',
      parentCommentId: json['parentCommentId']?.toString() ?? '',
      publisherId: json['publisherId']?.toString() ?? '',
      scheduledAt:
          DateTime.tryParse(json['scheduledAt']?.toString() ?? '') ?? now,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      status: EchoCommentReplyTaskStatus.values.firstWhere(
        (item) => item.name == json['status']?.toString(),
        orElse: () => EchoCommentReplyTaskStatus.pending,
      ),
      publishedAt:
          DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
      skipReason: json['skipReason']?.toString() ?? '',
      lastError: json['lastError']?.toString() ?? '',
    );
  }
}
