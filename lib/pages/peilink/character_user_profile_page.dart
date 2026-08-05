import 'package:flutter/material.dart';

import '../../models/character_user_profile.dart';
import '../../services/character_user_profile_storage_service.dart';

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
  late final CharacterUserProfileStorageService _storage;
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _identity = TextEditingController();
  final _relationship = TextEditingController();
  final _callName = TextEditingController();
  final _world = TextEditingController();
  final _description = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _storage = CharacterUserProfileStorageService(
      characterId: widget.characterId,
    );
    _load();
  }

  Future<void> _load() async {
    final profile = await _storage.load();
    if (!mounted) return;
    _name.text = profile.userName;
    _age.text = profile.age;
    _identity.text = profile.identity;
    _relationship.text = profile.relationship;
    _callName.text = profile.callName;
    _world.text = profile.world;
    _description.text = profile.description;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _storage.save(
      CharacterUserProfile(
        characterId: widget.characterId,
        userName: _name.text.trim(),
        age: _age.text.trim(),
        identity: _identity.text.trim(),
        relationship: _relationship.text.trim(),
        callName: _callName.text.trim(),
        world: _world.text.trim(),
        description: _description.text.trim(),
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
    _name.dispose();
    _age.dispose();
    _identity.dispose();
    _relationship.dispose();
    _callName.dispose();
    _world.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的个人设定'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              children: [
                Text(
                  '你在${widget.characterName}世界里的身份',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '只绑定当前角色，不会修改你的真实个人资料。',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                ),
                const SizedBox(height: 22),
                _field(_name, '姓名', '例如：林念念'),
                _field(_age, '年龄', '例如：24'),
                _field(_identity, '身份', '例如：妻子、弟子'),
                _field(_relationship, '关系', '例如：妻子、侄女'),
                _field(_callName, '他对你的称呼', '例如：念念、徒儿、声声'),
                _field(_world, '世界', '例如：现代都市、仙侠'),
                _field(_description, '补充', '补充你与当前角色的生活背景', maxLines: 4),
              ],
            ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
