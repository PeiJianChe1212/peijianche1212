enum LifeDecisionStatus {
  planned,
  materialized,
  completed,
  interrupted,
  postponed,
  cancelled,
}

extension LifeDecisionStatusX on LifeDecisionStatus {
  bool get isOpen =>
      this == LifeDecisionStatus.planned ||
      this == LifeDecisionStatus.materialized ||
      this == LifeDecisionStatus.postponed;

  bool get isTerminal => !isOpen;

  String get label {
    switch (this) {
      case LifeDecisionStatus.planned:
        return '等待落实';
      case LifeDecisionStatus.materialized:
        return '已落实待发生';
      case LifeDecisionStatus.completed:
        return '已完成';
      case LifeDecisionStatus.interrupted:
        return '被打断';
      case LifeDecisionStatus.postponed:
        return '已延期';
      case LifeDecisionStatus.cancelled:
        return '已取消';
    }
  }
}

class LifeDecision {
  const LifeDecision({
    required this.id,
    required this.characterId,
    required this.summary,
    required this.reason,
    required this.scheduledAt,
    required this.decidedAt,
    this.location = '',
    this.worldEventIds = const [],
    this.relatedCharacterNames = const [],
    this.resourceClaims = const {},
    this.causeNodeId = '',
    this.status = LifeDecisionStatus.planned,
    this.updatedAt,
    this.statusReason = '',
    this.completedAt,
    this.supersedesDecisionId = '',
    this.relationshipOpportunityId = '',
  });

  final String id;
  final String characterId;
  final String summary;
  final String reason;
  final DateTime scheduledAt;
  final DateTime decidedAt;
  final String location;
  final List<String> worldEventIds;
  final List<String> relatedCharacterNames;

  /// 本条决定需要占用的全世界共享资源。key 为资源 ID，value 为数量。
  final Map<String, int> resourceClaims;
  final String causeNodeId;

  /// 决定本身的生命周期。旧数据缺少该字段时默认仍在等待落实。
  final LifeDecisionStatus status;
  final DateTime? updatedAt;
  final String statusReason;
  final DateTime? completedAt;

  /// 延期或替代旧决定时，记录它承接自哪一条决定。
  final String supersedesDecisionId;

  /// 本条决定使用的关系机会。为空表示单人生活决定。
  final String relationshipOpportunityId;

  bool get isOpen => status.isOpen;
  bool get isTerminal => status.isTerminal;

  LifeDecision copyWith({
    String? id,
    String? characterId,
    String? summary,
    String? reason,
    DateTime? scheduledAt,
    DateTime? decidedAt,
    String? location,
    List<String>? worldEventIds,
    List<String>? relatedCharacterNames,
    Map<String, int>? resourceClaims,
    String? causeNodeId,
    LifeDecisionStatus? status,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
    String? statusReason,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? supersedesDecisionId,
    String? relationshipOpportunityId,
  }) {
    return LifeDecision(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      summary: summary ?? this.summary,
      reason: reason ?? this.reason,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      decidedAt: decidedAt ?? this.decidedAt,
      location: location ?? this.location,
      worldEventIds: worldEventIds ?? this.worldEventIds,
      relatedCharacterNames:
          relatedCharacterNames ?? this.relatedCharacterNames,
      resourceClaims: resourceClaims ?? this.resourceClaims,
      causeNodeId: causeNodeId ?? this.causeNodeId,
      status: status ?? this.status,
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
      statusReason: statusReason ?? this.statusReason,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
      supersedesDecisionId:
          supersedesDecisionId ?? this.supersedesDecisionId,
      relationshipOpportunityId:
          relationshipOpportunityId ?? this.relationshipOpportunityId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'summary': summary,
        'reason': reason,
        'scheduledAt': scheduledAt.toIso8601String(),
        'decidedAt': decidedAt.toIso8601String(),
        'location': location,
        'worldEventIds': worldEventIds,
        'relatedCharacterNames': relatedCharacterNames,
        'resourceClaims': resourceClaims,
        'causeNodeId': causeNodeId,
        'status': status.name,
        'updatedAt': updatedAt?.toIso8601String(),
        'statusReason': statusReason,
        'completedAt': completedAt?.toIso8601String(),
        'supersedesDecisionId': supersedesDecisionId,
        'relationshipOpportunityId': relationshipOpportunityId,
      };

  factory LifeDecision.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    return LifeDecision(
      id: _readText(json['id']).isEmpty
          ? 'decision_${now.microsecondsSinceEpoch}'
          : _readText(json['id']),
      characterId: _readText(json['characterId']),
      summary: _readText(json['summary']),
      reason: _readText(json['reason']),
      scheduledAt:
          DateTime.tryParse(_readText(json['scheduledAt'])) ?? now,
      decidedAt: DateTime.tryParse(_readText(json['decidedAt'])) ?? now,
      location: _readText(json['location']),
      worldEventIds: _readStringList(json['worldEventIds']),
      relatedCharacterNames:
          _readStringList(json['relatedCharacterNames']),
      resourceClaims: _readResourceClaims(json['resourceClaims']),
      causeNodeId: _readText(json['causeNodeId']),
      status: _readStatus(json['status']),
      updatedAt: DateTime.tryParse(_readText(json['updatedAt'])),
      statusReason: _readText(json['statusReason']),
      completedAt: DateTime.tryParse(_readText(json['completedAt'])),
      supersedesDecisionId: _readText(json['supersedesDecisionId']),
      relationshipOpportunityId:
          _readText(json['relationshipOpportunityId']),
    );
  }

  static LifeDecisionStatus _readStatus(dynamic value) {
    final text = _readText(value);
    return LifeDecisionStatus.values.firstWhere(
      (item) => item.name == text,
      orElse: () => LifeDecisionStatus.planned,
    );
  }


  static Map<String, int> _readResourceClaims(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, int>{};
    for (final entry in value.entries) {
      final id = _readText(entry.key);
      final quantity = entry.value is num
          ? (entry.value as num).toInt()
          : int.tryParse(_readText(entry.value));
      if (id.isEmpty || quantity == null || quantity <= 0) continue;
      result[id] = quantity;
    }
    return result;
  }

  static String _readText(dynamic value) => value?.toString().trim() ?? '';

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(_readText)
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }
}
