import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/user_profile_storage_service.dart';
import 'edit_profile_page.dart';
import 'profile_field_edit_page.dart';
import 'profile_region_page.dart';

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
      await _save(_profile.copyWith(avatarPath: path));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择头像失败：$error')),
      );
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

  Future<void> _editRegion() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileRegionPage(initialValue: _profile.region),
      ),
    );
    if (result == null) return;
    await _save(_profile.copyWith(region: result));
  }

  Future<void> _editPersona() async {
    final result = await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(initialProfile: _profile),
      ),
    );
    if (result == null) return;
    await _save(result);
  }

  String _show(String value, {String fallback = '未填写'}) {
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F2),
        surfaceTintColor: Colors.transparent,
        title: const Text('个人资料'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      _ProfileTile(
                        title: '头像',
                        trailing: _Avatar(path: _profile.avatarPath),
                        onTap: _pickAvatar,
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: '名字',
                        value: _profile.nickname,
                        onTap: () => _editText(
                          title: '设置名字',
                          value: _profile.nickname,
                          allowEmpty: false,
                          maxLength: 20,
                          update: (value) => _profile.copyWith(nickname: value),
                        ),
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: '性别',
                        value: _show(_profile.gender),
                        onTap: _editGender,
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: '地区',
                        value: _show(_profile.region),
                        onTap: _editRegion,
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: 'PeiLink ID',
                        value: _profile.peiLinkId,
                        onTap: () => _editText(
                          title: '设置 PeiLink ID',
                          value: _profile.peiLinkId,
                          hint: '用于展示的个人 ID',
                          allowEmpty: false,
                          maxLength: 30,
                          update: (value) => _profile.copyWith(peiLinkId: value),
                        ),
                      ),
                      const _InsetDivider(),
                      _ProfileTile(
                        title: '签名',
                        value: _show(_profile.signature),
                        onTap: () => _editText(
                          title: '设置签名',
                          value: _profile.signature,
                          hint: '写一句属于你的话',
                          maxLength: 30,
                          maxLines: 2,
                          update: (value) => _profile.copyWith(signature: value),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Text(
                    '这里是你的个人展示资料，不会自动加入角色聊天所读取的资料。',
                    style: TextStyle(
                      color: Color(0xFF999999),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
                Container(
                  color: Colors.white,
                  child: _ProfileTile(
                    title: '我的人设',
                    value: '给角色了解的你',
                    onTap: _editPersona,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 28),
                  child: Text(
                    '这里填写的称呼、作息、喜好与相处偏好，会加入角色聊天所读取的资料。',
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
            : const Icon(Icons.person_rounded, color: Color(0xFF999999), size: 32),
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
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) trailing!,
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
