class MemoryItem {
  MemoryItem({
    required this.content,
    required this.category,
    String? id,
    DateTime? createdAt,
    this.isPinned = false,
    this.isArchived = false,
    this.sourceMessageId,
  }) : id = id ?? _createId(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String content;
  final String category;
  final DateTime createdAt;
  final bool isPinned;
  final bool isArchived;
  final String? sourceMessageId;

  MemoryItem copyWith({
    String? content,
    String? category,
    bool? isPinned,
    bool? isArchived,
    String? sourceMessageId,
  }) {
    return MemoryItem(
      id: id,
      content: content ?? this.content,
      category: category ?? this.category,
      createdAt: createdAt,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'category': category,
    'createdAt': createdAt.toIso8601String(),
    'isPinned': isPinned,
    'isArchived': isArchived,
    'sourceMessageId': sourceMessageId,
  };

  factory MemoryItem.fromJson(Map<dynamic, dynamic> json) {
    return MemoryItem(
      id: json['id']?.toString(),
      content: json['content']?.toString() ?? '',
      category: json['category']?.toString() ?? '关于念念',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      isPinned: json['isPinned'] == true,
      isArchived: json['isArchived'] == true,
      sourceMessageId: json['sourceMessageId']?.toString(),
    );
  }

  static String _createId() =>
      'memory_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode.abs()}';
}
