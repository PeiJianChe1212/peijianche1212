import 'ai_character.dart';
import 'character_settings.dart';

class CharacterProfile {
  const CharacterProfile({
    required this.characterId,
    this.name = '',
    this.petName = '',
    this.socialId = '',
    this.age = '',
    this.gender = '',
    this.height = '',
    this.birthday = '',
    this.identity = '',
    this.occupation = '',
    this.location = '',
    this.overallAppearance = '',
    this.hairColor = '',
    this.eyes = '',
    this.bodyType = '',
    this.clothingStyle = '',
    this.specialMarks = '',
    this.aura = '',
    this.personalityTags = '',
    this.personalityDescription = '',
    this.surfacePersonality = '',
    this.deepPersonality = '',
    this.familyBackground = '',
    this.upbringing = '',
    this.importantExperiences = '',
    this.worldview = '',
    this.relationship = '',
    this.howMet = '',
    this.currentStage = '',
  });

  final String characterId;
  final String name, petName, socialId, age, gender, height, birthday;
  final String identity, occupation, location;
  final String overallAppearance, hairColor, eyes, bodyType;
  final String clothingStyle, specialMarks, aura;
  final String personalityTags, personalityDescription;
  final String surfacePersonality, deepPersonality;
  final String familyBackground, upbringing, importantExperiences, worldview;
  final String relationship, howMet, currentStage;

  double get basicCompletion => _completion([
    name,
    petName,
    socialId,
    age,
    gender,
    height,
    birthday,
    identity,
    occupation,
    location,
  ]);

  double get appearanceCompletion => _completion([
    overallAppearance,
    hairColor,
    eyes,
    bodyType,
    clothingStyle,
    specialMarks,
    aura,
  ]);

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'name': name,
    'petName': petName,
    'socialId': socialId,
    'age': age,
    'gender': gender,
    'height': height,
    'birthday': birthday,
    'identity': identity,
    'occupation': occupation,
    'location': location,
    'overallAppearance': overallAppearance,
    'hairColor': hairColor,
    'eyes': eyes,
    'bodyType': bodyType,
    'clothingStyle': clothingStyle,
    'specialMarks': specialMarks,
    'aura': aura,
    'personalityTags': personalityTags,
    'personalityDescription': personalityDescription,
    'surfacePersonality': surfacePersonality,
    'deepPersonality': deepPersonality,
    'familyBackground': familyBackground,
    'upbringing': upbringing,
    'importantExperiences': importantExperiences,
    'worldview': worldview,
    'relationship': relationship,
    'howMet': howMet,
    'currentStage': currentStage,
  };

  factory CharacterProfile.fromJson(Map<dynamic, dynamic> json, String id) {
    String read(String key) => json[key]?.toString().trim() ?? '';
    return CharacterProfile(
      characterId: id,
      name: read('name'),
      petName: read('petName').isNotEmpty ? read('petName') : read('nickname'),
      socialId: read('socialId'),
      age: read('age'),
      gender: read('gender'),
      height: read('height'),
      birthday: read('birthday'),
      identity: read('identity'),
      occupation: read('occupation'),
      location: read('location'),
      overallAppearance: read('overallAppearance'),
      hairColor: read('hairColor'),
      eyes: read('eyes'),
      bodyType: read('bodyType'),
      clothingStyle: read('clothingStyle'),
      specialMarks: read('specialMarks'),
      aura: read('aura'),
      personalityTags: read('personalityTags'),
      personalityDescription: read('personalityDescription'),
      surfacePersonality: read('surfacePersonality'),
      deepPersonality: read('deepPersonality'),
      familyBackground: read('familyBackground'),
      upbringing: read('upbringing'),
      importantExperiences: read('importantExperiences'),
      worldview: read('worldview'),
      relationship: read('relationship'),
      howMet: read('howMet'),
      currentStage: read('currentStage'),
    );
  }

  factory CharacterProfile.fromLegacy(
    AiCharacter character,
    CharacterSettings settings,
  ) => CharacterProfile(
    characterId: character.id,
    name: character.characterName,
    petName: character.remark,
    socialId: character.peiLinkId,
    birthday: settings.birthday,
    relationship: settings.relation,
    overallAppearance: settings.introduction,
    personalityDescription: settings.coreProfile,
    worldview: character.persona,
  );
}

double _completion(Iterable<String> values) {
  final fields = values.toList();
  if (fields.isEmpty) return 0;
  final completed = fields.where((value) => value.trim().isNotEmpty).length;
  return completed / fields.length;
}
