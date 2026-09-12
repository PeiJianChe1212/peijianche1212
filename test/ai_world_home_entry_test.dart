import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/pages/chat_page.dart';
import 'package:peijianche_app/pages/home_page.dart';
import 'package:peijianche_app/pages/peilink/peilink_echo_page.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/home_character_storage_service.dart';

/// Targeted coverage: AI World chat entry must follow the displayed character,
/// and the three quick actions must stay visually/functionally equivalent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('ai_world_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
  });

  tearDown(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      if (await documents.exists()) await documents.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  AiCharacter character(String id, String name) => AiCharacter(
    id: id,
    characterName: name,
    remark: '',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  /// 默认角色（裴简澈）保持为 active，AI World 展示的是另一个角色。
  Future<void> seed(
    WidgetTester tester, {
    required String displayId,
    required String activeId,
  }) async {
    await tester.runAsync(() async {
      final registry = CharacterRegistryService();
      await registry.saveCharacters([
        character('pei_jian_che', '裴简澈'),
        character('e', 'e'),
        character('q', 'q'),
      ]);
      // active 与 AI World 展示角色故意不同，复现真机 bug 场景。
      await registry.setActiveCharacter(activeId);
      await HomeCharacterStorageService().saveCharacterId(displayId);
    });
  }

  Future<String?> activeId(WidgetTester tester) => tester.runAsync(
    () => CharacterRegistryService().loadActiveCharacterId(),
  );

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await settle(tester);
    while (tester.takeException() != null) {}
  }

  testWidgets('AI World 展示角色 e 时，聊天入口进入 e（不是默认角色）', (tester) async {
    await seed(tester, displayId: 'e', activeId: 'q');
    await pumpHome(tester);

    expect(
      find.byKey(const ValueKey('ai-world-character-card')),
      findsOneWidget,
    );
    expect(await activeId(tester), 'q');

    await tester.tap(find.byKey(const ValueKey('ai-world-chat-entry')));
    await settle(tester, rounds: 25);
    while (tester.takeException() != null) {}

    expect(await activeId(tester), 'e', reason: '聊天目标必须是 AI World 当前展示角色');
    expect(find.byType(ChatPage), findsOneWidget);
    // 关闭聊天页，避免其定时器影响测试收尾。
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester, rounds: 8);
    while (tester.takeException() != null) {}
  });

  testWidgets('切换展示角色为 q 后，聊天入口立即跟随 q', (tester) async {
    await seed(tester, displayId: 'q', activeId: 'e');
    await pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('ai-world-chat-entry')));
    await settle(tester, rounds: 25);
    while (tester.takeException() != null) {}

    expect(await activeId(tester), 'q');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester, rounds: 8);
    while (tester.takeException() != null) {}
  });

  testWidgets('三个快捷入口都存在且可点击，Echo 仍进入 Echo 页面', (tester) async {
    await seed(tester, displayId: 'e', activeId: 'q');
    await pumpHome(tester);

    expect(find.byKey(const ValueKey('ai-world-chat-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-world-echo-entry')), findsOneWidget);
    expect(find.text('电话'), findsOneWidget);

    // Echo 入口保持原目标页面（角色 Echo 空间），只是视觉权重降低。
    await tester.tap(find.byKey(const ValueKey('ai-world-echo-entry')));
    await settle(tester, rounds: 30);
    while (tester.takeException() != null) {}
    expect(find.byType(PeiLinkEchoPage), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester, rounds: 8);
    while (tester.takeException() != null) {}
  });
}
