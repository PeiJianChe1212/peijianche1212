import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/pages/peilink/theme_decoration_page.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/services/peilink_theme_service.dart';
import 'package:peijianche_app/theme/chat_visual_theme.dart';
import 'package:peijianche_app/theme/effective_bubble_theme.dart';
import 'package:peijianche_app/theme/peilink_theme_config.dart';
import 'package:peijianche_app/theme/peilink_theme_registry.dart';
import 'package:peijianche_app/widgets/theme/peilink_theme_scope.dart';
import 'package:peijianche_app/widgets/theme/peilink_themed_avatar.dart';

import 'helpers/widget_test_cleanup.dart';

/// Bounded retry for Windows temp directory deletion.
///
/// On Windows, a file that was just written may still be locked by the OS
/// file cache when teardown runs (errno 32 / PathAccessException).  This
/// helper retries with exponential backoff up to 5 attempts.  It does NOT
/// catch-and-swallow: if all retries fail, the last FileSystemException is
/// rethrown so the test is marked as a real failure.
Future<void> deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } on FileSystemException {
      if (attempt == 9) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registry resolves butterfly_fox and retains default fallback', () {
    final registry = PeiLinkThemeRegistry();
    final theme = registry.chat('butterfly_fox');
    expect(theme.id, 'butterfly_fox');
    expect(theme.name, '蝶梦白狐');
    expect(registry.chat('invalid').id, 'default');
    expect(registry.chatThemes.map((item) => item.id), [
      'default',
      'butterfly_fox',
    ]);
  });

  test('Theme 01 exposes all frame roles and keeps private Echo isolated', () {
    final theme = PeiLinkThemeRegistry().chat('butterfly_fox');
    expect(theme.avatarFrameTheme.user?.id, 'butterfly_fox_user');
    expect(theme.avatarFrameTheme.character?.id, 'butterfly_fox_character');
    expect(theme.avatarFrameTheme.group?.id, 'butterfly_fox_group');
    expect(
      PeiLinkThemeController().privateEchoTheme('a').id,
      'default_private_echo',
    );
    expect(theme.publicEchoTheme.background.id, 'butterfly_fox_background');
  });

  testWidgets('theme dressing lists and applies both built-in themes live', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('batch3_dressing_'),
    ))!;
    addTearDown(() => deleteDirectoryWithRetry(directory));

    final themes = PeiLinkThemeController(
      storage: NativePlatformStorage(directory.path),
    );
    final appearance = PeiLinkAppearanceController.testing(
      fileProvider: () async => File('${directory.path}/appearance.json'),
    );
    var notifications = 0;
    themes.addListener(() => notifications++);

    await tester.pumpWidget(
      PeiLinkThemeScope(
        controller: themes,
        child: PeiLinkAppearanceScope(
          controller: appearance,
          child: const MaterialApp(home: ThemeDecorationPage()),
        ),
      ),
    );

    // --- UI verification: both themes listed ---
    expect(find.byKey(const ValueKey('theme-card-default')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('theme-card-butterfly_fox')),
      findsOneWidget,
    );
    expect(find.text('蝶梦白狐'), findsWidgets);

    // --- UI verification: tap Apply, theme switches immediately ---
    final applyButton = find.descendant(
      of: find.byKey(const ValueKey('theme-card-butterfly_fox')),
      matching: find.text('应用'),
    );
    await tester.ensureVisible(applyButton);
    await tester.pumpAndSettle();
    await tester.tap(applyButton);
    await tester.pump();

    // Controller notified and selected id updated synchronously.
    expect(themes.selectedChatThemeId, 'butterfly_fox');
    expect(notifications, greaterThan(0));

    // --- Deterministic persistence: await selectChatTheme fully completes ---
    // No fixed delay.  runAsync ensures the file write Future resolves before
    // we create a fresh controller to read it back.
    await tester.runAsync(() => themes.selectChatTheme('butterfly_fox'));

    // --- Persistence verification with a fresh controller ---
    final restored = PeiLinkThemeController(
      storage: NativePlatformStorage(directory.path),
    );
    await tester.runAsync(restored.load);
    expect(restored.selectedChatThemeId, 'butterfly_fox');
    restored.dispose();

    // Switch back to default (also verifies the controller is still functional).
    await tester.runAsync(() => themes.selectChatTheme('default'));
    expect(themes.chatTheme.id, 'default');

    // --- Explicit widget tree unmount ---
    // Ensures State.dispose() runs before teardown deletes the temp directory,
    // preventing Windows file lock (errno 32).
    await disposeTestWidgetTree(tester);
    themes.dispose();
    appearance.dispose();

    // Give Windows file cache a moment to release handles before teardown.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
  });

  testWidgets('followTheme uses Theme 01 bubble while custom still wins', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('batch3_bubble_'),
    ))!;
    addTearDown(() => deleteDirectoryWithRetry(directory));

    final themes = PeiLinkThemeController(
      storage: NativePlatformStorage(directory.path),
    );
    await tester.runAsync(() => themes.selectChatTheme('butterfly_fox'));
    final appearance = PeiLinkAppearanceController.testing(
      fileProvider: () async => File('${directory.path}/appearance.json'),
    );
    late ChatBubbleTheme resolved;
    Future<void> pump() => tester.pumpWidget(
      PeiLinkThemeScope(
        controller: themes,
        child: PeiLinkAppearanceScope(
          controller: appearance,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                resolved = effectiveBubbleTheme(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await pump();
    expect(resolved.id, ChatVisualThemeCatalog.minimal.id);
    await tester.runAsync(
      () => appearance.setBubbleTheme(ChatVisualThemeCatalog.candy),
    );
    await pump();
    expect(resolved.id, ChatVisualThemeCatalog.candy.id);

    await disposeTestWidgetTree(tester);
    themes.dispose();
    appearance.dispose();
  });

  testWidgets(
    'missing frame asset falls back safely and preview is config-driven',
    (tester) async {
      final theme = PeiLinkThemeRegistry().chat('butterfly_fox');
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              const PeiLinkThemedAvatar(
                size: 48,
                role: PeiLinkAvatarRole.user,
                frame: AvatarFrameSpec(id: 'missing', assetPath: 'missing.png'),
              ),
              PeiLinkThemePreviewCard(theme: theme),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PeiLinkThemePreviewCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
