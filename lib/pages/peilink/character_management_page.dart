import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../services/character_registry_service.dart';
import '../../theme/app_theme_background.dart';
import '../memory_page.dart';
import 'character_detail_page.dart';
import 'character_management_actions.dart';
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

  AiCharacter _character = AiCharacter.placeholder();
  bool _loading = true;
  bool _deleting = false;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final characters = await _registry.loadCharacters();
    final index = characters.indexWhere(
      (item) => item.id == widget.characterId,
    );
    if (!mounted) return;
    if (index < 0) {
      setState(() {
        _missing = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _character = characters[index];
      _loading = false;
    });
  }

  Future<void> _openMemory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemoryPage(characterId: _character.id)),
    );
  }

  Future<void> _restartCharacter() async {
    final restarted = await CharacterManagementActions.restart(
      context,
      _character,
    );
    if (!restarted || !mounted) return;
    _showSnack('已经重新开始');
    Navigator.of(context).pop(true);
  }

  Future<void> _deleteCharacter() async {
    setState(() => _deleting = true);
    try {
      final deleted = await CharacterManagementActions.deleteCharacter(
        context,
        _character,
      );
      if (!deleted) {
        if (mounted) setState(() => _deleting = false);
        return;
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      debugPrint('删除角色失败：$error');
      _showSnack('删除失败，请稍后再试');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            : _missing
            ? const Center(
                child: Text(
                  '这个角色已经不在了',
                  style: TextStyle(color: Color(0xFF8D8792)),
                ),
              )
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
                          backgroundColor: const Color(0xFFE5EBEE),
                          backgroundImage:
                              _character.avatarPath.isNotEmpty &&
                                  File(_character.avatarPath).existsSync()
                              ? FileImage(File(_character.avatarPath))
                              : null,
                          child:
                              _character.avatarPath.isNotEmpty &&
                                  File(_character.avatarPath).existsSync()
                              ? null
                              : const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Color(0xFF647C8B),
                                ),
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
                  const SizedBox(height: 10),
                  _Tile(
                    title: '导出角色',
                    subtitle: '导出角色文件',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CharacterDetailPage(character: _character),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Tile(
                    title: '重新开始角色',
                    subtitle: '重新开始当前角色的聊天与生活线',
                    warning: true,
                    onTap: _restartCharacter,
                  ),
                  const SizedBox(height: 10),
                  _Tile(
                    title: '删除角色',
                    subtitle: '永久删除角色及其所有独立数据',
                    destructive: true,
                    enabled: !_deleting,
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
    this.warning = false,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool destructive;
  final bool warning;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? const Color(0xFFAAAAAA)
        : destructive
        ? const Color(0xFFFA5151)
        : warning
        ? const Color(0xFF9A654F)
        : const Color(0xFF171717);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(16),
      ),
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
