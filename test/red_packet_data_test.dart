import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/red_packet_data.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'red_packet_data_test_',
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

  test('normal text message remains unchanged with null red packet data', () {
    final original = ChatMessage(role: 'user', content: '你好');
    final restored = ChatMessage.fromJson(original.toJson());

    expect(restored.type, MessageType.text);
    expect(restored.redPacket, isNull);
    expect(restored.content, '你好');
  });

  test('red packet message saves and restores integer amount data', () async {
    final storage = ChatStorageService(characterId: 'pei');
    await storage.saveMessages([_redPacketMessage(id: 'packet-1')]);

    final restored = (await storage.loadMessages()).single;

    expect(restored.type, MessageType.redPacket);
    expect(restored.redPacket?.amount, 52000);
    expect(restored.redPacket?.message, '平安喜乐');
    expect(restored.redPacket?.senderId, 'pei');
    expect(restored.redPacket?.isOpened, isFalse);
    expect(restored.redPacket?.openedAt, isNull);
  });

  test('red packet JSON round trip preserves opened state and time', () {
    final openedAt = DateTime.utc(2026, 8, 3, 12, 30);
    final original = RedPacketData(
      amount: 131400,
      message: '给你',
      senderId: 'pei',
      isOpened: true,
      openedAt: openedAt,
    );

    final restored = RedPacketData.fromJson(original.toJson());

    expect(restored.amount, 131400);
    expect(restored.message, '给你');
    expect(restored.senderId, 'pei');
    expect(restored.isOpened, isTrue);
    expect(restored.openedAt, openedAt);
    expect(original.toJson()['amount'], isA<int>());
  });

  test('legacy chat JSON without redPacket loads normally', () async {
    final directory = Directory('${documentsDirectory.path}/characters/legacy');
    await directory.create(recursive: true);
    await File('${directory.path}/chat_history.json').writeAsString(
      jsonEncode([
        {'id': 'legacy-1', 'role': 'user', 'content': '旧消息'},
      ]),
    );

    final restored = await ChatStorageService(
      characterId: 'legacy',
    ).loadMessages();

    expect(restored, hasLength(1));
    expect(restored.single.type, MessageType.text);
    expect(restored.single.redPacket, isNull);
  });

  test('legacy red packet JSON without receiverId defaults to empty', () {
    final restored = RedPacketData.fromJson({
      'amount': 52000,
      'message': '旧红包',
      'senderId': 'pei',
      'isOpened': false,
    });

    expect(restored.receiverId, '');
  });

  test('red packet storage is isolated for each character', () async {
    await ChatStorageService(
      characterId: 'pei',
    ).saveMessages([_redPacketMessage(id: 'pei-packet')]);

    final peiMessages = await ChatStorageService(
      characterId: 'pei',
    ).loadMessages();
    final cheMessages = await ChatStorageService(
      characterId: 'che',
    ).loadMessages();

    expect(peiMessages.single.id, 'pei-packet');
    expect(cheMessages, isEmpty);
  });

  test('unopened red packet and its amount are excluded from context', () {
    final context = ConversationContext([
      ChatMessage(role: 'user', content: '红包前的消息'),
      _redPacketMessage(id: 'hidden-packet'),
      ChatMessage(role: 'assistant', content: '红包后的消息'),
    ]);

    expect(context.messages.map((message) => message.content), [
      '红包前的消息',
      '红包后的消息',
    ]);
    expect(
      context.messages.any((message) => message.redPacket?.amount == 52000),
      isFalse,
    );
  });
}

ChatMessage _redPacketMessage({required String id}) {
  return ChatMessage(
    id: id,
    role: 'assistant',
    content: '',
    type: MessageType.redPacket,
    redPacket: const RedPacketData(
      amount: 52000,
      message: '平安喜乐',
      senderId: 'pei',
    ),
  );
}
