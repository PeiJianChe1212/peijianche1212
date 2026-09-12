import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/group_chat.dart';
import '../../models/group_member.dart';
import '../../services/character_registry_service.dart';
import '../../services/group_chat_storage_service.dart';

class CreateGroupChatPage extends StatefulWidget {
  const CreateGroupChatPage({super.key});

  @override
  State<CreateGroupChatPage> createState() => _CreateGroupChatPageState();
}

class _CreateGroupChatPageState extends State<CreateGroupChatPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();
  final GroupChatStorageService _storage = GroupChatStorageService();
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedIds = <String>{};

  List<AiCharacter> _characters = const [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCharacters();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCharacters() async {
    final characters = await _registry.loadCharacters();
    if (!mounted) return;
    setState(() {
      _characters = characters;
      _loading = false;
    });
  }

  Future<void> _createGroup() async {
    if (_selectedIds.length < 2 || _saving) return;
    final id = 'group_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    final selected = _characters
        .where((character) => _selectedIds.contains(character.id))
        .toList();
    final customName = _nameController.text.trim();
    final defaultName = selected
        .map((item) => item.displayName)
        .take(3)
        .join('、');
    final group = GroupChat(
      id: id,
      name: customName.isEmpty ? defaultName : customName,
      members: selected
          .map(
            (character) => GroupMember(
              groupId: id,
              characterId: character.id,
              joinedAt: now,
            ),
          )
          .toList(),
      createdAt: now,
      lastActiveAt: now,
    );

    setState(() => _saving = true);
    try {
      // 存储写入必须有上限，任何卡住都不能让用户停在“创建中”。
      await _storage
          .upsertGroup(group)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      _saving = false;
      // 结果类型保持 bool，兼容所有既有调用方的 Navigator.push<bool>。
      Navigator.pop(context, true);
    } catch (_) {
      // 失败时做最小回滚，避免留下半创建群聊。
      try {
        await _storage
            .deleteGroup(group.id)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // 回滚失败不覆盖主错误提示。
      }
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建群聊失败，请稍后再试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _selectedIds.length >= 2 && !_saving;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F4F4),
        surfaceTintColor: Colors.transparent,
        title: const Text('创建群聊'),
        actions: [
          TextButton(
            onPressed: canCreate ? _createGroup : null,
            child: Text(
              _saving ? '创建中' : '完成',
              style: TextStyle(
                color: canCreate
                    ? const Color(0xFF4E8EAD)
                    : const Color(0xFFB8B8B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: TextField(
                    controller: _nameController,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: '群名称（可稍后修改）',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '选择成员  ${_selectedIds.length}人',
                      style: const TextStyle(
                        color: Color(0xFF777777),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  // Material 外壳保证 CheckboxListTile 的水波纹可见。
                  child: Material(
                    color: Colors.white,
                    child: ListView.separated(
                      itemCount: _characters.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 76),
                      itemBuilder: (context, index) {
                        final character = _characters[index];
                        final selected = _selectedIds.contains(character.id);
                        return CheckboxListTile(
                          value: selected,
                          activeColor: const Color(0xFF4E8EAD),
                          secondary: _CharacterAvatar(character: character),
                          title: Text(character.displayName),
                          subtitle: character.relationship.trim().isEmpty
                              ? null
                              : Text(character.relationship),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedIds.add(character.id);
                              } else {
                                _selectedIds.remove(character.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _selectedIds.length < 2
                          ? '至少选择2名角色才能创建群聊'
                          : '第一批只开放群聊骨架，角色回复会在下一批接入。',
                      style: const TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CharacterAvatar extends StatelessWidget {
  const _CharacterAvatar({required this.character});

  final AiCharacter character;

  @override
  Widget build(BuildContext context) {
    final path = character.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.file(File(path), width: 46, height: 46, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBEE),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.auto_awesome_rounded),
    );
  }
}
