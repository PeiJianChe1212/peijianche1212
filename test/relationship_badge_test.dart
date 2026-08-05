import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/widgets/peilink/relationship_badge.dart';

void main() {
  testWidgets('existing relationship is shown with its matching symbol', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RelationshipBadge(relationship: '伴侣')),
      ),
    );

    expect(find.text('♡ 伴侣'), findsOneWidget);
  });

  testWidgets('empty relationship does not reserve badge content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RelationshipBadge(relationship: '未设置')),
      ),
    );

    expect(find.byKey(const ValueKey('relationship-badge')), findsNothing);
    expect(find.text('未设置'), findsNothing);
  });

  test('custom relationships remain visible for future expansion', () {
    expect(RelationshipBadge.displayTextFor('守护者'), '守护者');
    expect(RelationshipBadge.displayTextFor('AI伙伴'), '✦ AI伙伴');
  });
}
