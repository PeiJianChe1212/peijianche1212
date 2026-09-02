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
  });

  final MemorySummary? currentSummary;
  final List<EventMemory> eventMemories;
  final List<UserMemory> userMemories;
  final List<LegacyMemoryView> legacyMemories;
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

  /// Builds the provider messages, keeping implementation-only fields out of
  /// the prompt. Exposed for deterministic tests and preview controllers.
  List<Map<String, dynamic>> buildMessages(MemorySummaryGenerationInput input) {
    final lines = <String>[];
    final summary = input.currentSummary?.effectiveText ?? '';
    if (summary.isNotEmpty) {
      lines.add('[当前长期汇总]\n$summary');
    }

    final events = input.eventMemories
        .where(
          (item) =>
              item.content.trim().isNotEmpty &&
              item.status != EventMemoryStatus.forgotten,
        )
        .map((item) => '- ${item.content.trim()}');
    if (events.isNotEmpty) {
      lines.add('[共同经历]\n${events.join('\n')}');
    }

    final users = input.userMemories
        .where(
          (item) =>
              item.status == UserMemoryStatus.active &&
              item.displayText.trim().isNotEmpty,
        )
        .map((item) => '- ${item.displayText.trim()}');
    if (users.isNotEmpty) {
      lines.add('[关于用户的稳定认识]\n${users.join('\n')}');
    }

    final legacy = input.legacyMemories
        .where((item) => !item.legacyArchived && item.content.trim().isNotEmpty)
        .map((item) => '- ${item.content.trim()}');
    if (legacy.isNotEmpty) {
      lines.add('[旧版记忆参考]\n${legacy.join('\n')}');
    }

    final source = lines.isEmpty ? '（暂无可用的既有记忆。）' : lines.join('\n\n');
    return [
      {
        'role': 'system',
        'content':
            '你负责整理长期记忆汇总。只根据输入中明确表达的事实，输出紧凑、自然的纯文本 summary。不要编造、推断或写成小说，不要输出标题、JSON、Markdown、ID、状态、重要度或内部原因。',
      },
      {
        'role': 'user',
        'content':
            '请更新以下长期记忆汇总，保留仍然有效的认识，合并重复内容，删除无依据的推断。只输出新的 summaryText。\n\n$source',
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
    final text = result.trim();
    if (text.isEmpty) {
      throw const FormatException('模型返回了空的记忆汇总。');
    }
    return text;
  }
}
