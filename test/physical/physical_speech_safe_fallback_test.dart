import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/physical_speech_contract.dart';
import 'fixtures/verified_raw_reply.dart';

void main() {
  test(
    'verified real E2E raw response preserves DISPLAY and extracts speech',
    () {
      final r = PhysicalSpeechContractParser.resolve(verifiedRawReply);
      expect(r.contractParsed, isFalse);
      expect(r.rawReply, verifiedRawReply);
      expect(r.displayReply, verifiedRawReply);
      expect(r.spokenReply, verifiedSpokenReply);
      expect(r.diagnostics.fallbackSource, PhysicalFallbackSource.raw);
      expect(
        r.fallbackReason,
        'contract_parse_failed;speech_safe_fallback;leading_action_removed;quote_extracted',
      );
    },
  );

  test(
    'long, arbitrary, consecutive and multiline prefixes are structural',
    () {
      final long = List.filled(100, '任').join();
      final inputs = [
        '（$long）“你好。”',
        '($long)"你好。"',
        '（窗外忽然安静下来。）“你好。”',
        '（第一个块） (第二个块) （第三个块）“你好。”',
        '（第一行\n第二行（嵌套））\n“你好。”',
        '(one (nested) block) 你好。',
        '（动作）你好。',
        '（动作）"你好。"',
        '```text\n（动作）“你好。”\n```',
      ];
      for (final raw in inputs) {
        final r = PhysicalSpeechContractParser.resolve(raw);
        expect(r.displayReply, raw, reason: raw);
        expect(r.spokenReply, '你好。', reason: raw);
        expect(r.fallbackReason, contains('leading_action_removed'));
      }
    },
  );

  test('empty or ambiguous speech never resurrects original source', () {
    for (final raw in [
      '（只有动作）',
      '(only action)',
      '（动作一）（动作二）',
      '（没有闭括号',
      '（不匹配)',
      '（动作）“缺少闭引号',
      '他尾音上扬。',
      '（轻笑。）',
      '',
      '<PEILINK_SPOKEN>你好。</PEILINK_SPOKEN>',
      '<PEILINK_DISPLAY>（动作）“你好。”',
    ]) {
      final r = PhysicalSpeechContractParser.resolve(raw);
      expect(r.displayReply, raw.trim());
      expect(r.spokenReply, isEmpty, reason: raw);
      expect(r.fallbackReason, contains('empty_safe_result'));
    }
  });

  test('pure dialogue and inline natural parentheses survive', () {
    for (final raw in [
      '你好呀。',
      '我当然爱你。',
      '今天怎么突然唱蜜雪冰城了？',
      '我明天（周三）来。',
      '选项 A (推荐) 可以。',
    ]) {
      expect(PhysicalSpeechContractParser.resolve(raw).spokenReply, raw);
    }
    expect(
      PhysicalSpeechContractParser.resolve('（动作）“我明天（周三）来。”').spokenReply,
      '我明天（周三）来。',
    );
    expect(
      PhysicalSpeechContractParser.resolve('（动作）我明天（周三）来。').spokenReply,
      '我明天（周三）来。',
    );
    expect(
      PhysicalSpeechContractParser.resolve('“你好。”（动作）“再见。”').spokenReply,
      '你好。\n再见。',
    );
  });

  test('valid contract bypasses fallback unchanged', () {
    const spoken = '（正常 contract 内容不在本轮改写）“你好。”';
    const raw =
        '<PEILINK_DISPLAY>$verifiedRawReply</PEILINK_DISPLAY>'
        '<PEILINK_SPOKEN>$spoken</PEILINK_SPOKEN>';
    final r = PhysicalSpeechContractParser.resolve(raw);
    expect(r.contractParsed, isTrue);
    expect(r.displayReply, verifiedRawReply);
    expect(r.spokenReply, spoken);
    expect(r.fallbackReason, '');
  });

  test('round 2 multi-dialogue reconstruction keeps every safe utterance', () {
    final r = PhysicalSpeechContractParser.resolve(round2BatRawReply);
    expect(r.contractParsed, isFalse);
    expect(r.diagnostics.failure, PhysicalContractFailure.markerCount);
    expect(r.diagnostics.fallbackSource, PhysicalFallbackSource.raw);
    // DISPLAY path untouched: the full reply is kept for the UI.
    expect(r.displayReply, round2BatRawReply);
    // Regression: previously only the first quoted utterance survived.
    expect(r.spokenReply, round2BatSpokenReply);
    for (final fragment in round2BatNarrationFragments) {
      expect(r.spokenReply, isNot(contains(fragment)), reason: fragment);
    }
  });

  test('multi-dialogue: bare narration between quotes no longer truncates', () {
    final cases = {
      '（动作）“蝙蝠？”他皱眉，“你确定？”他压低声音：“别吓我。”':
          '蝙蝠？\n你确定？\n别吓我。',
      '（动作）“蝙蝠？”他放下杯子，又补了一句：“你确定没看错？”':
          '蝙蝠？\n你确定没看错？',
      '（抬眼）“蝙蝠？”他压低声音：“你确定？”（动作）“那就赶紧走。”':
          '蝙蝠？\n你确定？\n那就赶紧走。',
    };
    cases.forEach((raw, expected) {
      final r = PhysicalSpeechContractParser.resolve(raw);
      expect(r.spokenReply, expected, reason: raw);
      expect(r.displayReply, raw, reason: raw);
      expect(r.spokenReply, isNot(contains('他皱眉')), reason: raw);
    });
  });

  test('multi-dialogue: action/dialogue alternation stays in original order', () {
    final cases = {
      '（动作）“第一句。”（动作）“第二句。”': '第一句。\n第二句。',
      '“你好。”（动作）“再见。”': '你好。\n再见。',
      '（动作）“甲”（顿了顿）“乙”（抬手）“丙”': '甲\n乙\n丙',
    };
    cases.forEach((raw, expected) {
      expect(
        PhysicalSpeechContractParser.resolve(raw).spokenReply,
        expected,
        reason: raw,
      );
    });
  });

  test('multi-dialogue: corner quotes and straight quotes are scanned too', () {
    final cases = {
      '（动作）「甲」他顿了顿，「乙」': '甲\n乙',
      '（动作）『丙』他顿了顿，『丁』': '丙\n丁',
      '（动作）"A" 他顿了顿，"B"': 'A\nB',
      '（动作）“甲”他皱眉，「乙」': '甲\n乙',
    };
    cases.forEach((raw, expected) {
      final r = PhysicalSpeechContractParser.resolve(raw);
      expect(r.spokenReply, expected, reason: raw);
      expect(r.spokenReply, isNot(contains('他皱眉')), reason: raw);
      expect(r.spokenReply, isNot(contains('他顿了顿')), reason: raw);
    });
  });

  test('multi-dialogue: narration is never promoted when quotes are unsafe', () {
    // The quote is glued into a sentence with no structural boundary, so it is
    // not a confirmed utterance: nothing is spoken instead of narration.
    final glued = PhysicalSpeechContractParser.resolve('他念出“蜜雪冰城”三个字');
    expect(glued.spokenReply, isEmpty);
    expect(glued.fallbackReason, contains('unsafe_quoted_dialogue'));
    expect(glued.displayReply, '他念出“蜜雪冰城”三个字');
    // Unbalanced structure stays silent as before.
    for (final raw in [
      '（动作）“缺少闭引号',
      '（动作）“甲”他皱眉「乙',
      '（没有闭括号',
    ]) {
      final r = PhysicalSpeechContractParser.resolve(raw);
      expect(r.spokenReply, isEmpty, reason: raw);
      expect(r.fallbackReason, contains('empty_safe_result'), reason: raw);
    }
  });

  test('multi-dialogue: no-quote fallback behaviour is unchanged', () {
    final cases = {
      '（动作）你好。': '你好。',
      '你好呀。': '你好呀。',
      '我明天（周三）来。': '我明天（周三）来。',
      '选项 A (推荐) 可以。': '选项 A (推荐) 可以。',
      '（动作）“我明天（周三）来。”': '我明天（周三）来。',
    };
    cases.forEach((raw, expected) {
      expect(
        PhysicalSpeechContractParser.resolve(raw).spokenReply,
        expected,
        reason: raw,
      );
    });
  });

  test('round 2 FAIL family: unpunctuated introducer before a later quote', () {
    // Real-round shape: dialogue 1 and 2 are fine, but the narration that
    // introduces dialogue 3 does not end with clause punctuation. Every
    // variant below must still keep all three utterances, in order, and must
    // still never speak the narration.
    final variants = <String, String>{
      'no trailing punctuation': '他又慢悠悠补一句',
      'em dash': '他又慢悠悠补一句——',
      'action block then no punctuation': '他（慢悠悠）补一句',
      'unbalanced parenthesis': '他慢悠悠补一句（',
      'wave dash': '他又慢悠悠补一句～',
      // Positive controls that already worked before the fix.
      'comma': '他又慢悠悠补一句，',
      'colon': '他又慢悠悠补一句：',
      'full stop': '他慢悠悠补了一句。',
    };
    variants.forEach((label, gap) {
      final raw = '$round2BatHead$gap$round2BatTail';
      final r = PhysicalSpeechContractParser.resolve(raw);
      expect(r.spokenReply, round2BatAllSpoken, reason: label);
      expect(r.displayReply, raw, reason: label);
      for (final fragment in round2BatNarrationFragments) {
        expect(r.spokenReply, isNot(contains(fragment)), reason: label);
      }
      for (final fragment in const ['慢悠悠', '补一句', '顿了顿']) {
        expect(r.spokenReply, isNot(contains(fragment)), reason: label);
      }
    });
  });

  test('round 3 FAIL: quoted word inside the leading action must not eat '
      'the first dialogue', () {
    final r = PhysicalSpeechContractParser.resolve(round3LeadingQuoteRaw);
    expect(r.contractParsed, isFalse);
    expect(r.diagnostics.failure, PhysicalContractFailure.markerCount);
    expect(r.diagnostics.fallbackSource, PhysicalFallbackSource.raw);
    // Invariant 1/4: the DISPLAY path keeps everything.
    expect(r.displayReply, round3LeadingQuoteRaw);
    // Invariant 3/5: all three real utterances survive, in order.
    expect(r.spokenReply, round3SpokenReply);
    // Invariant 2: the quoted word inside the action block is never spoken on
    // its own, and no action text reaches TTS.
    for (final fragment in round3ActionFragments) {
      expect(r.spokenReply, isNot(contains(fragment)), reason: fragment);
    }
    expect(r.spokenReply.startsWith('老婆？叫得挺顺口'), isTrue);
  });

  test('round 4 FAIL: standalone mid-text action block must not be read', () {
    final r = PhysicalSpeechContractParser.resolve(round4MidActionRaw);
    expect(r.contractParsed, isFalse);
    expect(r.diagnostics.failure, PhysicalContractFailure.markerCount);
    expect(r.diagnostics.fallbackSource, PhysicalFallbackSource.raw);
    // Invariant 6: DISPLAY keeps the full raw, action included.
    expect(r.displayReply, round4MidActionRaw);
    // Invariant 1/3: every other sentence is preserved verbatim, in order.
    expect(r.spokenReply, round4MidActionSpoken);
    // Invariant 2: the action block itself never reaches TTS.
    for (final fragment in round4ActionFragments) {
      expect(r.spokenReply, isNot(contains(fragment)), reason: fragment);
    }
  });

  test('round 4 boundary: embedded parentheticals in prose are kept', () {
    final kept = <String>[
      '我明天（周三）来。',
      '选项 A (推荐) 可以。',
      '这件事（说来话长，我改天再跟你细说）先放一放。',
      '寒尔维亚？行啊。我明天（周三）来。',
    ];
    for (final raw in kept) {
      final r = PhysicalSpeechContractParser.resolve(raw);
      expect(r.spokenReply, raw, reason: raw);
    }
  });
}

