import 'package:flutter/material.dart';

import 'api_settings_page.dart';
import 'character_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.openingMessage,
    required this.conversationMode,
    required this.temperature,
    required this.replyLength,
    required this.initiative,
    required this.intimacy,
    required this.tsundere,
    required this.proactiveEnabled,
    required this.lateNightMessages,
    required this.maxProactivePerDay,
    required this.onSaveSettings,
  });

  final String openingMessage;
  final String conversationMode;
  final double temperature;
  final String replyLength;
  final double initiative;
  final double intimacy;
  final double tsundere;
  final bool proactiveEnabled;
  final bool lateNightMessages;
  final int maxProactivePerDay;

  final Future<void> Function({
    required String openingMessage,
    required String conversationMode,
    required double temperature,
    required String replyLength,
    required double initiative,
    required double intimacy,
    required double tsundere,
    required bool proactiveEnabled,
    required bool lateNightMessages,
    required int maxProactivePerDay,
  })
  onSaveSettings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _openingController;
  late String _conversationMode;
  late double _temperature;
  late String _replyLength;
  late double _initiative;
  late double _intimacy;
  late double _tsundere;
  late bool _proactiveEnabled;
  late bool _lateNightMessages;
  late int _maxProactivePerDay;

  bool _isSaving = false;

  static const Map<String, String> _modeTitles = {
    'basic': '日常模式',
    'heart': '心动模式',
    'delicate': '细腻模式',
    'long': '长聊模式',
    'deep': '认真模式',
  };

  static const Map<String, String> _modeDescriptions = {
    'basic': '像平时私聊一样自然，稳定又生活化',
    'heart': '亲密感更明显，但不强行撒糖',
    'delicate': '更留意措辞、情绪和微小变化',
    'long': '更愿意把话题接下去，适合沉浸聊天',
    'deep': '讨论复杂问题时更认真、更有条理',
  };

  static const Map<String, String> _lengthTitles = {
    'short': '简短',
    'standard': '适中',
    'long': '偏长',
  };

  @override
  void initState() {
    super.initState();
    _openingController = TextEditingController(text: widget.openingMessage);
    _conversationMode = widget.conversationMode;
    _temperature = widget.temperature;
    _replyLength = widget.replyLength;
    _initiative = widget.initiative;
    _intimacy = widget.intimacy;
    _tsundere = widget.tsundere;
    _proactiveEnabled = widget.proactiveEnabled;
    _lateNightMessages = widget.lateNightMessages;
    _maxProactivePerDay = widget.maxProactivePerDay;
  }

  @override
  void dispose() {
    _openingController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;

    final openingMessage = _openingController.text.trim();
    if (openingMessage.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('开场白不能为空')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      await widget.onSaveSettings(
        openingMessage: openingMessage,
        conversationMode: _conversationMode,
        temperature: _temperature,
        replyLength: _replyLength,
        initiative: _initiative,
        intimacy: _intimacy,
        tsundere: _tsundere,
        proactiveEnabled: _proactiveEnabled,
        lateNightMessages: _lateNightMessages,
        maxProactivePerDay: _maxProactivePerDay,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('裴简澈的聊天状态已保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _applyModePreset(String mode) {
    setState(() {
      _conversationMode = mode;
      switch (mode) {
        case 'heart':
          _temperature = 0.74;
          _replyLength = 'standard';
          _initiative = 0.72;
          _intimacy = 0.72;
          _tsundere = 0.58;
          break;
        case 'delicate':
          _temperature = 0.70;
          _replyLength = 'standard';
          _initiative = 0.62;
          _intimacy = 0.60;
          _tsundere = 0.48;
          break;
        case 'long':
          _temperature = 0.72;
          _replyLength = 'long';
          _initiative = 0.72;
          _intimacy = 0.55;
          _tsundere = 0.58;
          break;
        case 'deep':
          _temperature = 0.62;
          _replyLength = 'long';
          _initiative = 0.55;
          _intimacy = 0.42;
          _tsundere = 0.35;
          break;
        default:
          _temperature = 0.70;
          _replyLength = 'standard';
          _initiative = 0.58;
          _intimacy = 0.50;
          _tsundere = 0.62;
      }
    });
  }

  Future<void> _showModeDialog() async {
    final selectedMode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    '相处状态',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Text(
                    '选择状态会自动调整自由发挥、主动程度、亲密表达、嘴硬程度和回复长度，之后仍可手动微调。',
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                ),
                ..._modeTitles.entries.map((entry) {
                  final isSelected = entry.key == _conversationMode;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? Theme.of(sheetContext).colorScheme.primary
                          : Colors.black45,
                    ),
                    title: Text(entry.value),
                    subtitle: Text(_modeDescriptions[entry.key] ?? ''),
                    onTap: () => Navigator.pop(sheetContext, entry.key),
                  );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedMode == null || !mounted) return;
    _applyModePreset(selectedMode);
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTraitSlider({
    required IconData icon,
    required String title,
    required String lowLabel,
    required String highLabel,
    required String description,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16)),
              ),
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                lowLabel,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Text(
                highLabel,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.blue.shade100,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: [
          _buildSectionTitle('模型'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: const Text('模型与 API'),
              subtitle: const Text('切换 DeepSeek、豆包或其他兼容接口'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ApiSettingsPage()),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.psychology_alt_outlined),
              title: const Text('角色设定'),
              subtitle: const Text('编辑裴简澈的人设、规则、禁区与示例对话'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CharacterSettingsPage(),
                  ),
                );
              },
            ),
          ),
          _buildSectionTitle('聊天初始化'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.chat_bubble_outline),
                      SizedBox(width: 10),
                      Text(
                        '开场白',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openingController,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 120,
                    decoration: InputDecoration(
                      hintText: '输入新聊天开始时，裴简澈发送的第一句话',
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const Text(
                    '修改后不会影响现有聊天。清空聊天记录或首次进入时，才会使用新的开场白。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildSectionTitle('主动联系'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.mark_chat_unread_outlined),
                  title: const Text('允许裴简澈主动联系'),
                  subtitle: const Text('长时间没有聊天时，他可以在 App 内留下一条消息。'),
                  value: _proactiveEnabled,
                  onChanged: (value) => setState(() {
                    _proactiveEnabled = value;
                    if (!value) _lateNightMessages = false;
                  }),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.nightlight_outlined),
                  title: const Text('允许深夜消息'),
                  subtitle: const Text('23:00 到 02:00 之间也可能留下消息。'),
                  value: _proactiveEnabled && _lateNightMessages,
                  onChanged: !_proactiveEnabled
                      ? null
                      : (value) => setState(() => _lateNightMessages = value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.slow_motion_video_rounded),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('每天最多', style: TextStyle(fontSize: 16)),
                          ),
                          Text(
                            '$_maxProactivePerDay 条',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Slider(
                        value: _maxProactivePerDay.toDouble(),
                        min: 0,
                        max: 4,
                        divisions: 4,
                        onChanged: !_proactiveEnabled
                            ? null
                            : (value) => setState(
                                () => _maxProactivePerDay = value.round(),
                              ),
                      ),
                      const Text(
                        '主动消息有时间段和冷却限制，不会连续催促，也不会在后台调用模型。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildSectionTitle('人格引擎'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('相处状态'),
                  subtitle: Text(
                    '${_modeTitles[_conversationMode]} · ${_modeDescriptions[_conversationMode]}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showModeDialog,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('自由发挥', style: TextStyle(fontSize: 16)),
                          ),
                          Text(
                            _temperature.toStringAsFixed(2),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Slider(
                        value: _temperature,
                        min: 0.55,
                        max: 0.90,
                        divisions: 14,
                        label: _temperature.toStringAsFixed(2),
                        onChanged: (value) =>
                            setState(() => _temperature = value),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '严格遵循设定',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            '偶尔自然发挥',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '建议保持在 0.68～0.78。过低容易像客服，过高可能让口吻飘走。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _buildTraitSlider(
                  icon: Icons.forum_outlined,
                  title: '主动程度',
                  lowLabel: '等你开口',
                  highLabel: '主动接话',
                  description: '越高，越愿意延续话题、追问细节和自然开启后续内容。',
                  value: _initiative,
                  onChanged: (value) => setState(() => _initiative = value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _buildTraitSlider(
                  icon: Icons.favorite_border_rounded,
                  title: '亲密表达',
                  lowLabel: '克制含蓄',
                  highLabel: '明显亲近',
                  description: '控制亲近感的表达频率，不等于频繁亲亲抱抱或强行调情。',
                  value: _intimacy,
                  onChanged: (value) => setState(() => _intimacy = value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _buildTraitSlider(
                  icon: Icons.sentiment_satisfied_alt_outlined,
                  title: '嘴硬程度',
                  lowLabel: '坦率直接',
                  highLabel: '嘴硬爱逗',
                  description: '越高，越容易用反问、轻微吃醋和嘴硬掩饰真实情绪。',
                  value: _tsundere,
                  onChanged: (value) => setState(() => _tsundere = value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.subject_outlined),
                          SizedBox(width: 10),
                          Text('回复长度', style: TextStyle(fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: _lengthTitles.entries
                            .map(
                              (entry) => ButtonSegment<String>(
                                value: entry.key,
                                label: Text(entry.value),
                              ),
                            )
                            .toList(),
                        selected: {_replyLength},
                        onSelectionChanged: (selection) {
                          setState(() => _replyLength = selection.first);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '提示：选择相处状态后会先套用一组明显不同的默认配方，你仍可继续微调。所有设置从下一条回复开始生效。聊天记录请在聊天页右上角菜单中管理。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
