import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/red_packet_data.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';
import 'package:peijianche_app/widgets/chat/message_renderer.dart';
import 'package:peijianche_app/widgets/chat/renderers/red_packet_message_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'red_packet_interaction_test_',
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

  testWidgets('red packet card displays message without amount', (
    tester,
  ) async {
    await tester.pumpWidget(_messageApp(_message()));

    expect(find.text('红包'), findsOneWidget);
    expect(find.text('给你的'), findsOneWidget);
    expect(find.text('等待领取'), findsOneWidget);
    expect(find.text('¥520.00'), findsNothing);
  });

  testWidgets('tapping unopened red packet invokes open action', (
    tester,
  ) async {
    var tapCount = 0;
    await tester.pumpWidget(
      _messageApp(_message(), onTap: () => tapCount += 1),
    );

    await tester.tap(find.text('等待领取'));

    expect(tapCount, 1);
  });

  testWidgets('opened dialog displays amount message and sender', (
    tester,
  ) async {
    const data = RedPacketData(
      amount: 52000,
      message: '今天开心一点',
      senderId: 'pei',
      isOpened: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RedPacketOpenedDialog(data: data, senderName: '裴简澈'),
        ),
      ),
    );

    expect(find.text('恭喜收到红包'), findsOneWidget);
    expect(find.text('¥520.00'), findsOneWidget);
    expect(find.textContaining('今天开心一点'), findsOneWidget);
    expect(find.text('来自 裴简澈'), findsOneWidget);
  });

  test('opening persists state across service instances', () async {
    final storage = ChatStorageService(characterId: 'pei');
    await storage.saveMessages([_message()]);
    final openedAt = DateTime.utc(2026, 8, 3, 12);

    await storage.openRedPacket('packet-1', openedAt: openedAt);
    final restored = (await ChatStorageService(
      characterId: 'pei',
    ).loadMessages()).single;

    expect(restored.redPacket?.isOpened, isTrue);
    expect(restored.redPacket?.openedAt, openedAt);
  });

  test('opening an opened packet is idempotent', () async {
    final storage = ChatStorageService(characterId: 'pei');
    await storage.saveMessages([_message()]);
    final firstOpenedAt = DateTime.utc(2026, 8, 3, 12);
    final secondOpenedAt = DateTime.utc(2026, 8, 3, 13);

    await storage.openRedPacket('packet-1', openedAt: firstOpenedAt);
    final second = await storage.openRedPacket(
      'packet-1',
      openedAt: secondOpenedAt,
    );

    expect(second?.redPacket?.isOpened, isTrue);
    expect(second?.redPacket?.openedAt, firstOpenedAt);
  });

  testWidgets('normal text rendering remains unchanged', (tester) async {
    await tester.pumpWidget(
      _messageApp(ChatMessage(role: 'user', content: '普通消息')),
    );

    expect(find.text('普通消息'), findsOneWidget);
    expect(find.text('红包'), findsNothing);
  });
}

ChatMessage _message() {
  return ChatMessage(
    id: 'packet-1',
    role: 'assistant',
    content: '',
    type: MessageType.redPacket,
    redPacket: const RedPacketData(
      amount: 52000,
      message: '给你的',
      senderId: 'pei',
      receiverId: 'user',
    ),
  );
}

Widget _messageApp(ChatMessage message, {VoidCallback? onTap}) {
  return MaterialApp(
    home: Scaffold(
      body: MessageRenderer(
        message: message,
        onLongPress: () {},
        onRedPacketTap: onTap,
        assistantAvatar: const SizedBox.square(dimension: 40),
        userAvatar: const SizedBox.square(dimension: 40),
      ),
    ),
  );
}
