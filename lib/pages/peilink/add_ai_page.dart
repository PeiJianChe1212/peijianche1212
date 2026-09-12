import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'character_creation_page.dart';
import 'create_group_chat_page.dart';

class AddAiPage extends StatelessWidget {
  const AddAiPage({super.key});

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature会在后面的版本开放。')));
  }

  Future<void> _openCreation(BuildContext context) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CharacterCreationPage()),
    );
    if (created == true && context.mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _openCreateGroup(BuildContext context) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupChatPage()),
    );
    if (created == true && context.mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F4F4),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF4F4F4),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            '添加羁绊',
            style: TextStyle(
              color: Color(0xFF171717),
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 24),
          children: [
            _AddOption(
              icon: Icons.auto_awesome_rounded,
              iconColor: Color(0xFF8E7CC3),
              title: '创建新的 AI',
              subtitle: '赋予名字、关系与人格，把一个新角色加入 PeiLink',
              onTap: () => _openCreation(context),
            ),
            _AddOption(
              icon: Icons.file_download_outlined,
              iconColor: Color(0xFF2F80ED),
              title: '导入角色',
              subtitle: '以后可以通过角色文件或分享码导入',
              onTap: () => _showComingSoon(context, '导入角色'),
            ),
            _AddOption(
              icon: Icons.qr_code_scanner_rounded,
              iconColor: Color(0xFF7D89E6),
              title: '扫描分享码',
              subtitle: '扫描别人分享的角色二维码',
              onTap: () => _showComingSoon(context, '扫描分享码'),
            ),
            _AddOption(
              icon: Icons.groups_2_outlined,
              iconColor: Color(0xFFF2994A),
              title: '创建群聊',
              subtitle: '让多位 AI 和你一起聊天',
              onTap: () => _openCreateGroup(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Material 外壳保证 ListTile 的点击水波纹正常显示（避免被 ColoredBox 遮挡）。
    return Material(
      color: Colors.white,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        leading: SizedBox(
          width: 36,
          child: Icon(icon, color: iconColor, size: 27),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF171717),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFFB7B7B7),
        ),
      ),
    );
  }
}
