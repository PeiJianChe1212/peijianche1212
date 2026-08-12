import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/group_chat.dart';
import '../../models/group_member.dart';
import '../../services/character_registry_service.dart';
import '../../services/group_chat_storage_service.dart';
import '../../services/group_message_storage_service.dart';

class GroupChatSettingsPage extends StatefulWidget {
  const GroupChatSettingsPage({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupChatSettingsPage> createState() => _GroupChatSettingsPageState();
}

class _GroupChatSettingsPageState extends State<GroupChatSettingsPage> {
  final GroupChatStorageService _groupStorage = GroupChatStorageService();
  final CharacterRegistryService _registry = CharacterRegistryService();

  GroupChat? _group;
  List<AiCharacter> _characters = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _groupStorage.loadGroup(widget.groupId),
      _registry.loadCharacters(),
    ]);
    if (!mounted) return;
    setState(() {
      _group = results[0] as GroupChat?;
      _characters = results[1] as List<AiCharacter>;
      _loading = false;
    });
  }

  Future<void> _rename() async {
    final group = _group;
    if (group == null) return;

    // 不在异步弹窗外持有并手动释放 TextEditingController。
    // Flutter 关闭 Dialog 时仍可能在拆除 TextField 的依赖关系，过早 dispose
    // 会触发 framework.dart 的 _dependents.isEmpty 断言。
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameGroupDialog(initialName: group.name),
    );
    if (!mounted || name == null || name.isEmpty || name == group.name) return;
    await _save(group.copyWith(name: name));
  }

  Future<void> _editMembers() async {
    final group = _group;
    if (group == null) return;
    final selected = group.memberCharacterIds.toSet();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '管理群成员',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: selected.length >= 2
                              ? () => Navigator.pop(context, selected)
                              : null,
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _characters.length,
                      itemBuilder: (context, index) {
                        final character = _characters[index];
                        return CheckboxListTile(
                          value: selected.contains(character.id),
                          title: Text(character.displayName),
                          onChanged: (value) {
                            setSheetState(() {
                              if (value == true) {
                                selected.add(character.id);
                              } else {
                                selected.remove(character.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '群聊至少保留2名角色成员',
                      style: TextStyle(color: Color(0xFF999999)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null) return;
    final oldMembers = {
      for (final item in group.members) item.characterId: item,
    };
    final now = DateTime.now();
    final members = result
        .map(
          (id) =>
              oldMembers[id] ??
              GroupMember(groupId: group.id, characterId: id, joinedAt: now),
        )
        .toList();
    await _save(group.copyWith(members: members));
  }

  Future<void> _save(GroupChat group) async {
    await _groupStorage.upsertGroup(group);
    if (!mounted) return;
    setState(() => _group = group);
  }

  Future<void> _clearMessages() async {
    final confirmed = await _confirm('清空聊天记录', '清空后无法恢复，确定继续吗？');
    if (!confirmed) return;
    final group = _group;
    if (group == null) return;
    await GroupMessageStorageService(groupId: group.id).clearMessages();
    await _save(
      group.copyWith(
        lastMessage: '',
        clearLastMessageAt: true,
        lastActiveAt: DateTime.now(),
        unreadCount: 0,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('群聊记录已清空')));
  }

  Future<void> _deleteGroup() async {
    final confirmed = await _confirm('删除并退出群聊', '群聊和本地聊天记录都会被删除。');
    if (!confirmed) return;
    await _groupStorage.deleteGroup(widget.groupId);
    await GroupMessageStorageService(
      groupId: widget.groupId,
    ).deleteGroupDirectory();
    if (!mounted) return;
    Navigator.pop(context, 'deleted');
  }

  Future<bool> _confirm(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定'),
              ),
            ],
          ),
        ) ??
        false;
  }

  AiCharacter? _character(String id) {
    for (final item in _characters) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text('群聊设置'),
        backgroundColor: const Color(0xFFF4F4F4),
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : group == null
          ? const Center(child: Text('群聊不存在'))
          : ListView(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final member in group.members)
                        _MemberTile(character: _character(member.characterId)),
                      InkWell(
                        onTap: _editMembers,
                        borderRadius: BorderRadius.circular(8),
                        child: const SizedBox(
                          width: 58,
                          child: Column(
                            children: [
                              _AddMemberBox(),
                              SizedBox(height: 5),
                              Text(
                                '管理',
                                style: TextStyle(
                                  color: Color(0xFF777777),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _SettingTile(
                  title: '群名称',
                  trailing: group.name,
                  onTap: _rename,
                ),
                SwitchListTile(
                  tileColor: Colors.white,
                  title: const Text('消息免打扰'),
                  value: group.isMuted,
                  activeThumbColor: const Color(0xFF4E8EAD),
                  onChanged: (value) => _save(group.copyWith(isMuted: value)),
                ),
                SwitchListTile(
                  tileColor: Colors.white,
                  title: const Text('置顶聊天'),
                  value: group.isPinned,
                  activeThumbColor: const Color(0xFF4E8EAD),
                  onChanged: (value) => _save(group.copyWith(isPinned: value)),
                ),
                const SizedBox(height: 10),
                _SettingTile(title: '清空聊天记录', onTap: _clearMessages),
                const SizedBox(height: 10),
                _SettingTile(
                  title: '删除并退出群聊',
                  titleColor: const Color(0xFFD64545),
                  centered: true,
                  onTap: _deleteGroup,
                ),
              ],
            ),
    );
  }
}

class _RenameGroupDialog extends StatefulWidget {
  const _RenameGroupDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<_RenameGroupDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改群名称'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.character});

  final AiCharacter? character;

  @override
  Widget build(BuildContext context) {
    final item = character;
    return SizedBox(
      width: 58,
      child: Column(
        children: [
          _Avatar(character: item),
          const SizedBox(height: 5),
          Text(
            item?.displayName ?? '已移除',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.character});

  final AiCharacter? character;

  @override
  Widget build(BuildContext context) {
    final item = character;
    final path = item?.avatarPath.trim() ?? '';
    if (path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.file(File(path), width: 52, height: 52, fit: BoxFit.cover),
      );
    }
    if (item?.isBuiltIn == true) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset(
          'assets/images/pei_avatar.jpg',
          width: 52,
          height: 52,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBEE),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.auto_awesome_rounded),
    );
  }
}

class _AddMemberBox extends StatelessWidget {
  const _AddMemberBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD7D7D7)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.add_rounded, color: Color(0xFF999999)),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    required this.onTap,
    this.trailing = '',
    this.titleColor = const Color(0xFF222222),
    this.centered = false,
  });

  final String title;
  final String trailing;
  final Color titleColor;
  final bool centered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: ListTile(
        onTap: onTap,
        title: Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(color: titleColor),
        ),
        trailing: centered
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailing.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        trailing,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF999999)),
                      ),
                    ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFB0B0B0),
                  ),
                ],
              ),
      ),
    );
  }
}
