class PendingMemory {
  PendingMemory({
    required this.content,
    required this.reason,
    required this.category,
    String? id,
    DateTime? createdAt,
  }) : id = id ?? _createId(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String content;
  final String reason;
  final String category;
  final DateTime createdAt;

  PendingMemory copyWith({String? content, String? reason, String? category}) {
    return PendingMemory(
      id: id,
      content: content ?? this.content,
      reason: reason ?? this.reason,
      category: category ?? this.category,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'reason': reason,
    'category': category,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingMemory.fromJson(Map<dynamic, dynamic> json) {
    return PendingMemory(
      id: json['id']?.toString(),
      content: json['content']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '可能长期有效',
      category: json['category']?.toString() ?? '关于念念',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  static String _createId() =>
      'pending_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode.abs()}';
}
