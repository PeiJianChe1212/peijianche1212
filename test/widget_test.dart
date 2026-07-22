import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/main.dart';

void main() {
  testWidgets('应用可以启动并显示主页', (WidgetTester tester) async {
    await tester.pumpWidget(const PeiJianCheApp());
    expect(find.text('裴简澈'), findsWidgets);
    expect(find.text('进入聊天'), findsOneWidget);
  });
}
