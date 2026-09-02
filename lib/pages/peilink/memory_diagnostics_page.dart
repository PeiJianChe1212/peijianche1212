import 'package:flutter/material.dart';

import '../../config/peilink_runtime.dart';
import '../../models/ai_character.dart';
import '../../models/event_memory.dart';
import '../../models/user_memory.dart';
import '../../services/character_registry_service.dart';
import '../../services/memory_diagnostics_controller.dart';
import '../../theme/app_theme_background.dart';

class MemoryDiagnosticsPage extends StatefulWidget {
  const MemoryDiagnosticsPage({super.key});
  @override
  State<MemoryDiagnosticsPage> createState() => _MemoryDiagnosticsPageState();
}

class _MemoryDiagnosticsPageState extends State<MemoryDiagnosticsPage> {
  final controller = const MemoryDiagnosticsController();
  List<AiCharacter> characters = const [];
  String? selectedId;
  MemoryDiagnosticsSnapshot? snapshot;
  bool loading = true;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final loaded = await CharacterRegistryService().loadCharacters();
    if (!mounted) return;
    characters = loaded;
    selectedId = loaded.isEmpty ? null : loaded.first.id;
    await _read();
  }

  Future<void> _read() async {
    final id = selectedId;
    if (id == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final value = await controller.read(id);
    if (mounted) {
      setState(() {
        snapshot = value;
        loading = false;
      });
    }
  }

  Future<void> _check() async {
    final id = selectedId;
    if (id == null || checking) return;
    setState(() => checking = true);
    final outcome = await controller.checkAutoMemory(id);
    await _read();
    if (mounted) {
      setState(() => checking = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('检查结果：${outcome.name}')));
    }
  }

  String _date(DateTime? value) => value?.toLocal().toString() ?? '—';
  String _count(EventMemoryStatus status) =>
      '${snapshot?.events.where((e) => e.status == status).length ?? 0}';
  String _userCount(UserMemoryStatus status) =>
      '${snapshot?.users.where((e) => e.status == status).length ?? 0}';

  @override
  Widget build(BuildContext context) {
    if (!PeiLinkRuntime.developerToolsEnabled) {
      return const Scaffold(body: Center(child: Text('该功能仅在开发者版可用。')));
    }
    final s = snapshot;
    final extraction = selectedId == null
        ? null
        : controller.extraction(selectedId!);
    final retrieval = selectedId == null
        ? null
        : controller.retriever(selectedId!);
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Memory 诊断'),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(onPressed: _read, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedId,
                    decoration: const InputDecoration(labelText: '当前角色'),
                    items: characters
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      setState(() {
                        selectedId = value;
                        loading = true;
                      });
                      await _read();
                    },
                  ),
                  const SizedBox(height: 12),
                  _card('自动记忆状态', [
                    _row(
                      'autoMemoryEnabled',
                      '${s?.settings.autoMemoryEnabled ?? false}',
                    ),
                    _row('正在执行', '${s?.isRunning ?? false}'),
                    _row(
                      'lastProcessedMessageId',
                      s?.state.lastProcessedMessageId ?? '—',
                    ),
                    _row('lastProcessedAt', _date(s?.state.lastProcessedAt)),
                    _row(
                      'lastSuccessfulExtractionAt',
                      _date(s?.state.lastSuccessfulExtractionAt),
                    ),
                    _row('lastFailureAt', _date(s?.state.lastFailureAt)),
                    _row(
                      'lastFailedMessageId',
                      s?.state.lastFailedMessageId ?? '—',
                    ),
                    _row('未处理有效消息', '${s?.unprocessedMessages.length ?? 0}'),
                    _row('未处理 user 消息', '${s?.unprocessedUserMessages ?? 0}'),
                    _row('达到阈值', '${s?.reachesThreshold ?? false}'),
                    _row('失败冷却中', '${s?.coolingDown ?? false}'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: checking ? null : _check,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(checking ? '检查中…' : '检查自动记忆'),
                    ),
                  ]),
                  _card('Memory 数量', [
                    _row('active Event', _count(EventMemoryStatus.active)),
                    _row('fading Event', _count(EventMemoryStatus.fading)),
                    _row(
                      'pendingForget Event',
                      _count(EventMemoryStatus.pendingForget),
                    ),
                    _row(
                      'forgotten Event',
                      _count(EventMemoryStatus.forgotten),
                    ),
                    _row('active User', _userCount(UserMemoryStatus.active)),
                    _row(
                      'superseded User',
                      _userCount(UserMemoryStatus.superseded),
                    ),
                    _row(
                      'archived User',
                      _userCount(UserMemoryStatus.archived),
                    ),
                    _row('Legacy', '${s?.legacy.length ?? 0}'),
                    _row(
                      'Summary 存在',
                      '${s?.summary.effectiveText.isNotEmpty ?? false}',
                    ),
                  ]),
                  _card(
                    '最近一次 Extraction',
                    extraction == null
                        ? [const Text('暂无报告')]
                        : [
                            _row('时间', _date(extraction.triggeredAt)),
                            _row('result', extraction.result),
                            _row(
                              'batch / user',
                              '${extraction.batchMessageCount} / ${extraction.userMessageCount}',
                            ),
                            _row(
                              'first / last',
                              '${extraction.firstMessageId ?? '—'} / ${extraction.lastMessageId ?? '—'}',
                            ),
                            _row('provider', extraction.providerName),
                            _row(
                              'Event 候选 / 写入 / 去重',
                              '${extraction.eventCandidateCount} / ${extraction.eventWrittenCount} / ${extraction.eventDeduplicatedCount}',
                            ),
                            _row(
                              'User 候选 / 新增 / 更新',
                              '${extraction.userCandidateCount} / ${extraction.userCreatedCount} / ${extraction.userUpdatedCount}',
                            ),
                            _row(
                              'cursorAdvanced',
                              '${extraction.cursorAdvanced}',
                            ),
                            _row('failureType', extraction.failureType ?? '—'),
                            _row(
                              'rawResponseShape',
                              extraction.rawResponseShape ?? '—',
                            ),
                            _row(
                              'parseOutcome',
                              extraction.parseOutcome ?? '—',
                            ),
                            ExpansionTile(
                              title: const Text('提取结果'),
                              children: [
                                ...extraction.eventTexts.map(
                                  (e) => ListTile(title: Text('Event：$e')),
                                ),
                                ...extraction.userTexts.map(
                                  (e) => ListTile(title: Text('User：$e')),
                                ),
                              ],
                            ),
                          ],
                  ),
                  _card(
                    '最近一次 Retriever',
                    retrieval == null
                        ? [const Text('暂无报告')]
                        : [
                            _row('query 长度', '${retrieval.queryLength}'),
                            _row('recallIntent', '${retrieval.recallIntent}'),
                            _row(
                              'Event / User / Legacy 候选',
                              '${retrieval.eventCandidates} / ${retrieval.userCandidates} / ${retrieval.legacyCandidates}',
                            ),
                            _row(
                              '最终 Event / User / Legacy',
                              '${retrieval.selectedEventCount} / ${retrieval.selectedUserCount} / ${retrieval.legacyFallbackCount}',
                            ),
                            _row('Summary 注入', '${retrieval.summaryInjected}'),
                            _row(
                              '角色用户资料注入',
                              '${retrieval.characterUserProfileInjected}',
                            ),
                            _row(
                              'Context 字符',
                              '${retrieval.contextCharacters}',
                            ),
                            _row(
                              'injectedEventIds',
                              retrieval.injectedEventIds.join(', '),
                            ),
                            _row(
                              'Recall 成功 / 失败',
                              '${retrieval.recallSuccessCount} / ${retrieval.recallFailureCount}',
                            ),
                            ...retrieval.eventItems.map(
                              (e) => ListTile(
                                dense: true,
                                title: Text(e.id),
                                subtitle: Text(
                                  '${e.status} · score=${e.score.toStringAsFixed(3)} · current=${e.currentQueryContribution.toStringAsFixed(3)} · context=${e.contextExpansionContribution.toStringAsFixed(3)} · ${e.reason.name}',
                                ),
                              ),
                            ),
                          ],
                  ),
                  _card('Event 生命周期', [
                    for (final e in s?.events ?? const <EventMemory>[])
                      ListTile(
                        title: Text(e.id),
                        subtitle: Text(
                          'status=${e.status.name}  created=${_date(e.createdAt)}\nlastRecalled=${_date(e.lastRecalledAt)}  recallCount=${e.recallCount}  pinned=${e.isPinned}\neffectiveAge=${controller.effectiveAge(e, DateTime.now()).inDays} 天  nextBoundary≈${controller.daysToNextBoundary(e, DateTime.now())?.toString() ?? '—'} 天',
                        ),
                      ),
                  ]),
                ],
              ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
  Widget _row(String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 190,
          child: Text(key, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}
