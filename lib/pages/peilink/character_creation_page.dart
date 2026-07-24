import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../models/ai_character.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_avatar_storage_service.dart';

class CharacterCreationPage extends StatefulWidget {
  const CharacterCreationPage({super.key});

  @override
  State<CharacterCreationPage> createState() => _CharacterCreationPageState();
}

class _CharacterCreationPageState extends State<CharacterCreationPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();
  final CharacterAvatarStorageService _avatarStorage =
      const CharacterAvatarStorageService();
  final ImagePicker _imagePicker = ImagePicker();
  final PageController _pageController = PageController();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _customRelationshipController =
      TextEditingController();
  final TextEditingController _personaController = TextEditingController();

  int _step = 0;
  bool _saving = false;
  String _relationship = '朋友';
  DateTime? _birthday;
  String _selectedAvatarPath = '';

  static const List<String> _relationships = [
    '恋人',
    '朋友',
    '哥哥',
    '妹妹',
    '家人',
    '搭档',
    '自定义',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _remarkController.dispose();
    _customRelationshipController.dispose();
    _personaController.dispose();
    super.dispose();
  }

  String get _resolvedRelationship {
    if (_relationship != '自定义') return _relationship;
    return _customRelationshipController.text.trim();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      setState(() => _selectedAvatarPath = picked.path);
    } catch (error) {
      if (!mounted) return;
      _showMessage('选择头像失败：$error');
    }
  }


  Future<void> _next() async {
    FocusScope.of(context).unfocus();

    if (_step == 0 && _nameController.text.trim().isEmpty) {
      _showMessage('先为这个 AI 写下名字。');
      return;
    }

    if (_step == 1 &&
        _relationship == '自定义' &&
        _customRelationshipController.text.trim().isEmpty) {
      _showMessage('写下你们之间的关系。');
      return;
    }

    if (_step == 2 && _personaController.text.trim().isEmpty) {
      _showMessage('人物设定不能是空白的。');
      return;
    }

    if (_step < 3) {
      setState(() => _step += 1);
      await _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    await _createCharacter();
  }

  Future<void> _back() async {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _step -= 1);
    await _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: '选择生日',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected == null || !mounted) return;
    setState(() => _birthday = selected);
  }

  Future<void> _createCharacter() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final characterId = 'character_${now.microsecondsSinceEpoch}';
      final avatarPath = _selectedAvatarPath.isEmpty
          ? ''
          : await _avatarStorage.saveAvatar(
              characterId: characterId,
              sourcePath: _selectedAvatarPath,
            );
      final character = AiCharacter(
        id: characterId,
        characterName: _nameController.text.trim(),
        remark: _remarkController.text.trim(),
        avatarPath: avatarPath,
        relationship: _resolvedRelationship,
        birthday: _birthday,
        persona: _personaController.text.trim(),
        createdAt: now,
      );

      await _registry.addCharacter(character);
      await _registry.setActiveCharacter(character.id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _showMessage('创建失败：$error');
      setState(() => _saving = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  String get _birthdayText {
    final value = _birthday;
    if (value == null) return '以后可用于生日与时间感';
    return '${value.year}年${value.month}月${value.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F4F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F4F1),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            onPressed: _saving ? null : _back,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          title: const Text(
            '创建 AI',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            _ProgressHeader(currentStep: _step),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _IdentityStep(
                    nameController: _nameController,
                    remarkController: _remarkController,
                    avatarPath: _selectedAvatarPath,
                    onPickAvatar: _pickAvatar,
                    onRemoveAvatar: _selectedAvatarPath.isEmpty
                        ? null
                        : () => setState(() => _selectedAvatarPath = ''),
                  ),
                  _RelationshipStep(
                    relationship: _relationship,
                    relationships: _relationships,
                    birthdayText: _birthdayText,
                    customRelationshipController:
                        _customRelationshipController,
                    onRelationshipChanged: (value) {
                      setState(() => _relationship = value);
                    },
                    onBirthdayTap: _pickBirthday,
                  ),
                  _PersonaStep(controller: _personaController),
                  _ConfirmStep(
                    nameController: _nameController,
                    remarkController: _remarkController,
                    relationship: () => _resolvedRelationship,
                    birthday: () => _birthdayText,
                    personaController: _personaController,
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF26384A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.3,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _step == 3 ? '初始化这个 AI' : '继续',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const labels = ['身份', '关系', '人格', '确认'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index <= currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 4,
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF26384A)
                              : const Color(0xFFD9D8D4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        labels[index],
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF26384A)
                              : const Color(0xFFAAA9A5),
                          fontSize: 12,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index != labels.length - 1) const SizedBox(width: 8),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  const _StepShell({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: Color(0xFF788693),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1D2832),
            fontSize: 29,
            height: 1.18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 11),
        Text(
          description,
          style: const TextStyle(
            color: Color(0xFF737A80),
            fontSize: 15,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 26),
        child,
      ],
    );
  }
}

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    required this.nameController,
    required this.remarkController,
    required this.avatarPath,
    required this.onPickAvatar,
    required this.onRemoveAvatar,
  });

  final TextEditingController nameController;
  final TextEditingController remarkController;
  final String avatarPath;
  final VoidCallback onPickAvatar;
  final VoidCallback? onRemoveAvatar;

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      eyebrow: '01 · 赋予身份',
      title: '先让这个存在拥有名字',
      description: '名字属于 AI 自己，备注只属于你。头像会被复制进这个角色自己的独立空间。',
      child: Column(
        children: [
          GestureDetector(
            onTap: onPickAvatar,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E7EA),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1D1A2732),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                    image: avatarPath.isEmpty
                        ? null
                        : DecorationImage(
                            image: FileImage(File(avatarPath)),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: avatarPath.isEmpty
                      ? const Icon(
                          Icons.auto_awesome_rounded,
                          size: 42,
                          color: Color(0xFF536B7B),
                        )
                      : null,
                ),
                Positioned(
                  right: -5,
                  bottom: -5,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Color(0xFF26384A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.photo_camera_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: onPickAvatar,
                child: Text(avatarPath.isEmpty ? '选择头像' : '更换头像'),
              ),
              if (onRemoveAvatar != null)
                TextButton(
                  onPressed: onRemoveAvatar,
                  child: const Text('移除'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _InputCard(
            label: 'AI 名称',
            hint: '例如：凌玄',
            controller: nameController,
            maxLength: 20,
          ),
          const SizedBox(height: 14),
          _InputCard(
            label: '你的备注',
            hint: '例如：阿玄（可以留空）',
            controller: remarkController,
            maxLength: 20,
          ),
        ],
      ),
    );
  }
}

