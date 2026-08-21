import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/main.dart' show PeiJianCheApp;
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/pages/home_page.dart';
import 'package:peijianche_app/pages/peilink/calendar_page.dart';
import 'package:peijianche_app/pages/peilink/peilink_echo_page.dart';
import 'package:peijianche_app/pages/peilink/peilink_home_page.dart';
import 'package:peijianche_app/services/user_profile_storage_service.dart';

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('peilink_widget_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => documents.path);
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await documents.delete(recursive: true);
  });

  testWidgets('User 空白环境停留启动页后进入 PeiLink 首页', (WidgetTester tester) async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    await tester.pumpWidget(
      const PeiJianCheApp(initialHasVisibleCharacter: false),
    );
    await tester.pump();
    expect(find.text('欢迎来到 PeiLink'), findsNothing);
    expect(find.text('创建第一位 AI'), findsNothing);
    expect(find.text('裴简澈'), findsNothing);

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.textContaining('这里还没有角色'), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ai-world-character-card')),
      findsOneWidget,
    );
    expect(find.text('暂无角色'), findsOneWidget);
    expect(find.textContaining('等待连接'), findsWidgets);
    expect(find.byKey(const ValueKey('ai-world-create-entry')), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-800, 0), 1200);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('PEILINK LIFE'), findsOneWidget);
    expect(find.text('还没有纪念日'), findsOneWidget);
    expect(find.text('记录一个值得记住的日子'), findsOneWidget);
    expect(find.text('星期'), findsNothing);
    expect(find.byKey(const ValueKey('life-calendar-card')), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-800, 0), 1200);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('ai-world-apps-page')), findsOneWidget);
  });

  testWidgets('日历页只展示本地月历与选中日期', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PeiLinkCalendarPage(initialDate: DateTime(2026, 8, 22)),
      ),
    );
    await tester.pump();

    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('2026年8月22日'), findsOneWidget);
    expect(find.text('星期六'), findsOneWidget);
  });

  testWidgets('User 无角色时 Echo 正常打开', (tester) async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    await tester.pumpWidget(
      const MaterialApp(home: PeiLinkEchoPage(embedded: true)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();

    expect(find.byType(PeiLinkEchoPage), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.textContaining('Echo 加载失败'), findsNothing);
  });

  testWidgets('User 无角色时首页聊天进入消息列表', (tester) async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    await tester.pumpWidget(
      const PeiJianCheApp(initialHasVisibleCharacter: false),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ai-world-chat-entry')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PeiLinkHomePage, skipOffstage: false), findsOneWidget);
  });

  test('User 首次资料使用空状态默认值', () async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    final profile = await UserProfileStorageService().loadProfile();

    expect(profile.nickname, '未设置');
    expect(profile.peiLinkId, '未设置');
    expect(profile.signature, isEmpty);
    expect(profile.identity, '未填写');
    expect(profile.avatarPath, isEmpty);
  });

  test('User 旧版开发测试默认资料会被清理', () async {
    PeiLinkRuntime.configure(PeiLinkBuild.user);
    final storage = UserProfileStorageService();
    await storage.saveProfile(
      const UserProfile(
        nickname: '念念',
        peiLinkId: '一只小狐念',
        peiCallName: '念念',
        identity: '裴简澈的恋人',
      ),
    );

    final profile = await storage.loadProfile();
    expect(profile.nickname, '未设置');
    expect(profile.peiLinkId, '未设置');
    expect(profile.identity, '未填写');
  });
}
