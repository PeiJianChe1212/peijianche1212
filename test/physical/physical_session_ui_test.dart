import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/pages/peilink/physical_host_page.dart';

void main() {
  testWidgets('session summary shows turn count and clears only when idle', (
    tester,
  ) async {
    var clearCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalSessionSummary(
            turnCount: 3,
            isBusy: false,
            onClear: () => clearCalls++,
          ),
        ),
      ),
    );

    expect(find.text('本次实体会话：3 轮'), findsOneWidget);
    await tester.tap(find.text('清空实体会话'));
    expect(clearCalls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalSessionSummary(
            turnCount: 3,
            isBusy: true,
            onClear: () => clearCalls++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('清空实体会话'));
    expect(clearCalls, 1);
  });
}
