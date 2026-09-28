import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/platform/storage/native_platform_storage.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/services/peilink_theme_service.dart';
import 'package:peijianche_app/theme/app_theme_background.dart';
import 'package:peijianche_app/theme/chat_visual_theme.dart';
import 'package:peijianche_app/theme/effective_bubble_theme.dart';
import 'package:peijianche_app/theme/peilink_theme_config.dart';
import 'package:peijianche_app/theme/peilink_theme_registry.dart';
import 'package:peijianche_app/widgets/theme/peilink_theme_chrome.dart';
import 'package:peijianche_app/widgets/theme/peilink_theme_scope.dart';
import 'package:peijianche_app/widgets/theme/peilink_themed_avatar.dart';

PeiLinkThemeConfig chatTheme(String id, String bubbleId) => PeiLinkThemeConfig(
  id: id,
  name: id,
  subtitle: 'test',
  chatBackground: AppThemeBackground.current,
  groupBackground: AppThemeBackground.current,
  topBarTheme: const PeiLinkTopBarTheme(),
  groupTopBarTheme: const PeiLinkTopBarTheme(),
  bottomBarTheme: const PeiLinkBottomBarTheme(),
  iconTheme: const PeiLinkIconTheme(),
  defaultBubbleThemeId: bubbleId,
  publicEchoTheme: PublicEchoThemeConfig(
    background: AppThemeBackground.current,
    topBarTheme: const PeiLinkTopBarTheme(),
  ),
);

