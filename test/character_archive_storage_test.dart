import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_archive.dart';
import 'package:peijianche_app/services/character_archive_storage_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('peilink_archive_test_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  CharacterArchiveStorageService storage(String id) {
    return CharacterArchiveStorageService(
      characterId: id,
      fileProvider: (characterId) async =>
          File('${directory.path}/$characterId/character_archive.json'),
    );
  }

  test('existing character without archive opens as empty', () async {
    final archive = await storage('pei_jian_che').load();

    expect(archive.characterId, 'pei_jian_che');
    expect(archive.values, isEmpty);
  });

  test('new character initializes an empty archive file', () async {
    final service = storage('new_character');

    await service.initialize();

    final file = File('${directory.path}/new_character/character_archive.json');
    expect(await file.exists(), isTrue);
    expect((await service.load()).values, isEmpty);
  });

  test('initialization does not overwrite an existing archive', () async {
    final service = storage('existing_character');
    await service.save(
      const CharacterArchive(
        characterId: 'existing_character',
        values: {'likes': '咖啡'},
      ),
    );

    await service.initialize();

    expect((await service.load()).value('likes'), '咖啡');
  });

  test('archive edits persist and reload', () async {
    final service = storage('bai_zhuo');
    await service.save(
      const CharacterArchive(
        characterId: 'bai_zhuo',
        values: {'favoriteFood': '桂花糕', 'whenAngry': '沉默'},
      ),
    );

    final restored = await service.load();
    expect(restored.value('favoriteFood'), '桂花糕');
    expect(restored.value('whenAngry'), '沉默');
  });

  test('language and growth fields persist and reload', () async {
    final service = storage('archive_v24');
    await service.save(
      const CharacterArchive(
        characterId: 'archive_v24',
        values: {
          'languageHabits': '句子简短',
          'commonExpressions': '嗯',
          'speakingStyle': '克制',
          'chatPace': '慢',
          'expressionTraits': '很少使用感叹号',
          'childhoodExperience': '在海边长大',
          'adolescence': '独自求学',
          'turningPoints': '离开故乡',
          'influentialPeople': '祖父',
          'lifeExperience': '长期旅行',
        },
      ),
    );

    final restored = await service.load();
    expect(restored.value('languageHabits'), '句子简短');
    expect(restored.value('expressionTraits'), '很少使用感叹号');
    expect(restored.value('childhoodExperience'), '在海边长大');
    expect(restored.value('lifeExperience'), '长期旅行');
  });

  test('archive completion counts old and new fields without mutation', () {
    const archive = CharacterArchive(
      characterId: 'completion',
      values: {'likes': '咖啡', 'languageHabits': '简短'},
    );

    expect(archive.completion, 2 / CharacterArchive.fieldKeys.length);
    expect(archive.values.length, 2);
  });

  test('different characters use isolated archive files', () async {
    await storage('character_a').save(
      const CharacterArchive(
        characterId: 'character_a',
        values: {'likes': '咖啡'},
      ),
    );
    await storage('character_b').save(
      const CharacterArchive(
        characterId: 'character_b',
        values: {'likes': '茶'},
      ),
    );

    expect((await storage('character_a').load()).value('likes'), '咖啡');
    expect((await storage('character_b').load()).value('likes'), '茶');
  });
}
