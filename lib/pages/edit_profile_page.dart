// ignore_for_file: unused_field, unused_import, unused_element

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user_profile.dart';
import '../services/user_profile_storage_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.initialProfile});

  final UserProfile initialProfile;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _storage = UserProfileStorageService();

  late final TextEditingController _nicknameController;
  late final TextEditingController _birthdayController;
  late final TextEditingController _identityController;
  late final TextEditingController _workController;
  late final TextEditingController _likesController;
  late final TextEditingController _dislikesController;
  late final TextEditingController _preferenceController;

  late String _avatarPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _nicknameController = TextEditingController(text: profile.peiCallName);
    _birthdayController = TextEditingController(text: profile.birthday);
    _identityController = TextEditingController(text: profile.identity);
    _workController = TextEditingController(text: profile.workAndSchedule);
    _likesController = TextEditingController(text: profile.likes);
    _dislikesController = TextEditingController(text: profile.dislikes);
    _preferenceController = TextEditingController(
      text: profile.interactionPreference,
    );
    _avatarPath = profile.avatarPath;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _birthdayController.dispose();
    _identityController.dispose();
    _workController.dispose();
    _likesController.dispose();
    _dislikesController.dispose();
    _preferenceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = widget.initialProfile.copyWith(
      peiCallName: _nicknameController.text.trim(),
      birthday: _birthdayController.text.trim(),
      identity: _identityController.text.trim(),
      workAndSchedule: _workController.text.trim(),
      likes: _likesController.text.trim(),
      dislikes: _dislikesController.text.trim(),
      interactionPreference: _preferenceController.text.trim(),
    );

    try {
      await _storage.saveProfile(profile);
      if (!mounted) return;
      Navigator.pop(context, profile);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存资料失败，请稍后再试')));
    }
  }

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
          title: const Text('我的人设'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中' : '保存'),
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: _EditBackground()),
            Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
                children: [
                  _SectionCard(
                    title: '角色眼中的你',
                    children: [
                      _ProfileField(
                        controller: _nicknameController,
                        label: '角色对你的称呼',
                        hint: '例如：念念',
                        maxLength: 20,
                        requiredField: true,
                      ),
                      _ProfileField(
                        controller: _birthdayController,
                        label: '生日',
                        hint: '例如：3月8日，年份可不填',
                        maxLength: 30,
                      ),
                      _ProfileField(
                        controller: _identityController,
                        label: '身份与关系',
                        hint: '例如：裴简澈的恋人',
                        maxLength: 60,
                        requiredField: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: '他需要知道的你',
                    children: [
                      _ProfileField(
                        controller: _workController,
                        label: '工作与作息',
                        hint: '例如：客服，隔天上班，凌晨下班',
                        maxLines: 3,
                        maxLength: 180,
                      ),
                      _ProfileField(
                        controller: _likesController,
                        label: '喜欢的事物',
                        hint: '兴趣、食物、游戏、旅行等',
                        maxLines: 4,
                        maxLength: 260,
                      ),
                      _ProfileField(
                        controller: _dislikesController,
                        label: '不喜欢的事物',
                        hint: '雷点、讨厌的表达或行为',
                        maxLines: 4,
                        maxLength: 260,
                      ),
                      _ProfileField(
                        controller: _preferenceController,
                        label: '相处偏好',
                        hint: '希望他怎样回应你、陪伴你',
                        maxLines: 5,
                        maxLength: 360,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? '正在保存…' : '保存资料'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '这些内容只保存在当前设备中。保存后，新的聊天会自动读取。',
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

class _EditBackground extends StatelessWidget {
  const _EditBackground();

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

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.avatarPath,
    required this.onPick,
    required this.onRemove,
  });

  final String avatarPath;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final avatarFile = avatarPath.isEmpty ? null : File(avatarPath);
    final hasAvatar = avatarFile != null && avatarFile.existsSync();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 46,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            backgroundImage: hasAvatar ? FileImage(File(avatarPath)) : null,
            child: hasAvatar
                ? null
                : Icon(
                    Icons.person_rounded,
                    color: Colors.white.withValues(alpha: 0.78),
                    size: 54,
                  ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(hasAvatar ? '更换头像' : '选择头像'),
              ),
              if (hasAvatar)
                TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('移除'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.requiredField = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final bool requiredField;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        style: const TextStyle(color: Colors.white),
        validator: requiredField
            ? (value) {
                if (value == null || value.trim().isEmpty) return '这里不能空着';
                return null;
              }
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: maxLines > 1,
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.30)),
          counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          ),
        ),
      ),
    );
  }
}
