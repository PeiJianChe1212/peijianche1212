import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/user_profile_storage_service.dart';
import '../profile_page.dart';
import 'peilink_echo_page.dart';

class PeiLinkMePage extends StatefulWidget {
  const PeiLinkMePage({super.key});

  @override
  State<PeiLinkMePage> createState() => _PeiLinkMePageState();
}

class _PeiLinkMePageState extends State<PeiLinkMePage> {
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
  }

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
    await _loadProfile();
  }


  Future<void> _openMyEcho() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PeiLinkEchoPage()),
    );
  }

  void _showComingSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title会在后面的版本开放。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarFile = _profile.avatarPath.isEmpty
        ? null
        : File(_profile.avatarPath);
    final hasAvatar = avatarFile != null && avatarFile.existsSync();

    return Container(
      color: const Color(0xFFF4F4F4),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          InkWell(
            onTap: _openProfile,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 68,
                      height: 68,
                      color: const Color(0xFFE9E9E9),
                      child: hasAvatar
                          ? Image.file(avatarFile, fit: BoxFit.cover)
                          : const Icon(
                              Icons.person_rounded,
                              color: Color(0xFF999999),
                              size: 38,
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _profile.nickname,
                          style: const TextStyle(
                            color: Color(0xFF171717),
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'PeiLink ID：${_profile.peiLinkId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF777777),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.qr_code_rounded,
                    color: Color(0xFF777777),
                    size: 24,
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFB7B7B7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _MeTile(
            icon: Icons.account_balance_wallet_outlined,
            title: '服务',
            onTap: () => _showComingSoon('服务'),
          ),
          _MeTile(
            icon: Icons.bookmark_border_rounded,
            title: '收藏',
            onTap: () => _showComingSoon('收藏'),
          ),
          _MeTile(
            icon: Icons.auto_awesome_outlined,
            title: '我的 Echo',
            onTap: _openMyEcho,
          ),
          _MeTile(
            icon: Icons.emoji_emotions_outlined,
            title: '表情',
            onTap: () => _showComingSoon('表情'),
          ),
        ],
      ),
    );
  }
}

class _MeTile extends StatelessWidget {
  const _MeTile({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF576B95)),
        title: Text(
          title,
          style: const TextStyle(color: Color(0xFF171717), fontSize: 16),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFFB7B7B7),
        ),
        onTap: onTap,
      ),
    );
  }
}
