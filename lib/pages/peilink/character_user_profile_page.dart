import 'package:flutter/material.dart';

import '../../models/character_user_profile.dart';
import '../../services/character_user_profile_storage_service.dart';
import '../../theme/app_theme_background.dart';

class CharacterUserProfilePage extends StatefulWidget {
  const CharacterUserProfilePage({
    super.key,
    required this.characterId,
    required this.characterName,
  });
  final String characterId;
  final String characterName;

  @override
  State<CharacterUserProfilePage> createState() =>
      _CharacterUserProfilePageState();
}

class _CharacterUserProfilePageState extends State<CharacterUserProfilePage> {
  static const _descriptionLimit = 2000;
  late final CharacterUserProfileStorageService _storage;
  final _name = TextEditingController();
  final _description = TextEditingController();
  CharacterUserProfile? _profile;
  String _gender = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _storage = CharacterUserProfileStorageService(
      characterId: widget.characterId,
    );
    _description.addListener(_refreshCount);
    _load();
  }

  void _refreshCount() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final profile = await _storage.load();
    if (!mounted) return;
    _profile = profile;
    _name.text = profile.userName;
    _gender = profile.gender;
    _description.text = profile.effectiveDescription;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving || _profile == null) return;
    setState(() => _saving = true);
    await _storage.save(
      _profile!.copyWith(
        userName: _name.text.trim(),
        gender: _gender,
        personaDescription: _description.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('个人设定已保存')));
  }

  @override
  void dispose() {
    _description.removeListener(_refreshCount);
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('我的个人设定'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
                children: [
                  Text(
                    '你在「${widget.characterName}」世界里的身份',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF292536),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '只对当前角色生效，不修改真实个人资料。',
                    style: TextStyle(color: Color(0xFF918A9B), fontSize: 13),
                  ),
                  const SizedBox(height: 22),
                  _ProfileCard(
                    title: '设定名称',
                    caption: '角色如何称呼或认识你',
                    child: _SoftTextField(
                      controller: _name,
                      hintText: '例如：林念念',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ProfileCard(
                    title: '性别',
                    child: Row(
                      children: [
                        _GenderChoice(
                          symbol: '♀',
                          label: '女',
                          selected: _gender == '女',
                          onTap: () => setState(() => _gender = '女'),
                        ),
                        const SizedBox(width: 10),
                        _GenderChoice(
                          symbol: '♂',
                          label: '男',
                          selected: _gender == '男',
                          onTap: () => setState(() => _gender = '男'),
                        ),
                        const SizedBox(width: 10),
                        _GenderChoice(
                          symbol: '∞',
                          label: '其他',
                          selected: _gender == '其他',
                          onTap: () => setState(() => _gender = '其他'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ProfileCard(
                    title: '设定描述',
                    caption: '年龄、身份、与角色的关系、角色如何称呼你、所在世界，以及任何希望角色知道的信息。',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _SoftTextField(
                          controller: _description,
                          hintText: '用你习惯的方式，描述角色眼中的你……',
                          minLines: 7,
                          maxLines: 12,
                          maxLength: _descriptionLimit,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${_description.text.characters.length} / $_descriptionLimit',
                          style: const TextStyle(
                            color: Color(0xFFA29BAB),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(_saving ? '正在保存…' : '保存设定'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: const Color(0xFF7063C8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.title, required this.child, this.caption});
  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (caption != null) ...[
          const SizedBox(height: 5),
          Text(
            caption!,
            style: const TextStyle(
              color: Color(0xFF9A93A2),
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 13),
        child,
      ],
    ),
  );
}

class _SoftTextField extends StatelessWidget {
  const _SoftTextField({
    required this.controller,
    required this.hintText,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
  });
  final TextEditingController controller;
  final String hintText;
  final int? minLines;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    minLines: minLines,
    maxLines: maxLines,
    maxLength: maxLength,
    decoration: InputDecoration(
      hintText: hintText,
      counterText: '',
      filled: true,
      fillColor: const Color(0xFFF5F3FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class _GenderChoice extends StatelessWidget {
  const _GenderChoice({
    required this.symbol,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String symbol;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0EDFF) : const Color(0xFFF8F7FB),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? const Color(0xFF8275DD) : const Color(0xFFE5E1EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              symbol,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF7164C9)
                    : const Color(0xFF777181),
                fontSize: 23,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ),
  );
}