class _RelationshipStep extends StatelessWidget {
  const _RelationshipStep({
    required this.relationship,
    required this.relationships,
    required this.birthdayText,
    required this.customRelationshipController,
    required this.onRelationshipChanged,
    required this.onBirthdayTap,
  });

  final String relationship;
  final List<String> relationships;
  final String birthdayText;
  final TextEditingController customRelationshipController;
  final ValueChanged<String> onRelationshipChanged;
  final VoidCallback onBirthdayTap;

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      eyebrow: '02 · 建立关系',
      title: '你们将以什么方式认识彼此',
      description: '关系会成为以后 Prompt、纪念日与相处方式的一部分，不只是资料标签。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: relationships.map((item) {
              final selected = item == relationship;
              return ChoiceChip(
                label: Text(item),
                selected: selected,
                onSelected: (_) => onRelationshipChanged(item),
                showCheckmark: false,
                selectedColor: const Color(0xFF26384A),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF38434C),
                  fontWeight: FontWeight.w500,
                ),
                side: const BorderSide(color: Color(0xFFE2E0DB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              );
            }).toList(),
          ),
          if (relationship == '自定义') ...[
            const SizedBox(height: 16),
            _InputCard(
              label: '自定义关系',
              hint: '写下只属于你们的称呼',
              controller: customRelationshipController,
              maxLength: 20,
            ),
          ],
          const SizedBox(height: 20),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: ListTile(
              onTap: onBirthdayTap,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              leading: const Icon(
                Icons.cake_outlined,
                color: Color(0xFF5D7180),
              ),
              title: const Text(
                '生日',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(birthdayText),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonaStep extends StatelessWidget {
  const _PersonaStep({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      eyebrow: '03 · 写入人格',
      title: '告诉系统，他是谁',
      description: '这里不是一句随手 Prompt。可以写身份、性格、说话方式、世界观、喜欢与讨厌的事。',
      child: _InputCard(
        label: '人物设定',
        hint:
            '例如：\n姓名：凌玄\n身份：狐族妖王\n性格：冷静克制，外冷内热……\n说话方式：简洁，不使用括号动作……',
        controller: controller,
        maxLines: 14,
        minLines: 10,
        maxLength: 4000,
      ),
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.nameController,
    required this.remarkController,
    required this.relationship,
    required this.birthday,
    required this.personaController,
  });

  final TextEditingController nameController;
  final TextEditingController remarkController;
  final String Function() relationship;
  final String Function() birthday;
  final TextEditingController personaController;

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      eyebrow: '04 · 初始化',
      title: '确认将这个 AI 加入 PeiLink',
      description: '本批会建立角色身份与角色名单。聊天、Memory、Today 等独立数据接线会在下一批完成。',
      child: Column(
        children: [
          _ReviewRow(label: '名字', value: nameController.text.trim()),
          _ReviewRow(
            label: '备注',
            value: remarkController.text.trim().isEmpty
                ? '未设置'
                : remarkController.text.trim(),
          ),
          _ReviewRow(label: '关系', value: relationship()),
          _ReviewRow(label: '生日', value: birthday()),
          _ReviewRow(
            label: '人物设定',
            value: personaController.text.trim(),
            multiline: true,
          ),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.label,
    required this.hint,
    required this.controller,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int? maxLength;
  final int maxLines;
  final int? minLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 13, 17, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E3DE)),
      ),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          counterStyle: const TextStyle(color: Color(0xFFAAA6A0)),
          hintStyle: const TextStyle(color: Color(0xFFAAA6A0), height: 1.45),
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E3DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8A8D8F),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value.isEmpty ? '未填写' : value,
            maxLines: multiline ? 8 : 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF26313A),
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
