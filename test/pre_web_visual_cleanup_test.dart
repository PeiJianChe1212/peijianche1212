import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/pages/peilink/character_creation_page.dart';

void main() {
  test('AI WORLD crop viewport follows every target screen ratio', () {
    const screens = <Size>[
      Size(360, 800),
      Size(412, 915),
      Size(600, 600),
      Size(915, 412),
      Size(320, 720),
    ];
    for (final screen in screens) {
      final viewport = backgroundCropViewportSize(screen);
      expect(viewport.aspectRatio, closeTo(screen.aspectRatio, 0.000001));
      expect(viewport.width, lessThanOrEqualTo(320));
      expect(viewport.height, lessThanOrEqualTo(420));
    }
  });

  test(
    'cover fills viewport without a blank edge for required image ratios',
    () {
      const target = Size(360, 800);
      const sources = <Size>[
        Size(900, 1600), // 竖图、人脸靠上
        Size(1080, 2400), // 接近手机比例、人脸居中
        Size(1200, 1200), // 方图、人脸靠边
        Size(1920, 1080), // 横图
        Size(1200, 2000),
        Size(1000, 1800),
        Size(1600, 900),
      ];
      for (final source in sources) {
        final rendered = backgroundCoverRenderSize(source, target);
        expect(rendered.width, greaterThanOrEqualTo(target.width));
        expect(rendered.height, greaterThanOrEqualTo(target.height));
        expect(
          rendered.width == target.width || rendered.height == target.height,
          isTrue,
        );

        // The saved crop has the final viewport ratio. AI WORLD therefore
        // uses every saved pixel instead of applying another crop.
        final display = applyBoxFit(BoxFit.cover, target, target);
        expect(display.source, target);
        expect(display.destination, target);
      }
    },
  );

  testWidgets('long character fields are full-width single-column inputs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CharacterCreationPage()));

    Future<Rect> fieldRect(String label) async {
      final key = switch (label) {
        '外貌' => 'appearance',
        '性格' => 'personality',
        _ => throw ArgumentError(label),
      };
      final finder = find.byKey(ValueKey('character-field-$key'));
      for (
        var attempt = 0;
        attempt < 8 && finder.evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -380));
        await tester.pump();
      }
      expect(finder, findsOneWidget);
      await tester.pumpAndSettle();
      return tester.getRect(finder);
    }

    final appearance = await fieldRect('外貌');
    final personality = await fieldRect('性格');
    expect(appearance.width, greaterThan(340));
    expect(personality.width, greaterThan(340));
    expect((appearance.left - personality.left).abs(), lessThan(1));
    expect(appearance.top, isNot(personality.top));

    final appearanceField = tester.widget<TextField>(
      find.byKey(const ValueKey('character-field-appearance')),
    );
    expect(appearanceField.maxLength, 800);
    expect(appearanceField.maxLines, 4);
    expect(find.text('✦  创建角色'), findsOneWidget);
  });
}
