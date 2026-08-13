import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/widgets/chat/chat_input_area.dart';

void main() {
  testWidgets('more button expands inline panel and moves input upward', (
    tester,
  ) async {
    var redPacketOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: _InputAreaHarness(onRedPacket: () => redPacketOpened = true),
      ),
    );

    final initialY = tester.getTopLeft(find.byType(TextField)).dy;
    await tester.tap(find.byTooltip('更多功能'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.redeem_outlined), findsOneWidget);
    expect(tester.getTopLeft(find.byType(TextField)).dy, lessThan(initialY));

    await tester.tap(find.byIcon(Icons.redeem_outlined));
    expect(redPacketOpened, isTrue);
    expect(find.byIcon(Icons.redeem_outlined), findsOneWidget);

    await tester.tap(find.byTooltip('收起功能栏'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.redeem_outlined), findsNothing);
  });

  testWidgets('tapping the input closes the inline panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _InputAreaHarness(onRedPacket: () {})),
    );

    await tester.tap(find.byTooltip('更多功能'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.redeem_outlined), findsNothing);
  });
}

class _InputAreaHarness extends StatefulWidget {
  const _InputAreaHarness({required this.onRedPacket});

  final VoidCallback onRedPacket;

  @override
  State<_InputAreaHarness> createState() => _InputAreaHarnessState();
}

class _InputAreaHarnessState extends State<_InputAreaHarness> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  bool expanded = false;

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Expanded(child: SizedBox()),
          ChatInputArea(
            controller: controller,
            focusNode: focusNode,
            isLoading: false,
            isMorePanelOpen: expanded,
            onSend: () {},
            onMore: () {
              focusNode.unfocus();
              setState(() => expanded = !expanded);
            },
            onInputTap: () => setState(() => expanded = false),
            onUserPersona: () {},
            onPickImage: () {},
            onChangeAvatar: () {},
            onRedPacket: widget.onRedPacket,
            onUnavailable: (_) {},
          ),
        ],
      ),
    );
  }
}
