class LifeMomentCandidate {
  const LifeMomentCandidate({
    required this.id,
    required this.scene,
    required this.event,
    required this.detail,
    required this.feeling,
    required this.shareHook,
    required this.occurredAt,
    this.decisionId = '',
    this.causeNodeId = '',
    this.relatedCharacterNames = const [],
    this.decisionSummary = '',
    this.decisionReason = '',
    this.worldEventIds = const [],
    this.resourceClaims = const {},
    this.renderedAt,
    this.rendererVersion = 0,
    this.relationshipOpportunityId = '',
  });

  final String id;
  final String scene;
  final String event;
  final String detail;
  final String feeling;
  final String shareHook;
  final DateTime occurredAt;

  /// 追溯本条生活事件来自哪一个 Life Decision。
  /// 旧数据没有该字段时保持为空，不影响兼容读取。
  final String decisionId;
  final String causeNodeId;
  final List<String> relatedCharacterNames;

  /// 决定生成当时的只读快照。
  ///
  /// 即使未来决策历史被延期、改名或清理，已经发生的生活仍然能够说明
  /// 当时决定了什么、为什么决定，以及依赖了哪些世界事实和共享资源。
  final String decisionSummary;
  final String decisionReason;
  final List<String> worldEventIds;
  final Map<String, int> resourceClaims;

  /// 本条事件何时被 Life Event Renderer 正式落盘。
  final DateTime? renderedAt;
  final int rendererVersion;
  final String relationshipOpportunityId;

  LifeMomentCandidate copyWith({
    String? id,
    String? scene,
    String? event,
    String? detail,
    String? feeling,
    String? shareHook,
    DateTime? occurredAt,
    String? decisionId,
    String? causeNodeId,
    List<String>? relatedCharacterNames,
    String? decisionSummary,
    String? decisionReason,
    List<String>? worldEventIds,
    Map<String, int>? resourceClaims,
    DateTime? renderedAt,
    bool clearRenderedAt = false,
    int? rendererVersion,
    String? relationshipOpportunityId,
  }) {
    return LifeMomentCandidate(
      id: id ?? this.id,
      scene: scene ?? this.scene,
      event: event ?? this.event,
      detail: detail ?? this.detail,
      feeling: feeling ?? this.feeling,
      shareHook: shareHook ?? this.shareHook,
      occurredAt: occurredAt ?? this.occurredAt,
      decisionId: decisionId ?? this.decisionId,
      causeNodeId: causeNodeId ?? this.causeNodeId,
      relatedCharacterNames:
          relatedCharacterNames ?? this.relatedCharacterNames,
      decisionSummary: decisionSummary ?? this.decisionSummary,
      decisionReason: decisionReason ?? this.decisionReason,
      worldEventIds: worldEventIds ?? this.worldEventIds,
      resourceClaims: resourceClaims ?? this.resourceClaims,
      renderedAt: clearRenderedAt ? null : (renderedAt ?? this.renderedAt),
      rendererVersion: rendererVersion ?? this.rendererVersion,
      relationshipOpportunityId:
          relationshipOpportunityId ?? this.relationshipOpportunityId,
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
        'decisionId': decisionId,
        'causeNodeId': causeNodeId,
        'relatedCharacterNames': relatedCharacterNames,
        'decisionSummary': decisionSummary,
        'decisionReason': decisionReason,
        'worldEventIds': worldEventIds,
        'resourceClaims': resourceClaims,
        'renderedAt': renderedAt?.toIso8601String(),
        'rendererVersion': rendererVersion,
        'relationshipOpportunityId': relationshipOpportunityId,
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
      decisionId: json['decisionId']?.toString().trim() ?? '',
      causeNodeId: json['causeNodeId']?.toString().trim() ?? '',
      relatedCharacterNames: rawNames is List
          ? rawNames
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
          : const [],
      decisionSummary: json['decisionSummary']?.toString().trim() ?? '',
      decisionReason: json['decisionReason']?.toString().trim() ?? '',
      worldEventIds: _readStringList(json['worldEventIds']),
      resourceClaims: _readResourceClaims(json['resourceClaims']),
      renderedAt:
          DateTime.tryParse(json['renderedAt']?.toString().trim() ?? ''),
      rendererVersion: _readInt(json['rendererVersion']),
      relationshipOpportunityId:
          json['relationshipOpportunityId']?.toString().trim() ?? '',
    );
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  static Map<String, int> _readResourceClaims(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, int>{};
    for (final entry in value.entries) {
      final id = entry.key.toString().trim();
      final quantity = entry.value is num
          ? (entry.value as num).toInt()
          : int.tryParse(entry.value?.toString() ?? '');
      if (id.isEmpty || quantity == null || quantity <= 0) continue;
      result[id] = quantity;
    }
    return result;
  }

  static int _readInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
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
