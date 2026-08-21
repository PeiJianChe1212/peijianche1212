class CharacterUserProfile {
  const CharacterUserProfile({
    required this.characterId,
    this.userName = '',
    this.gender = '',
    this.age = '',
    this.identity = '',
    this.relationship = '',
    this.callName = '',
    this.world = '',
    this.description = '',
    this.personaDescription = '',
  });

  final String characterId;
  final String userName;
  final String gender;
  final String age;
  final String identity;
  final String relationship;
  final String callName;
  final String world;
  final String description;
  final String personaDescription;

  CharacterUserProfile copyWith({
    String? userName,
    String? gender,
    String? age,
    String? identity,
    String? relationship,
    String? callName,
    String? world,
    String? description,
    String? personaDescription,
  }) {
    return CharacterUserProfile(
      characterId: characterId,
      userName: userName ?? this.userName,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      identity: identity ?? this.identity,
      relationship: relationship ?? this.relationship,
      callName: callName ?? this.callName,
      world: world ?? this.world,
      description: description ?? this.description,
      personaDescription: personaDescription ?? this.personaDescription,
    );
  }

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'userName': userName,
    'gender': gender,
    'age': age,
    'identity': identity,
    'relationship': relationship,
    'callName': callName,
    'world': world,
    'description': description,
    'personaDescription': personaDescription,
  };

  factory CharacterUserProfile.fromJson(
    Map<dynamic, dynamic> json, {
    required String characterId,
  }) {
    return CharacterUserProfile(
      characterId: characterId,
      userName: json['userName']?.toString().trim() ?? '',
      gender: json['gender']?.toString().trim() ?? '',
      age: json['age']?.toString().trim() ?? '',
      identity: json['identity']?.toString().trim() ?? '',
      relationship: json['relationship']?.toString().trim() ?? '',
      callName: json['callName']?.toString().trim() ?? '',
      world: json['world']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      personaDescription: json['personaDescription']?.toString().trim() ?? '',
    );
  }

  /// 新 UI 只展示一个综合描述；旧字段仅在尚未保存新描述时合并。
  String get effectiveDescription {
    final current = personaDescription.trim();
    if (current.isNotEmpty) return current;
    return [
      if (age.trim().isNotEmpty) '年龄：${age.trim()}',
      if (identity.trim().isNotEmpty) '身份：${identity.trim()}',
      if (relationship.trim().isNotEmpty) '与角色的关系：${relationship.trim()}',
      if (callName.trim().isNotEmpty) '角色对我的称呼：${callName.trim()}',
      if (world.trim().isNotEmpty) '所在世界：${world.trim()}',
      if (description.trim().isNotEmpty) '补充：${description.trim()}',
    ].join('\n');
  }
}
