import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/conversation/chat_reply_sanitizer.dart';

void main() {
  group('ChatReplySanitizer', () {
    test('removes bracket and stage directions while keeping dialogue', () {
      const value = '（低笑一声）\n*摸了摸你的头*\n【开心】\n吃了，你呢？';
      expect(ChatReplySanitizer.clean(value), '吃了，你呢？');
    });

    test('removes required leading action variants', () {
      expect(ChatReplySanitizer.clean('（轻笑）想我了？'), '想我了？');
      expect(ChatReplySanitizer.clean('*揉了揉眉心* 知道了。'), '知道了。');
      expect(ChatReplySanitizer.clean('【声音放轻】早点睡。'), '早点睡。');
      expect(ChatReplySanitizer.clean('(轻笑) 想我了？'), '想我了？');
      expect(ChatReplySanitizer.clean('[叹气] 早点睡。'), '早点睡。');
    });

    test('removes a leading stage direction describing vocal delivery', () {
      const value =
          '（翻东西的动作顿了半秒，尾音带着点漫不经心的调侃）'
          '你这是在给录音设备报数，还是在测试我听力？';
      expect(ChatReplySanitizer.clean(value), '你这是在给录音设备报数，还是在测试我听力？');
    });

    test('preserves natural narration and normal inline parentheses', () {
      const value = '我刚靠在沙发上休息了一会儿，今天还不错。\n这本是第二版（修订版），内容更完整。';
      expect(ChatReplySanitizer.clean(value), value);
    });

    test('removes an action-only bubble between normal text', () {
      const value = '他夸你什么？\n（看了你一眼）\n你猜。';
      expect(ChatReplySanitizer.clean(value), '他夸你什么？\n你猜。');
    });

    test('removes a lightweight English-parenthesis action', () {
      const value = '先说正事。\n(smiles)\n别躲。';
      expect(ChatReplySanitizer.clean(value), '先说正事。\n别躲。');
    });

    test('preserves ordinary parenthetical explanation', () {
      const value = '今天周五（不是周六）。\n版本号是 2.0（稳定版）。';
      expect(ChatReplySanitizer.clean(value), value);
    });

    test('cleans narration colon but preserves normal spoken colons', () {
      expect(ChatReplySanitizer.clean('嘴角不自觉地扬起来，语气放软：想我还不来找我？'), '想我还不来找我？');
      expect(ChatReplySanitizer.clean('顿了顿，声音压低了些：我马上回来。'), '我马上回来。');
      for (final value in [
        '我跟你说：今天那个会真的烦死了。',
        '原因很简单：我想你了。',
        '店里新来了三样东西：蛋糕、咖啡、冰淇淋。',
        '重点是：今晚我能早点回来。',
      ]) {
        expect(ChatReplySanitizer.clean(value), value);
      }
    });

    test('action-only output becomes safely empty', () {
      expect(ChatReplySanitizer.clean('（轻笑）'), isEmpty);
    });

    test('removes a high-confidence bare opening narration', () {
      expect(ChatReplySanitizer.clean('“顿了一下，跟我说说。'), '跟我说说。');
      expect(ChatReplySanitizer.clean('他顿了一下，跟我说说。'), '跟我说说。');
    });

    test('removes only orphan boundary quotes', () {
      expect(ChatReplySanitizer.clean('画的我？”'), '画的我？');
      expect(ChatReplySanitizer.clean('“那可得好好看看...'), '那可得好好看看...');
      expect(ChatReplySanitizer.clean('看《小王子》吗？'), '看《小王子》吗？');
      expect(ChatReplySanitizer.clean('「知道了。」'), '「知道了。」');
      expect(ChatReplySanitizer.clean('"知道了。"'), '"知道了。"');
    });

    test('preserves normal quoted speech and punctuation', () {
      const quoted = '“他说：今天不来了”';
      expect(ChatReplySanitizer.clean(quoted), quoted);
      expect(ChatReplySanitizer.clean('你画的是我？'), '你画的是我？');
      expect(ChatReplySanitizer.clean('重点是：别迟到。'), '重点是：别迟到。');
    });

    test('keeps multiple bubbles while cleaning individual directions', () {
      const value = '（轻笑）想我还不来找我？\n\n我这边马上收尾。\n\n晚点带你去吃饭。';
      expect(ChatReplySanitizer.clean(value), '想我还不来找我？\n我这边马上收尾。\n晚点带你去吃饭。');
    });

    test('does not remove ordinary text around inline parentheses', () {
      const value = '这条路（靠河的那条）晚上更安静，你要去就穿厚点。';
      expect(ChatReplySanitizer.clean(value), value);
    });

    test('removes internal fences, system markers and message numbers', () {
      expect(
        ChatReplySanitizer.clean('```json\n【系统提示】\n消息1：第一条。\n消息2：第二条。\n```'),
        '第一条。\n第二条。',
      );
    });
  });
}
