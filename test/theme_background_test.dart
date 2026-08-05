import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/theme/app_theme_background.dart';

void main() {
  test('default light theme exposes a readable background configuration', () {
    final background = AppThemeBackground.defaultLight;

    expect(background.id, 'default_light');
    expect(background.opacity, inInclusiveRange(0.0, 1.0));
    expect(background.primaryColor, isNot(background.secondaryColor));
  });

  testWidgets('theme background layer renders below page content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ThemeBackgroundContainer(child: Text('page content')),
      ),
    );

    expect(
      find.byKey(const ValueKey('theme-background-cat_paw_blush')),
      findsOneWidget,
    );
    expect(find.text('page content'), findsOneWidget);
  });

  testWidgets('every built-in image theme can be selected', (tester) async {
    for (final background in AppThemeBackground.builtInPack) {
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeBackgroundContainer(
            background: background,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(ValueKey('theme-background-${background.id}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
