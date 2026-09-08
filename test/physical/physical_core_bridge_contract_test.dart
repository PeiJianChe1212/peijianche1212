import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/physical/physical_speech_contract.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/core_bridge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('core_bridge_contract_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => documents.path);
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    await CharacterRegistryService().saveAllCharacters([
      AiCharacter(
        id: 'contract_character',
        characterName: 'Contract 测试角色',
        remark: '',
        createdAt: DateTime(2026, 9, 8),
      ),
    ]);
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await documents.delete(recursive: true);
  });

  test('normal CoreBridge reply keeps contract null and request unchanged', () async {
    final calls = <({List<String> contents, String? contract})>[];
    final service = CoreBridgeService(
      replySender: ({
        required messages,
        required characterId,
        required conversationMode,
        required temperature,
        required replyLength,
        required initiative,
        required intimacy,
        required tsundere,
        String? physicalSpeechContract,
      }) async {
        calls.add((
          contents: messages.map((message) => message.content).toList(),
          contract: physicalSpeechContract,
        ));
        return '普通回复';
      },
    );

    await service.reply(
      characterId: 'contract_character',
      userText: '普通消息',
    );
    await service.reply(
      characterId: 'contract_character',
      userText: '普通消息',
      physicalSpeechContract: PhysicalSpeechContract.instruction,
    );

    expect(calls, hasLength(2));
    expect(calls[0].contract, isNull);
    expect(calls[1].contract, PhysicalSpeechContract.instruction);
    expect(calls[0].contents, calls[1].contents);
  });
}
