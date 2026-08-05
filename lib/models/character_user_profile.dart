class CharacterUserProfile {
  const CharacterUserProfile({
    required this.characterId,
    this.userName = '',
    this.age = '',
    this.identity = '',
    this.relationship = '',
    this.callName = '',
    this.world = '',
    this.description = '',
  });

  final String characterId;
  final String userName;
  final String age;
  final String identity;
  final String relationship;
  final String callName;
  final String world;
  final String description;

  CharacterUserProfile copyWith({
    String? userName,
    String? age,
    String? identity,
    String? relationship,
    String? callName,
    String? world,
    String? description,
  }) {
    return CharacterUserProfile(
      characterId: characterId,
      userName: userName ?? this.userName,
      age: age ?? this.age,
      identity: identity ?? this.identity,
      relationship: relationship ?? this.relationship,
      callName: callName ?? this.callName,
      world: world ?? this.world,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'userName': userName,
    'age': age,
    'identity': identity,
    'relationship': relationship,
    'callName': callName,
    'world': world,
    'description': description,
  };

  factory CharacterUserProfile.fromJson(
    Map<dynamic, dynamic> json, {
    required String characterId,
  }) {
    return CharacterUserProfile(
      characterId: characterId,
      userName: json['userName']?.toString().trim() ?? '',
      age: json['age']?.toString().trim() ?? '',
      identity: json['identity']?.toString().trim() ?? '',
      relationship: json['relationship']?.toString().trim() ?? '',
      callName: json['callName']?.toString().trim() ?? '',
      world: json['world']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
    );
  }
}
