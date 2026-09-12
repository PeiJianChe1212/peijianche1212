import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/pages/peilink/theme_decoration_page.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/theme/chat_visual_theme.dart';
import 'package:peijianche_app/widgets/chat/chat_bubble_surface.dart';
import 'package:peijianche_app/widgets/chat/message_bubble.dart';
import 'package:peijianche_app/widgets/chat/message_renderer.dart';

void main() {
  late Directory dir;
  late PeiLinkAppearanceController controller;
  Future<File> file() async => File('${dir.path}/appearance.json');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bubble_test_');
    controller = PeiLinkAppearanceController.testing(fileProvider: file);
  });
  tearDown(() async {
    controller.dispose();
    await dir.delete(recursive: true);
  });

  test('stable IDs, order and original colors remain compatible', () {
    final old = ChatVisualThemeCatalog.bubbleThemes.take(4).toList();
    expect(old.map((t) => t.id), [
      'minimal',
      'qq_rounded',
      'soft_cloud',
      'glass',
    ]);
    expect(old.map((t) => t.borderRadius), [14, 32, 26, 10]);
    expect(old.map((t) => t.userBubbleColor.toARGB32()), [
      0xFFDCE3FF,
      0xFFFFD9DF,
      0xFFE0EDFF,
      0xB8CFE8F4,
    ]);
    expect(
      ChatVisualThemeCatalog.bubbleThemes.map((t) => t.id).toSet().length,
      9,
    );
  });

  test('original four have distinct structure independent of fill color', () {
    final original = ChatVisualThemeCatalog.bubbleThemes.take(4).toList();
    final structures = original
        .map(
          (t) => (
            t.decoration(isUser: false).borderRadius,
            t.border,
            t.tailStyle,
            t.highlight,
          ),
        )
        .toSet();
    expect(structures.length, 4);
    expect(original[0].tailStyle, ChatBubbleTailStyle.brandWing);
    expect(original[1].tailStyle, ChatBubbleTailStyle.softRound);
    expect(original[2].cornerShape, isNotNull);
    expect(original[2].tailStyle, ChatBubbleTailStyle.none);
    expect(original[3].decoration(isUser: false).gradient, isNotNull);
    expect(original[3].border, isNotNull);
  });

  test('glass highlight retains readable text on light and dark backdrops', () {
    final theme = ChatVisualThemeCatalog.glass;
    for (final user in [true, false]) {
      for (final background in [Colors.black, Colors.white]) {
        final base = Color.alphaBlend(
          theme.decoration(isUser: user).color!,
          background,
        );
        for (final sheen in (theme.highlight! as LinearGradient).colors) {
          final fill = Color.alphaBlend(sheen, base);
          final foreground = MessageBubble.textColorForRole(
            user ? 'user' : 'assistant',
          );
          expect(
            (fill.computeLuminance() + .05) /
                (foreground.computeLuminance() + .05),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    }
  });

  test(
    'all themes save, notify and reload without touching font/background',
    () async {
      await controller.setFontTheme(ChatVisualThemeCatalog.kai);
      final background = controller.background.id;
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (final theme in ChatVisualThemeCatalog.bubbleThemes) {
        final saved = controller.setBubbleTheme(theme);
        expect(controller.bubbleTheme, theme);
        await saved;
        final restored = PeiLinkAppearanceController.testing(
          fileProvider: file,
        );
        await restored.load();
        expect(restored.bubbleTheme.id, theme.id);
        expect(restored.fontTheme.id, 'kai');
        expect(restored.background.id, background);
        restored.dispose();
      }
      expect(notifications, 9);
    },
  );

  test(
    'all foregrounds retain 4.5 contrast over light and dark backgrounds',
    () {
      for (final theme in ChatVisualThemeCatalog.bubbleThemes) {
        for (final user in [true, false]) {
          for (final background in [
            Colors.black,
            Colors.white,
            const Color(0xFF24334C),
          ]) {
            final fill = Color.alphaBlend(
              theme.decoration(isUser: user).color!,
              background,
            );
            final foreground = MessageBubble.textColorForRole(
              user ? 'user' : 'assistant',
            );
            expect(
              (fill.computeLuminance() + .05) /
                  (foreground.computeLuminance() + .05),
              greaterThanOrEqualTo(4.5),
              reason: '${theme.id}: $user',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'preview and both live roles share decoration and update immediately',
    (tester) async {
      for (final theme in ChatVisualThemeCatalog.bubbleThemes) {
        await tester.pumpWidget(
          PeiLinkAppearanceScope(
            controller: controller,
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    BubbleThemePreview(theme: theme),
                    for (final role in ['assistant', 'user'])
                      MessageBubble(
                        message: ChatMessage(
                          id: role,
                          role: role,
                          content: '你好',
                        ),
                        isUser: role == 'user',
                        showTail: true,
                        onLongPress: () {},
                        child: const Text('你好'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() => controller.setBubbleTheme(theme));
        await tester.pump();
        final surfaces = tester
            .widgetList<ChatBubbleSurface>(find.byType(ChatBubbleSurface))
            .toList();
        expect(surfaces.length, 4);
        for (final surface in surfaces) {
          expect(surface.theme, theme);
        }
        final containers = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(ChatBubbleSurface),
                matching: find.byType(Container),
              ),
            )
            .where((c) => c.decoration is BoxDecoration)
            .toList();
        expect(containers.map((c) => c.decoration).toList(), [
          theme.decoration(isUser: false),
          theme.decoration(isUser: true),
          theme.decoration(isUser: false),
          theme.decoration(isUser: true),
        ]);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('all themes wrap long Chinese emoji content at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final theme in ChatVisualThemeCatalog.bubbleThemes) {
      await tester.runAsync(() => controller.setBubbleTheme(theme));
      await tester.pumpWidget(
        PeiLinkAppearanceScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final role in ['user', 'assistant'])
                      MessageRenderer(
                        message: ChatMessage(
                          id: role,
                          role: role,
                          content: '今天过得怎么样？还不错呀～😊（一起散步）' * 12,
                        ),
                        onLongPress: () {},
                        assistantAvatar: const SizedBox(width: 40),
                        userAvatar: const SizedBox(width: 40),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: theme.id);
      for (final element in find.byType(ChatBubbleSurface).evaluate()) {
        expect(
          (element.renderObject as RenderBox).size.width,
          lessThanOrEqualTo(320 * .72),
        );
      }
    }
  });

  testWidgets(
    'system messages bypass shell and red packet shell stays transparent',
    (tester) async {
      await tester.runAsync(
        () => controller.setBubbleTheme(ChatVisualThemeCatalog.journal),
      );
      await tester.pumpWidget(
        PeiLinkAppearanceScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  MessageRenderer(
                    message: ChatMessage(
                      id: 'system',
                      role: 'system',
                      content: '系统提示',
                    ),
                    onLongPress: () {},
                    assistantAvatar: const SizedBox(),
                    userAvatar: const SizedBox(),
                  ),
                  MessageBubble(
                    message: ChatMessage(
                      id: 'packet',
                      role: 'user',
                      content: '',
                      type: MessageType.redPacket,
                    ),
                    isUser: true,
                    showTail: true,
                    onLongPress: () {},
                    child: const Text('红包专用卡片'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(ChatBubbleSurface), findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(ChatBubbleSurface),
          matching: find.byType(Container),
        ),
      );
      expect((container.decoration as BoxDecoration).color, Colors.transparent);
      expect(container.padding, EdgeInsets.zero);
      expect(
        find.descendant(
          of: find.byType(ChatBubbleSurface),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'bubble selection cards contain two real previews and selected marker',
    (tester) async {
      await tester.pumpWidget(
        PeiLinkAppearanceScope(
          controller: controller,
          child: const MaterialApp(home: ThemeDecorationPage()),
        ),
      );
      await tester.tap(find.text('聊天气泡').first);
      await tester.pumpAndSettle();
      final choice = find.byKey(const ValueKey('bubble-choice-paper_note'));
      await tester.scrollUntilVisible(
        choice,
        250,
        scrollable: find.descendant(
          of: find.byKey(const Key('bubble-theme-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(
          find.descendant(of: choice, matching: find.byType(InkWell)).first,
        );
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if ((await (await file()).readAsString()).contains('paper_note')) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      expect(controller.bubbleTheme.id, 'paper_note');
      expect(
        find.descendant(of: choice, matching: find.byType(ChatBubbleSurface)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: choice, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
