class GroupMember {
  const GroupMember({
    required this.groupId,
    required this.characterId,
    required this.joinedAt,
    this.groupNickname = '',
    this.allowInitiative = true,
    this.activityLevel = 0.5,
    this.relationshipLabel = '',
    this.lastSpokeAt,
  });

  final String groupId;
  final String characterId;
  final String groupNickname;
  final bool allowInitiative;
  final double activityLevel;
  final DateTime joinedAt;
  final String relationshipLabel;
  final DateTime? lastSpokeAt;

  GroupMember copyWith({
    String? groupNickname,
    bool? allowInitiative,
    double? activityLevel,
    String? relationshipLabel,
    DateTime? lastSpokeAt,
    bool clearLastSpokeAt = false,
  }) {
    return GroupMember(
      groupId: groupId,
      characterId: characterId,
      groupNickname: groupNickname ?? this.groupNickname,
      allowInitiative: allowInitiative ?? this.allowInitiative,
      activityLevel: activityLevel ?? this.activityLevel,
      joinedAt: joinedAt,
      relationshipLabel: relationshipLabel ?? this.relationshipLabel,
      lastSpokeAt: clearLastSpokeAt ? null : (lastSpokeAt ?? this.lastSpokeAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'characterId': characterId,
        'groupNickname': groupNickname,
        'allowInitiative': allowInitiative,
        'activityLevel': activityLevel,
        'joinedAt': joinedAt.toIso8601String(),
        'relationshipLabel': relationshipLabel,
        'lastSpokeAt': lastSpokeAt?.toIso8601String(),
      };

  factory GroupMember.fromJson(Map<dynamic, dynamic> json) {
    return GroupMember(
      groupId: json['groupId']?.toString() ?? '',
      characterId: json['characterId']?.toString() ?? '',
      groupNickname: json['groupNickname']?.toString() ?? '',
      allowInitiative: json['allowInitiative'] != false,
      activityLevel: (json['activityLevel'] as num?)?.toDouble() ?? 0.5,
      joinedAt: DateTime.tryParse(json['joinedAt']?.toString() ?? '') ??
          DateTime.now(),
      relationshipLabel: json['relationshipLabel']?.toString() ?? '',
      lastSpokeAt: DateTime.tryParse(json['lastSpokeAt']?.toString() ?? ''),
    );
  }
}
