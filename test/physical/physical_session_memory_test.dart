import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/physical/physical_session_memory.dart';

void main() {
  PhysicalSessionTurn turn(int index, {int textLength = 1}) =>
      PhysicalSessionTurn(
        userTranscript: List.filled(textLength, '用').join(),
        assistantSpokenText: '答$index',
        completedAt: DateTime(2026, 8, 31, 12, index),
      );

  test('preserves turn and chat message order', () {
    final memory = PhysicalSessionMemory();
    memory.add(
      PhysicalSessionTurn(
        userTranscript: '我刚买了个蛋糕',
        assistantSpokenText: '什么味的？',
        completedAt: DateTime(2026, 8, 31, 12),
      ),
    );
    memory.add(
      PhysicalSessionTurn(
        userTranscript: '草莓的',
        assistantSpokenText: '听起来不错。',
        completedAt: DateTime(2026, 8, 31, 12, 1),
      ),
    );

    expect(memory.turnCount, 2);
    expect(memory.toChatMessages().map((item) => item.content), [
      '我刚买了个蛋糕',
      '什么味的？',
      '草莓的',
      '听起来不错。',
    ]);
    expect(
      memory.toChatMessages().every((item) => item.source == 'physical'),
      isTrue,
    );
  });

  test('keeps only the newest eight complete turns', () {
    final memory = PhysicalSessionMemory();
    for (var index = 0; index < 10; index++) {
      memory.add(turn(index));
    }

    expect(memory.turnCount, 8);
    expect(memory.turns.first.assistantSpokenText, '答2');
    expect(memory.turns.last.assistantSpokenText, '答9');
  });

  test('trims oldest complete turns at the 4000 character limit', () {
    final memory = PhysicalSessionMemory();
    memory.add(turn(1, textLength: 2200));
    memory.add(turn(2, textLength: 2200));

    expect(memory.turnCount, 1);
    expect(memory.turns.single.assistantSpokenText, '答2');
  });

  test('clear removes all in-memory turns', () {
    final memory = PhysicalSessionMemory()..add(turn(1));
    memory.clear();
    expect(memory.turns, isEmpty);
    expect(memory.turnCount, 0);
  });
}
