import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/services/peilink_appearance_service.dart';
import 'package:peijianche_app/theme/app_theme_background.dart';
import 'package:peijianche_app/theme/chat_visual_theme.dart';

void main() {
  test(
    'background, bubble and font selections persist across reloads',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'peilink_appearance',
      );
      final file = File('${directory.path}/appearance.json');
      Future<File> fileProvider() async => file;

      try {
        final first = PeiLinkAppearanceController.testing(
          fileProvider: fileProvider,
        );
        await first.setBackground(AppThemeBackground.softCloudBlue);
        await first.setBubbleTheme(ChatVisualThemeCatalog.glass);
        await first.setFontTheme(ChatVisualThemeCatalog.kai);

        final restored = PeiLinkAppearanceController.testing(
          fileProvider: fileProvider,
        );
        await restored.load();

        expect(restored.background.id, AppThemeBackground.softCloudBlue.id);
        expect(restored.bubbleTheme.id, ChatVisualThemeCatalog.glass.id);
        expect(restored.fontTheme.id, ChatVisualThemeCatalog.kai.id);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
