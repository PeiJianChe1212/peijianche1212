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
}
