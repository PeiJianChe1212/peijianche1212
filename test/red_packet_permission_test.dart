import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/red_packet_data.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'red_packet_permission_test_',
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

  test('user cannot open a red packet sent by the same user', () async {
    final storage = ChatStorageService(characterId: 'pei');
    await storage.saveMessages([_packet(senderId: 'user', receiverId: 'pei')]);

    final result = await storage.openRedPacket(
      'packet-1',
      currentUserId: 'user',
    );
    final restored = (await storage.loadMessages()).single;

    expect(result, isNull);
    expect(restored.redPacket?.isOpened, isFalse);
    expect(restored.redPacket?.openedAt, isNull);
  });

  test('user can open an AI red packet addressed to the user', () async {
    final storage = ChatStorageService(characterId: 'pei');
    await storage.saveMessages([_packet(senderId: 'pei', receiverId: 'user')]);
    final openedAt = DateTime.utc(2026, 8, 3, 12);

    final result = await storage.openRedPacket(
      'packet-1',
      currentUserId: 'user',
      openedAt: openedAt,
    );

    expect(result?.redPacket?.isOpened, isTrue);
    expect(result?.redPacket?.openedAt, openedAt);
  });

  test('opened state persists after chat storage is recreated', () async {
    final storage = ChatStorageService(characterId: 'pei');
    await storage.saveMessages([_packet(senderId: 'pei', receiverId: 'user')]);
    await storage.openRedPacket('packet-1', currentUserId: 'user');

    final restored = (await ChatStorageService(
      characterId: 'pei',
    ).loadMessages()).single;

    expect(restored.redPacket?.isOpened, isTrue);
    expect(restored.redPacket?.openedAt, isNotNull);
  });

  test('a different character cannot access another chat red packet', () async {
    final roleA = ChatStorageService(characterId: 'role_a');
    final roleB = ChatStorageService(characterId: 'role_b');
    await roleA.saveMessages([_packet(senderId: 'role_a', receiverId: 'user')]);

    final result = await roleB.openRedPacket('packet-1', currentUserId: 'user');

    expect(result, isNull);
    expect(await roleB.loadMessages(), isEmpty);
    expect((await roleA.loadMessages()).single.redPacket?.isOpened, isFalse);
  });

  test('legacy packet without receiver loads but cannot be opened', () async {
    final storage = ChatStorageService(characterId: 'legacy');
    await storage.saveMessages([_packet(senderId: 'pei', receiverId: '')]);

    final restored = (await storage.loadMessages()).single;
    final result = await storage.openRedPacket(
      'packet-1',
      currentUserId: 'user',
    );

    expect(restored.redPacket?.receiverId, '');
    expect(result, isNull);
  });
}

ChatMessage _packet({required String senderId, required String receiverId}) {
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
