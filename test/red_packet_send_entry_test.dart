import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/widgets/chat/chat_more_panel.dart';
import 'package:peijianche_app/widgets/chat/red_packet_send_dialog.dart';
import 'package:peijianche_app/widgets/chat/renderers/red_packet_message_renderer.dart';

void main() {
  testWidgets('red packet entry is available from the more panel', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMorePanel(
            onPickImage: () {},
            onRedPacket: () => opened = true,
            onUnavailable: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('红包'));

    expect(opened, isTrue);
  });

  testWidgets('amount and message can be entered and submitted', (
    tester,
  ) async {
    RedPacketDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<RedPacketDraft>(
                  context: context,
                  builder: (_) => const RedPacketSendDialog(),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('red_packet_amount')),
      '520.08',
    );
    await tester.enterText(
      find.byKey(const ValueKey('red_packet_message')),
      '给你的',
    );
    await tester.tap(find.text('发送红包'));
    await tester.pumpAndSettle();

    expect(result?.amount, 52008);
    expect(result?.message, '给你的');
  });

  test('submitted draft creates an unopened red packet chat message', () {
    final message = buildRedPacketMessage(
      const RedPacketDraft(amount: 52000, message: '给你的'),
      receiverId: 'pei',
    );

    expect(message.role, 'user');
    expect(message.type, MessageType.redPacket);
    expect(message.redPacket?.amount, 52000);
    expect(message.redPacket?.message, '给你的');
    expect(message.redPacket?.senderId, 'user');
    expect(message.redPacket?.receiverId, 'pei');
    expect(message.redPacket?.isOpened, isFalse);
  });

  testWidgets('sent red packet data renders as a card', (tester) async {
    final message = buildRedPacketMessage(
      const RedPacketDraft(amount: 52000, message: '给你的'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RedPacketMessageRenderer(data: message.redPacket!),
        ),
      ),
    );

    expect(find.text('红包'), findsOneWidget);
    expect(find.text('给你的'), findsOneWidget);
    expect(find.text('等待对方领取'), findsOneWidget);
    expect(find.text('¥520.00'), findsNothing);
  });

  test('yuan input converts exactly to integer cents', () {
    expect(parseYuanToCents('520'), 52000);
    expect(parseYuanToCents('0.01'), 1);
    expect(parseYuanToCents('12.3'), 1230);
    expect(parseYuanToCents('1.234'), isNull);
    expect(parseYuanToCents('abc'), isNull);
  });
}
