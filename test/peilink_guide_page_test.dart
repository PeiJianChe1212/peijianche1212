import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/guide_knowledge.dart';
import 'package:peijianche_app/pages/peilink/peilink_guide_page.dart';

void main() {
  test('Guide knowledge matches public feature keywords', () {
    expect(GuideKnowledge.answer('Echo 怎么用？'), contains('生活回声'));
    expect(GuideKnowledge.answer('如何导入 .pei？'), contains('.pei'));
    expect(GuideKnowledge.answer('能看我的聊天记录吗？'), GuideKnowledge.privacyBoundary);
  });

  testWidgets('Guide displays Ache, answers and filters help topics', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PeiLinkGuidePage())),
    );

    expect(find.text('有什么问题可以问我吗？🦋'), findsOneWidget);
    expect(find.text('新手指南'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ask-ache-field')),
      '羁绊怎么成长？',
    );
    await tester.tap(find.byKey(const ValueKey('ask-ache-send')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ache-reply')), findsOneWidget);
    expect(find.textContaining('真实交流'), findsOneWidget);

    final searchField = find.byType(TextField).last;
    await tester.enterText(searchField, 'Echo');
    await tester.pump();
    expect(find.text('Echo 是什么'), findsOneWidget);
  });
}
