import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/memory_extraction_result.dart';
import 'package:peijianche_app/services/auto_memory_extraction_service.dart';
import 'package:peijianche_app/services/memory2_extractor.dart';
import 'package:peijianche_app/services/character_deletion_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/relationship_memory_storage_service.dart';
import 'package:peijianche_app/services/shared_experience_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('memory9_cleanup_');
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
    await documents.delete(recursive: true);
  });

  test('removes target shared experiences and preserves other raw rows',
      () async {
    final raw = [
      {
        'id': 'target',
        'participantIds': ['character-a', 'other'],
        'summary': 'target',
        'futureExtension': {'keep': true},
      },
      {
        'id': 'other',
        'participantIds': ['other', 'another'],
        'summary': 'other',
        'futureExtension': ['untouched'],
      },
    ];
    final file = File('${documents.path}/shared_experiences.json');
    await file.writeAsString(jsonEncode(raw));
    final storage = SharedExperienceStorageService();

    await storage.validateForRemoval();
    await storage.removeForCharacter('character-a');

    expect(jsonDecode(await file.readAsString()), [raw[1]]);
  });

  test('removes target relationship memories and preserves other raw rows',
      () async {
    final raw = [
      {
        'id': 'target',
        'characterIdA': 'character-a',
        'characterIdB': 'other',
        'summary': 'target',
        'futureExtension': {'keep': true},
      },
      {
        'id': 'other',
        'characterIdA': 'other',
        'characterIdB': 'another',
        'summary': 'other',
        'futureExtension': ['untouched'],
      },
    ];
    final file = File('${documents.path}/relationship_memories.json');
    await file.writeAsString(jsonEncode(raw));
    final storage = RelationshipMemoryStorageService();

    await storage.validateForRemoval();
    await storage.removeForCharacter('character-a');

    expect(jsonDecode(await file.readAsString()), [raw[1]]);
  });

  test('rejects corrupt shared experiences without overwriting', () async {
    final file = File('${documents.path}/shared_experiences.json');
    const corrupt = '{"not":"a list"}';
    await file.writeAsString(corrupt);
    final storage = SharedExperienceStorageService();

    expect(storage.validateForRemoval(), throwsFormatException);
    expect(storage.removeForCharacter('character-a'), throwsFormatException);
    expect(await file.readAsString(), corrupt);
  });

  test('rejects corrupt relationship memories without overwriting', () async {
    final file = File('${documents.path}/relationship_memories.json');
    const corrupt = '[{"characterIdA":42,"characterIdB":"other"}]';
    await file.writeAsString(corrupt);
    final storage = RelationshipMemoryStorageService();

    expect(storage.validateForRemoval(), throwsFormatException);
    expect(storage.removeForCharacter('character-a'), throwsFormatException);
    expect(await file.readAsString(), corrupt);
  });

  test('deletion service removes target global rows and private directory',
      () async {
    final target = _character('target');
    final other = _character('other');
    final registryFile = File('${documents.path}/character_registry.json');
    await registryFile.writeAsString(jsonEncode([target.toJson(), other.toJson()]));
    final targetDir = Directory('${documents.path}/characters/target')
      ..createSync(recursive: true);
    await File('${targetDir.path}/memories.json').writeAsString('[]');
    await File('${documents.path}/shared_experiences.json').writeAsString(
      jsonEncode([
        {'id': 'target', 'participantIds': ['target', 'other'], 'summary': 'x'},
        {'id': 'other', 'participantIds': ['other', 'third'], 'summary': 'y'},
      ]),
    );
    await File('${documents.path}/relationship_memories.json').writeAsString(
      jsonEncode([
        {'id': 'target', 'characterIdA': 'target', 'characterIdB': 'other'},
        {'id': 'other', 'characterIdA': 'other', 'characterIdB': 'third'},
      ]),
    );

    await CharacterDeletionService().delete('target');

    expect(await targetDir.exists(), isFalse);
    expect((jsonDecode(await registryFile.readAsString()) as List).length, 1);
    expect(
      (jsonDecode(await File('${documents.path}/shared_experiences.json').readAsString())
          as List)
          .single['id'],
      'other',
    );
    expect(
      (jsonDecode(await File('${documents.path}/relationship_memories.json').readAsString())
          as List)
          .single['id'],
      'other',
    );
  });

  test('bad registry prevents deletion before directory or global cleanup',
      () async {
    final registryFile = File('${documents.path}/character_registry.json');
    await registryFile.writeAsString('{bad');
    final targetDir = Directory('${documents.path}/characters/target')
      ..createSync(recursive: true);
    final sharedFile = File('${documents.path}/shared_experiences.json');
    await sharedFile.writeAsString(
      '[{"participantIds":["target","other"],"summary":"x"}]',
    );
    final originalShared = await sharedFile.readAsString();

    expect(
      CharacterDeletionService().delete('target'),
      throwsA(isA<FormatException>()),
    );
    expect(await targetDir.exists(), isTrue);
    expect(await registryFile.readAsString(), '{bad');
    expect(await sharedFile.readAsString(), originalShared);
  });

  test('registry deletion failure keeps private directory for retry', () async {
    final target = _character('target');
    final registryFile = File('${documents.path}/character_registry.json');
    await registryFile.writeAsString(jsonEncode([target.toJson()]));
    final targetDir = Directory('${documents.path}/characters/target')
      ..createSync(recursive: true);
    await File('${documents.path}/shared_experiences.json').writeAsString(
      '[{"participantIds":["target","other"],"summary":"x"}]',
    );
    await File('${documents.path}/relationship_memories.json').writeAsString(
      '[{"characterIdA":"target","characterIdB":"other"}]',
    );
    final sharedBefore =
        await File('${documents.path}/shared_experiences.json').readAsString();
    final relationshipBefore = await File(
      '${documents.path}/relationship_memories.json',
    ).readAsString();

    expect(
      CharacterDeletionService(registry: _FailingDeleteRegistry())
          .delete('target'),
      throwsStateError,
    );
    expect(await targetDir.exists(), isTrue);
    expect(
      await File('${documents.path}/shared_experiences.json').readAsString(),
      sharedBefore,
    );
    expect(
      await File('${documents.path}/relationship_memories.json').readAsString(),
      relationshipBefore,
    );
  });

  test('deletion protection blocks extraction before its first await', () async {
    final gate = Completer<void>();
    var gatewayCalls = 0;
    final extraction = AutoMemoryExtractionService(
      characterId: 'protected',
      gateway: _CountingGateway(() => gatewayCalls++),
      messagesLoader: () async => _messages(),
      settingsLoader: () async => CharacterSettings.genericDefaults().copyWith(
            characterName: '角色',
            autoMemoryEnabled: true,
          ),
      userNameLoader: () async => '用户',
      legacyLoader: () async => const [],
    );
    final deleting = AutoMemoryExtractionService.duringCharacterDeletion(
      'protected',
      () => gate.future,
    );
    expect(
      await extraction.maybeExtract(),
      AutoMemoryExtractionOutcome.alreadyRunning,
    );
    expect(gatewayCalls, 0);
    gate.complete();
    await deleting;
  });

  test('failed deletion protection is released for a later extraction',
      () async {
    await expectLater(
      AutoMemoryExtractionService.duringCharacterDeletion(
        'released',
        () async => throw StateError('delete failed'),
      ),
      throwsStateError,
    );
    var gatewayCalls = 0;
    final extraction = AutoMemoryExtractionService(
      characterId: 'released',
      gateway: _CountingGateway(() => gatewayCalls++),
      messagesLoader: () async => _messages(),
      settingsLoader: () async => CharacterSettings.genericDefaults().copyWith(
            characterName: '角色',
            autoMemoryEnabled: true,
          ),
      userNameLoader: () async => '用户',
      legacyLoader: () async => const [],
    );
    await extraction.maybeExtract();
    expect(gatewayCalls, 1);
  });
}

AiCharacter _character(String id) => AiCharacter(
      id: id,
      characterName: id,
      remark: '',
      createdAt: DateTime(2026, 1, 1),
    );

class _FailingDeleteRegistry extends CharacterRegistryService {
  @override
  Future<void> deleteCharacter(String characterId) async {
    throw StateError('simulated registry failure');
  }
}

class _CountingGateway implements Memory2ExtractionGateway {
  _CountingGateway(this.onCall);

  final void Function() onCall;

  @override
  Future<MemoryExtractionResult> extract(Memory2ExtractionRequest request) {
    onCall();
    return Future.value(const MemoryExtractionResult());
  }
}

List<ChatMessage> _messages() => List.generate(
      8,
      (index) => ChatMessage(
        id: 'message_$index',
        role: index.isEven ? 'user' : 'assistant',
        content: '测试消息 $index',
        createdAt: DateTime.utc(2026, 9, 1, 0, index),
      ),
    );
