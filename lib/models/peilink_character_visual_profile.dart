import 'character_profile.dart';

class PeiLinkCharacterVisualProfile {
  const PeiLinkCharacterVisualProfile({
    required this.characterId,
    this.gender = '',
    this.ageAppearance = '',
    this.height = '',
    this.bodyType = '',
    this.overallAppearance = '',
    this.hairColor = '',
    this.hairStyle = '',
    this.eyeColor = '',
    this.stableMarks = '',
    this.clothingStyle = '',
  });

  factory PeiLinkCharacterVisualProfile.fromProfile(CharacterProfile profile) {
    final appearance = profile.overallAppearance.trim();
    return PeiLinkCharacterVisualProfile(
      characterId: profile.characterId,
      gender: profile.gender.trim(),
      ageAppearance: profile.age.trim(),
      height: profile.height.trim(),
      bodyType: profile.bodyType.trim(),
      overallAppearance: appearance,
      hairColor: profile.hairColor.trim(),
      hairStyle: _hairStyleFrom(appearance),
      eyeColor: profile.eyes.trim(),
      stableMarks: profile.specialMarks.trim(),
      clothingStyle: profile.clothingStyle.trim(),
    );
  }

  final String characterId;
  final String gender;
  final String ageAppearance;
  final String height;
  final String bodyType;
  final String overallAppearance;
  final String hairColor;
  final String hairStyle;
  final String eyeColor;
  final String stableMarks;
  final String clothingStyle;

  static String _hairStyleFrom(String appearance) {
    if (appearance.isEmpty) return '';
    final match = RegExp(
      r'([^，。；;]{0,12}(?:短发|长发|卷发|直发|马尾|刘海|发型)[^，。；;]{0,12})',
    ).firstMatch(appearance);
    return match?.group(1)?.trim() ?? '';
  }
}

class PeiLinkVisualContext {
  const PeiLinkVisualContext({this.characterProfiles = const {}});

  final Map<String, PeiLinkCharacterVisualProfile> characterProfiles;
}
