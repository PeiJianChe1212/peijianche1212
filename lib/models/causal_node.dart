enum CausalNodeType {
  worldEvent,
  decision,
  lifeEvent,
  echo,
  other,
}

class CausalNode {
  const CausalNode({
    required this.id,
    required this.type,
    required this.sourceId,
    required this.title,
    required this.occurredAt,
    required this.createdAt,
    this.parentIds = const [],
    this.characterId = '',
    this.detail = '',
    this.metadata = const {},
  });

  final String id;
  final CausalNodeType type;
  final String sourceId;
  final String title;
  final String detail;
  final DateTime occurredAt;
  final DateTime createdAt;
  final List<String> parentIds;
  final String characterId;
  final Map<String, dynamic> metadata;

  CausalNode copyWith({
    String? id,
    CausalNodeType? type,
    String? sourceId,
    String? title,
    String? detail,
    DateTime? occurredAt,
    DateTime? createdAt,
    List<String>? parentIds,
    String? characterId,
    Map<String, dynamic>? metadata,
  }) {
    return CausalNode(
      id: id ?? this.id,
      type: type ?? this.type,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      occurredAt: occurredAt ?? this.occurredAt,
      createdAt: createdAt ?? this.createdAt,
      parentIds: parentIds ?? this.parentIds,
      characterId: characterId ?? this.characterId,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'sourceId': sourceId,
        'title': title,
        'detail': detail,
        'occurredAt': occurredAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'parentIds': parentIds,
        'characterId': characterId,
        'metadata': metadata,
      };

  factory CausalNode.fromJson(Map<dynamic, dynamic> json) {
    final now = DateTime.now();
    final typeName = _readText(json['type']);
    return CausalNode(
      id: _readText(json['id']),
      type: CausalNodeType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => CausalNodeType.other,
      ),
      sourceId: _readText(json['sourceId']),
      title: _readText(json['title']),
      detail: _readText(json['detail']),
      occurredAt: DateTime.tryParse(_readText(json['occurredAt'])) ?? now,
      createdAt: DateTime.tryParse(_readText(json['createdAt'])) ?? now,
      parentIds: _readStringList(json['parentIds']),
      characterId: _readText(json['characterId']),
      metadata: _readMap(json['metadata']),
    );
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

  static Map<String, dynamic> _readMap(dynamic value) {
    if (value is! Map) return const {};
    return Map<String, dynamic>.from(value);
  }
}
