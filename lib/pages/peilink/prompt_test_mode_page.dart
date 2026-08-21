import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/peilink_runtime.dart';
import '../../models/prompt_test_mode.dart';
import '../../models/prompt_experiment_mode.dart';
import '../../models/api_settings.dart';
import '../../services/prompt_test_mode_service.dart';
import '../../services/prompt_experiment_mode_service.dart';
import '../../services/api_settings_storage_service.dart';
import '../../services/prompt_test_snapshot_service.dart';

class PromptTestModePage extends StatefulWidget {
  const PromptTestModePage({super.key});

  @override
  State<PromptTestModePage> createState() => _PromptTestModePageState();
}

class _PromptTestModePageState extends State<PromptTestModePage> {
  final _service = PromptTestModeService();
  final _experimentService = PromptExperimentModeService();
  PromptTestMode _mode = PromptTestMode.peilinkFull;
  PromptExperimentMode? _experiment;
  AIProvider _provider = AIProvider.deepseek;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.load(),
      _experimentService.load(),
      ApiSettingsStorageService().loadSettings(),
    ]);
    if (!mounted) return;
    setState(() {
      _mode = results[0] as PromptTestMode;
      _experiment = results[1] as PromptExperimentMode?;
      _provider = (results[2] as ApiSettings).provider;
      _loading = false;
    });
  }

  Future<void> _select(PromptTestMode? mode) async {
    if (mode == null || (mode == _mode && _experiment == null)) return;
    await _service.save(mode);
    await _experimentService.clear();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _experiment = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已切换为${mode.label}，从下一条模型回复开始生效。')));
  }

  Future<void> _selectExperiment(PromptExperimentMode? experiment) async {
    if (experiment == null || experiment == _experiment) return;
    if (experiment.requiredProvider != _provider) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${experiment.code} 需要 ${experiment.requiredProvider.label}；当前是 ${_provider.label}。',
          ),
        ),
      );
      return;
    }
    await _experimentService.save(experiment);
    if (!mounted) return;
    setState(() => _experiment = experiment);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已启用 ${experiment.description}，从下一条请求开始生效。')),
    );
  }

  void _showPrompt() {
    final snapshot = PromptTestSnapshotService.latest;
    final matchesMode =
        snapshot?.mode == _mode && snapshot?.experiment == _experiment;
    final text = matchesMode ? snapshot!.displayText : '';
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: SizedBox(
          width: 760,
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '当前最终 Prompt',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _experiment?.description ?? _mode.label,
                            style: const TextStyle(color: Color(0xFF6E5BD7)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '复制',
                      onPressed: text.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: text),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Prompt 已复制')),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy_all_outlined),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: text.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Text(
                            '当前模式还没有生成过模型请求。\n请回到单聊发送一条消息，再来查看实际发送顺序。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              height: 1.6,
                            ),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: SelectableText(
                          text,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.55,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PeiLinkRuntime.developerToolsEnabled) {
      return const Scaffold(body: Center(child: Text('该功能仅在开发者版可用。')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Prompt 测试模式')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 2, 4, 14),
                  child: Text(
                    '只改变单聊最终发送给文字模型的 Prompt。不会清空聊天记录，也不会修改角色、记忆或其他模块数据。',
                    style: TextStyle(color: Colors.black54, height: 1.5),
                  ),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: RadioGroup<PromptTestMode>(
                    groupValue: _experiment == null ? _mode : null,
                    onChanged: _select,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < PromptTestMode.values.length;
                          index++
                        ) ...[
                          RadioListTile<PromptTestMode>(
                            value: PromptTestMode.values[index],
                            title: Text(PromptTestMode.values[index].label),
                            subtitle: Text(
                              PromptTestMode.values[index].description,
                            ),
                          ),
                          if (index < PromptTestMode.values.length - 1)
                            const Divider(height: 1, indent: 56),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '模块级实验 · 当前 Provider：${_provider.label}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '实验只启用卡片列出的模块。Provider 不匹配的实验不可选择，请到 API 设置切换并保存后返回。',
                  style: TextStyle(color: Colors.black54, height: 1.45),
                ),
                const SizedBox(height: 10),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: RadioGroup<PromptExperimentMode>(
                    groupValue: _experiment,
                    onChanged: _selectExperiment,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < PromptExperimentMode.values.length;
                          index++
                        ) ...[
                          Builder(
                            builder: (context) {
                              final item = PromptExperimentMode.values[index];
                              final compatible =
                                  item.requiredProvider == _provider;
                              return RadioListTile<PromptExperimentMode>(
                                value: item,
                                enabled: compatible,
                                title: Text(item.description),
                                subtitle: Text(
                                  compatible
                                      ? '启用：${item.enabledModules.join('、')}'
                                      : '需要 ${item.requiredProvider.label}',
                                ),
                              );
                            },
                          ),
                          if (index < PromptExperimentMode.values.length - 1)
                            const Divider(height: 1, indent: 56),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _showPrompt,
                  icon: const Icon(Icons.data_object_rounded),
                  label: const Text('查看当前最终 Prompt'),
                ),
                const SizedBox(height: 10),
                const Text(
                  '预览内容来自最近一次真正准备发送给模型的请求，并按 system、历史消息等实际顺序展示。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45, fontSize: 12),
                ),
              ],
            ),
    );
  }
}
