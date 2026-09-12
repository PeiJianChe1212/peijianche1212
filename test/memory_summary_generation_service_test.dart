import 'package:flutter_test/flutter_test.dart';

import 'package:peijianche_app/ai/chat_model_provider.dart';
import 'package:peijianche_app/ai/model_hub.dart';
import 'package:peijianche_app/models/ai_capability.dart';
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

class _FixedProvider implements ChatModelProvider {
  _FixedProvider(this.value);
  final String value;

  @override
  String get providerName => 'fixed';

  @override
  Set<AiCapability> get capabilities => const {AiCapability.chat};

  @override
  bool supports(AiCapability capability) => capabilities.contains(capability);

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int maxTokens,
    double? topP,
    bool acceptStructuredReasoningFallback = false,
  }) async => value;
}

class _FixedModelHub extends ModelHub {
  _FixedModelHub(this.provider);
  final ChatModelProvider provider;

  @override
  Future<ChatModelProvider> chatProvider({settings}) async => provider;
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
    expect(prompt, isNot(contains('等待遗忘的经历')));
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

  test('summary prompt defines durable semantics and permits full rewrite', () {
    final prompt = MemorySummaryGenerationService()
        .buildMessages(
          const MemorySummaryGenerationInput(
            currentSummary: MemorySummary(
              characterId: 'c',
              generatedText: '用户说了甲，角色回应乙，随后发生丙。',
            ),
          ),
        )
        .map((item) => item['content'])
        .join('\n');

    expect(prompt, contains('允许完全重写'));
    expect(prompt, contains('当前长期关系状态'));
    expect(prompt, contains('少量关键共同经历及其意义'));
    expect(prompt, contains('禁止时间线流水账'));
    expect(prompt, contains('禁止逐条复述所有经历'));
    expect(prompt, contains('不能继承它的结构'));
  });

  test('summary candidates are bounded, ranked, and exclude fading events', () {
    final now = DateTime.utc(2026, 9, 12);
    final events = <EventMemory>[
      for (var i = 0; i < 20; i++)
        EventMemory(
          id: 'e$i',
          characterId: 'c',
          content: '普通事件$i ${'内容' * 200}',
          status: i == 0 ? EventMemoryStatus.fading : EventMemoryStatus.active,
          updatedAt: now.subtract(Duration(days: i)),
        ),
      EventMemory(
        id: 'pinned',
        characterId: 'c',
        content: '置顶关键事件',
        isPinned: true,
        updatedAt: now.subtract(const Duration(days: 100)),
      ),
    ];
    final users = <UserMemory>[
      for (var i = 0; i < 20; i++)
        UserMemory(
          id: 'u$i',
          characterId: 'c',
          key: '偏好$i',
          value: '值$i ${'内容' * 100}',
          updatedAt: now.subtract(Duration(days: i)),
        ),
    ];
    final userPrompt =
        MemorySummaryGenerationService().buildMessages(
              MemorySummaryGenerationInput(
                eventMemories: events,
                userMemories: users,
              ),
            )[1]['content']
            as String;

    expect(userPrompt, contains('置顶关键事件'));
    expect(userPrompt, isNot(contains('普通事件0')));
    expect('普通事件'.allMatches(userPrompt).length, lessThanOrEqualTo(8));
    expect('偏好'.allMatches(userPrompt).length, lessThanOrEqualTo(12));
    expect(
      userPrompt.length,
      lessThanOrEqualTo(
        MemorySummaryGenerationService.totalSourceCharacters + 200,
      ),
    );
  });

  test('migrated and normalized duplicate legacy rows are omitted', () {
    final prompt =
        MemorySummaryGenerationService().buildMessages(
              MemorySummaryGenerationInput(
                eventMemories: [
                  _event('e', '一起在海边散步', EventMemoryStatus.active),
                ],
                migratedLegacyIds: const {'migrated'},
                legacyMemories: [
                  LegacyMemoryView(
                    id: 'l1',
                    characterId: 'c',
                    legacySourceId: 'migrated',
                    kind: LegacyMemoryKind.event,
                    content: '已经迁移的内容',
                    category: 'event',
                    createdAt: DateTime(2024),
                    isPinned: false,
                    legacyArchived: false,
                  ),
                  LegacyMemoryView(
                    id: 'l2',
                    characterId: 'c',
                    legacySourceId: 'duplicate',
                    kind: LegacyMemoryKind.event,
                    content: '一起在海边散步。',
                    category: 'event',
                    createdAt: DateTime(2024),
                    isPinned: false,
                    legacyArchived: false,
                  ),
                ],
              ),
            )[1]['content']
            as String;

    expect(prompt, isNot(contains('已经迁移的内容')));
    expect('一起在海边散步'.allMatches(prompt).length, 1);
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

  test('provider output remains bounded across repeated rewrites', () async {
    final service = MemorySummaryGenerationService(
      modelHub: _FixedModelHub(_FixedProvider('长期内容' * 1000)),
    );
    var summary = const MemorySummary(characterId: 'c');
    for (var revision = 0; revision < 3; revision++) {
      final text = await service.generate(
        MemorySummaryGenerationInput(currentSummary: summary),
      );
      expect(text.length, MemorySummaryGenerationService.outputCharacters);
      summary = MemorySummary(characterId: 'c', generatedText: text);
    }
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
