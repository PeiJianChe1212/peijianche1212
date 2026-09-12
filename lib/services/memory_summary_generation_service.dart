import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/event_memory.dart';
import '../models/legacy_memory_view.dart';
import '../models/memory_summary.dart';
import '../models/user_memory.dart';

/// Input used when a user explicitly asks to update the long-term summary.
///
/// The lists are snapshots. This service does not load or mutate memory
/// storage, and the provider is called exactly once per [generate] call.
class MemorySummaryGenerationInput {
  const MemorySummaryGenerationInput({
    this.currentSummary,
    this.eventMemories = const [],
    this.userMemories = const [],
    this.legacyMemories = const [],
    this.migratedLegacyIds = const {},
  });

  final MemorySummary? currentSummary;
  final List<EventMemory> eventMemories;
  final List<UserMemory> userMemories;
  final List<LegacyMemoryView> legacyMemories;
  final Set<String> migratedLegacyIds;
}

abstract interface class MemorySummaryGenerationGateway {
  Future<String> generate(MemorySummaryGenerationInput input);
}

/// Generates a compact summary through the application's configured chat
/// provider. It is deliberately not tied to a particular vendor or model.
class MemorySummaryGenerationService implements MemorySummaryGenerationGateway {
  MemorySummaryGenerationService({http.Client? client, ModelHub? modelHub})
    : _modelHub = modelHub ?? ModelHub(client: client);

  final ModelHub _modelHub;

  static const int maximumEventCandidates = 8;
  static const int eventCharacters = 240;
  static const int maximumUserCandidates = 12;
  static const int userCharacters = 180;
  static const int maximumLegacyCandidates = 4;
  static const int legacyCharacters = 180;
  static const int currentSummaryCharacters = 1200;
  static const int totalSourceCharacters = 6000;
  static const int outputCharacters = 1200;

  /// Builds the provider messages, keeping implementation-only fields out of
  /// the prompt. Exposed for deterministic tests and preview controllers.
  List<Map<String, dynamic>> buildMessages(MemorySummaryGenerationInput input) {
    final lines = <String>[];
    var remaining = totalSourceCharacters;
    final selected = <String>{};

    void addSection(String title, Iterable<String> values, int itemLimit) {
      final kept = <String>[];
      for (final raw in values) {
        final value = _truncate(raw.trim(), itemLimit);
        final normalized = _normalize(value);
        if (value.isEmpty || normalized.isEmpty || !selected.add(normalized)) {
          continue;
        }
        final line = '- $value';
        final addition =
            (kept.isEmpty ? title.length + 3 + (lines.isEmpty ? 0 : 2) : 1) +
            line.length;
        if (addition > remaining) break;
        kept.add(line);
        remaining -= addition;
      }
      if (kept.isNotEmpty) lines.add('[$title]\n${kept.join('\n')}');
    }

    final summary = _truncate(
      input.currentSummary?.effectiveText ?? '',
      currentSummaryCharacters,
    );
    addSection('旧汇总参考（允许完全重写）', [summary], currentSummaryCharacters);

    final events =
        input.eventMemories
            .where(
              (item) =>
                  item.content.trim().isNotEmpty &&
                  item.status == EventMemoryStatus.active,
            )
            .toList()
          ..sort((a, b) {
            final pinned = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
            if (pinned != 0) return pinned;
            final recall = b.recallCount.compareTo(a.recallCount);
            if (recall != 0) return recall;
            final aTime = a.lastRecalledAt ?? a.updatedAt;
            final bTime = b.lastRecalledAt ?? b.updatedAt;
            return bTime.compareTo(aTime);
          });
    addSection(
      '候选关键共同经历',
      events.take(maximumEventCandidates).map((item) => item.content),
      eventCharacters,
    );

    final users =
        input.userMemories
            .where(
              (item) =>
                  item.status == UserMemoryStatus.active &&
                  item.displayText.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) {
            final pinned = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
            return pinned != 0 ? pinned : b.updatedAt.compareTo(a.updatedAt);
          });
    addSection(
      '关于用户的稳定认识',
      users.take(maximumUserCandidates).map((item) => item.displayText),
      userCharacters,
    );

    final legacy =
        input.legacyMemories
            .where(
              (item) =>
                  !item.legacyArchived &&
                  !input.migratedLegacyIds.contains(item.legacySourceId) &&
                  item.content.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) {
            final pinned = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
            return pinned != 0 ? pinned : b.createdAt.compareTo(a.createdAt);
          });
    addSection(
      '未迁移旧版记忆参考',
      legacy.take(maximumLegacyCandidates).map((item) => item.content),
      legacyCharacters,
    );

    final source = lines.isEmpty ? '（暂无可用的既有记忆。）' : lines.join('\n\n');
    return [
      {
        'role': 'system',
        'content':
            '你负责重写 PeiLink 的长期关系记忆。只保留当前长期关系状态、稳定相处模式、用户稳定偏好、重要约定、少量关键共同经历及其意义，以及明确的关系变化。旧汇总仅供核对事实，你可以完全重写，不能继承它的结构。不要编造或推断。禁止时间线流水账，禁止“用户说……角色回应……”式转述，禁止逐条复述所有经历，禁止为了覆盖输入硬塞事件，禁止保留没有长期价值的日常动作。只输出紧凑自然的纯文本，不要标题、JSON、Markdown、ID、状态、重要度或内部原因，全文不超过 $outputCharacters 个字符。',
      },
      {
        'role': 'user',
        'content':
            '根据以下有界候选重写长期记忆汇总。候选不是待逐项覆盖的清单；只选择真正具有长期价值且仍有依据的内容，合并重复，删除过时、低价值或无依据内容。只输出新的 summaryText。\n\n$source',
      },
    ];
  }

  @override
  Future<String> generate(MemorySummaryGenerationInput input) async {
    final provider = await _modelHub.chatProvider();
    final result = await provider.complete(
      messages: buildMessages(input),
      temperature: 0.2,
      maxTokens: 800,
    );
    final text = _truncate(result.trim(), outputCharacters);
    if (text.isEmpty) {
      throw const FormatException('模型返回了空的记忆汇总。');
    }
    return text;
  }

  static String _truncate(String value, int maximum) {
    if (value.length <= maximum) return value;
    return '${value.substring(0, maximum - 1).trimRight()}…';
  }

  static String _normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r"[\s，。！？、,.!?~～“”'‘’（）()\[\]【】:_：-]"),
    '',
  );
}
