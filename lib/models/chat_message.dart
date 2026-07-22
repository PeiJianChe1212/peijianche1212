class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    String? id,
    DateTime? createdAt,
    this.isFavorite = false,
    this.source = 'normal',
  }) : id = id ?? _createId(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final bool isFavorite;
  final String source;

  ChatMessage copyWith({
    String? role,
    String? content,
    DateTime? createdAt,
    bool? isFavorite,
    String? source,
  }) {
    return ChatMessage(
      id: id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'isFavorite': isFavorite,
    'source': source,
  };

  factory ChatMessage.fromJson(Map<dynamic, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    return ChatMessage(
      id: json['id']?.toString(),
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      createdAt: createdAt,
      isFavorite: json['isFavorite'] == true,
      source: json['source']?.toString() ?? 'normal',
    );
  }

  static String _createId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode.abs()}';
}
