import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../theme/app_theme_background.dart';
import '../../widgets/peilink/relationship_badge.dart';
import '../memory_page.dart';
import 'character_detail_page.dart';
import 'character_management_actions.dart';
import 'character_profile_home_page.dart';
import 'theme_decoration_page.dart';

class ChatSettingsPage extends StatefulWidget {
  const ChatSettingsPage({super.key, required this.character});

  final AiCharacter character;

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _clearChat() async {
    final changed = await CharacterManagementActions.clearChat(
      context,
      widget.character,
    );
    if (changed && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _restartCharacter() async {
    final changed = await CharacterManagementActions.restart(
      context,
      widget.character,
    );
    if (changed && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _deleteCharacter() async {
    final deleted = await CharacterManagementActions.deleteCharacter(
      context,
      widget.character,
    );
    if (deleted && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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
                  () => _open(MemoryPage(characterId: widget.character.id)),
                ),
                _tile(
                  '导出角色',
                  Icons.output_rounded,
                  () => _open(CharacterDetailPage(character: widget.character)),
                ),
              ],
            ),
            const _SectionLabel('当前聊天'),
            _GlassSection(
              children: [
                _tile(
                  '设置当前聊天背景',
                  Icons.wallpaper_rounded,
                  () => _open(const ThemeDecorationPage()),
                ),
                _tile('删除聊天记录', Icons.delete_outline_rounded, _clearChat),
              ],
            ),
            const SizedBox(height: 22),
            _GlassSection(
              children: [
                _actionTile(
                  '重新开始角色',
                  '重新开始当前角色的聊天与生活线',
                  _restartCharacter,
                  color: const Color(0xFF9A654F),
                ),
                _actionTile(
                  '删除角色',
                  '永久删除角色及其独立数据',
                  _deleteCharacter,
                  color: const Color(0xFFD85858),
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

  Widget _actionTile(
    String title,
    String subtitle,
    VoidCallback onTap, {
    required Color color,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF8D8792), fontSize: 12),
      ),
      onTap: onTap,
    );
  }
}

class _GlassSection extends StatelessWidget {
  const _GlassSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.74),
      borderRadius: BorderRadius.circular(18),
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
          color: Color(0xFF8C83A2),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
