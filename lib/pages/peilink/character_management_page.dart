import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_scope_service.dart';
import '../../services/session_reset_service.dart';
import '../../theme/app_theme_background.dart';
import '../memory_page.dart';
import 'character_profile_home_page.dart';

class CharacterManagementPage extends StatefulWidget {
  const CharacterManagementPage({super.key, required this.characterId});

  final String characterId;

  @override
  State<CharacterManagementPage> createState() =>
      _CharacterManagementPageState();
}

class _CharacterManagementPageState extends State<CharacterManagementPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();

  AiCharacter _character = AiCharacter.peiJianChe();
  bool _loading = true;
  bool _deleting = false;

  SessionResetService get _sessionReset =>
      SessionResetService(characterId: _character.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final characters = await _registry.loadCharacters();
    final character = characters.firstWhere(
      (item) => item.id == widget.characterId,
      orElse: AiCharacter.peiJianChe,
    );
    if (!mounted) return;
    setState(() {
      _character = character;
      _loading = false;
    });
  }

  Future<void> _openMemory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MemoryPage()),
    );
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
                        onPressed: () => Navigator.pop(dialogContext, false),
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
        content: const Text('角色资料、聊天、Memory、Today 和所有独立数据都会一起删除。这个操作无法撤销。'),
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
              decoration: const InputDecoration(border: OutlineInputBorder()),
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
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('角色管理'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(top: 10, bottom: 30),
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundImage:
                              _character.avatarPath.isNotEmpty &&
                                  File(_character.avatarPath).existsSync()
                              ? FileImage(File(_character.avatarPath))
                              : _character.isBuiltIn
                              ? const AssetImage('assets/images/pei_avatar.jpg')
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _character.displayName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Tile(
                    title: '角色资料',
                    subtitle: '基础、外貌、性格、背景与关系资料',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CharacterProfileHomePage(character: _character),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Tile(
                    title: 'Memory',
                    subtitle: '${_character.characterName}独立保存的长期记忆',
                    onTap: _openMemory,
                  ),
                  _Tile(
                    title: '心声',
                    subtitle: '看看他最近没有说出口的话',
                    onTap: () => _soon('心声'),
                  ),
                  const SizedBox(height: 10),
                  _Tile(
                    title: '导出角色',
                    subtitle: '以后可生成角色文件或分享码',
                    onTap: () => _soon('导出角色'),
                  ),
                  const SizedBox(height: 10),
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
        title: Text(title, style: TextStyle(color: foreground, fontSize: 16)),
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
