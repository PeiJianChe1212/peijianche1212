import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/pages/peilink/character_creation_page.dart';

void main() {
  test('profile edits keep the same character id and untouched fields', () {
    const original = CharacterProfile(
      characterId: 'character_existing',
      name: '旧名字',
      personalityDescription: '旧性格',
      backgroundStory: '旧背景',
      occupation: '未展示但必须保留的职业',
      familyBackground: '未展示但必须保留的家庭资料',
      currentStage: '当前关系阶段',
    );

    final edited = mergeCharacterProfileEdits(original, const {
      'name': '新名字',
      'personalityDescription': '新性格',
      'backgroundStory': '新背景',
    });

    expect(edited.characterId, original.characterId);
    expect(edited.name, '新名字');
    expect(edited.personalityDescription, '新性格');
    expect(edited.backgroundStory, '新背景');
    expect(edited.occupation, original.occupation);
    expect(edited.familyBackground, original.familyBackground);
    expect(edited.currentStage, original.currentStage);
  });

  test(
    'edit path updates in place and never recreates or clears runtime data',
    () {
      final source = File(
        'lib/pages/peilink/character_creation_page.dart',
      ).readAsStringSync();
      final editBody = source.substring(
        source.indexOf('Future<void> _saveExisting'),
      );

      expect(editBody, contains('updateCharacter(updatedCharacter)'));
      expect(editBody, contains('character.id'));
      expect(editBody, isNot(contains('addCharacter(character)')));
      expect(editBody, isNot(contains('deleteCharacter')));
      expect(editBody, isNot(contains('deleteAllData')));
      expect(editBody, isNot(contains('CharacterArchiveStorageService')));
    },
  );
}
