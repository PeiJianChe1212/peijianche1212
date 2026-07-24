class AiCharacter {
  const AiCharacter({
    required this.id,
    required this.characterName,
    required this.remark,
    required this.createdAt,
    this.avatarPath = '',
    this.relationship = '',
    this.peiLinkId = '',
    this.birthday,
    this.persona = '',
    this.isBuiltIn = false,
  });

  static const String defaultCharacterId = 'pei_jian_che';

  final String id;
  final String characterName;
  final String remark;
  final String avatarPath;
  final String relationship;
  final String peiLinkId;
  final DateTime? birthday;
  final String persona;
  final DateTime createdAt;
  final bool isBuiltIn;

  String get displayName => remark.trim().isEmpty ? characterName : remark.trim();

  AiCharacter copyWith({
    String? characterName,
    String? remark,
    String? avatarPath,
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

    return AiCharacter(
      id: rawId.isEmpty ? defaultCharacterId : rawId,
      characterName: rawName.isEmpty ? '未命名 AI' : rawName,
      remark: json['remark']?.toString().trim() ?? '',
      avatarPath: json['avatarPath']?.toString().trim() ?? '',
      relationship: json['relationship']?.toString().trim() ?? '',
      peiLinkId: _readPeiLinkId(json, rawId),
      birthday: DateTime.tryParse(json['birthday']?.toString() ?? ''),
      persona: json['persona']?.toString().trim() ?? '',
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

  factory AiCharacter.peiJianChe() => AiCharacter(
    id: defaultCharacterId,
    characterName: '裴简澈',
    remark: '老裴',
    relationship: '恋人',
    peiLinkId: 'peijianche1212',
    birthday: DateTime(2000, 12, 12),
    createdAt: DateTime(2024, 12, 12),
    isBuiltIn: true,
  );
}
