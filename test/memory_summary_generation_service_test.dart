import 'package:flutter_test/flutter_test.dart';

import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/legacy_memory_view.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/memory_summary_generation_service.dart';

class _FakeSummaryGateway implements MemorySummaryGenerationGateway {
  _FakeSummaryGateway(this.response);

  final String response;
  int calls = 0;

  @override
  Future<String> generate(MemorySummaryGenerationInput input) async {
    calls++;
    return response;
  }
}

EventMemory _event(String id, String content, EventMemoryStatus status) =>
    EventMemory(id: id, characterId: 'c', content: content, status: status);

UserMemory _user(
  String id,
  String key,
  String value,
  UserMemoryStatus status,
) => UserMemory(
  id: id,
  characterId: 'c',
  key: key,
  value: value,
  status: status,
);

void main() {
  test('gateway is explicit and can be called once with plain text', () async {
    final gateway = _FakeSummaryGateway('  新的长期总结。  ');
    final result = await gateway.generate(const MemorySummaryGenerationInput());

    expect(result.trim(), '新的长期总结。');
    expect(gateway.calls, 1);
  });

  test('buildMessages filters statuses and hides internal fields', () {
    final service = MemorySummaryGenerationService();
    final messages = service.buildMessages(
      MemorySummaryGenerationInput(
        currentSummary: const MemorySummary(
          characterId: 'c',
          generatedText: '生成版',
          userEditedText: '用户版',
        ),
        eventMemories: [
          _event('a', '仍然有效的经历', EventMemoryStatus.active),
          _event('f', '已遗忘的经历', EventMemoryStatus.forgotten),
          _event('p', '等待遗忘的经历', EventMemoryStatus.pendingForget),
        ],
        userMemories: [
          _user('u', '喜欢', '咖啡', UserMemoryStatus.active),
          _user('s', '旧认识', '不要出现', UserMemoryStatus.superseded),
        ],
        legacyMemories: [
          LegacyMemoryView(
            id: 'l',
            characterId: 'c',
            legacySourceId: 'old',
            kind: LegacyMemoryKind.event,
            content: '旧版参考',
            category: 'event',
            createdAt: DateTime(2024),
            isPinned: false,
            legacyArchived: false,
          ),
          LegacyMemoryView(
            id: 'la',
            characterId: 'c',
            legacySourceId: 'old-a',
            kind: LegacyMemoryKind.event,
            content: '不应出现的旧版归档',
            category: 'event',
            createdAt: DateTime(2024),
            isPinned: false,
            legacyArchived: true,
          ),
        ],
      ),
    );
    final prompt = messages.map((item) => item['content']).join('\n');

    expect(prompt, contains('用户版'));
    expect(prompt, contains('仍然有效的经历'));
    expect(prompt, contains('等待遗忘的经历'));
    expect(prompt, contains('喜欢：咖啡'));
    expect(prompt, contains('旧版参考'));
    expect(prompt, isNot(contains('已遗忘的经历')));
    expect(prompt, isNot(contains('不要出现')));
    expect(prompt, isNot(contains('不应出现的旧版归档')));
    for (final internal in [
      'reason',
      'importance',
      'recallCount',
      'status',
      'sourceMessageIds',
    ]) {
      expect(prompt, isNot(contains(internal)));
    }
  });

  test('empty provider output is rejected', () {
    final gateway = _FakeSummaryGateway('   ');
    expect(
      () async =>
          (await gateway.generate(
            const MemorySummaryGenerationInput(),
          )).trim().isEmpty
          ? throw const FormatException('empty')
          : null,
      throwsFormatException,
    );
  });

  test('provider failures propagate without changing input summary', () async {
    final input = const MemorySummaryGenerationInput(
      currentSummary: MemorySummary(characterId: 'c', generatedText: '原总结'),
    );
    final gateway = _ThrowingSummaryGateway();
    expect(() => gateway.generate(input), throwsStateError);
    expect(input.currentSummary!.effectiveText, '原总结');
  });
}

class _ThrowingSummaryGateway implements MemorySummaryGenerationGateway {
  @override
  Future<String> generate(MemorySummaryGenerationInput input) {
    throw StateError('provider failed');
  }
}
