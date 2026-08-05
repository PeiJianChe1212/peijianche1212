import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';

void main() {
  test(
    'legacy character data seeds the structured profile without mutation',
    () {
      final character = AiCharacter.peiJianChe();
      final legacy = CharacterSettings.defaults();

      final profile = CharacterProfile.fromLegacy(character, legacy);

      expect(profile.characterId, character.id);
      expect(profile.name, character.characterName);
      expect(profile.birthday, legacy.birthday);
      expect(profile.relationship, legacy.relation);
      expect(profile.personalityDescription, legacy.coreProfile);
    },
  );

  test('structured profile fields survive json round trip', () {
    const profile = CharacterProfile(
      characterId: 'character_a',
      name: '裴简澈',
      age: '28',
      height: '188cm',
      hairColor: '银白',
      personalityTags: '清冷,克制',
      surfacePersonality: '看起来疏离',
      deepPersonality: '内心柔软',
      currentStage: '稳定交往',
    );

    final restored = CharacterProfile.fromJson(
      profile.toJson(),
      profile.characterId,
    );

    expect(restored.age, '28');
    expect(restored.height, '188cm');
    expect(restored.hairColor, '银白');
    expect(restored.surfacePersonality, '看起来疏离');
    expect(restored.deepPersonality, '内心柔软');
    expect(restored.currentStage, '稳定交往');
  });

  test('legacy nickname is preserved as the new pet name', () {
    final profile = CharacterProfile.fromJson(const {
      'nickname': '阿澈',
      'socialId': 'peijianche1212',
    }, 'character_a');

    expect(profile.petName, '阿澈');
    expect(profile.socialId, 'peijianche1212');
  });

  test('profile completion is calculated from non-empty fields', () {
    const profile = CharacterProfile(
      characterId: 'completion',
      name: '裴简澈',
      age: '28',
      overallAppearance: '银发',
    );

    expect(profile.basicCompletion, 2 / 10);
    expect(profile.appearanceCompletion, 1 / 7);
  });
}
