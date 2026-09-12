/// 用户在某个群聊里公开呈现的身份。
///
/// 它与全局 [UserProfile] 以及角色专属的 CharacterUserProfile 都不相同：
/// 同一个群里的不同角色可以有各自的私人视角，而这里只描述"用户在这个群里
/// 公开的身份"。落盘时按 groupId 独立保存，不写入 GroupMember 数组。
class GroupUserProfile {
  const GroupUserProfile({
    required this.groupId,
    this.displayName = '',
    this.avatarPath = '',
    this.selfDescription = '',
    this.updatedAt,
  });

  final String groupId;
  final String displayName;
  final String avatarPath;
  final String selfDescription;
  final DateTime? updatedAt;

  bool get isEmpty =>
      displayName.trim().isEmpty &&
      avatarPath.trim().isEmpty &&
      selfDescription.trim().isEmpty;

  GroupUserProfile copyWith({
    String? displayName,
    String? avatarPath,
    String? selfDescription,
    DateTime? updatedAt,
  }) {
    return GroupUserProfile(
      groupId: groupId,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      selfDescription: selfDescription ?? this.selfDescription,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'groupId': groupId,
    'displayName': displayName,
    'avatarPath': avatarPath,
    'selfDescription': selfDescription,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory GroupUserProfile.fromJson(
    Map<dynamic, dynamic> json, {
    required String groupId,
  }) {
    return GroupUserProfile(
      groupId: groupId,
      displayName: json['displayName']?.toString().trim() ?? '',
      avatarPath: json['avatarPath']?.toString().trim() ?? '',
      selfDescription: json['selfDescription']?.toString().trim() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}
