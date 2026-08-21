import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'character_profile_structure_page.dart';

import '../../models/ai_character.dart';
import '../../models/character_settings.dart';
import '../../services/character_avatar_storage_service.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';

class CharacterProfileEditPage extends StatefulWidget {
  const CharacterProfileEditPage({super.key, required this.characterId});

  final String characterId;

  @override
  State<CharacterProfileEditPage> createState() =>
      _CharacterProfileEditPageState();
}

class _CharacterProfileEditPageState extends State<CharacterProfileEditPage> {
  CharacterSettingsStorageService get _storage =>
      CharacterSettingsStorageService(characterId: widget.characterId);
  final CharacterRegistryService _registry = CharacterRegistryService();
  final CharacterAvatarStorageService _avatarStorage =
      const CharacterAvatarStorageService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _relationController = TextEditingController();
  final TextEditingController _birthdayController = TextEditingController();
  final TextEditingController _introductionController = TextEditingController();

  CharacterSettings _settings = CharacterSettings.defaults();
  AiCharacter _character = AiCharacter.placeholder();
  String _avatarPath = '';
  bool _removeAvatar = false;
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
    _remarkController.dispose();
    _relationController.dispose();
    _birthdayController.dispose();
    _introductionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final characters = await _registry.loadCharacters();
    final character = characters.firstWhere(
      (item) => item.id == widget.characterId,
      orElse: AiCharacter.placeholder,
    );
    final settings = await _storage.loadSettings();
    if (!mounted) return;

    _settings = settings;
    _character = character;
    _avatarPath = character.avatarPath;
    _nameController.text = settings.characterName;
    _remarkController.text = settings.remark;
    _relationController.text = settings.relation;
    _birthdayController.text = settings.birthday;
    _introductionController.text = character.characterIntro;
    setState(() => _loading = false);
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _avatarPath = picked.path;
        _removeAvatar = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('选择头像失败，请稍后再试')));
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final characterName = _nameController.text.trim();
    if (characterName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('角色本名不能为空')));
      return;
    }

    setState(() => _saving = true);

    try {
      var savedAvatarPath = _character.avatarPath;
      if (_removeAvatar) {
        await _avatarStorage.removeAvatar(_character.id);
        savedAvatarPath = '';
      } else if (_avatarPath.isNotEmpty &&
          _avatarPath != _character.avatarPath) {
        savedAvatarPath = await _avatarStorage.saveAvatar(
          characterId: _character.id,
          sourcePath: _avatarPath,
        );
      }

      final updatedSettings = _settings.copyWith(
        characterName: characterName,
        remark: _remarkController.text.trim(),
        relation: _relationController.text.trim(),
        birthday: _birthdayController.text.trim(),
      );
      await _storage.saveSettings(updatedSettings);

      await _registry.updateCharacter(
        _character.copyWith(
          characterName: characterName,
          remark: _remarkController.text.trim(),
          relationship: _relationController.text.trim(),
          avatarPath: savedAvatarPath,
          characterIntro: _introductionController.text.trim(),
          persona: _character.persona,
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

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarFile = _avatarPath.isEmpty ? null : File(_avatarPath);
    final hasAvatar = avatarFile != null && avatarFile.existsSync();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text('基础资料'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF4F4F4),
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 30),
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _pickAvatar,
                        child: CircleAvatar(
                          radius: 46,
                          backgroundColor: const Color(0xFFE5EBEE),
                          backgroundImage: hasAvatar
                              ? FileImage(avatarFile)
                              : null,
                          child: hasAvatar
                              ? null
                              : const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 40,
                                  color: Color(0xFF647C8B),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _pickAvatar,
                            child: Text(hasAvatar ? '更换头像' : '选择头像'),
                          ),
                          if (hasAvatar)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _avatarPath = '';
                                  _removeAvatar = true;
                                });
                              },
                              child: const Text('移除'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),
                Container(
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(
                      Icons.view_agenda_outlined,
                      color: Color(0xFF526A78),
                    ),
                    title: const Text('角色档案'),
                    subtitle: const Text('查看结构化资料框架，暂不迁移原 Prompt'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CharacterProfileStructurePage(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                _field('本名', _nameController),
                _field('备注', _remarkController, hint: '你现在想怎么称呼他，例如：老裴、臭狐狸'),
                _field('关系', _relationController, hint: '例如：恋人、朋友、家人'),
                const SizedBox(height: 10),
                _field('生日', _birthdayController, hint: '例如：12月12日'),
                const SizedBox(height: 10),
                _field(
                  '角色简介',
                  _introductionController,
                  hint: '一句介绍，留空时资料页显示“暂未填写”',
                  maxLines: 2,
                  maxLength: 20,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    '备注只影响你看到的名字，不会改变角色本名。',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 13),
                  ),
                ),
              ],
            ),
    );
  }
}
