import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/user_profile_storage_service.dart';
import '../../theme/app_dimensions.dart';
import '../../theme/app_theme_background.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../profile_page.dart';
import '../settings_page.dart';
import 'theme_decoration_page.dart';

/// PeiLink 中用户与 AI 世界的控制中心。
class PeiLinkProfileDrawer extends StatefulWidget {
  const PeiLinkProfileDrawer({
    super.key,
    required this.onOpenCharacterManagement,
    required this.onOpenMyEcho,
    this.onProfileChanged,
  });

  final VoidCallback onOpenCharacterManagement;
  final VoidCallback onOpenMyEcho;
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

  @override
  Widget build(BuildContext context) {
    final avatarPath = _profile.avatarPath.trim();
    final avatarFile = avatarPath.isEmpty ? null : File(avatarPath);
    final hasAvatar = avatarFile?.existsSync() == true;
    final nickname = _profile.nickname.trim().isEmpty
        ? '未设置'
        : _profile.nickname.trim();
    final signature = _profile.signature.trim().isEmpty
        ? '写一句属于你的话'
        : _profile.signature.trim();
    final peiLinkId = _profile.peiLinkId.trim().isEmpty
        ? '未设置'
        : _profile.peiLinkId.trim();

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
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    AppDimensions.radiusMedium,
                  ),
                  onTap: () =>
                      _openPage(const ProfilePage(), refreshProfile: true),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFECE6F5)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0D67558C),
                          blurRadius: 22,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileAvatar(
                          file: hasAvatar ? avatarFile : null,
                          size: AppDimensions.avatarLarge,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(nickname, style: AppTextStyles.pageTitle),
                        const SizedBox(height: 4),
                        Text(
                          signature,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.supporting.copyWith(
                            color: const Color(0xFF827A90),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'PeiLink ID：$peiLinkId',
                          style: AppTextStyles.caption.copyWith(
                            color: const Color(0xFF776B91),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const _DrawerSectionLabel('功能入口'),
              _DrawerTile(
                icon: Icons.waves_rounded,
                title: '我的 Echo',
                onTap: widget.onOpenMyEcho,
              ),
              _DrawerTile(
                icon: Icons.people_outline_rounded,
                title: '角色管理',
                onTap: widget.onOpenCharacterManagement,
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
      padding: const EdgeInsets.fromLTRB(22, 18, 20, 7),
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
      color: Colors.white.withValues(alpha: 0.76),
      child: ListTile(
        minTileHeight: 52,
        contentPadding: const EdgeInsets.symmetric(horizontal: 22),
        leading: Icon(icon, size: 21, color: const Color(0xFF6F79A8)),
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
