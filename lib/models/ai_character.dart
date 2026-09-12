class AiCharacter {
  const AiCharacter({
    required this.id,
    required this.characterName,
    required this.remark,
    required this.createdAt,
    this.avatarPath = '',
    this.socialAvatarPath = '',
    String? backgroundImage,
    String portraitPath = '',
    this.introduction = '',
    this.characterIntro = '',
    this.relationship = '',
    this.peiLinkId = '',
    this.birthday,
    this.persona = '',
    this.isBuiltIn = false,
  }) : backgroundImage = backgroundImage ?? portraitPath;

  static const String defaultCharacterId = 'pei_jian_che';

  final String id;
  final String characterName;
  final String remark;
  final String avatarPath;
  final String socialAvatarPath;
  String get effectiveSocialAvatarPath =>
      socialAvatarPath.trim().isNotEmpty ? socialAvatarPath : avatarPath;
  final String backgroundImage;
  String get portraitPath => backgroundImage;
  final String introduction;
  final String characterIntro;
  final String relationship;
  final String peiLinkId;
  final DateTime? birthday;
  final String persona;
  final DateTime createdAt;
  final bool isBuiltIn;

  String get displayName =>
      remark.trim().isEmpty ? characterName : remark.trim();

  AiCharacter copyWith({
    String? characterName,
    String? remark,
    String? avatarPath,
    String? socialAvatarPath,
    String? backgroundImage,
    String? portraitPath,
    String? introduction,
    String? characterIntro,
    String? relationship,
    String? peiLinkId,
    DateTime? birthday,
    bool clearBirthday = false,
    String? persona,
    DateTime? createdAt,
    bool? isBuiltIn,
  }) {
    return AiCharacter(
      id: id,
      characterName: characterName ?? this.characterName,
      remark: remark ?? this.remark,
      avatarPath: avatarPath ?? this.avatarPath,
      socialAvatarPath: socialAvatarPath ?? this.socialAvatarPath,
      backgroundImage: backgroundImage ?? portraitPath ?? this.backgroundImage,
      introduction: introduction ?? this.introduction,
      characterIntro: characterIntro ?? this.characterIntro,
      relationship: relationship ?? this.relationship,
      peiLinkId: peiLinkId ?? this.peiLinkId,
      birthday: clearBirthday ? null : (birthday ?? this.birthday),
      persona: persona ?? this.persona,
      createdAt: createdAt ?? this.createdAt,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'characterName': characterName,
    'remark': remark,
    'avatarPath': avatarPath,
    if (socialAvatarPath.isNotEmpty) 'socialAvatarPath': socialAvatarPath,
    'backgroundImage': backgroundImage,
    'introduction': introduction,
    'characterIntro': characterIntro,
    'relationship': relationship,
    'peiLinkId': peiLinkId,
    'birthday': birthday?.toIso8601String(),
    'persona': persona,
    'createdAt': createdAt.toIso8601String(),
    'isBuiltIn': isBuiltIn,
  };

  factory AiCharacter.fromJson(Map<dynamic, dynamic> json) {
    final rawId = json['id']?.toString().trim() ?? '';
    final rawName = json['characterName']?.toString().trim() ?? '';
    final persona = json['persona']?.toString().trim() ?? '';

    return AiCharacter(
      id: rawId.isEmpty ? defaultCharacterId : rawId,
      characterName: rawName.isEmpty ? '未命名 AI' : rawName,
      remark: json['remark']?.toString().trim() ?? '',
      avatarPath: json['avatarPath']?.toString().trim() ?? '',
      socialAvatarPath: json['socialAvatarPath']?.toString().trim() ?? '',
      backgroundImage:
          (json['backgroundImage'] ?? json['portraitPath'])
              ?.toString()
              .trim() ??
          '',
      introduction: json.containsKey('introduction')
          ? (json['introduction']?.toString().trim() ?? '')
          : '',
      characterIntro: json['characterIntro']?.toString().trim() ?? '',
      relationship: json['relationship']?.toString().trim() ?? '',
      peiLinkId: _readPeiLinkId(json, rawId),
      birthday: DateTime.tryParse(json['birthday']?.toString() ?? ''),
      persona: persona,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isBuiltIn: json['isBuiltIn'] == true,
    );
  }

  static String _readPeiLinkId(Map<dynamic, dynamic> json, String rawId) {
    final saved = json['peiLinkId']?.toString().trim() ?? '';
    if (saved.isNotEmpty) return saved;

    final normalized = rawId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '')
        .replaceAll(RegExp(r'_+'), '_');
    if (normalized.isNotEmpty) return normalized;
    return 'peilink_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 页面初始占位角色，仅用于 State 初始化，加载真实角色后会被替换。
  /// 不代表任何具体 AI 角色，用户版首次安装时角色数量为 0。
  factory AiCharacter.placeholder() => AiCharacter(
    id: '',
    characterName: '',
    remark: '',
    createdAt: DateTime(2024, 12, 12),
  );
}
