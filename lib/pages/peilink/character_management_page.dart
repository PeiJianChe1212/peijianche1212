import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/character_settings.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_scope_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../services/session_reset_service.dart';
import '../character_settings_page.dart';
import '../memory_page.dart';
import 'character_profile_edit_page.dart';

class CharacterManagementPage extends StatefulWidget {
  const CharacterManagementPage({super.key});

  @override
  State<CharacterManagementPage> createState() =>
      _CharacterManagementPageState();
}

class _CharacterManagementPageState extends State<CharacterManagementPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();

  CharacterSettings _settings = CharacterSettings.defaults();
  AiCharacter _character = AiCharacter.peiJianChe();
  bool _loading = true;
  bool _deleting = false;

  CharacterSettingsStorageService get _storage =>
      CharacterSettingsStorageService(characterId: _character.id);

  SessionResetService get _sessionReset =>
      SessionResetService(characterId: _character.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final character = await _registry.loadActiveCharacter();
    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();

    if (!mounted) return;
    setState(() {
      _character = character;
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _openProfileEdit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CharacterProfileEditPage()),
    );
    if (changed == true) await _load();
  }

  Future<void> _editCallName() async {
    var editedValue = _settings.userCallName;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('他对你的专属称呼'),
        content: TextFormField(
          initialValue: _settings.userCallName,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '例如：念念、小狐狸、林小姐'),
          onChanged: (value) => editedValue = value,
          onFieldSubmitted: (value) =>
              Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, editedValue.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (value == null || value.isEmpty) return;
    await _storage.saveSettings(_settings.copyWith(userCallName: value));
    await _load();
  }


  Future<void> _openMemory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MemoryPage()),
    );
  }

  Future<void> _openPersonaAndConversation() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CharacterSettingsPage()),
    );
    await _load();
  }

  Future<void> _showClearChatConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空聊天记录？'),
        content: Text(
          '只会删除你和${_character.characterName}的聊天消息，长期记忆、待审核记忆和 Today 都会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _sessionReset.clearChatOnly();
    _showSnack('聊天记录已清空，记忆仍然保留');
  }

  Future<void> _showCleanupOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('仅清空聊天'),
              subtitle: const Text('删除消息，保留长期记忆、待审核记忆和 Today'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _sessionReset.clearChatOnly();
                _showSnack('聊天记录已清空，记忆仍然保留');
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded, color: Colors.red),
              title: const Text('重新开始', style: TextStyle(color: Colors.red)),
              subtitle: const Text('清空聊天、长期记忆、待审核记忆和 Today'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('重新开始这段关系？'),
                    content: Text(
                      '这会清空你和${_character.characterName}的聊天、长期记忆、待审核记忆、Today 与生活痕迹，但不会删除角色本身。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(dialogContext, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('重新开始'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await _sessionReset.resetSharedStory();
                _showSnack('已经重新开始');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCharacter() async {
    if (_character.isBuiltIn) return;

    final firstConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除${_character.characterName}？'),
        content: const Text(
          '角色资料、聊天、Memory、Today 和所有独立数据都会一起删除。这个操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('继续删除'),
          ),
        ],
      ),
    );
    if (firstConfirmed != true || !mounted) return;

    var typedName = '';
    final secondConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('最后确认'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请输入角色本名“${_character.characterName}”确认删除：'),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: (value) => typedName = value.trim(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                typedName == _character.characterName,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );

    if (secondConfirmed != true || !mounted) {
      if (secondConfirmed == false && typedName.isNotEmpty) {
        _showSnack('名称不一致，没有删除');
      }
      return;
    }

    setState(() => _deleting = true);
    try {
      await CharacterScopeService(_character.id).deleteAllData();
      await _registry.deleteCharacter(_character.id);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _showSnack('删除失败：$error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _soon(String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title会在后面的版本开放。')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text('角色设置'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF4F4F4),
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 30),
              children: [
                _Tile(
                  title: '编辑备注与资料',
                  subtitle: _settings.remark.trim().isEmpty
                      ? '当前没有备注'
                      : '当前备注：${_settings.remark}',
                  onTap: _openProfileEdit,
                ),
                _Tile(
                  title: '他对你的专属称呼',
                  subtitle: _settings.userCallName,
                  onTap: _editCallName,
                ),
                const SizedBox(height: 10),
                _Tile(
                  title: '人设与相处方式',
                  subtitle: '人设、回复节奏、主动程度和亲密表达',
                  onTap: _openPersonaAndConversation,
                ),
                const SizedBox(height: 10),
                _Tile(
                  title: 'Memory',
                  subtitle: '${_character.characterName}独立保存的长期记忆',
                  onTap: _openMemory,
                ),
                _Tile(
                  title: '共同回忆',
                  subtitle: '纪念日、重要事件和聊天留下的痕迹',
                  onTap: () => _soon('共同回忆'),
                ),
                _Tile(
                  title: '心声',
                  subtitle: '看看他最近没有说出口的话',
                  onTap: () => _soon('心声'),
                ),
                const SizedBox(height: 10),
                _Tile(
                  title: '角色权限',
                  subtitle: '记忆、Echo 和未来功能的使用权限',
                  onTap: () => _soon('角色权限'),
                ),
                const SizedBox(height: 10),
                _Tile(
                  title: '导出角色',
                  subtitle: '以后可生成角色文件或分享码',
                  onTap: () => _soon('导出角色'),
                ),
                const SizedBox(height: 10),
                _Tile(
                  title: '清空聊天记录',
                  subtitle: '只删除消息，保留角色与记忆',
                  onTap: _showClearChatConfirmation,
                ),
                _Tile(
                  title: '清理与重置',
                  subtitle: '清空聊天，或重新开始这段关系',
                  onTap: _showCleanupOptions,
                ),
                const SizedBox(height: 10),
                _Tile(
                  title: _character.isBuiltIn ? '内置角色不可删除' : '删除角色',
                  subtitle: _character.isBuiltIn
                      ? '裴简澈是 PeiLink 的内置角色'
                      : '永久删除角色及其所有独立数据',
                  destructive: !_character.isBuiltIn,
                  enabled: !_character.isBuiltIn && !_deleting,
                  onTap: _deleteCharacter,
                ),
              ],
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool destructive;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? const Color(0xFFAAAAAA)
        : destructive
            ? const Color(0xFFFA5151)
            : const Color(0xFF171717);

    return Container(
      color: Colors.white,
      child: ListTile(
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        title: Text(
          title,
          style: TextStyle(color: foreground, fontSize: 16),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(color: Color(0xFF999999), fontSize: 13),
              ),
        trailing: destructive || !enabled
            ? null
            : const Icon(Icons.chevron_right_rounded, color: Color(0xFFB7B7B7)),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
