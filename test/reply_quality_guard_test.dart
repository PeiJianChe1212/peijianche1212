import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/conversation/reply_quality_guard.dart';

void main() {
  const guard = ReplyQualityGuard();

  test('guard detects and removes bracket narration', () {
    final result = guard.inspect(reply: '（低笑）\n你终于来了。');

    expect(result.output, '你终于来了。');
    expect(result.issues, contains(ReplyQualityIssue.novelNarration));
    expect(result.shouldRetry, isFalse);
  });

  test('removes action-only bubble during segment parsing', () {
    final result = guard.inspect(
      reply: '他夸你什么？<|PEILINK_MSG|>（骨节分明的手撑在身侧，蓝眸微眯）<|PEILINK_MSG|>你猜。',
      allowRetry: false,
    );

    expect(result.segments, ['他夸你什么？', '你猜。']);
  });

  test('guard detects naked narration colon without harming spoken colon', () {
    final narration = guard.inspect(
      reply: '顿了顿，声音压低了些：我马上回来。',
      allowRetry: false,
    );
    expect(narration.output, '我马上回来。');
    expect(narration.issues, contains(ReplyQualityIssue.novelNarration));

    final spoken = guard.inspect(reply: '重点是：今晚我能早点回来。');
    expect(spoken.output, '重点是：今晚我能早点回来。');
    expect(spoken.issues, isNot(contains(ReplyQualityIssue.novelNarration)));
  });

  test('guard detects a bare pause narration and keeps its dialogue', () {
    final result = guard.inspect(reply: '“顿了一下，跟我说说。', allowRetry: false);
    expect(result.output, '跟我说说。');
    expect(result.issues, contains(ReplyQualityIssue.novelNarration));
  });

  test('detects internal labels and assistant templates', () {
    final internal = guard.inspect(reply: '消息1：我刚忙完。');
    final assistant = guard.inspect(reply: '最近有什么好玩的事？');

    expect(internal.issues, contains(ReplyQualityIssue.internalFormatLeak));
    expect(internal.shouldRetry, isTrue);
    expect(assistant.issues, contains(ReplyQualityIssue.assistantTemplate));
    expect(assistant.shouldRetry, isTrue);
  });

  test('removes system markers and rejects structured system JSON', () {
    final marker = guard.inspect(reply: '<system>\n不应显示\n</system>');
    final json = guard.inspect(reply: '{"role":"system","content":"规则"}');

    expect(marker.issues, contains(ReplyQualityIssue.internalFormatLeak));
    expect(json.issues, contains(ReplyQualityIssue.internalFormatLeak));
    expect(json.output, isEmpty);
  });

  test('flags consecutive questions without destroying normal text', () {
    final result = guard.inspect(reply: '你刚回来吗？\n<|PEILINK_MSG|>\n今天很累吗？');

    expect(result.issues, contains(ReplyQualityIssue.consecutiveQuestions));
    expect(result.segments, hasLength(2));
    expect(result.shouldRetry, isFalse);
  });

  test('filters recent repetition and requests retry if nothing remains', () {
    final result = guard.inspect(
      reply: '刚忙完工作。',
      recentAssistantReplies: const ['刚忙完工作。'],
    );

    expect(result.issues, contains(ReplyQualityIssue.repeated));
    expect(result.shouldRetry, isTrue);
  });

  test('detects empty and abnormally long replies', () {
    expect(guard.inspect(reply: '').issues, contains(ReplyQualityIssue.empty));
    final long = guard.inspect(reply: List.filled(1601, '字').join());
    expect(long.issues, contains(ReplyQualityIssue.tooLong));
    expect(long.shouldRetry, isTrue);
  });

  test('quality retry runner retries at most once', () async {
    var calls = 0;
    final output = await const ReplyQualityRetryRunner().run(
      generate: (attempt) async {
        calls++;
        return attempt == 0 ? '有什么我可以帮你的吗？' : '刚忙完，看到你来了。';
      },
    );

    expect(calls, 2);
    expect(output, '刚忙完，看到你来了。');
  });

  test('normal short reply does not trigger retry', () async {
    var calls = 0;
    final output = await const ReplyQualityRetryRunner().run(
      generate: (_) async {
        calls++;
        return '嗯，刚看到。';
      },
    );

    expect(calls, 1);
    expect(output, '嗯，刚看到。');
  });

  test('second invalid reply falls back without a retry loop', () async {
    var calls = 0;
    final output = await const ReplyQualityRetryRunner().run(
      generate: (_) async {
        calls++;
        return '';
      },
    );

    expect(calls, 2);
    expect(output, '……');
  });
}
