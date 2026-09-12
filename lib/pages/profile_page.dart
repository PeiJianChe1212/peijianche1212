import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/user_profile_storage_service.dart';
import 'profile_field_edit_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _storage = UserProfileStorageService();
  final _picker = ImagePicker();
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

  Future<void> _save(UserProfile profile) async {
    await _storage.saveProfile(profile);
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  Future<void> _editText({
    required String title,
    required String value,
    required UserProfile Function(String value) update,
    String hint = '',
    int maxLength = 40,
    int maxLines = 1,
    bool allowEmpty = true,
  }) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileTextEditPage(
          title: title,
          initialValue: value,
          hintText: hint,
          maxLength: maxLength,
          maxLines: maxLines,
          allowEmpty: allowEmpty,
        ),
      ),
    );
    if (result == null) return;
    await _save(update(result));
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null) return;
      final path = await _storage.saveAvatarCopy(picked.path);
      if (path.isEmpty) return;
      imageCache.evict(FileImage(File(path)));
      await _save(_profile.copyWith(avatarPath: path));
    } catch (error) {
      if (!mounted) return;
      debugPrint('选择用户头像失败：$error');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('选择头像失败，请稍后再试')));
    }
  }

  Future<void> _editGender() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileGenderEditPage(initialValue: _profile.gender),
      ),
    );
    if (result == null) return;
    await _save(_profile.copyWith(gender: result));
  }

  Future<void> _editBirthday() async {
    final stored = DateTime.tryParse(_profile.profileBirthday);
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: stored ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: '选择生日',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected == null) return;
    final value =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
    await _save(_profile.copyWith(profileBirthday: value));
  }

  String _show(String value, {String fallback = '未填写'}) {
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }

  String _showBirthday(String value) {
    final date = DateTime.tryParse(value.trim());
    return date == null ? '未设置' : '${date.year}年${date.month}月${date.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F6FB),
        surfaceTintColor: Colors.transparent,
        title: const Text('个人资料'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const _SectionLabel('基本资料'),
                _ProfileSection(
                  child: Column(
                    children: [
                      _ProfileTile(
                        title: '头像',
                        trailing: _Avatar(path: _profile.avatarPath),
                        onTap: _pickAvatar,
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: '昵称',
                        value: _show(_profile.nickname, fallback: '未设置'),
                        onTap: () => _editText(
                          title: '设置昵称',
                          value: _profile.nickname,
                          allowEmpty: false,
                          maxLength: 20,
                          update: (value) => _profile.copyWith(nickname: value),
                        ),
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: '签名',
                        value: _show(_profile.signature, fallback: '写一句属于你的话'),
                        onTap: () => _editText(
                          title: '设置签名',
                          value: _profile.signature,
                          hint: '写一句属于你的话',
                          maxLength: 30,
                          maxLines: 2,
                          update: (value) =>
                              _profile.copyWith(signature: value),
                        ),
                      ),
                    ],
                  ),
                ),
                const _SectionLabel('个人信息'),
                _ProfileSection(
                  child: Column(
                    children: [
                      _ProfileTile(
                        title: '性别',
                        value: _show(_profile.gender),
                        onTap: _editGender,
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: '生日',
                        value: _showBirthday(_profile.profileBirthday),
                        onTap: _editBirthday,
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: 'PeiLink ID',
                        value: _show(_profile.peiLinkId, fallback: '未设置'),
                        onTap: () => _editText(
                          title: '设置 PeiLink ID',
                          value: _profile.peiLinkId,
                          hint: '用于展示的个人 ID',
                          allowEmpty: false,
                          maxLength: 30,
                          update: (value) =>
                              _profile.copyWith(peiLinkId: value),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 14, 24, 28),
                  child: Text(
                    '这里是你的个人展示资料，不会自动加入角色聊天。',
                    style: TextStyle(
                      color: Color(0xFF999999),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
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

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFEDE8F4)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A67558C),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final file = path.isEmpty ? null : File(path);
    final hasImage = file != null && file.existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 54,
        height: 54,
        color: const Color(0xFFEDEDED),
        child: hasImage
            ? Image.file(file, fit: BoxFit.cover)
            : const Icon(
                Icons.person_rounded,
                color: Color(0xFF999999),
                size: 32,
              ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.title,
    required this.onTap,
    this.value,
    this.trailing,
  });

  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 72,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?trailing,
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 210),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF777777), fontSize: 16),
              ),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFB6B6B6)),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _InsetDivider extends StatelessWidget {
  const _InsetDivider();
  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 20, color: Color(0xFFEAEAEA));
  }
}
