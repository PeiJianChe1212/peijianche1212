import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/auto_memory_extraction_service.dart';
import '../services/memory_center_controller.dart';
import '../services/memory_content_boundary.dart';
import '../services/memory_source_resolver.dart';

class MemoryReprocessingPage extends StatefulWidget {
  const MemoryReprocessingPage({super.key, required this.controller});
  final MemoryCenterController controller;
  @override
  State<MemoryReprocessingPage> createState() => _MemoryReprocessingPageState();
}

class _MemoryReprocessingPageState extends State<MemoryReprocessingPage> {
  List<ChatMessage>? messages;
  final selected = <String>{};
  bool running = false;
  String result = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final loaded = await widget.controller.loadReprocessingMessages();
      if (mounted) setState(() => messages = loaded);
    } catch (_) {
      if (mounted) {
        setState(() {
          messages = [];
          result = '聊天记录暂时不可用';
        });
      }
    }
  }

  int get characters => (messages ?? <ChatMessage>[])
      .where((m) => selected.contains(m.id))
      .fold(0, (sum, m) => sum + MemoryContentBoundary.sourceCharacters(m));
  bool get valid =>
      selected.isNotEmpty &&
      selected.length <= AutoMemoryExtractionService.reprocessingMessageLimit &&
      characters <= AutoMemoryExtractionService.reprocessingCharacterLimit;
  Future<void> reprocess() async {
    if (!valid || running) return;
    setState(() {
      running = true;
      result = '';
    });
    try {
      final outcome = await widget.controller.reprocessMessages(
        selected.toList(),
      );
      if (!mounted) return;
      setState(
        () => result = switch (outcome) {
          MemoryReprocessingOutcome.success => '整理完成，已有记忆和保护规则仍然保留',
          MemoryReprocessingOutcome.empty => '这段聊天没有整理出新的记忆',
          MemoryReprocessingOutcome.invalidRange => '范围过大，请减少选择的消息',
          MemoryReprocessingOutcome.sourceUnavailable => '部分原始消息已不可用，请返回后重新选择',
          MemoryReprocessingOutcome.alreadyRunning => '记忆正在整理，请稍后再试',
          MemoryReprocessingOutcome.failed => '整理失败，请稍后主动重试',
        },
      );
    } catch (_) {
      if (mounted) setState(() => result = '整理失败，请稍后主动重试');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('重新整理聊天记录')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '从最近 100 条中选择要重新整理的原消息。每次最多 16 条、12,000 字符（含视觉描述）；确认后进行一次 AI 整理。',
          ),
        ),
        Text('已选 ${selected.length} 条 · $characters 字符'),
        if (characters > AutoMemoryExtractionService.reprocessingCharacterLimit)
          const Text('范围过大，请缩小范围'),
        Expanded(
          child: messages == null
              ? const Center(child: CircularProgressIndicator())
              : messages!.isEmpty
              ? const Center(child: Text('没有可重新整理的聊天记录'))
              : ListView.builder(
                  itemCount: messages!.length,
                  itemBuilder: (_, index) {
                    final message = messages![index];
                    return CheckboxListTile(
                      key: ValueKey('reprocess-${message.id}'),
                      value: selected.contains(message.id),
                      title: Text(
                        MemorySourceResolver.shortText(message.content).isEmpty
                            ? '图片消息'
                            : MemorySourceResolver.shortText(message.content),
                      ),
                      subtitle: Text(
                        '${message.role == 'user' ? '用户' : '角色'} · ${message.createdAt.toLocal().toString().split('.').first}',
                      ),
                      onChanged:
                          running ||
                              (!selected.contains(message.id) &&
                                  selected.length >=
                                      AutoMemoryExtractionService
                                          .reprocessingMessageLimit)
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  selected.add(message.id);
                                } else {
                                  selected.remove(message.id);
                                }
                              });
                            },
                    );
                  },
                ),
        ),
        if (result.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(result)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: valid && !running ? reprocess : null,
              child: Text(running ? '正在整理…' : '确认整理选中的消息'),
            ),
          ),
        ),
      ],
    ),
  );
}
