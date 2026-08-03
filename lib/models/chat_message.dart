import 'red_packet_data.dart';

enum MessageType { text, image, redPacket, voice, system, card }

enum MessageStatus { normal, recalled }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    String? id,
    DateTime? createdAt,
    this.isFavorite = false,
    this.source = 'normal',
    this.type = MessageType.text,
    this.messageStatus = MessageStatus.normal,
    this.redPacket,
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
  final MessageStatus messageStatus;
  final RedPacketData? redPacket;
  final Map<String, dynamic> metadata;

  bool get isRecalled => messageStatus == MessageStatus.recalled;
  bool get isPendingRedPacket =>
      type == MessageType.redPacket && redPacket?.isOpened != true;
  bool get isVisibleInConversationContext => !isRecalled && !isPendingRedPacket;

  ChatMessage copyWith({
    String? role,
    String? content,
    DateTime? createdAt,
    bool? isFavorite,
    String? source,
    MessageType? type,
    MessageStatus? messageStatus,
    RedPacketData? redPacket,
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
      messageStatus: messageStatus ?? this.messageStatus,
      redPacket: redPacket ?? this.redPacket,
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
    'messageStatus': messageStatus.name,
    'redPacket': redPacket?.toJson(),
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
      messageStatus: _messageStatusFromJson(
        json['messageStatus'] ?? json['status'],
      ),
      redPacket: _redPacketFromJson(json['redPacket']),
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

  static MessageStatus _messageStatusFromJson(dynamic value) {
    final statusName = value?.toString();
    return MessageStatus.values.firstWhere(
      (status) => status.name == statusName,
      orElse: () => MessageStatus.normal,
    );
  }

  static RedPacketData? _redPacketFromJson(dynamic value) {
    if (value is! Map) return null;
    return RedPacketData.fromJson(value);
  }

  static Map<String, dynamic> _metadataFromJson(dynamic value) {
    if (value is! Map) return const {};

    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String _createId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode.abs()}';
}
