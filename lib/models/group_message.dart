enum GroupSenderType { user, character, system }

enum GroupMessageType { text, image, video, voice, card, system }

enum GroupMessageStatus { sending, sent, failed }

enum GroupMessageSource {
  userInput,
  characterReply,
  characterInitiative,
  lifeEvent,
  worldEvent,
  echoShare,
  system,
}

class GroupMessage {
  GroupMessage({
    required this.groupId,
    required this.senderType,
    required this.senderId,
    required this.content,
    String? id,
    DateTime? createdAt,
    this.messageType = GroupMessageType.text,
    this.replyToMessageId,
    this.mentionedMemberIds = const [],
    this.status = GroupMessageStatus.sent,
    this.sourceType = GroupMessageSource.userInput,
    this.sourceEventId,
  })  : id = id ?? _createId(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String groupId;
  final GroupSenderType senderType;
  final String senderId;
  final String content;
  final GroupMessageType messageType;
  final String? replyToMessageId;
  final List<String> mentionedMemberIds;
  final DateTime createdAt;
  final GroupMessageStatus status;
  final GroupMessageSource sourceType;
  final String? sourceEventId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'senderType': senderType.name,
        'senderId': senderId,
        'content': content,
        'messageType': messageType.name,
        'replyToMessageId': replyToMessageId,
        'mentionedMemberIds': mentionedMemberIds,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'sourceType': _sourceTypeJsonName(sourceType),
        'sourceEventId': sourceEventId,
      };

  factory GroupMessage.fromJson(Map<dynamic, dynamic> json) {
    return GroupMessage(
      id: json['id']?.toString(),
      groupId: json['groupId']?.toString() ?? '',
      senderType: GroupSenderType.values.firstWhere(
        (value) => value.name == json['senderType']?.toString(),
        orElse: () => GroupSenderType.character,
      ),
      senderId: json['senderId']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      messageType: GroupMessageType.values.firstWhere(
        (value) => value.name == json['messageType']?.toString(),
        orElse: () => GroupMessageType.text,
      ),
      replyToMessageId: json['replyToMessageId']?.toString(),
      mentionedMemberIds: json['mentionedMemberIds'] is List
          ? (json['mentionedMemberIds'] as List)
              .map((item) => item.toString())
              .toList()
          : const [],
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      status: GroupMessageStatus.values.firstWhere(
        (value) => value.name == json['status']?.toString(),
        orElse: () => GroupMessageStatus.sent,
      ),
      sourceType: _sourceTypeFromJson(json['sourceType']),
      sourceEventId: json['sourceEventId']?.toString(),
    );
  }

  static String _createId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode.abs()}';

  static String _sourceTypeJsonName(GroupMessageSource value) {
    switch (value) {
      case GroupMessageSource.userInput:
        return 'user_input';
      case GroupMessageSource.characterReply:
        return 'character_reply';
      case GroupMessageSource.characterInitiative:
        return 'character_initiative';
      case GroupMessageSource.lifeEvent:
        return 'life_event';
      case GroupMessageSource.worldEvent:
        return 'world_event';
      case GroupMessageSource.echoShare:
        return 'echo_share';
      case GroupMessageSource.system:
        return 'system';
    }
  }

  static GroupMessageSource _sourceTypeFromJson(dynamic raw) {
    switch (raw?.toString()) {
      case 'character_reply':
        return GroupMessageSource.characterReply;
      case 'character_initiative':
        return GroupMessageSource.characterInitiative;
      case 'life_event':
        return GroupMessageSource.lifeEvent;
      case 'world_event':
        return GroupMessageSource.worldEvent;
      case 'echo_share':
        return GroupMessageSource.echoShare;
      case 'system':
        return GroupMessageSource.system;
      case 'user_input':
      default:
        return GroupMessageSource.userInput;
    }
  }
}
