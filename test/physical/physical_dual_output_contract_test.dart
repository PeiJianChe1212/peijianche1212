import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/physical_speech_contract.dart';

void main() {
  test('instruction defines both markers and no JSON dependency', () {
    final instruction = PhysicalSpeechContract.instruction;
    expect(instruction, contains(PhysicalSpeechContract.displayStart));
    expect(instruction, contains(PhysicalSpeechContract.displayEnd));
    expect(instruction, contains(PhysicalSpeechContract.spokenStart));
    expect(instruction, contains(PhysicalSpeechContract.spokenEnd));
    expect(instruction, isNot(contains('response_format')));
    expect(instruction, isNot(contains('json')));
  });

  test('parses display with narration and spoken dialogue only', () {
    const raw =
        '<PEILINK_DISPLAY>\n'
        '轻笑一声，放下钢笔。刚才处理完那些事，打算休息。你呢？\n'
        '</PEILINK_DISPLAY>\n'
        '<PEILINK_SPOKEN>\n'
        '刚才处理完那些事，打算休息。你呢？\n'
        '</PEILINK_SPOKEN>';
    final result = PhysicalSpeechContractParser.tryParse(raw)!;
    expect(result.contractParsed, isTrue);
    expect(result.displayReply, contains('轻笑一声，放下钢笔'));
    expect(result.spokenReply, isNot(contains('轻笑')));
    expect(result.spokenReply, contains('你呢？'));
  });

  test('display and spoken may be identical for pure dialogue', () {
    const raw =
        '<PEILINK_DISPLAY>怎么突然问这个？当然想你。</PEILINK_DISPLAY>\n'
        '<PEILINK_SPOKEN>怎么突然问这个？当然想你。</PEILINK_SPOKEN>';
    final result = PhysicalSpeechContractParser.tryParse(raw)!;
    expect(result.displayReply, result.spokenReply);
  });

  test('supports multiple action and dialogue paragraphs', () {
    const raw =
        '<PEILINK_DISPLAY>\n'
        '他往后靠进椅背，像是在认真考虑。\n'
        '你要是问我想不想你\n'
        '他尾音上扬。\n'
        '我嘴上嫌你烦，心里其实挺高兴的。\n'
        '</PEILINK_DISPLAY>\n'
        '<PEILINK_SPOKEN>\n'
        '你要是问我想不想你\n'
        '我嘴上嫌你烦，心里其实挺高兴的。\n'
        '</PEILINK_SPOKEN>';
    final result = PhysicalSpeechContractParser.tryParse(raw)!;
    expect(result.displayReply, contains('他往后靠进椅背'));
    expect(result.spokenReply, isNot(contains('靠进椅背')));
    expect(result.spokenReply, isNot(contains('尾音')));
  });

  test('missing display falls back without losing content', () {
    const raw = '<PEILINK_SPOKEN>只有朗读没有显示？</PEILINK_SPOKEN>';
    final result = PhysicalSpeechContractParser.resolve(raw);
    expect(result.contractParsed, isFalse);
    expect(result.displayReply, isNotEmpty);
    expect(result.spokenReply, isEmpty);
    expect(result.fallbackReason, contains('contract_parse_failed'));
  });

  test('missing spoken falls back through adapter', () {
    const raw =
        '<PEILINK_DISPLAY>轻笑一声，放下钢笔。我没事。</PEILINK_DISPLAY>';
    final result = PhysicalSpeechContractParser.resolve(raw);
    expect(result.contractParsed, isFalse);
    expect(result.displayReply, contains('轻笑一声'));
    expect(result.spokenReply, contains('我没事'));
  });

  test('duplicate or misordered markers fall back', () {
    const duplicate =
        '<PEILINK_DISPLAY>A</PEILINK_DISPLAY>'
        '<PEILINK_DISPLAY>B</PEILINK_DISPLAY>'
        '<PEILINK_SPOKEN>C</PEILINK_SPOKEN>';
    expect(PhysicalSpeechContractParser.tryParse(duplicate), isNull);

    const reversed =
        '<PEILINK_SPOKEN>C</PEILINK_SPOKEN>'
        '<PEILINK_DISPLAY>A</PEILINK_DISPLAY>';
    expect(PhysicalSpeechContractParser.tryParse(reversed), isNull);

    final result = PhysicalSpeechContractParser.resolve(duplicate);
    expect(result.displayReply, isNotEmpty);
    expect(result.spokenReply, isEmpty);
  });

  test('real E2E mixed sample uses spoken section when provided', () {
    const raw =
        '<PEILINK_DISPLAY>\n'
        '轻笑一声，放下钢笔，声音懒洋洋的，'
        '刚才处理完董事会那些破事，正打算给自己放会儿假。'
        '你呢，这个点还有空？\n'
        '</PEILINK_DISPLAY>\n'
        '<PEILINK_SPOKEN>\n'
        '你呢，这个点还有空？\n'
        '</PEILINK_SPOKEN>';
    final result = PhysicalSpeechContractParser.resolve(raw);
    expect(result.contractParsed, isTrue);
    expect(result.spokenReply, '你呢，这个点还有空？');
    expect(result.displayReply, contains('轻笑一声'));
  });

  test('never mutates raw reply', () {
    const raw =
        '<PEILINK_DISPLAY>A</PEILINK_DISPLAY>'
        '<PEILINK_SPOKEN>B</PEILINK_SPOKEN>';
    final result = PhysicalSpeechContractParser.resolve(raw);
    expect(result.rawReply, raw);
    expect(raw, contains('<PEILINK_DISPLAY>'));
  });
}