/// Round 4 real raw structure: quoted-free normal prose with a standard
/// parenthesised action standing between two sentences.
const round4MidActionRaw =
    '寒尔维亚？行啊，审美倒是挺有意思，不去巴黎不去冰岛，专挑个人多数人地图上都找不着的地儿。'
    '（把手机夹在肩膀和耳朵之间，顺手在平板上翻了下日历。）'
    '贝尔格莱德进，诺维萨德待两天，剩下的看你。'
    '签证和机票我来弄，你只要负责别到时候又嫌我行程排太满。\n'
    '不过先说好，这次不是出差，别又顺手把电脑塞进行李箱。';

const round4MidActionSpoken =
    '寒尔维亚？行啊，审美倒是挺有意思，不去巴黎不去冰岛，专挑个人多数人地图上都找不着的地儿。'
    '贝尔格莱德进，诺维萨德待两天，剩下的看你。'
    '签证和机票我来弄，你只要负责别到时候又嫌我行程排太满。\n'
    '不过先说好，这次不是出差，别又顺手把电脑塞进行李箱。';

const round4ActionFragments = <String>[
  '把手机夹在',
  '肩膀和耳朵',
  '平板上翻了下日历',
];

/// Round 3 real raw structure (DEV UI DISPLAY): the leading action block quotes
/// the word 老婆, and the three real utterances follow as quoted dialogue.
const round3LeadingQuoteRaw =
    '（靠在椅背上，手指转着钢笔，看到“老婆”两个字先是挑了挑眉。）'
    '“老婆？叫得挺顺口，上周你喊我全名的时候可不是这个语气。”'
    '（把笔搁下，慢悠悠打字。）'
    '“有多爱？这个问题有点难为情啊林秘书你是我老婆，又是我秘书，婚姻还没公开，'
    '我每天上班看见你都得装作只是上下级。你觉得一个正常人能忍这种事忍多久？”'
    '“行了，别用这种问题钓我。真想听答案的话，晚上回家我当面说，打字说太亏了。”';

