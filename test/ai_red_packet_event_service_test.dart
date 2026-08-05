import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/red_packet_data.dart';
import 'package:peijianche_app/prompt_composer/prompt_composer.dart';
import 'package:peijianche_app/prompt_composer/prompt_context.dart';
import 'package:peijianche_app/services/ai_red_packet_event_service.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'ai_red_packet_event_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documentsDirectory.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await documentsDirectory.delete(recursive: true);
  });

  test('AI automatically receives a red packet addressed to itself', () async {
    final storage = ChatStorageService(characterId: 'pei');
    final message = _packet(receiverId: 'pei');
    await storage.saveMessages([message]);
    final receivedAt = DateTime.utc(2026, 8, 3, 16);

    final event = await AiRedPacketEventService(
      characterId: 'pei',
      storage: storage,
    ).receive(message, receivedAt: receivedAt);

    expect(event, isNotNull);
    expect(event?.shouldGenerateReply, isTrue);
    expect(event?.message.redPacket?.isOpened, isTrue);
    expect(event?.message.redPacket?.openedAt, receivedAt);
  });

  test('AI receive state persists after storage is recreated', () async {
    final storage = ChatStorageService(characterId: 'pei');
    final message = _packet(receiverId: 'pei');
    await storage.saveMessages([message]);
    await AiRedPacketEventService(
      characterId: 'pei',
      storage: storage,
    ).receive(message);

    final restored = (await ChatStorageService(
      characterId: 'pei',
    ).loadMessages()).single;

    expect(restored.redPacket?.isOpened, isTrue);
    expect(restored.redPacket?.openedAt, isNotNull);
  });

  test(
    'event context requests natural reply without exposing amount',
    () async {
      final storage = ChatStorageService(characterId: 'pei');
      final message = _packet(receiverId: 'pei');
      await storage.saveMessages([message]);
      final event = await AiRedPacketEventService(
        characterId: 'pei',
        storage: storage,
      ).receive(message);

      final context = event!.buildContext();
      const base = ContextBuildResult(
        messages: [
          {'role': 'system', 'content': 'character'},
        ],
        systemPrompt: 'character',
      );
      final composed = PromptComposer(
        baseContext: base,
      ).addContext(PromptContext.redPacketEvent(context)).compose();

      expect(context, contains('User sent you a red packet.'));
      expect(context, contains('Respond naturally'));
      expect(context, isNot(contains('520')));
      expect(context, isNot(contains('yuan')));
      expect(composed.systemPrompt, contains(context));
    },
  );

  test('AI cannot receive a packet addressed to another character', () async {
    final storage = ChatStorageService(characterId: 'pei');
    final message = _packet(receiverId: 'che');
    await storage.saveMessages([message]);

    final event = await AiRedPacketEventService(
      characterId: 'pei',
      storage: storage,
    ).receive(message);

    expect(event, isNull);
    expect((await storage.loadMessages()).single.redPacket?.isOpened, isFalse);
  });

  test('AI cannot receive a packet sent by itself', () async {
    final storage = ChatStorageService(characterId: 'pei');
    final message = _packet(senderId: 'pei', receiverId: 'user');
    await storage.saveMessages([message]);

    final event = await AiRedPacketEventService(
      characterId: 'pei',
      storage: storage,
    ).receive(message);

    expect(event, isNull);
    expect((await storage.loadMessages()).single.redPacket?.isOpened, isFalse);
  });
}

ChatMessage _packet({String senderId = 'user', required String receiverId}) {
  return ChatMessage(
    id: 'packet-1',
    role: senderId == 'user' ? 'user' : 'assistant',
    content: '',
    type: MessageType.redPacket,
    redPacket: RedPacketData(
      amount: 52000,
      message: '给你的',
      senderId: senderId,
      receiverId: receiverId,
    ),
  );
}
