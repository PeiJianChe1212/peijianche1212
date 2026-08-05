import 'package:flutter/material.dart';

import '../models/character_settings.dart';
import '../services/character_settings_storage_service.dart';

enum CharacterSettingsSection { persona, interaction }

class CharacterSettingsPage extends StatefulWidget {
  const CharacterSettingsPage({super.key, required this.section});

  final CharacterSettingsSection section;

  @override
  State<CharacterSettingsPage> createState() => _CharacterSettingsPageState();
}

class _CharacterSettingsPageState extends State<CharacterSettingsPage> {
  final _storage = CharacterSettingsStorageService();

  final _callNameController = TextEditingController();
  final _coreController = TextEditingController();
  final _behaviorController = TextEditingController();
  final _forbiddenController = TextEditingController();
  final _examplesController = TextEditingController();

  CharacterSettings _loadedSettings = CharacterSettings.defaults();

  bool _loading = true;
  bool _saving = false;

  late String _conversationMode;
  late double _temperature;
  late String _replyLength;
  late double _initiative;
  late double _intimacy;
  late double _tsundere;
  late bool _proactiveEnabled;
  late bool _lateNightMessages;
  late int _maxProactivePerDay;

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
    _apply(CharacterSettings.defaults());
    _load();
  }

  @override
  void dispose() {
    _callNameController.dispose();
    _coreController.dispose();
    _behaviorController.dispose();
    _forbiddenController.dispose();
    _examplesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _storage.loadSettings();
    if (!mounted) return;
    _apply(settings);
    setState(() => _loading = false);
  }

  void _apply(CharacterSettings settings) {
    _loadedSettings = settings;
    _callNameController.text = settings.userCallName;
    _coreController.text = settings.coreProfile;
    _behaviorController.text = settings.behaviorStyle;
    _forbiddenController.text = settings.forbiddenRules;
    _examplesController.text = settings.exampleDialogues;
    _conversationMode = settings.conversationMode;
    _temperature = settings.temperature;
    _replyLength = settings.replyLength;
    _initiative = settings.initiative;
    _intimacy = settings.intimacy;
    _tsundere = settings.tsundere;
    _proactiveEnabled = settings.proactiveEnabled;
    _lateNightMessages = settings.lateNightMessages;
    _maxProactivePerDay = settings.maxProactivePerDay;
  }

  CharacterSettings _currentSettings() => _loadedSettings.copyWith(
    userCallName: _callNameController.text.trim(),
    coreProfile: _coreController.text.trim(),
    behaviorStyle: _behaviorController.text.trim(),
    forbiddenRules: _forbiddenController.text.trim(),
    exampleDialogues: _examplesController.text.trim(),
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

  Future<void> _save() async {
    if (_saving) return;
    final settings = _currentSettings();

    if (settings.userCallName.isEmpty ||
        settings.coreProfile.isEmpty ||
        settings.behaviorStyle.isEmpty ||
        settings.forbiddenRules.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('对你的称呼、核心人设、行为规则和禁止事项不能为空')));
      return;
    }

    setState(() => _saving = true);
    try {
      await _storage.saveSettings(settings);
      _loadedSettings = settings;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${settings.characterName}的角色设置已保存，从下一条回复开始生效')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                '相处模式',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            RadioGroup<String>(
              groupValue: _conversationMode,
              onChanged: (value) => Navigator.pop(sheetContext, value),
              child: Column(
                children: _modeTitles.entries
                    .map(
                      (entry) => RadioListTile<String>(
                        value: entry.key,
                        title: Text(entry.value),
                        subtitle: Text(_modeDescriptions[entry.key] ?? ''),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) _applyModePreset(selected);
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复默认角色设置？'),
        content: const Text('当前编辑内容会被默认版本替换。恢复后仍需点击保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _apply(CharacterSettings.defaults());
    setState(() {});
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        color: Colors.black54,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _editorCard({
    required IconData icon,
    required String title,
    required String description,
    required TextEditingController controller,
    required int minLines,
    required int maxLines,
    String? helper,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF7F8FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                helperText: helper,
                helperMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderTile({
    required IconData icon,
    required String title,
    required String description,
    required double value,
    required ValueChanged<double> onChanged,
    String lowLabel = '低',
    String highLabel = '高',
  }) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(description),
          ),
          trailing: Text(value.toStringAsFixed(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              Slider(value: value, onChanged: onChanged),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    lowLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  Text(
                    highLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _currentSettings();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.section == CharacterSettingsSection.persona ? '人设' : '相处方式',
        ),
        backgroundColor: Colors.blue.shade100,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
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
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '这里保存 ${settings.characterName} 自己的人设、相处模式、主动联系和 Memory。以后新增其他角色时，彼此不会互相串设置。',
                    style: const TextStyle(height: 1.5),
                  ),
                ),
                if (widget.section == CharacterSettingsSection.interaction)
                  _sectionTitle('相处方式'),
                if (widget.section == CharacterSettingsSection.interaction)
                  Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.tune_rounded),
                          title: const Text('相处模式'),
                          subtitle: Text(
                            '${_modeTitles[_conversationMode]} · ${_modeDescriptions[_conversationMode]}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _showModeDialog,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _sliderTile(
                          icon: Icons.auto_awesome_outlined,
                          title: '自由发挥',
                          description: '越高越灵活，越低越稳定。建议保持在 0.68～0.78。',
                          value: _temperature,
                          onChanged: (value) =>
                              setState(() => _temperature = value),
                          lowLabel: '更稳定',
                          highLabel: '更灵活',
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _sliderTile(
                          icon: Icons.forum_outlined,
                          title: '主动程度',
                          description: '控制他延续话题、追问细节和主动开启后续内容的程度。',
                          value: _initiative,
                          onChanged: (value) =>
                              setState(() => _initiative = value),
                          lowLabel: '等你开口',
                          highLabel: '主动接话',
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _sliderTile(
                          icon: Icons.favorite_border_rounded,
                          title: '亲密表达',
                          description: '控制亲近感的表达频率，不等于反复亲亲抱抱。',
                          value: _intimacy,
                          onChanged: (value) =>
                              setState(() => _intimacy = value),
                          lowLabel: '克制含蓄',
                          highLabel: '明显亲近',
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _sliderTile(
                          icon: Icons.sentiment_satisfied_alt_outlined,
                          title: '嘴硬程度',
                          description: '控制反问、轻微吃醋和嘴硬掩饰真实情绪的频率。',
                          value: _tsundere,
                          onChanged: (value) =>
                              setState(() => _tsundere = value),
                          lowLabel: '坦率直接',
                          highLabel: '嘴硬爱逗',
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
                                  setState(
                                    () => _replyLength = selection.first,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.section == CharacterSettingsSection.interaction)
                  _sectionTitle('主动联系'),
                if (widget.section == CharacterSettingsSection.interaction)
                  Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.notifications_active_outlined,
                          ),
                          title: const Text('允许主动联系'),
                          subtitle: const Text('关闭后，当前角色不会主动发起新消息。'),
                          value: _proactiveEnabled,
                          onChanged: (value) =>
                              setState(() => _proactiveEnabled = value),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile(
                          secondary: const Icon(Icons.nightlight_outlined),
                          title: const Text('允许深夜消息'),
                          subtitle: const Text('关闭后，深夜时段不会主动打扰你。'),
                          value: _lateNightMessages,
                          onChanged: _proactiveEnabled
                              ? (value) =>
                                    setState(() => _lateNightMessages = value)
                              : null,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.mark_chat_unread_outlined),
                          title: const Text('每天最多主动联系'),
                          subtitle: Text('$_maxProactivePerDay 次'),
                          trailing: DropdownButton<int>(
                            value: _maxProactivePerDay,
                            underline: const SizedBox.shrink(),
                            items: List.generate(
                              5,
                              (index) => DropdownMenuItem<int>(
                                value: index,
                                child: Text('$index 次'),
                              ),
                            ),
                            onChanged: _proactiveEnabled
                                ? (value) {
                                    if (value != null) {
                                      setState(
                                        () => _maxProactivePerDay = value,
                                      );
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.section == CharacterSettingsSection.persona)
                  _sectionTitle('人设'),
                if (widget.section == CharacterSettingsSection.persona)
                  _editorCard(
                    icon: Icons.badge_outlined,
                    title: '核心人设',
                    description: '身份、性格、关系中的稳定底色。尽量写长期不变的内容。',
                    controller: _coreController,
                    minLines: 8,
                    maxLines: 18,
                  ),
                if (widget.section == CharacterSettingsSection.persona)
                  _editorCard(
                    icon: Icons.record_voice_over_outlined,
                    title: '说话与行为规则',
                    description: '决定他如何接话、安慰、吃醋、开玩笑，以及回复节奏。',
                    controller: _behaviorController,
                    minLines: 8,
                    maxLines: 18,
                  ),
                if (widget.section == CharacterSettingsSection.persona)
                  _editorCard(
                    icon: Icons.block_outlined,
                    title: '禁止事项',
                    description: '把最容易串味、油腻、模板化或让你不舒服的表达写在这里。',
                    controller: _forbiddenController,
                    minLines: 7,
                    maxLines: 16,
                  ),
                if (widget.section == CharacterSettingsSection.persona)
                  _editorCard(
                    icon: Icons.chat_outlined,
                    title: '示例对话',
                    description:
                        '每行使用“${settings.userCallName}：……”或“${settings.characterName}：……”。示例越自然，越容易稳定口吻。',
                    controller: _examplesController,
                    minLines: 12,
                    maxLines: 24,
                    helper:
                        '例如：\n${settings.userCallName}：你今天心情怎么样？\n${settings.characterName}：还行。你怎么突然问这个？',
                  ),
                OutlinedButton.icon(
                  onPressed: _restoreDefaults,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('恢复默认角色设置'),
                ),
              ],
            ),
    );
  }
}