CharacterEchoThemeConfig echoTheme(String id) => CharacterEchoThemeConfig(
  id: id,
  background: AppThemeBackground.current,
  topBarTheme: const PeiLinkTopBarTheme(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default and invalid chat theme IDs safely resolve default', () {
    final registry = PeiLinkThemeRegistry();
    expect(registry.chat(null).id, 'default');
    expect(registry.chat('missing').id, 'default');
    expect(registry.privateEcho(null).id, 'default_private_echo');
  });

  test('missing saved selection remains default', () async {
    final directory = await Directory.systemTemp.createTemp('theme_missing_');
    addTearDown(() => directory.delete(recursive: true));
    final controller = PeiLinkThemeController(
      storage: NativePlatformStorage(directory.path),
    );
    await controller.load();
    expect(controller.selectedChatThemeId, 'default');
  });

  test('preset components can be mixed, cleared and restored', () async {
    final directory = await Directory.systemTemp.createTemp('theme_v2_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = NativePlatformStorage(directory.path);
    final controller = PeiLinkThemeController(storage: storage);
    await controller.applyFullTheme('butterfly_fox');
    await controller.setAvatarFrameOverride('default');
    await controller.setBackgroundOverride('default');
    await controller.setBottomNavigationOverride('default');
    await controller.setBubbleOverride('milk_candy');
    expect(
      controller.chatTheme.chatBackground.id,
      PeiLinkThemeDefaults.chat.chatBackground.id,
    );
    expect(controller.chatTheme.avatarFrameTheme.user, isNull);
    expect(
      controller.chatTheme.navigationTheme,
      same(PeiLinkThemeDefaults.chat.navigationTheme),
    );
    expect(controller.chatTheme.defaultBubbleThemeId, 'milk_candy');

    final restored = PeiLinkThemeController(storage: storage);
    await restored.load();
    expect(restored.selectedThemePresetId, 'butterfly_fox');
    expect(restored.avatarFrameOverrideId, 'default');
    expect(restored.bubbleOverrideId, 'milk_candy');
    await restored.applyFullTheme('butterfly_fox');
    expect(restored.backgroundOverrideId, isNull);
    expect(restored.avatarFrameOverrideId, isNull);
    expect(restored.bubbleOverrideId, isNull);
    expect(restored.bottomNavigationOverrideId, isNull);
  });

  test(
    'legacy selectedChatThemeId migrates to preset with null overrides',
    () async {
      final directory = await Directory.systemTemp.createTemp('theme_legacy_');
      addTearDown(() => directory.delete(recursive: true));
      final storage = NativePlatformStorage(directory.path);
      await storage.writeText(
        'theme_selections.json',
        jsonEncode({'selectedChatThemeId': 'butterfly_fox'}),
      );
      final controller = PeiLinkThemeController(storage: storage);
      await controller.load();
      expect(controller.selectedThemePresetId, 'butterfly_fox');
      expect(controller.backgroundOverrideId, isNull);
      expect(controller.avatarFrameOverrideId, isNull);
      expect(controller.bubbleOverrideId, isNull);
      expect(controller.bottomNavigationOverrideId, isNull);
    },
  );

  test('default, user and character avatars share rounded-square shape', () {
    expect(
      PeiLinkThemeDefaults.chat.avatarFrameTheme.avatarShape,
      PeiLinkAvatarShape.roundedSquare,
    );
    final frames = PeiLinkThemeDefaults.butterflyFox.avatarFrameTheme;
    expect(frames.avatarShape, PeiLinkAvatarShape.roundedSquare);
    expect(frames.user?.shape, PeiLinkAvatarShape.roundedSquare);
    expect(frames.character?.shape, PeiLinkAvatarShape.roundedSquare);
    expect(frames.group?.paddingRatio, lessThan(frames.user!.paddingRatio));
  });

  test('public Echo is a variant of the selected global chat theme', () {
    final selected = chatTheme('selected', ChatVisualThemeCatalog.cloud.id);
    final registry = PeiLinkThemeRegistry(chatThemes: [selected]);
    expect(
      registry.chat('selected').publicEchoTheme,
      same(selected.publicEchoTheme),
    );
  });

  test('private Echo themes are isolated by character ID', () async {
    final directory = await Directory.systemTemp.createTemp('private_echo_');
    addTearDown(() => directory.delete(recursive: true));
    final registry = PeiLinkThemeRegistry(
      privateEchoThemes: [echoTheme('midnight'), echoTheme('sakura')],
    );
    final controller = PeiLinkThemeController(
      storage: NativePlatformStorage(directory.path),
      registry: registry,
    );
    await controller.setPrivateEchoTheme('a', 'midnight');
    await controller.setPrivateEchoTheme('b', 'sakura');
    expect(controller.privateEchoTheme('a').id, 'midnight');
    expect(controller.privateEchoTheme('b').id, 'sakura');
    expect(controller.privateEchoTheme('c').id, 'default_private_echo');
    expect(controller.selectedChatThemeId, 'default');
    final restored = PeiLinkThemeController(
      storage: NativePlatformStorage(directory.path),
      registry: registry,
    );
    await restored.load();
    expect(restored.privateEchoTheme('a').id, 'midnight');
    expect(restored.privateEchoTheme('b').id, 'sakura');
  });

  testWidgets(
    'avatar frame is absent by default and overlay is non-interactive',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              const PeiLinkThemedAvatar(size: 40, role: PeiLinkAvatarRole.user),
              PeiLinkThemedAvatar(
                size: 40,
                role: PeiLinkAvatarRole.character,
                frame: const AvatarFrameSpec(
                  id: 'test-frame',
                  border: Border.fromBorderSide(BorderSide(color: Colors.red)),
                ),
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('peilink-avatar-frame-overlay')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('peilink-avatar-frame-overlay')),
          matching: find.byType(DecoratedBox),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(PeiLinkThemedAvatar).last);
      expect(taps, 1);
    },
  );

  testWidgets(
    'followTheme and custom bubble modes resolve without changing IDs',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bubble_mode_'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final appearance = PeiLinkAppearanceController.testing(
        fileProvider: () async => File('${directory.path}/appearance.json'),
      );
      final themeController = PeiLinkThemeController(
        storage: NativePlatformStorage(directory.path),
        registry: PeiLinkThemeRegistry(
          chatThemes: [
            chatTheme('cloud-theme', ChatVisualThemeCatalog.cloud.id),
          ],
        ),
      );
      await tester.runAsync(
        () => themeController.selectChatTheme('cloud-theme'),
      );
      late ChatBubbleTheme resolved;
      Widget app() => PeiLinkThemeScope(
        controller: themeController,
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
      );
      await tester.pumpWidget(app());
      expect(resolved.id, ChatVisualThemeCatalog.cloud.id);
      await tester.runAsync(
        () => appearance.setBubbleTheme(ChatVisualThemeCatalog.candy),
      );
      await tester.pumpWidget(app());
      expect(resolved.id, ChatVisualThemeCatalog.candy.id);
    },
  );

  testWidgets('theme decoration layer never intercepts gestures', (
    tester,
  ) async {
    var taps = 0;
    final controller = PeiLinkThemeController();
    await tester.pumpWidget(
      PeiLinkThemeScope(
        controller: controller,
        child: MaterialApp(
          home: PeiLinkThemeScaffold(
            decoration: const PeiLinkDecorationTheme(
              top: BoxDecoration(color: Colors.red),
            ),
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(20, 20));
    expect(taps, 1);
  });

  test('legacy appearance config keeps its bubble as custom', () async {
    final directory = await Directory.systemTemp.createTemp('legacy_theme_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/appearance.json');
    await file.writeAsString(jsonEncode({'bubbleThemeId': 'milk_candy'}));
    final appearance = PeiLinkAppearanceController.testing(
      fileProvider: () async => file,
    );
    await appearance.load();
    expect(appearance.bubbleThemeMode, BubbleThemeMode.custom);
    expect(appearance.bubbleTheme.id, 'milk_candy');
  });
}
