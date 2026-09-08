import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';
import 'package:peijianche_app/services/core_bridge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    documents = await Directory.systemTemp.createTemp('core_bridge_service_');
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
    'loads formal history, appends transient user turn and never writes it',
    () async {
      final character = AiCharacter(
        id: 'bridge_character',
        characterName: 'Bridge 测试角色',
        remark: '',
        createdAt: DateTime(2026, 8, 28),
      );
      await CharacterRegistryService().saveAllCharacters([character]);
      final storage = ChatStorageService(characterId: character.id);
      await storage.saveMessages([
        ChatMessage(role: 'user', content: '历史用户消息'),
        ChatMessage(role: 'assistant', content: '历史角色回复'),
      ]);
      final historyFile = File(
        '${documents.path}/peilink_user/characters/${character.id}/chat_history.json',
      );
      final before = await historyFile.readAsBytes();

      final service = CoreBridgeService(
        replySender:
            ({
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
              expect(characterId, character.id);
              expect(messages.map((message) => message.content), [
                '历史用户消息',
                '历史角色回复',
                'Physical 本轮消息',
              ]);
              expect(messages.last.role, 'user');
              return '测试 Provider 的清理后回复';
            },
      );
      addTearDown(service.dispose);

      final reply = await service.reply(
        characterId: character.id,
        userText: 'Physical 本轮消息',
      );
      final after = await historyFile.readAsBytes();
      expect(reply, '测试 Provider 的清理后回复');
      expect(after, before);
      expect((await storage.loadMessages()).length, 2);
    },
  );

  test(
    'unknown character is rejected instead of falling back to active role',
    () async {
      final service = CoreBridgeService(
        replySender:
            ({
              required messages,
              required characterId,
              required conversationMode,
              required temperature,
              required replyLength,
              required initiative,
              required intimacy,
              required tsundere,
              String? physicalSpeechContract,
            }) async => 'unexpected',
      );
      addTearDown(service.dispose);

      await expectLater(
        service.reply(characterId: 'missing', userText: '你好'),
        throwsA(
          isA<CoreBridgeException>().having(
            (error) => error.code,
            'code',
            'CHARACTER_NOT_FOUND',
          ),
        ),
      );
    },
  );

  test(
    'injects transient physical context after formal history and never writes it',
    () async {
      final character = AiCharacter(
        id: 'transient_character',
        characterName: '临时上下文角色',
        remark: '',
        createdAt: DateTime(2026, 8, 31),
      );
      await CharacterRegistryService().saveAllCharacters([character]);
      final storage = ChatStorageService(characterId: character.id);
      await storage.saveMessages([ChatMessage(role: 'user', content: '正式历史')]);
      final historyFile = File(
        '${documents.path}/peilink_user/characters/${character.id}/chat_history.json',
      );
      final before = await historyFile.readAsBytes();
      final service = CoreBridgeService(
        replySender:
            ({
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
              expect(messages.map((message) => message.content), [
                '正式历史',
                '我刚买了个蛋糕',
                '什么味的？',
                '草莓的',
              ]);
              return '草莓蛋糕不错。';
            },
      );
      addTearDown(service.dispose);

      await service.reply(
        characterId: character.id,
        userText: '草莓的',
        transientContext: [
          ChatMessage(role: 'user', content: '我刚买了个蛋糕', source: 'physical'),
          ChatMessage(role: 'assistant', content: '什么味的？', source: 'physical'),
        ],
      );

      expect(await historyFile.readAsBytes(), before);
      expect((await storage.loadMessages()).length, 1);
    },
  );
}
