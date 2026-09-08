import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_scope_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/pei_file_service.dart';
import 'package:peijianche_app/services/user_profile_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;
  // Deliberate synthetic collision fixtures, not a provenance whitelist.
  final character = AiCharacter(
    id: 'explicit-user-character',
    characterName: '裴简澈',
    remark: '老裴',
    relationship: '恋人',
    birthday: DateTime(2000, 12, 12),
    introduction: '银白短发、蓝色眼睛，外冷内热，偶尔嘴硬。',
    createdAt: DateTime(2026, 1, 1),
  );
  final settings = CharacterSettings.fromAiCharacter(character).copyWith(
    userCallName: '念念',
    anniversary: '1月17日',
    coreProfile: '用户明确填写的人设',
    behaviorStyle: '用户明确填写的行为',
    forbiddenRules: '用户明确填写的边界',
    exampleDialogues: '念念：你好\n裴简澈：你好',
  );

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    documents = await Directory.systemTemp.createTemp('preserved_profiles_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => documents.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    await documents.delete(recursive: true);
  });

  test('new installation and missing fields remain neutral', () async {
    expect(await CharacterRegistryService().loadAllCharacters(), isEmpty);
    expect((await UserProfileStorageService().loadProfile()).toJson(),
        const UserProfile().toJson());
    expect(CharacterSettings.defaults().toJson(),
        CharacterSettings.genericDefaults().toJson());
    final file = await CharacterScopeService('missing').dataFile(
      'character_settings.json',
    );
    await file.writeAsString('{}');
    expect((await CharacterSettingsStorageService(characterId: 'missing')
            .loadSettings()).toJson(),
        CharacterSettings.genericDefaults().toJson());
    final root = await getApplicationDocumentsDirectory();
    await File('${root.path}/user_profile.json').writeAsString('{}');
    expect((await UserProfileStorageService().loadProfile()).toJson(),
        const UserProfile().toJson());
  });

  test('explicit settings survive new service instances and do not rewrite file',
      () async {
    await CharacterRegistryService().saveAllCharacters([character]);
    await CharacterSettingsStorageService(characterId: character.id)
        .saveSettings(settings);
    final file = await CharacterScopeService(character.id)
        .dataFile('character_settings.json');
    final before = await file.readAsString();
    for (var pass = 0; pass < 2; pass++) {
      final loaded = await CharacterSettingsStorageService(
        characterId: character.id,
      ).loadSettings();
      expect(loaded.toJson(), settings.toJson());
    }
    expect(await file.readAsString(), before);
  });

  for (final includeMemory in [false, true]) {
    test('explicit .pei v${includeMemory ? 2 : 1} settings survive both loads',
        () async {
      final service = PeiFileService();
      final bytes = await service.exportCharacter(
        character, settings, includeMemories: includeMemory,
      );
      final package = service.parse(bytes);
      expect(package.settings.toJson(), settings.toJson());
      final imported = await service.importCharacter(package);
      for (var pass = 0; pass < 2; pass++) {
        final loaded = await CharacterSettingsStorageService(
          characterId: imported.character.id,
        ).loadSettings();
        expect(loaded.toJson(), settings.toJson());
      }
    });
  }

  test('explicit UserProfile collision values survive loading without writes',
      () async {
    const profile = UserProfile(
      nickname: '念念', peiLinkId: '一只小狐念', peiCallName: '念念',
      identity: '裴简澈的恋人', birthday: '1月17日',
      likes: '用户明确填写',
    );
    await UserProfileStorageService().saveProfile(profile);
    final root = await getApplicationDocumentsDirectory();
    final file = File('${root.path}/user_profile.json');
    final before = await file.readAsString();
    for (var pass = 0; pass < 2; pass++) {
      expect((await UserProfileStorageService().loadProfile()).toJson(),
          profile.toJson());
    }
    expect(await file.readAsString(), before);
  });

  test('unmarked old data is preserved rather than guessed from its contents',
      () async {
    final file = await CharacterScopeService('unmarked')
        .dataFile('character_settings.json');
    await file.writeAsString(jsonEncode(settings.toJson()));
    final loaded = await CharacterSettingsStorageService(characterId: 'unmarked')
        .loadSettings();
    expect(loaded.toJson(), settings.toJson());
  });
}
