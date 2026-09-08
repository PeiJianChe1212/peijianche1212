import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_archive.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/pei_file_service.dart';
import 'package:peijianche_app/services/prompt_experiment_context_builder.dart';

const privateTerms = ['念念', '林念念', '一只小狐念', '裴简澈', '车云千'];

void expectNoPrivateTerms(String value) {
  for (final term in privateTerms) {
    expect(
      value,
      isNot(contains(term)),
      reason: 'unexpected private term: $term',
    );
  }
}

String finalSystemPrompt({
  required CharacterSettings settings,
  required String characterId,
  UserProfile user = const UserProfile(),
}) => PromptExperimentContextBuilder.buildFacts(
  settings: settings,
  profile: CharacterProfile(
    characterId: characterId,
    name: settings.characterName,
  ),
  archive: CharacterArchive(characterId: characterId),
  user: user,
  memory: '',
  currentTime: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    documents = await Directory.systemTemp.createTemp('privacy_isolation_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => documents.path);
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test(
    'fresh user and character produce a private-term-free final prompt',
    () async {
      final character = AiCharacter(
        id: 'test_a',
        characterName: '测试角色A',
        remark: '',
        persona: '安静、可靠。',
        createdAt: DateTime(2026, 8, 27),
      );
      await CharacterRegistryService().saveAllCharacters([character]);

      final settings = await CharacterSettingsStorageService(
        characterId: character.id,
      ).loadSettings();
      final prompt = finalSystemPrompt(
        settings: settings,
        characterId: character.id,
        user: const UserProfile(nickname: '测试用户A'),
      );

      expect(settings.userCallName, isEmpty);
      expectNoPrivateTerms(jsonEncode(settings.toJson()));
      expectNoPrivateTerms(prompt);
    },
  );

  test('empty user name does not create a concrete name in final prompt', () {
    final settings = CharacterSettings.fromAiCharacter(
      AiCharacter(
        id: 'empty_user',
        characterName: '空用户名角色',
        remark: '',
        createdAt: DateTime(2026, 8, 27),
      ),
    );
    final prompt = finalSystemPrompt(
      settings: settings,
      characterId: 'empty_user',
    );

    expect(settings.userCallName, isEmpty);
    expectNoPrivateTerms(prompt);
  });

  test('two character prompts remain isolated', () {
    CharacterSettings settings(String id, String name, String marker) =>
        CharacterSettings.fromAiCharacter(
          AiCharacter(
            id: id,
            characterName: name,
            remark: '',
            persona: marker,
            createdAt: DateTime(2026, 8, 27),
          ),
        );
    final first = finalSystemPrompt(
      settings: settings('a', '测试角色A', '仅属于A的资料'),
      characterId: 'a',
    );
    final second = finalSystemPrompt(
      settings: settings('b', '测试角色B', '仅属于B的资料'),
      characterId: 'b',
    );

    expect(first, contains('仅属于A的资料'));
    expect(first, isNot(contains('仅属于B的资料')));
    expect(second, contains('仅属于B的资料'));
    expect(second, isNot(contains('仅属于A的资料')));
    expectNoPrivateTerms('$first\n$second');
  });

  test('.pei missing optional settings uses neutral import defaults', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'peilink.character',
          'version': 1,
          'character': {'name': '导入角色', 'persona': '导入包自带人设'},
          'configuration': {'characterName': '导入角色', 'coreProfile': '导入包自带人设'},
        }),
      ),
    );
    final package = PeiFileService().parse(bytes);

    expect(package.settings.userCallName, isEmpty);
    expectNoPrivateTerms(jsonEncode(package.settings.toJson()));
  });

  test(
    'persisted public character settings are not classified by value',
    () async {
      final character = AiCharacter(
        id: 'legacy_public',
        characterName: '旧版角色',
        remark: '',
        createdAt: DateTime(2025, 1, 1),
      );
      await CharacterRegistryService().saveAllCharacters([character]);
      final storage = CharacterSettingsStorageService(
        characterId: character.id,
      );
      await storage.saveSettings(
        CharacterSettings.fromAiCharacter(
          character,
        ).copyWith(userCallName: '念念'),
      );

      final migrated = await storage.loadSettings();
      expect(migrated.userCallName, '念念');
      final persisted = await storage.loadSettings();
      expect(persisted.userCallName, '念念');
    },
  );
}
