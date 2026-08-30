import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/pei_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('peilink_pei_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('exports and parses version 1 without private systems', () async {
    final avatar = File('${documents.path}/avatar.png');
    await avatar.writeAsBytes([1, 2, 3, 4]);
    final character = AiCharacter(
      id: 'source',
      characterName: '阿澄',
      remark: '澄澄',
      avatarPath: avatar.path,
      introduction: '安静可靠。',
      persona: '喜欢观察星空。',
      createdAt: DateTime(2026, 8, 11),
    );
    final settings = CharacterSettings.fromAiCharacter(
      character,
    ).copyWith(conversationMode: 'deep', temperature: 0.8);

    final bytes = await PeiFileService().exportCharacter(character, settings);
    final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final parsed = PeiFileService().parse(bytes);

    expect(raw['format'], 'peilink.character');
    expect(raw['version'], 1);
    expect(raw.containsKey('chatMessages'), isFalse);
    expect(raw.containsKey('apiKey'), isFalse);
    expect(raw.containsKey('characterProfile'), isFalse);
    expect(raw.containsKey('characterArchive'), isFalse);
    expect((raw['reserved'] as Map)['echo'], isNull);
    expect((raw['reserved'] as Map)['memory'], isNull);
    expect(parsed.character.characterName, '阿澄');
    expect(parsed.settings.conversationMode, 'deep');
    expect(parsed.avatarBytes, Uint8List.fromList([1, 2, 3, 4]));
  });

  test('rejects damaged and unsupported files with distinct errors', () {
    expect(
      () => PeiFileService().parse(Uint8List.fromList(utf8.encode('broken'))),
      throwsA(isA<PeiFileCorruptedException>()),
    );
    final futureVersion = Uint8List.fromList(
      utf8.encode(jsonEncode({'format': 'peilink.character', 'version': 99})),
    );
    expect(
      () => PeiFileService().parse(futureVersion),
      throwsA(isA<PeiFileUnsupportedVersionException>()),
    );
  });

  test('duplicate import creates an isolated chat-ready character', () async {
    final registry = CharacterRegistryService();
    final original = AiCharacter(
      id: 'original',
      characterName: '阿澄',
      remark: '',
      createdAt: DateTime(2026, 1, 1),
    );
    await registry.saveAllCharacters([original]);
    final sourceSettings = CharacterSettings.fromAiCharacter(
      original,
    ).copyWith(coreProfile: '独立导入的人设', conversationMode: 'deep');
    final bytes = await PeiFileService().exportCharacter(
      original,
      sourceSettings,
    );

    final result = await PeiFileService(
      registry: registry,
    ).importCharacter(PeiFileService().parse(bytes));
    final stored = await registry.loadAllCharacters();
    final importedSettings = await CharacterSettingsStorageService(
      characterId: result.character.id,
    ).loadSettings();

    expect(result.renamed, isTrue);
    expect(result.character.characterName, '阿澄 (2)');
    expect(stored.length, 2);
    expect(stored.first.id, original.id);
    expect(importedSettings.coreProfile, '独立导入的人设');
    expect(importedSettings.conversationMode, 'deep');
  });

  test('name collision suffix never overwrites an existing name', () {
    expect(PeiFileService.uniqueName('阿澄', ['阿澄', '阿澄 (2)']), '阿澄 (3)');
  });
}
