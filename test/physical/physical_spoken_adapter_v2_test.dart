import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/physical_speech_text_adapter.dart';

void main() {
  test('keeps a clean real E2E spoken reply unchanged', () {
    const raw =
        '听到了，耳朵又没聋。\n'
        '刚挂了顾言白那通麻烦电话，正琢磨着要不要把你从文件堆里捞出来透口气。';
    expect(PhysicalSpeechTextAdapter.fromCoreReply(raw), raw);
  });

  test('removes standalone narration between unquoted dialogue lines', () {
    const raw =
        '他往后靠进椅背，手指轻轻敲了两下桌面，像是在认真考虑。\n'
        '你要是问我想不想你\n'
        '他尾音上扬。\n'
        '要让我自己说，那就是你问这种问题的时候，'
        '我嘴上嫌你烦，心里其实挺高兴的。';
    expect(
      PhysicalSpeechTextAdapter.fromCoreReply(raw),
      '你要是问我想不想你\n'
          '要让我自己说，那就是你问这种问题的时候，'
          '我嘴上嫌你烦，心里其实挺高兴的。',
    );
  });

  test('keeps only quoted dialogue when narration surrounds Chinese quotes', () {
    const raw = '他顿了顿，声音放轻：“我没事，就是有点困。”';
    expect(PhysicalSpeechTextAdapter.fromCoreReply(raw), '我没事，就是有点困。');
  });

  test('removes standalone and inline parenthetical action blocks', () {
    expect(
      PhysicalSpeechTextAdapter.fromCoreReply('（抬手揉了揉眉心）行，听你的。'),
      '行，听你的。',
    );
    expect(
      PhysicalSpeechTextAdapter.fromCoreReply(
        '行，听你的。（抬手揉了揉眉心）明天再说。',
      ),
      '行，听你的。明天再说。',
    );
    expect(
      PhysicalSpeechTextAdapter.fromCoreReply(
        '裴检测？（被你叫法逗笑，慢悠悠放下手里的文件）这名字倒是新鲜。',
      ),
      '裴检测？\n这名字倒是新鲜。',
    );
  });

  test('removes a star-delimited action block and keeps dialogue', () {
    expect(
      PhysicalSpeechTextAdapter.fromCoreReply('知道了。*轻笑了一声*那你去忙吧。'),
      '知道了。那你去忙吧。',
    );
  });

  test('keeps unquoted pure dialogue untouched', () {
    const raw = '怎么突然问这个？当然想你。';
    expect(PhysicalSpeechTextAdapter.fromCoreReply(raw), raw);
  });

  test('keeps informative parentheticals that should be read aloud', () {
    const raw = '今天周五（不是周六），版本 2.0（稳定版）。';
    expect(PhysicalSpeechTextAdapter.fromCoreReply(raw), raw);
  });

  test('extracts English double-quoted dialogue after narration', () {
    const raw = '他说："I am fine, just a little tired."';
    expect(
      PhysicalSpeechTextAdapter.fromCoreReply(raw),
      'I am fine, just a little tired.',
    );
  });

  test('extracts Chinese single-quoted dialogue after narration', () {
    const raw = '他顿了顿：‘我没事。’';
    expect(PhysicalSpeechTextAdapter.fromCoreReply(raw), '我没事。');
  });

  test('conservatively preserves incomplete/unpaired quotes', () {
    const raw = '他说：“我没事。';
    final result = PhysicalSpeechTextAdapter.fromCoreReply(raw);
    expect(result, contains('我没事'));
    expect(result, isNotEmpty);
  });

  test('falls back to sanitized speech when filtering would empty a reply', () {
    const raw = '（抬手揉了揉眉心）\n他尾音上扬。';
    final result = PhysicalSpeechTextAdapter.fromCoreReplyDetailed(raw);
    expect(result.text, isNotEmpty);
    expect(result.fallbackUsed, isTrue);
    expect(result.note, contains('fallback_after_empty_filter'));
  });

  test('never mutates the raw reply string', () {
    const raw = '他顿了顿，声音放轻：“我没事。”';
    expect(PhysicalSpeechTextAdapter.fromCoreReply(raw), '我没事。');
    expect(raw, '他顿了顿，声音放轻：“我没事。”');
  });
}
