import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/guide_knowledge.dart';
import 'package:peijianche_app/pages/peilink/peilink_guide_page.dart';

void main() {
  test('Guide knowledge matches public feature keywords', () {
    expect(GuideKnowledge.answer('Echo 怎么用？'), contains('生活回声'));
    expect(GuideKnowledge.answer('如何导入 .pei？'), contains('.pei'));
    expect(GuideKnowledge.answer('能看我的聊天记录吗？'), GuideKnowledge.privacyBoundary);
    expect(GuideKnowledge.answer('为什么他忘了'), contains('Memory'));
    expect(GuideKnowledge.answer('清空聊天会删记忆吗'), contains('清空当前角色'));
    expect(GuideKnowledge.answer('倒数日'), contains('纪念日'));
    expect(GuideKnowledge.answer('忙碌状态是真的吗'), contains('本地生活状态'));
    expect(GuideKnowledge.answer('API Key 保存在哪里'), contains('安全存储'));
    expect(GuideKnowledge.entries.length, greaterThanOrEqualTo(50));
  });

  testWidgets('Guide displays Ache, answers and filters help topics', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PeiLinkGuidePage())),
    );

    expect(find.text('关于 PeiLink，有什么想知道的？'), findsOneWidget);
    expect(find.text('使用说明'), findsOneWidget);
    expect(find.text('开始使用'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('ask-ache-field')),
      '羁绊怎么成长？',
    );
    await tester.tap(find.byKey(const ValueKey('ask-ache-send')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ache-reply')), findsOneWidget);
    expect(find.textContaining('真实交流'), findsOneWidget);

    final searchField = find.byKey(const ValueKey('guide-search-field'));
    await tester.enterText(searchField, 'Echo');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Echo 是什么？'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Echo 是什么？'), findsOneWidget);
  });
}
