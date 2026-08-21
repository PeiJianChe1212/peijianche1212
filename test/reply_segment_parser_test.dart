import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/conversation/reply_segment_parser.dart';

void main() {
  group('ReplySegmentParser', () {
    test('keeps a short reply in one bubble', () {
      expect(ReplySegmentParser.parse('哈哈。'), ['哈哈。']);
    });

    test('parses explicit PeiLink message separators', () {
      expect(
        ReplySegmentParser.parse(
          '刚忙完。<|PEILINK_MSG|>本来想休息一下。<|PEILINK_MSG|>结果先看到你的消息了。',
        ),
        ['刚忙完。', '本来想休息一下。', '结果先看到你的消息了。'],
      );
    });

    test('falls back to complete sentence boundaries', () {
      expect(ReplySegmentParser.parse('刚把事情收尾了。今天忙得有点久。本来还想着晚点找你。'), [
        '刚把事情收尾了。',
        '今天忙得有点久。',
        '本来还想着晚点找你。',
      ]);
    });

    test('accepts a JSON array for compatibility', () {
      expect(ReplySegmentParser.parse('["第一条。","第二条。"]'), ['第一条。', '第二条。']);
    });
  });
}
