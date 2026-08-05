import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/services/transient_event_reply_guard.dart';

void main() {
  test('red packet event adds a current user turn without an amount', () async {
    late List<Map<String, dynamic>> sentMessages;

    final reply = await TransientEventReplyGuard.completeWithEmptyReplyFallback(
      messages: const [
        {'role': 'system', 'content': 'character context'},
      ],
      complete: (messages) async {
        sentMessages = messages;
        return 'natural reply';
      },
    );

    expect(reply, 'natural reply');
    expect(sentMessages.last['role'], 'user');
    expect(sentMessages.last['content'], contains('red packet'));
    expect(sentMessages.last['content'], isNot(contains('520')));
  });

  test('empty event reply retries once and does not throw', () async {
    var attempts = 0;

    final reply = await TransientEventReplyGuard.completeWithEmptyReplyFallback(
      messages: const [],
      complete: (_) async {
        attempts++;
        throw const FormatException('API 返回了空回复');
      },
      localFallback: () => '角色化兜底回复',
    );

    expect(reply, '角色化兜底回复');
    expect(attempts, 2);
  });

  test('fallback can recover with a reply on the second request', () async {
    var attempts = 0;

    final reply = await TransientEventReplyGuard.completeWithEmptyReplyFallback(
      messages: const [],
      complete: (_) async => ++attempts == 1 ? '' : 'recovered reply',
    );

    expect(reply, 'recovered reply');
    expect(attempts, 2);
  });
}
