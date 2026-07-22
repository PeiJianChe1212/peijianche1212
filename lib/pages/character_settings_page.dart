import 'package:flutter/material.dart';

import '../conversation/conversation_engine.dart';
import '../models/character_settings.dart';
import '../services/character_settings_storage_service.dart';
import '../services/memory_storage_service.dart';
import '../services/prompt_builder.dart';
import '../services/settings_storage_service.dart';
import '../services/user_profile_storage_service.dart';

class CharacterSettingsPage extends StatefulWidget {
  const CharacterSettingsPage({super.key});

  @override
  State<CharacterSettingsPage> createState() => _CharacterSettingsPageState();
}

class _CharacterSettingsPageState extends State<CharacterSettingsPage> {
  final _storage = CharacterSettingsStorageService();
  final _profileStorage = UserProfileStorageService();
  final _memoryStorage = MemoryStorageService();
  final _chatSettingsStorage = SettingsStorageService();

  final _coreController = TextEditingController();
  final _behaviorController = TextEditingController();
  final _forbiddenController = TextEditingController();
  final _examplesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
    _coreController.text = settings.coreProfile;
    _behaviorController.text = settings.behaviorStyle;
    _forbiddenController.text = settings.forbiddenRules;
    _examplesController.text = settings.exampleDialogues;
  }

  CharacterSettings _currentSettings() => CharacterSettings(
    coreProfile: _coreController.text.trim(),
    behaviorStyle: _behaviorController.text.trim(),
    forbiddenRules: _forbiddenController.text.trim(),
    exampleDialogues: _examplesController.text.trim(),
  );

  Future<void> _save() async {
    if (_saving) return;
    final settings = _currentSettings();
    if (settings.coreProfile.isEmpty ||
        settings.behaviorStyle.isEmpty ||
        settings.forbiddenRules.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('核心人设、行为规则和禁止事项不能为空')));
      return;
    }

    setState(() => _saving = true);
    try {
      await _storage.saveSettings(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('裴简澈的人设已保存，从下一条回复开始生效')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复默认人设？'),
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

  Future<void> _previewPrompt() async {
    final profile = await _profileStorage.loadProfile();
    final memoryPrompt = await _memoryStorage.buildPromptSection();
    final chatSettings = await _chatSettingsStorage.loadSettings();
    final characterSettings = _currentSettings();

    final conversationEngine = ConversationEngine.build(
      messages: const [],
      conversationMode: chatSettings.conversationMode,
    );

    final preview = PromptBuilder.buildSystemPrompt(
      characterSettings: characterSettings,
      userProfile: profile,
      timeContext: '【当前时间】\n预览模式：实际聊天时会自动写入当前日期和时段。',
      conversationEnginePrompt: conversationEngine.prompt,
      personalityPrompt:
          '【当前人格调节】\n主动程度 ${chatSettings.initiative.toStringAsFixed(2)}，亲密表达 ${chatSettings.intimacy.toStringAsFixed(2)}，嘴硬程度 ${chatSettings.tsundere.toStringAsFixed(2)}。',
      replyLengthPrompt: '当前回复长度：${chatSettings.replyLength}',
      memoryPrompt: memoryPrompt,
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.86,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined),
                    SizedBox(width: 10),
                    Text(
                      '最终 Prompt 预览',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '这是当前编辑内容与用户资料、关系设定、记忆等拼接后的预览。示例对话会作为独立消息发送，不显示在这里。',
                  style: TextStyle(color: Colors.black54, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      preview,
                      style: const TextStyle(fontSize: 14, height: 1.55),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色设定'),
        backgroundColor: Colors.blue.shade100,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '预览最终 Prompt',
            onPressed: _loading ? null : _previewPrompt,
            icon: const Icon(Icons.visibility_outlined),
          ),
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
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '这里控制“裴简澈是谁、怎么说话、绝对不能怎么说”。修改后不会影响旧聊天，从下一条新回复开始生效。',
                    style: TextStyle(height: 1.5),
                  ),
                ),
                _editorCard(
                  icon: Icons.badge_outlined,
                  title: '核心人设',
                  description: '身份、性格、关系中的稳定底色。尽量写长期不变的内容。',
                  controller: _coreController,
                  minLines: 8,
                  maxLines: 18,
                ),
                _editorCard(
                  icon: Icons.record_voice_over_outlined,
                  title: '说话与行为规则',
                  description: '决定他如何接话、安慰、吃醋、开玩笑，以及回复节奏。',
                  controller: _behaviorController,
                  minLines: 8,
                  maxLines: 18,
                ),
                _editorCard(
                  icon: Icons.block_outlined,
                  title: '禁止事项',
                  description: '把最容易串味、油腻、模板化或让你不舒服的表达写在这里。',
                  controller: _forbiddenController,
                  minLines: 7,
                  maxLines: 16,
                ),
                _editorCard(
                  icon: Icons.chat_outlined,
                  title: '示例对话',
                  description: '每行使用“念念：……”或“裴简澈：……”。成对示例越自然，越容易稳定口吻。',
                  controller: _examplesController,
                  minLines: 12,
                  maxLines: 24,
                  helper: '例如：\n念念：你是不是又吃醋了？\n裴简澈：没有。你少给我制造证据。',
                ),
                OutlinedButton.icon(
                  onPressed: _restoreDefaults,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('恢复默认人设'),
                ),
              ],
            ),
    );
  }
}
