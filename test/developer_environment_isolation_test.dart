import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/developer_environment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp(
      'peilink_environment_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  test(
    'fresh public workspace is empty and does not seed Pei Jianche',
    () async {
      PeiLinkRuntime.configure(PeiLinkBuild.user);
      final registry = CharacterRegistryService();
      expect(await registry.loadCharacters(), isEmpty);
      expect(await registry.loadAllCharacters(), isEmpty);
    },
  );

  test(
    'developer role stays stored while hidden from public workspace',
    () async {
      PeiLinkRuntime.configure(PeiLinkBuild.dev);
      final registry = CharacterRegistryService();
      final user = AiCharacter(
        id: 'user_role',
        characterName: '测试角色',
        remark: '',
        createdAt: DateTime(2026, 8, 9),
      );
      await registry.saveAllCharacters([
        AiCharacter(
          id: AiCharacter.defaultCharacterId,
          characterName: '裴简澈',
          remark: '',
          createdAt: DateTime(2024, 12, 12),
          isBuiltIn: true,
        ),
        user,
      ]);
      await File(
        '${documents.path}/peilink_dev/developer_environment.json',
      ).writeAsString(jsonEncode({'enabled': false}));

      final visible = await registry.loadCharacters();
      final stored = await registry.loadAllCharacters();
      expect(visible.map((item) => item.id), ['user_role']);
      expect(
        stored.map((item) => item.id),
        contains(AiCharacter.defaultCharacterId),
      );
    },
  );

  test(
    'developer sandbox reveals the private role without migration',
    () async {
      PeiLinkRuntime.configure(PeiLinkBuild.dev);
      final registry = CharacterRegistryService();
      await registry.saveAllCharacters([
        AiCharacter(
          id: AiCharacter.defaultCharacterId,
          characterName: '裴简澈',
          remark: '',
          createdAt: DateTime(2024, 12, 12),
          isBuiltIn: true,
        ),
      ]);
      await File(
        '${documents.path}/peilink_dev/developer_environment.json',
      ).writeAsString(jsonEncode({'enabled': true}));

      final visible = await registry.loadCharacters();
      expect(visible.single.id, AiCharacter.defaultCharacterId);
    },
  );

  test('dev and user builds use independent named data roots', () async {
    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    final devRegistry = CharacterRegistryService();
    await devRegistry.saveAllCharacters([
      AiCharacter(
        id: 'dev_role',
        characterName: '开发角色',
        remark: '',
        createdAt: DateTime(2026, 8, 12),
      ),
    ]);

    PeiLinkRuntime.configure(PeiLinkBuild.user);
    final userRegistry = CharacterRegistryService();
    expect(await userRegistry.loadAllCharacters(), isEmpty);
    await userRegistry.saveAllCharacters([
      AiCharacter(
        id: 'user_role',
        characterName: '用户角色',
        remark: '',
        createdAt: DateTime(2026, 8, 12),
      ),
    ]);

    PeiLinkRuntime.configure(PeiLinkBuild.dev);
    expect((await devRegistry.loadAllCharacters()).single.id, 'dev_role');
    expect(
      await File(
        '${documents.path}/peilink_dev/character_registry.json',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        '${documents.path}/peilink_user/character_registry.json',
      ).exists(),
      isTrue,
    );
  });

  test('user build rejects developer environment activation', () async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    final service = DeveloperEnvironmentService();

    expect(service.accessGranted(designatedAccount: true), isFalse);
    expect(
      () => service.setEnabled(true, designatedAccount: true),
      throwsA(isA<StateError>()),
    );
    expect(await service.isEnabled(), isFalse);
  });
}
