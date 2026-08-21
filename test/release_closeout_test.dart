import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/pages/environment_bootstrap_page.dart';
import 'package:peijianche_app/pages/home_page.dart';
import 'package:peijianche_app/pages/settings_page.dart';
import 'package:peijianche_app/services/feedback_submission_service.dart';

void main() {
  tearDown(() => PeiLinkRuntime.configure(PeiLinkBuild.unspecified));

  testWidgets(
    'developer access is hidden behind exactly seven silent logo taps',
    (tester) async {
      PeiLinkRuntime.configure(PeiLinkBuild.dev);
      await tester.pumpWidget(
        MaterialApp(
          home: EnvironmentBootstrapPage(
            initialVisibility: Future.value(false),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('开发者与测试环境'), findsNothing);

      final logo = find.byKey(const Key('developer-secret-logo'));
      await tester.tap(logo);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('欢迎来到 PeiLink'), findsOneWidget);
      expect(find.text('开发者验证'), findsNothing);

      for (var index = 1; index < 6; index++) {
        await tester.tap(logo);
        await tester.pump();
        expect(find.text('开发者验证'), findsNothing);
      }
      await tester.tap(logo);
      await tester.pumpAndSettle();

      expect(find.text('开发者验证'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isFalse);
    },
  );

  testWidgets('user build has no developer logo gesture or verification', (
    tester,
  ) async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    await tester.pumpWidget(
      MaterialApp(
        home: EnvironmentBootstrapPage(initialVisibility: Future.value(false)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('developer-secret-logo')), findsNothing);
    expect(find.byKey(const Key('user-welcome-logo')), findsOneWidget);
    expect(find.text('创建第一位 AI'), findsNothing);
    expect(find.text('开发者验证'), findsNothing);

    await tester.pump(const Duration(milliseconds: 3100));
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('settings exposes questionnaire and no legacy help entry', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    expect(find.text('帮助与反馈'), findsNothing);
    expect(find.text('反馈与建议'), findsOneWidget);
    expect(find.text('前往腾讯问卷提交反馈'), findsOneWidget);
    expect(find.text('开发者与测试环境'), findsNothing);
  });

  test(
    'feedback metadata contains only explicit form and basic system fields',
    () {
      final report = FeedbackSubmissionService().buildReport(
        category: 'Bug反馈',
        title: '标题',
        content: '内容',
        contact: '',
        hasScreenshot: true,
        submittedAt: DateTime(2026, 8, 10, 1, 2, 3),
      );
      expect(report, contains('【PeiLink版本】'));
      expect(report, contains('【系统版本】'));
      expect(report, contains('【设备信息】'));
      expect(report, contains('【提交时间】2026-08-10T01:02:03.000'));
      expect(report, isNot(contains('聊天记录')));
      expect(report, isNot(contains('角色资料')));
    },
  );
}
