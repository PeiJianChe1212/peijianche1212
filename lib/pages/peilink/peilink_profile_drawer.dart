import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/user_profile_storage_service.dart';
import '../../theme/app_dimensions.dart';
import '../../theme/app_theme_background.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../memory_page.dart';
import '../profile_page.dart';
import '../settings_page.dart';
import 'peilink_echo_page.dart';
import 'theme_decoration_page.dart';

/// PeiLink 中用户与 AI 世界的控制中心。
class PeiLinkProfileDrawer extends StatefulWidget {
  const PeiLinkProfileDrawer({
    super.key,
    required this.onOpenRelationships,
    this.onProfileChanged,
  });

  final VoidCallback onOpenRelationships;
  final ValueChanged<UserProfile>? onProfileChanged;

  @override
  State<PeiLinkProfileDrawer> createState() => _PeiLinkProfileDrawerState();
}

class _PeiLinkProfileDrawerState extends State<PeiLinkProfileDrawer> {
  final _storage = UserProfileStorageService();
  UserProfile _profile = const UserProfile();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _storage.loadProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
    widget.onProfileChanged?.call(profile);
  }

  Future<void> _openPage(Widget page, {bool refreshProfile = false}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (refreshProfile) await _loadProfile();
  }

  void _showComingSoon(String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title 将在后续版本开放')));
  }

  @override
  Widget build(BuildContext context) {
    final avatarPath = _profile.avatarPath.trim();
    final avatarFile = avatarPath.isEmpty ? null : File(avatarPath);
    final hasAvatar = avatarFile?.existsSync() == true;
    final signature = _profile.signature.trim().isEmpty
        ? '未设置'
        : _profile.signature.trim();
    final relationship = _profile.identity.trim().isEmpty
        ? '正在连接 AI 世界'
        : _profile.identity.trim();

    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(0, 380).toDouble(),
      shape: const RoundedRectangleBorder(),
      backgroundColor: Colors.transparent,
      child: ThemeBackgroundContainer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    AppDimensions.radiusMedium,
                  ),
                  onTap: () =>
                      _openPage(const ProfilePage(), refreshProfile: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileAvatar(
                          file: hasAvatar ? avatarFile : null,
                          size: AppDimensions.avatarLarge,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(_profile.nickname, style: AppTextStyles.pageTitle),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'PeiLink ID：${_profile.peiLinkId}',
                          style: AppTextStyles.caption,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          signature,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.supporting,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5EFF4),
                            borderRadius: BorderRadius.circular(
                              AppDimensions.radiusPill,
                            ),
                          ),
                          child: Text(
                            relationship,
                            style: AppTextStyles.caption.copyWith(
                              color: const Color(0xFF52788A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const _DrawerSectionLabel('快捷区域'),
              _DrawerTile(
                icon: Icons.notifications_none_rounded,
                title: '消息设置',
                onTap: () => _showComingSoon('消息设置'),
              ),
              _DrawerTile(
                icon: Icons.manage_accounts_outlined,
                title: '账号管理',
                onTap: () => _showComingSoon('账号管理'),
              ),
              const _DrawerSectionLabel('功能入口'),
              _DrawerTile(
                icon: Icons.people_outline_rounded,
                title: '角色管理',
                onTap: widget.onOpenRelationships,
              ),
              _DrawerTile(
                icon: Icons.bookmark_border_rounded,
                title: '收藏',
                onTap: () => _openPage(const MemoryPage()),
              ),
              _DrawerTile(
                icon: Icons.photo_library_outlined,
                title: '相册',
                onTap: () => _openPage(const PeiLinkEchoPage()),
              ),
              _DrawerTile(
                icon: Icons.palette_outlined,
                title: '主题装扮',
                onTap: () => _openPage(const ThemeDecorationPage()),
              ),
              _DrawerTile(
                icon: Icons.settings_outlined,
                title: '设置',
                onTap: () => _openPage(const SettingsPage()),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.file, required this.size});

  final File? file;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFE3E7E9),
        child: file != null
            ? Image.file(file!, fit: BoxFit.cover)
            : Icon(
                Icons.person_rounded,
                size: size * 0.54,
                color: const Color(0xFF8B969C),
              ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(label, style: AppTextStyles.caption),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, size: 22, color: const Color(0xFF52788A)),
        title: Text(title, style: AppTextStyles.bodyCompact),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: 21,
          color: Color(0xFFB1B8BC),
        ),
        onTap: onTap,
      ),
    );
  }
}
