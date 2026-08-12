import 'package:flutter/material.dart';

import '../../theme/app_theme_background.dart';
import 'character_creation_page.dart';
import 'character_import_page.dart';
import 'create_group_chat_page.dart';

class AiCreationCenterPage extends StatefulWidget {
  const AiCreationCenterPage({super.key});

  @override
  State<AiCreationCenterPage> createState() => _AiCreationCenterPageState();
}

class _AiCreationCenterPageState extends State<AiCreationCenterPage> {
  bool _changed = false;

  Future<void> _openCharacterCreation() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CharacterCreationPage()),
    );
    if (created == true) _changed = true;
  }

  Future<void> _openGroupCreation() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupChatPage()),
    );
    if (created != null) _changed = true;
  }

  Future<void> _openCharacterImport() async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CharacterImportPage()),
    );
    if (imported == true) _changed = true;
  }

  void _comingSoon(String name) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$name入口已预留，将在后续数据管理版本开放')));

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.pop(context, _changed);
    },
    child: ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('创建 AI'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context, _changed),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            _CenterCard(
              icon: Icons.auto_awesome_rounded,
              color: const Color(0xFF8A53E4),
              title: '新建角色',
              subtitle: '从零开始创建一个全新的 AI 角色',
              onTap: _openCharacterCreation,
            ),
            _CenterCard(
              icon: Icons.folder_copy_rounded,
              color: const Color(0xFFA546E6),
              title: '导入角色',
              subtitle: '导入角色文件，恢复角色数据',
              onTap: _openCharacterImport,
            ),
            _CenterCard(
              icon: Icons.workspace_premium_rounded,
              color: const Color(0xFF9270D8),
              title: '我的模板',
              subtitle: '使用已保存的角色模板快速创建',
              onTap: () => _comingSoon('我的模板'),
            ),
            _CenterCard(
              icon: Icons.edit_note_rounded,
              color: const Color(0xFF7964D8),
              title: '草稿箱',
              subtitle: '继续编辑尚未完成的角色',
              onTap: () => _comingSoon('草稿箱'),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .62),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.groups_2_rounded,
                    size: 48,
                    color: Color(0xFF7A4BD1),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '创建群聊',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '与多个 AI 角色共同聊天',
                    style: TextStyle(color: Color(0xFF777185)),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _openGroupCreation,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8053D6),
                    ),
                    child: const Text('去创建'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .9)),
    ),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF777185), fontSize: 12.5),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF9A8DB1),
      ),
    ),
  );
}
