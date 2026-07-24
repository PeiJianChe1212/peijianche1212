enum MessageType {
  text,
  image,
  voice,
  system,
  card,
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    String? id,
    DateTime? createdAt,
    this.isFavorite = false,
    this.source = 'normal',
    this.type = MessageType.text,
    this.metadata = const {},
  }) : id = id ?? _createId(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final bool isFavorite;
  final String source;
  final MessageType type;
  final Map<String, dynamic> metadata;

  ChatMessage copyWith({
    String? role,
    String? content,
    DateTime? createdAt,
    bool? isFavorite,
    String? source,
    MessageType? type,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      source: source ?? this.source,
      type: type ?? this.type,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'isFavorite': isFavorite,
    'source': source,
    'type': type.name,
    'metadata': metadata,
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
      type: _messageTypeFromJson(json['type']),
      metadata: _metadataFromJson(json['metadata']),
    );
  }

  static MessageType _messageTypeFromJson(dynamic value) {
    final typeName = value?.toString();
    return MessageType.values.firstWhere(
      (type) => type.name == typeName,
      orElse: () => MessageType.text,
    );
  }

  static Map<String, dynamic> _metadataFromJson(dynamic value) {
    if (value is! Map) return const {};

    return value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
  }

  static String _createId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode.abs()}';
}
