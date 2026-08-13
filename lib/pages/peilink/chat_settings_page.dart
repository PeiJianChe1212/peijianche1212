import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../theme/app_theme_background.dart';
import '../../widgets/peilink/relationship_badge.dart';
import '../memory_page.dart';
import 'character_detail_page.dart';
import 'character_management_page.dart';
import 'character_profile_home_page.dart';
import 'create_group_chat_page.dart';
import 'theme_decoration_page.dart';

class ChatSettingsPage extends StatefulWidget {
  const ChatSettingsPage({super.key, required this.character});

  final AiCharacter character;

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  bool _pinned = false;
  bool _hidden = false;
  bool _muted = false;

  void _soon(String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title功能暂未开放。')));
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  ImageProvider? get _avatarProvider {
    final path = widget.character.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return FileImage(File(path));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('聊天设置'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
          children: [
            _GlassSection(
              children: [
                ListTile(
                  onTap: () =>
                      _open(CharacterDetailPage(character: widget.character)),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    radius: 25,
                    backgroundColor: const Color(0xFFE7ECEF),
                    backgroundImage: _avatarProvider,
                    child: _avatarProvider == null
                        ? const Icon(Icons.auto_awesome_rounded)
                        : null,
                  ),
                  title: Text(
                    widget.character.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: RelationshipBadge(
                    relationship: widget.character.relationship,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const _SectionLabel('聊天管理'),
            _GlassSection(
              children: [
                _tile(
                  '发起群聊',
                  Icons.group_add_outlined,
                  () => _open(const CreateGroupChatPage()),
                ),
                _tile('查找聊天记录', Icons.search_rounded, () => _soon('查找聊天记录')),
                _switch('置顶聊天', _pinned, (v) => setState(() => _pinned = v)),
                _tile(
                  '特别关注',
                  Icons.favorite_border_rounded,
                  () => _soon('特别关注'),
                ),
                _switch('隐藏会话', _hidden, (v) => setState(() => _hidden = v)),
                _switch('消息免打扰', _muted, (v) => setState(() => _muted = v)),
                _tile(
                  '设置当前聊天背景',
                  Icons.wallpaper_rounded,
                  () => _open(const ThemeDecorationPage()),
                ),
                _tile(
                  '删除聊天记录',
                  Icons.delete_outline_rounded,
                  () => _soon('删除聊天记录'),
                  destructive: true,
                ),
              ],
            ),
            const _SectionLabel('角色管理'),
            _GlassSection(
              children: [
                _tile(
                  '角色资料',
                  Icons.edit_note_rounded,
                  () => _open(
                    CharacterProfileHomePage(character: widget.character),
                  ),
                ),
                _tile(
                  'Memory',
                  Icons.inbox_outlined,
                  () => _open(const MemoryPage()),
                ),
                _tile('心声', Icons.cloud_outlined, () => _soon('心声')),
                _tile('导出角色', Icons.output_rounded, () => _soon('导出角色')),
                _tile(
                  '清理与重置',
                  Icons.cleaning_services_outlined,
                  () => _open(
                    CharacterManagementPage(characterId: widget.character.id),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(
        title,
        style: TextStyle(color: destructive ? const Color(0xFFE64C4C) : null),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF666666),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