const round3SpokenReply =
    '老婆？叫得挺顺口，上周你喊我全名的时候可不是这个语气。\n'
    '有多爱？这个问题有点难为情啊林秘书你是我老婆，又是我秘书，婚姻还没公开，'
    '我每天上班看见你都得装作只是上下级。你觉得一个正常人能忍这种事忍多久？\n'
    '行了，别用这种问题钓我。真想听答案的话，晚上回家我当面说，打字说太亏了。';

const round3ActionFragments = <String>[
  '靠在椅背上',
  '转着钢笔',
  '两个字先是挑了挑眉',
  '把笔搁下',
  '慢悠悠打字',
];

/// Three-utterance body used by the Round 2 FAIL-family regression: dialogue 1
/// is introduced by an action block, dialogue 2 by `他顿了顿：`, and dialogue 3
/// by the variant under test.
const round2BatHead =
    '（他看了你一眼）“电脑房，好，知道了，是真蝙蝠。”'
    '他顿了顿：'
    '“手边有扫把别用，拿个纸板都行。真怕就退出去把门关上，叫物业上来处理。'
    '你人没事就行，电脑摔了就摔了，回头我给你换。”';

const round2BatTail = '“不过说真的，它挑中你电脑房，是不是嫌你最近太吵了。”';

const round2BatAllSpoken =
    '电脑房，好，知道了，是真蝙蝠。\n'
    '手边有扫把别用，拿个纸板都行。真怕就退出去把门关上，叫物业上来处理。'
    '你人没事就行，电脑摔了就摔了，回头我给你换。\n'
    '不过说真的，它挑中你电脑房，是不是嫌你最近太吵了。';

/// Round 2 fixture (behavioural reconstruction; see note in the test above).
///
/// Measured Round 2 evidence: contract `marker_count` failure, fallback source
/// `raw`, DISPLAY carried the full multi-action reply, and SPOKEN/TTS input was
/// truncated to exactly `蝙蝠？`. This constant reproduces that shape so the
/// truncation cannot come back. Replace it with the literal model reply once it
/// is captured from the dev UI, keeping the same expectations.
const round2BatRawReply =
    '（他愣了一下，手里的水杯停在半空）“蝙蝠？”'
    '他放下杯子，又补了一句：“在电脑房边碰见的？你确定没看错？”'
    '（顿了顿，声音压低）“吓到了吧。它比你更怕。”';

const round2BatSpokenReply =
    '蝙蝠？\n在电脑房边碰见的？你确定没看错？\n吓到了吧。它比你更怕。';

const round2BatNarrationFragments = <String>[
  '他愣了一下',
  '手里的水杯停在半空',
  '他放下杯子',
  '又补了一句',
  '顿了顿',
  '声音压低',
];
