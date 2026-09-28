import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/pages/peilink/theme_decoration_page.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/theme/chat_visual_theme.dart';
import 'package:peijianche_app/widgets/chat/renderers/text_message_renderer.dart';

import 'helpers/widget_test_cleanup.dart';

Iterable<TextSpan> leaves(InlineSpan span) sync* {
  if (span is TextSpan) {
    if (span.text != null) yield span;
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* leaves(child);
    }
  }
}

void main() {
  late Directory dir;
  late PeiLinkAppearanceController controller;
  Future<File> file() async => File('${dir.path}/appearance.json');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('font_test_');
    controller = PeiLinkAppearanceController.testing(fileProvider: file);
  });
  tearDown(() async {
    controller.dispose();
    // Bounded retry for Windows file lock (errno 32).
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
        return;
      } on FileSystemException {
        if (attempt == 9) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
  });

  test(
    'catalog maps stable ids to bundled open-source families',
    () {
      expect(ChatVisualThemeCatalog.fontThemes.map((f) => f.fontFamily), [
        'sans-serif',
        'PeiLinkHandwriting',
        'PeiLinkKai',
        'PeiLinkGentleRounded',
        'PeiLinkTechMono',
      ]);
      // Legacy ids must never change (no index based migration).
      expect(ChatVisualThemeCatalog.fontThemes.map((f) => f.id), [
        'system',
        'hard_pen',
        'kai',
        'gentle_rounded',
        'tech',
      ]);
      for (final font in ChatVisualThemeCatalog.fontThemes) {
        expect(font.isAvailable, isTrue, reason: '${font.id} must be选择可用');
        expect(font.effectiveFont, font);
        if (font.id != 'system') {
          expect(
            font.fontFamilyFallback,
            isNotEmpty,
            reason: '${font.id} needs a CJK fallback chain',
          );
        }
      }
      expect(ChatVisualThemeCatalog.hardPen.name, '手写体');
    },
  );

  test(
    'all saved IDs reload without rewriting other appearance settings',
    () async {
      await controller.setBubbleTheme(ChatVisualThemeCatalog.glass);
      final background = controller.background.id;
      for (final font in ChatVisualThemeCatalog.fontThemes) {
        await controller.setFontTheme(font);
        final restored = PeiLinkAppearanceController.testing(
          fileProvider: file,
        );
        await restored.load();
        expect(restored.fontTheme.id, font.id);
        expect(restored.fontTheme.fontFamily, font.fontFamily);
        expect(restored.bubbleTheme.id, 'glass');
        expect(restored.background.id, background);
        restored.dispose();
      }
    },
  );

  testWidgets(
    'font cards preview every bundled family and stay selectable',
    (tester) async {
      await tester.runAsync(
        () => controller.setFontTheme(ChatVisualThemeCatalog.kai),
      );
      await tester.pumpWidget(
        PeiLinkAppearanceScope(
          controller: controller,
          child: const MaterialApp(home: ThemeDecorationPage()),
        ),
      );
      await tester.tap(find.text('字体').first);
      await tester.pumpAndSettle();
      for (final font in ChatVisualThemeCatalog.fontThemes) {
        final choice = find.byKey(ValueKey('font-choice-${font.id}')).last;
        await tester.ensureVisible(choice);
        final tile = tester.widget<ListTile>(choice);
        expect(tile.enabled, isTrue);
        expect(tile.onTap, isNotNull);
        final preview = tester.widget<Text>(
          find.byKey(ValueKey('font-preview-${font.id}')).last,
        );
        expect(preview.data, '今天天气真好呀～');
        expect(preview.style!.fontFamily, font.fontFamily);
      }
      expect(find.textContaining('字体资源缺失'), findsNothing);
      final system = find.byKey(const ValueKey('font-choice-system')).last;
      await tester.ensureVisible(system);
      await tester.runAsync(() async {
        await tester.tap(system);
        // The UI callback starts an async save; wait for it before reopening.
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if ((await (await file()).readAsString()).contains(
            '"fontThemeId":"system"',
          )) {
            break;
          }
        }
        final restored = PeiLinkAppearanceController.testing(
          fileProvider: file,
        );
        await restored.load();
        expect(restored.fontTheme.id, 'system');
        restored.dispose();
      });

      // Explicit widget tree unmount before teardown deletes temp dir.
      await disposeTestWidgetTree(tester);
    },
  );

  for (final role in ['user', 'assistant', 'system', 'error']) {
    testWidgets(
      '$role content updates immediately, excluding code and system text',
      (tester) async {
        const text = '你好（微笑）`a(b)`\n```dart\nf(x)\n```\n再见';
        await tester.pumpWidget(
          PeiLinkAppearanceScope(
            controller: controller,
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const Text('页面标题'),
                    TextMessageRenderer(
                      message: ChatMessage(id: 'm', role: role, content: text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        // Synthetic family proves style propagation only; it is not a shipped font.
        await tester.runAsync(
          () => controller.setFontTheme(
            const ChatFontTheme(
              id: 'test',
              name: 'test',
              fontFamily: 'TestBodyFont',
            ),
          ),
        );
        await tester.pump();
        final rendered = tester.widget<Text>(
          find.descendant(
            of: find.byType(TextMessageRenderer),
            matching: find.byType(Text),
          ),
        );
        expect(rendered.textSpan!.toPlainText(), text);
        for (final span in leaves(rendered.textSpan!)) {
          expect(
            span.style!.fontFamily,
            span.text!.contains('`')
                ? 'monospace'
                : (role == 'user' || role == 'assistant'
                      ? 'TestBodyFont'
                      : null),
          );
        }
        expect(
          tester.widget<Text>(find.text('页面标题')).style?.fontFamily,
          isNull,
        );
        await tester.runAsync(
          () => controller.setFontTheme(ChatVisualThemeCatalog.systemFont),
        );
        await tester.pump();
        final reset = tester.widget<Text>(
          find.descendant(
            of: find.byType(TextMessageRenderer),
            matching: find.byType(Text),
          ),
        );
        expect(
          leaves(reset.textSpan!).first.style!.fontFamily,
          role == 'user' || role == 'assistant' ? 'sans-serif' : null,
        );

        await disposeTestWidgetTree(tester);
      },
    );
  }
}
