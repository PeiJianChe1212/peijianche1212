import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/pages/peilink/physical_host_page.dart';
import 'package:peijianche_app/physical/physical_session_controller.dart';

void main() {
  testWidgets('end-to-end button is present and disabled while busy', (
    tester,
  ) async {
    var taps = 0;

    Future<void> pump(bool enabled) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalEndToEndButton(
            enabled: enabled,
            onPressed: () => taps++,
          ),
        ),
      ),
    );

    await pump(false);
    expect(
      find.byKey(const ValueKey('physical-end-to-end-turn')),
      findsOneWidget,
    );
    expect(find.text('一键完整对话（录音 → AI → 播放）'), findsOneWidget);

    final disabled = tester.widget<FilledButton>(
      find.byKey(const ValueKey('physical-end-to-end-turn')),
    );
    expect(disabled.onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey('physical-end-to-end-turn')),
    );
    expect(taps, 0);

    await pump(true);
    final enabled = tester.widget<FilledButton>(
      find.byKey(const ValueKey('physical-end-to-end-turn')),
    );
    expect(enabled.onPressed, isNotNull);
    await tester.tap(
      find.byKey(const ValueKey('physical-end-to-end-turn')),
    );
    expect(taps, 1);
  });

  testWidgets('E2E timing card shows stage durations', (tester) async {
    const timing = PhysicalE2ETiming(
      statusMs: 12,
      recordMs: 8050,
      asrMs: 3500,
      llmMs: 4200,
      ttsMs: 5100,
      resampleMs: 30,
      audioMs: 2400,
      totalMs: 23400,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PhysicalE2ETimingCard(timing: timing)),
      ),
    );

    expect(
      find.byKey(const ValueKey('physical-e2e-timing')),
      findsOneWidget,
    );
    expect(find.textContaining('E2E 耗时统计'), findsOneWidget);
    expect(find.textContaining('status: 12 ms'), findsOneWidget);
    expect(find.textContaining('record: 8050 ms'), findsOneWidget);
    expect(find.textContaining('ASR: 3500 ms'), findsOneWidget);
    expect(find.textContaining('LLM: 4200 ms'), findsOneWidget);
    expect(find.textContaining('TTS: 5100 ms'), findsOneWidget);
    expect(find.textContaining('resample: 30 ms'), findsOneWidget);
    expect(find.textContaining('audio/playback: 2400 ms'), findsOneWidget);
    expect(find.textContaining('total: 23400 ms'), findsOneWidget);
    expect(find.textContaining('失败阶段: -'), findsOneWidget);
  });
}
