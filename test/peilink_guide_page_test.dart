import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/guide_knowledge.dart';
import 'package:peijianche_app/pages/peilink/peilink_guide_page.dart';
import 'package:peijianche_app/pages/settings_page.dart';
import 'package:peijianche_app/services/feedback_form_launcher.dart';

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
    expect(GuideKnowledge.answer('怎么修改角色人设'), contains('编辑角色设定'));
    expect(GuideKnowledge.answer('图片怎么保存'), contains('系统相册'));
    expect(GuideKnowledge.answer('怎么回溯消息'), contains('删除它之后'));
    expect(GuideKnowledge.answer('怎么创建群聊'), contains('至少两个角色'));
    expect(GuideKnowledge.answer('聊天气泡在哪'), contains('主题装扮'));
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

  testWidgets('Guide and Settings feedback entries use the same formal form', (
    tester,
  ) async {
    final openedUrls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FeedbackFormLauncher.channel, (call) async {
          expect(call.method, 'open');
          openedUrls.add(call.arguments as String);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FeedbackFormLauncher.channel, null),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PeiLinkGuidePage())),
    );
    expect(find.text('帮助与反馈'), findsNothing);
    expect(find.text('反馈与建议'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-feedback-entry')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.tap(find.text('反馈与建议'));
    await tester.pump();

    expect(openedUrls, [
      FeedbackFormLauncher.formUrl,
      FeedbackFormLauncher.formUrl,
    ]);
  });
}
