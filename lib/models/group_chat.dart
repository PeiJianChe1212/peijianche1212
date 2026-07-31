import 'group_member.dart';

enum GroupHeat { quiet, normal, active, heated }

class GroupChat {
  const GroupChat({
    required this.id,
    required this.name,
    required this.members,
    required this.createdAt,
    required this.lastActiveAt,
    this.avatarPath = '',
    this.lastMessage = '',
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.summaryContext = '',
    this.currentTopic = '',
    this.heat = GroupHeat.normal,
  });

  final String id;
  final String name;
  final String avatarPath;
  final List<GroupMember> members;
  final DateTime createdAt;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final DateTime lastActiveAt;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final String summaryContext;
  final String currentTopic;
  final GroupHeat heat;

  List<String> get memberCharacterIds =>
      members.map((member) => member.characterId).toList(growable: false);

  GroupChat copyWith({
    String? name,
    String? avatarPath,
    List<GroupMember>? members,
    String? lastMessage,
    DateTime? lastMessageAt,
    bool clearLastMessageAt = false,
    DateTime? lastActiveAt,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    String? summaryContext,
    String? currentTopic,
    GroupHeat? heat,
  }) {
    return GroupChat(
      id: id,
      name: name ?? this.name,
      avatarPath: avatarPath ?? this.avatarPath,
      members: members ?? this.members,
      createdAt: createdAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt:
          clearLastMessageAt ? null : (lastMessageAt ?? this.lastMessageAt),
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      summaryContext: summaryContext ?? this.summaryContext,
      currentTopic: currentTopic ?? this.currentTopic,
      heat: heat ?? this.heat,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarPath': avatarPath,
        'members': members.map((member) => member.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'lastMessage': lastMessage,
        'lastMessageAt': lastMessageAt?.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'unreadCount': unreadCount,
        'isPinned': isPinned,
        'isMuted': isMuted,
        'summaryContext': summaryContext,
        'currentTopic': currentTopic,
        'heat': heat.name,
      };

  factory GroupChat.fromJson(Map<dynamic, dynamic> json) {
    final rawMembers = json['members'];
    return GroupChat(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名群聊',
      avatarPath: json['avatarPath']?.toString() ?? '',
      members: rawMembers is List
          ? rawMembers.whereType<Map>().map(GroupMember.fromJson).toList()
          : const [],
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      lastMessage: json['lastMessage']?.toString() ?? '',
      lastMessageAt:
          DateTime.tryParse(json['lastMessageAt']?.toString() ?? ''),
      lastActiveAt:
          DateTime.tryParse(json['lastActiveAt']?.toString() ?? '') ??
              DateTime.now(),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      isPinned: json['isPinned'] == true,
      isMuted: json['isMuted'] == true,
      summaryContext: json['summaryContext']?.toString() ?? '',
      currentTopic: json['currentTopic']?.toString() ?? '',
      heat: GroupHeat.values.firstWhere(
        (value) => value.name == json['heat']?.toString(),
        orElse: () => GroupHeat.normal,
      ),
    );
  }
}
