import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_profile.dart';
import '../services/user_profile_storage_service.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _storage = UserProfileStorageService();
  UserProfile _profile = const UserProfile();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _storage.loadProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  Future<void> _editProfile() async {
    final result = await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(initialProfile: _profile),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _profile = result);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('资料已经保存，下一次聊天会自动读取。')));
  }

  String _show(String value) => value.trim().isEmpty ? '未填写' : value.trim();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF10151D),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('我'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _editProfile,
              tooltip: '编辑资料',
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: _ProfileBackground()),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                  children: [
                    _ProfileHeader(profile: _profile),
                    const SizedBox(height: 18),
                    _ProfileSection(
                      title: '基本资料',
                      children: [
                        _ProfileRow(label: '昵称', value: _profile.nickname),
                        _ProfileRow(
                          label: '裴简澈对你的称呼',
                          value: _profile.peiCallName,
                        ),
                        _ProfileRow(
                          label: '生日',
                          value: _show(_profile.birthday),
                        ),
                        _ProfileRow(label: '身份', value: _profile.identity),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ProfileSection(
                      title: '他需要知道的你',
                      children: [
                        _ProfileRow(
                          label: '工作与作息',
                          value: _show(_profile.workAndSchedule),
                        ),
                        _ProfileRow(
                          label: '喜欢的事物',
                          value: _show(_profile.likes),
                        ),
                        _ProfileRow(
                          label: '不喜欢的事物',
                          value: _show(_profile.dislikes),
                        ),
                        _ProfileRow(
                          label: '相处偏好',
                          value: _show(_profile.interactionPreference),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _editProfile,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑我的资料'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '这些内容只保存在当前设备中，并会在发送消息时自动加入裴简澈看到的资料。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBackground extends StatelessWidget {
  const _ProfileBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF273748), Color(0xFF151D27), Color(0xFF090D13)],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final avatarFile = profile.avatarPath.isEmpty
        ? null
        : File(profile.avatarPath);
    final hasAvatar = avatarFile != null && avatarFile.existsSync();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.5,
              ),
              image: DecorationImage(
                image: hasAvatar
                    ? FileImage(avatarFile)
                    : const AssetImage('assets/images/user_avatar_default.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.nickname,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '这一次，手机里也有属于你的位置。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.56),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
