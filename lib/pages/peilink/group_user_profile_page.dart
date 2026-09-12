import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/group_user_profile.dart';
import '../../widgets/group/group_visuals.dart';
import '../../services/group_user_profile_storage_service.dart';

/// "我的群聊身份"编辑页：按 groupId 独立保存，与其它群互不影响。
class GroupUserProfilePage extends StatefulWidget {
  const GroupUserProfilePage({
    super.key,
    required this.groupId,
    this.groupName = '',
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupUserProfilePage> createState() => _GroupUserProfilePageState();
}

class _GroupUserProfilePageState extends State<GroupUserProfilePage> {
  final _picker = ImagePicker();
  late final GroupUserProfileStorageService _storage =
      GroupUserProfileStorageService(groupId: widget.groupId);
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _avatarPath = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // 显示时叠加全局用户资料作为默认值，但不写盘。
    final profile = await _storage.loadResolved();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile.displayName;
      _descriptionController.text = profile.selfDescription;
      _avatarPath = profile.avatarPath;
      _loading = false;
    });
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null) return;
      final path = await _storage.saveAvatarCopy(picked.path);
      if (!mounted || path.isEmpty) return;
      setState(() => _avatarPath = path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('选择头像失败，请稍后再试')));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _storage.save(
        GroupUserProfile(
          groupId: widget.groupId,
          displayName: _nameController.text.trim(),
          avatarPath: _avatarPath,
          selfDescription: _descriptionController.text.trim(),
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后再试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GroupVisuals.page,
      appBar: AppBar(
        backgroundColor: GroupVisuals.page,
        surfaceTintColor: Colors.transparent,
        title: const Text('我的群聊身份'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: Text(
              _saving ? '保存中' : '保存',
              style: TextStyle(
                color: _saving ? const Color(0xFFB8B8B8) : GroupVisuals.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  decoration: GroupVisuals.card(),
                  child: Row(
                    children: [
                      InkWell(
                        key: const ValueKey('group-identity-avatar'),
                        onTap: _pickAvatar,
                        borderRadius: BorderRadius.circular(16),
                        child: _Avatar(path: _avatarPath),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.groupName.isEmpty
                              ? '这个群里，大家看到的你'
                              : '在「${widget.groupName}」里，大家看到的你',
                          style: const TextStyle(
                            color: Color(0xFF8A9298),
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _FieldCard(
                  label: '群内昵称',
                  child: TextField(
                    key: const ValueKey('group-identity-name'),
                    controller: _nameController,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '这个群里显示的名字',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _FieldCard(
                  label: '群内身份说明',
                  child: TextField(
                    key: const ValueKey('group-identity-description'),
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '例如：和大家认识很久的朋友',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 14, 6, 0),
                  child: Text(
                    '这里只描述你在本群公开的身份，不会覆盖各角色对你的私人设定。',
                    style: TextStyle(
                      color: Color(0xFF9AA5AB),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: GroupVisuals.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6F8FA3),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          child,
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
    final trimmed = path.trim();
    final file = trimmed.isEmpty ? null : File(trimmed);
    final hasImage = file?.existsSync() == true;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFECE8F5),
        border: Border.all(color: const Color(0xFFD4CCE5)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.file(file!, fit: BoxFit.cover)
          : const Icon(
              Icons.person_rounded,
              color: Color(0xFF7E8B92),
              size: 30,
            ),
    );
  }
}
