class LifeMomentCandidate {
  const LifeMomentCandidate({
    required this.id,
    required this.scene,
    required this.event,
    required this.detail,
    required this.feeling,
    required this.shareHook,
    required this.occurredAt,
    this.relatedCharacterNames = const [],
  });

  final String id;
  final String scene;
  final String event;
  final String detail;
  final String feeling;
  final String shareHook;
  final DateTime occurredAt;
  final List<String> relatedCharacterNames;

  LifeMomentCandidate copyWith({
    String? id,
    String? scene,
    String? event,
    String? detail,
    String? feeling,
    String? shareHook,
    DateTime? occurredAt,
    List<String>? relatedCharacterNames,
  }) {
    return LifeMomentCandidate(
      id: id ?? this.id,
      scene: scene ?? this.scene,
      event: event ?? this.event,
      detail: detail ?? this.detail,
      feeling: feeling ?? this.feeling,
      shareHook: shareHook ?? this.shareHook,
      occurredAt: occurredAt ?? this.occurredAt,
      relatedCharacterNames:
          relatedCharacterNames ?? this.relatedCharacterNames,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scene': scene,
        'event': event,
        'detail': detail,
        'feeling': feeling,
        'shareHook': shareHook,
        'occurredAt': occurredAt.toIso8601String(),
        'relatedCharacterNames': relatedCharacterNames,
      };

  factory LifeMomentCandidate.fromJson(Map<dynamic, dynamic> json) {
    final rawNames = json['relatedCharacterNames'];
    return LifeMomentCandidate(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : DateTime.now().microsecondsSinceEpoch.toString(),
      scene: json['scene']?.toString().trim() ?? '',
      event: json['event']?.toString().trim() ?? '',
      detail: json['detail']?.toString().trim() ?? '',
      feeling: json['feeling']?.toString().trim() ?? '',
      shareHook: json['shareHook']?.toString().trim() ?? '',
      occurredAt:
          DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
              DateTime.now(),
      relatedCharacterNames: rawNames is List
          ? rawNames
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
          : const [],
    );
  }
}

class EchoMomentDecision {
  const EchoMomentDecision({
    required this.shouldShare,
    required this.score,
    required this.reason,
    required this.candidate,
    required this.suggestImage,
  });

  final bool shouldShare;
  final double score;
  final String reason;
  final LifeMomentCandidate candidate;
  final bool suggestImage;
}
