import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/dev_only/physical_speech_diagnostics_card.dart';
import 'package:peijianche_app/pages/peilink/physical_host_page.dart';
import 'package:peijianche_app/physical/physical_speech_contract.dart';

String contract(String display, String spoken) =>
    '<PEILINK_DISPLAY>$display</PEILINK_DISPLAY>'
    '<PEILINK_SPOKEN>$spoken</PEILINK_SPOKEN>';

void main() {
  testWidgets('user and unspecified direct Physical page hides diagnostics', (
    tester,
  ) async {
    addTearDown(() => PeiLinkRuntime.configure(PeiLinkBuild.unspecified));
    for (final build in [PeiLinkBuild.user, PeiLinkBuild.unspecified]) {
      PeiLinkRuntime.configure(build);
      await tester.pumpWidget(
        MaterialApp(home: PhysicalHostPage(key: ValueKey(build))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PhysicalSpeechDiagnosticsCard), findsNothing);
      expect(find.text('Speech Contract Diagnostics'), findsNothing);
      expect(find.textContaining('preview:'), findsNothing);
    }
  });

  test('success diagnostics do not filter erroneous spoken narration', () {
    const text = '（轻笑。）\n你好。';
    final reply = PhysicalSpeechContractParser.resolve(contract(text, text));
    final d = reply.diagnostics;
    expect(d.contractParsed, isTrue);
    expect(
      [
        d.displayStartCount,
        d.displayEndCount,
        d.spokenStartCount,
        d.spokenEndCount,
      ],
      [1, 1, 1, 1],
    );
    expect(d.markerOrderValid, isTrue);
    expect(d.displayBlockLength, text.length);
    expect(d.spokenBlockLength, text.length);
    expect(d.failure, PhysicalContractFailure.none);
    expect(d.fallbackSource, PhysicalFallbackSource.none);
    expect(d.fallbackReason, '');
    expect(reply.spokenReply, text);
  });

  test(
    'missing markers, reversed order, empty blocks and fallback diagnostics',
    () {
      final cases = <(String, PhysicalContractFailure, PhysicalFallbackSource)>[
        (
          '你好。',
          PhysicalContractFailure.markerCount,
          PhysicalFallbackSource.raw,
        ),
        (
          '<PEILINK_DISPLAY>你好。</PEILINK_DISPLAY>',
          PhysicalContractFailure.markerCount,
          PhysicalFallbackSource.displayCandidate,
        ),
        (
          '<PEILINK_SPOKEN>你好。</PEILINK_SPOKEN>'
              '<PEILINK_DISPLAY>你好。</PEILINK_DISPLAY>',
          PhysicalContractFailure.markerOrder,
          PhysicalFallbackSource.displayCandidate,
        ),
        (
          contract('你好。', ' \n '),
          PhysicalContractFailure.emptySpoken,
          PhysicalFallbackSource.displayCandidate,
        ),
        (
          contract(' ', '你好。'),
          PhysicalContractFailure.emptyDisplay,
          PhysicalFallbackSource.raw,
        ),
      ];
      for (final (raw, failure, source) in cases) {
        final r = PhysicalSpeechContractParser.resolve(raw);
        expect(r.diagnostics.contractParsed, isFalse);
        expect(r.diagnostics.failure, failure);
        expect(r.diagnostics.fallbackSource, source);
        expect(r.diagnostics.fallbackReason, r.fallbackReason);
        expect(r.fallbackReason, startsWith('contract_parse_failed;'));
      }
      final unmarked = PhysicalSpeechContractParser.resolve('你好。').diagnostics;
      expect(
        [
          unmarked.displayStartCount,
          unmarked.displayEndCount,
          unmarked.spokenStartCount,
          unmarked.spokenEndCount,
        ],
        [0, 0, 0, 0],
      );
      expect(unmarked.markerOrderValid, isFalse);
      expect(unmarked.displayBlockLength, isNull);
      expect(unmarked.spokenBlockLength, isNull);
      final empty = PhysicalSpeechContractParser.resolve(
        contract('你好。', '\n'),
      ).diagnostics;
      expect(empty.spokenBlockLength, 0);
      expect(empty.markerOrderValid, isTrue);
    },
  );

  test('real long narration is excluded from speech-safe fallback', () {
    const narration = '（看到这条消息，先是愣了两秒，随即低低笑出声来，手指在手机屏幕上轻敲两下。）';
    const dialogue = '我倒是想问问，你这是在给我点歌，还是替你家公司谈广告合作？';
    const display = '$narration\n\n“$dialogue”';
    final r = PhysicalSpeechContractParser.resolve(
      '<PEILINK_DISPLAY>$display</PEILINK_DISPLAY>',
    );
    expect(r.displayReply, display);
    expect(r.spokenReply, dialogue);
    expect(
      r.diagnostics.fallbackReason,
      'contract_parse_failed;speech_safe_fallback;leading_action_removed;quote_extracted',
    );
  });

  test(
    'diagnostics preserve wrappers, duplicate rejection and safety fallback',
    () {
      final good = contract('你好。', '你好。');
      expect(
        PhysicalSpeechContractParser.resolve('```\n$good\n```').contractParsed,
        isTrue,
      );
      final duplicate = PhysicalSpeechContractParser.resolve(
        '$good<PEILINK_SPOKEN>',
      );
      expect(duplicate.diagnostics.spokenStartCount, 2);
      expect(duplicate.diagnostics.spokenBlockLength, isNull);
      expect(
        duplicate.diagnostics.failure,
        PhysicalContractFailure.markerCount,
      );
      final safety = PhysicalSpeechContractParser.resolve(
        '<PEILINK_DISPLAY>（轻笑。）</PEILINK_DISPLAY>',
      );
      expect(safety.spokenReply, isEmpty);
      expect(
        safety.diagnostics.fallbackReason,
        'contract_parse_failed;speech_safe_fallback;leading_action_removed;empty_safe_result',
      );
    },
  );

  testWidgets(
    'Dev diagnostics previews escape newlines and isolate user build',
    (tester) async {
      addTearDown(() => PeiLinkRuntime.configure(PeiLinkBuild.unspecified));
      final r = PhysicalSpeechContractParser.resolve(
        contract('（轻笑。）\n你好。', '你好。'),
      );
      Widget card(String? tts) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PhysicalSpeechDiagnosticsCard(
              diagnostics: r.diagnostics,
              displayReply: r.displayReply,
              spokenReply: r.spokenReply,
              ttsInputExact: tts,
            ),
          ),
        ),
      );
      PeiLinkRuntime.configure(PeiLinkBuild.dev);
      await tester.pumpWidget(card('你好。'));
      for (final label in [
        'Speech Contract Diagnostics',
        'Contract parsed: true',
        'Marker counts: D-start=1 / D-end=1 / S-start=1 / S-end=1',
        'Marker order: valid',
        'Failure category: none',
        'Fallback source: none',
        'Fallback reason: (none)',
        r'DISPLAY preview: （轻笑。）\n你好。',
        'SPOKEN preview: 你好。',
        'TTS INPUT preview: 你好。',
        'TTS INPUT == SPOKEN: true',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.pumpWidget(card(null));
      expect(find.text('TTS INPUT == SPOKEN: not captured'), findsOneWidget);
      await tester.pumpWidget(card('不同'));
      expect(find.text('TTS INPUT == SPOKEN: false'), findsOneWidget);
      for (final build in [PeiLinkBuild.user, PeiLinkBuild.unspecified]) {
        PeiLinkRuntime.configure(build);
        await tester.pumpWidget(card('你好。'));
        expect(find.text('Speech Contract Diagnostics'), findsNothing);
        expect(find.textContaining('preview:'), findsNothing);
      }
    },
  );
}
