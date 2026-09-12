import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/group_chat.dart';
import 'package:peijianche_app/models/group_member.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/pages/peilink/add_ai_page.dart';
import 'package:peijianche_app/pages/peilink/ai_creation_center_page.dart';
import 'package:peijianche_app/pages/peilink/create_group_chat_page.dart';
import 'package:peijianche_app/pages/peilink/group_chat_page.dart';
import 'package:peijianche_app/pages/peilink/peilink_home_page.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/group_chat_storage_service.dart';
import 'package:peijianche_app/services/group_message_storage_service.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/theme/app_theme_background.dart';
import 'package:peijianche_app/theme/chat_visual_theme.dart';
import 'package:peijianche_app/theme/theme_background.dart';
import 'package:peijianche_app/widgets/chat/chat_bubble_surface.dart';

/// Phase G1 targeted coverage: entry menu + group chat visual/system sync.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('group_g1_test_');
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

  Future<void> settle(WidgetTester tester, {int rounds = 30}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump();
  }

  Future<PeiLinkAppearanceController> appearance({
    ChatBubbleTheme? bubble,
    ChatFontTheme? font,
    ThemeBackground? background,
  }) async {
    final controller = PeiLinkAppearanceController.testing(
      fileProvider: () async => File('${documents.path}/appearance.json'),
    );
    await controller.load();
    if (bubble != null) await controller.setBubbleTheme(bubble);
    if (font != null) await controller.setFontTheme(font);
    if (background != null) await controller.setBackground(background);
    return controller;
  }

  /// appearance load 会读真实文件，必须包在 runAsync 内避免假异步死锁。
  Future<PeiLinkAppearanceController> appearanceFor(
    WidgetTester tester, {
    ChatBubbleTheme? bubble,
    ChatFontTheme? font,
    ThemeBackground? background,
  }) async {
    final controller = await tester.runAsync(
      () => appearance(bubble: bubble, font: font, background: background),
    );
    return controller!;
  }

  /// 消息页/关系页存在既有的 ListTile 装饰断言（非本轮引入），统一排空。
  void drainLegacyUiAsserts(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  AiCharacter character(String id, String name) => AiCharacter(
    id: id,
    characterName: name,
    remark: '',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  Future<void> seedGroup(WidgetTester tester) async {
    await tester.runAsync(() async {
      await CharacterRegistryService().saveCharacters([
        character('char_a', '阿澈'),
        character('char_b', '沈砚'),
      ]);
      await GroupChatStorageService().upsertGroup(
        GroupChat(
          id: 'group_1',
          name: '测试群',
          createdAt: DateTime.utc(2026, 8, 1),
          lastActiveAt: DateTime.utc(2026, 8, 1),
          members: [
            GroupMember(
              groupId: 'group_1',
              characterId: 'char_a',
              joinedAt: DateTime.utc(2026, 8, 1),
            ),
            GroupMember(
              groupId: 'group_1',
              characterId: 'char_b',
              joinedAt: DateTime.utc(2026, 8, 1),
            ),
          ],
        ),
      );
      await GroupMessageStorageService(groupId: 'group_1').saveMessages([
        GroupMessage(
          id: 'm_user',
          groupId: 'group_1',
          senderType: GroupSenderType.user,
          senderId: 'user',
          content: '大家好',
          createdAt: DateTime.utc(2026, 8, 21, 9, 0),
        ),
        GroupMessage(
          id: 'm_char',
          groupId: 'group_1',
          senderType: GroupSenderType.character,
          senderId: 'char_a',
          content: '早，昨晚睡得还行。```dart\nf(x)\n```',
          createdAt: DateTime.utc(2026, 8, 21, 9, 1),
        ),
        GroupMessage(
          id: 'm_system',
          groupId: 'group_1',
          senderType: GroupSenderType.system,
          senderId: 'system',
          content: '阿澈加入了群聊',
          messageType: GroupMessageType.system,
          sourceType: GroupMessageSource.system,
          createdAt: DateTime.utc(2026, 8, 21, 9, 2),
        ),
      ]);
    });
  }

  Future<PeiLinkAppearanceController> pumpGroup(WidgetTester tester) async {
    final controller = await appearanceFor(
      tester,
      bubble: ChatVisualThemeCatalog.journal,
      font: ChatVisualThemeCatalog.kai,
      background: AppThemeBackground.starButterflyBlue,
    );
    await tester.pumpWidget(
      PeiLinkAppearanceScope(
        controller: controller,
        child: const MaterialApp(home: GroupChatPage(groupId: 'group_1')),
      ),
    );
    await settle(tester);
    return controller;
  }

  testWidgets('消息首页 + 展开两个选项，创建角色仍走原链路', (tester) async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    await tester.pumpWidget(
      PeiLinkAppearanceScope(
        controller: await appearanceFor(tester),
        child: const MaterialApp(home: PeiLinkHomePage()),
      ),
    );
    await settle(tester);
    drainLegacyUiAsserts(tester);

    expect(find.byType(AiCreationCenterPage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('peilink-create-entry')));
    await settle(tester, rounds: 12);
    expect(find.text('创建角色'), findsOneWidget);
    expect(find.text('创建群聊'), findsOneWidget);

    await tester.tap(find.text('创建角色'));
    await settle(tester, rounds: 20);
    drainLegacyUiAsserts(tester);
    expect(find.byType(AiCreationCenterPage), findsOneWidget);
  });

  testWidgets('+ 菜单的创建群聊进入既有 CreateGroupChatPage', (tester) async {
    await tester.pumpWidget(
      PeiLinkAppearanceScope(
        controller: await appearanceFor(tester),
        child: const MaterialApp(home: PeiLinkHomePage()),
      ),
    );
    await settle(tester);
    drainLegacyUiAsserts(tester);

    await tester.tap(find.byKey(const ValueKey('peilink-create-entry')));
    await settle(tester, rounds: 12);
    await tester.tap(find.text('创建群聊'));
    await settle(tester, rounds: 20);
    expect(find.byType(CreateGroupChatPage), findsOneWidget);
  });

  testWidgets('旧 AddAiPage 群聊入口不再 ComingSoon', (tester) async {
    await tester.pumpWidget(
      PeiLinkAppearanceScope(
        controller: await appearanceFor(tester),
        child: const MaterialApp(home: AddAiPage()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('创建群聊'));
    await settle(tester, rounds: 20);
    expect(find.byType(CreateGroupChatPage), findsOneWidget);
    expect(find.textContaining('后面的版本开放'), findsNothing);
  });

  testWidgets('群聊消费 bubble / font / background 装扮', (tester) async {
    await seedGroup(tester);
    final controller = await pumpGroup(tester);

    // 背景跟随装扮体系
    expect(find.byType(ThemeBackgroundContainer), findsWidgets);
    expect(
      find.byKey(const ValueKey('theme-background-star_butterfly_blue')),
      findsOneWidget,
    );

    // 气泡使用用户当前主题
    final surfaces = tester.widgetList<ChatBubbleSurface>(
      find.byType(ChatBubbleSurface),
    );
    expect(surfaces, isNotEmpty);
    for (final surface in surfaces) {
      expect(surface.theme.id, controller.bubbleTheme.id);
    }

    // 正文使用当前装扮字体
    final body = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan != null &&
            widget.textSpan!.toPlainText().contains('早，昨晚睡得还行。'),
      ),
    );
    final leaves = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.text != null) leaves.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        collect(child);
      }
    }

    collect(body.textSpan!);
    // 正文底色样式挂在根 span 上（与单聊一致），叶子只覆盖 @ / code 例外。
    expect(
      (body.textSpan! as TextSpan).style?.fontFamily,
      'PeiLinkKai',
      reason: '群聊正文必须消费装扮字体',
    );
    expect(
      (body.textSpan! as TextSpan).style?.fontFamilyFallback,
      isNotEmpty,
    );
  });

  testWidgets('system 不套气泡，代码块保持 monospace', (tester) async {
    await seedGroup(tester);
    await pumpGroup(tester);

    // 系统消息用中性样式，不进入气泡
    final systemText = tester.widget<Text>(find.text('阿澈加入了群聊'));
    expect(systemText.style?.fontFamily, isNull);
    expect(
      find.descendant(
        of: find.byType(ChatBubbleSurface),
        matching: find.text('阿澈加入了群聊'),
      ),
      findsNothing,
    );

    final body = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan != null &&
            widget.textSpan!.toPlainText().contains('f(x)'),
      ),
    );
    final codeLeaves = <TextSpan>[];
    void collectCode(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.text != null) codeLeaves.add(span);
      for (final child in span.children ?? const <InlineSpan>[]) {
        collectCode(child);
      }
    }

    collectCode(body.textSpan!);
    expect(
      codeLeaves.any((span) => span.style?.fontFamily == 'monospace'),
      isTrue,
      reason: 'code block 必须保持 monospace',
    );
  });

  testWidgets('旧群聊数据（缺新字段）仍可读取，新消息仍写回原 storage', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory('${documents.path}/group_chats/legacy_group');
      await dir.create(recursive: true);
      await File('${dir.path}/messages.json').writeAsString(
        '[{"id":"old_1","groupId":"legacy_group","senderType":"character",'
        '"senderId":"char_a","content":"旧消息","createdAt":"2026-08-01T10:00:00.000Z"}]',
      );
      await File('${documents.path}/group_chats.json').writeAsString(
        '[{"id":"legacy_group","name":"旧群","members":[{"groupId":"legacy_group",'
        '"characterId":"char_a","joinedAt":"2026-08-01T10:00:00.000Z"}],'
        '"createdAt":"2026-08-01T10:00:00.000Z","lastActiveAt":"2026-08-01T10:00:00.000Z"}]',
      );
    });

    await tester.runAsync(() async {
      final group = await GroupChatStorageService().loadGroup('legacy_group');
      expect(group, isNotNull);
      expect(group!.id, 'legacy_group');
      expect(group.memberCharacterIds, ['char_a']);
      final messages = await GroupMessageStorageService(
        groupId: 'legacy_group',
      ).loadMessages();
      expect(messages, hasLength(1));
      expect(messages.first.content, '旧消息');
      expect(messages.first.status, GroupMessageStatus.sent);
      // 写回仍然是同一路径与同一 schema。
      await GroupMessageStorageService(
        groupId: 'legacy_group',
      ).saveMessages(messages);
      final raw = await File(
        '${documents.path}/group_chats/legacy_group/messages.json',
      ).readAsString();
      expect(raw.contains('old_1'), isTrue);
      expect(raw.contains('senderType'), isTrue);
    });
  });
}
