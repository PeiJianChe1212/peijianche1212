import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/widgets/chat/message_renderer.dart';

void main() {
  testWidgets('long pressing a normal user message opens its action callback', (
    tester,
  ) async {
    var longPressed = false;
    await tester.pumpWidget(
      _app(
        ChatMessage(role: 'user', content: '测试撤回'),
        onLongPress: () => longPressed = true,
      ),
    );

    await tester.longPress(find.text('测试撤回'));

    expect(longPressed, isTrue);
  });

  testWidgets('recalled user message keeps its bubble and replaces content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ChatMessage(
          role: 'user',
          content: '不应显示的原文',
          messageStatus: MessageStatus.recalled,
        ),
      ),
    );

    expect(find.text('你撤回了一条消息'), findsOneWidget);
    expect(find.text('不应显示的原文'), findsNothing);
  });

  testWidgets('recalled AI message uses the peer recall label', (tester) async {
    await tester.pumpWidget(
      _app(
        ChatMessage(
          role: 'assistant',
          content: '不应显示的回复',
          messageStatus: MessageStatus.recalled,
        ),
      ),
    );

    expect(find.text('对方撤回了一条消息'), findsOneWidget);
    expect(find.text('不应显示的回复'), findsNothing);
  });
}

Widget _app(ChatMessage message, {VoidCallback? onLongPress}) {
  return MaterialApp(
    home: Scaffold(
      body: MessageRenderer(
        message: message,
        onLongPress: onLongPress ?? () {},
        assistantAvatar: const SizedBox.square(dimension: 40),
        userAvatar: const SizedBox.square(dimension: 40),
      ),
    ),
  );
}
