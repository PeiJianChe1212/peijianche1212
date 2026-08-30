import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/pages/home_page.dart';

void main() {
  testWidgets('Life desktop renders its fixed widget layout', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('PEILINK LIFE'), findsOneWidget);
    expect(find.text('\u7eaa\u5ff5\u65e5'), findsOneWidget);
    expect(find.text('\u4e16\u754c\u72b6\u6001'), findsOneWidget);
    expect(find.text('\u6700\u8fd1\u52a8\u6001'), findsOneWidget);
    expect(find.text('\u751f\u6d3b\u5e94\u7528'), findsOneWidget);
    expect(find.text('\u76f8\u518c'), findsOneWidget);
    expect(find.text('\u8bbe\u7f6e'), findsOneWidget);
  });

  for (final size in <Size>[
    const Size(320, 640),
    const Size(360, 800),
    const Size(411, 891),
  ]) {
    testWidgets('three home desktops fit ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: HomePage(initialHasVisibleCharacter: false)),
      );
      await tester.pump();
      expect(find.text('还没有角色'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.fling(find.byType(PageView), const Offset(-600, 0), 1200);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('PEILINK LIFE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.fling(find.byType(PageView), const Offset(-600, 0), 1200);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('应用空间'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('three home desktops tolerate enlarged text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.25)),
          child: child!,
        ),
        home: const HomePage(initialHasVisibleCharacter: false),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1200);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('PEILINK LIFE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1200);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('应用空间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
