import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/pages/peilink/physical_host_page.dart';
import 'package:peijianche_app/physical/doubao_speech_clients.dart';
import 'package:peijianche_app/physical/pcm_audio_gain.dart';

void main() {
  testWidgets('session summary shows turn count and clears only when idle', (
    tester,
  ) async {
    var clearCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalSessionSummary(
            turnCount: 3,
            isBusy: false,
            onClear: () => clearCalls++,
          ),
        ),
      ),
    );

    expect(find.text('本次实体会话：3 轮'), findsOneWidget);
    await tester.tap(find.text('清空实体会话'));
    expect(clearCalls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhysicalSessionSummary(
            turnCount: 3,
            isBusy: true,
            onClear: () => clearCalls++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('清空实体会话'));
    expect(clearCalls, 1);
  });

  testWidgets('ASR stats card shows only desensitized diagnostics', (
    tester,
  ) async {
    const stats = AsrTranscribeStats(
      inputBytes: 256000,
      inputPeak: 320,
      inputRms: 42.5,
      selectedGain: 5,
      gainReason: GainReason.lowLevelBoosted,
      outputPeak: 1600,
      outputRms: 212.5,
      outputClippingRatio: 0.00025,
      asrStatusCode: '20000003',
      asrMessage: 'Silent audio',
      asrLogId: 'safe-logid',
      resultStructure: AsrResultStructure(
        resultTextLength: 9,
        utterances: [
          AsrUtteranceStructure(textLength: 4, startTime: 100, endTime: 900),
        ],
      ),
      success: false,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PhysicalAsrStatsCard(stats: stats)),
      ),
    );

    expect(find.text('ASR 脱敏统计'), findsOneWidget);
    expect(find.textContaining('inputBytes=256000'), findsOneWidget);
    expect(find.textContaining('selectedGain=5.00'), findsOneWidget);
    expect(find.textContaining('outputRMS=212.5'), findsOneWidget);
    expect(find.textContaining('asrStatusCode=20000003'), findsOneWidget);
    expect(find.textContaining('asrMessage=Silent audio'), findsOneWidget);
    expect(find.textContaining('asrLogId=safe-logid'), findsOneWidget);
    expect(find.textContaining('resultTextLength=9'), findsOneWidget);
    expect(find.textContaining('utteranceCount=1'), findsOneWidget);
    expect(
      find.textContaining('utterance[0] textLength=4 100-900'),
      findsOneWidget,
    );
    expect(find.textContaining('API Key'), findsNothing);
    expect(find.textContaining('base64'), findsNothing);
    expect(find.textContaining('不能进入统计的完整识别文本'), findsNothing);
  });
}
