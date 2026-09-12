import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/group_chat.dart';
import '../../models/group_member.dart';
import '../../models/group_user_profile.dart';
import '../../models/user_profile.dart';
import '../../services/character_registry_service.dart';
import '../../services/group_chat_storage_service.dart';
import '../../services/group_message_storage_service.dart';
import '../../services/group_user_profile_storage_service.dart';
import '../../services/user_profile_storage_service.dart';
import 'group_user_profile_page.dart';
import '../../widgets/group/group_visuals.dart';

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
  UserProfile _userProfile = const UserProfile();
  GroupUserProfile _groupUserProfile = const GroupUserProfile(groupId: '');
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
      UserProfileStorageService().loadProfile(),
      GroupUserProfileStorageService(groupId: widget.groupId).loadResolved(),
    ]);
    if (!mounted) return;
    setState(() {
      _group = results[0] as GroupChat?;
      _characters = results[1] as List<AiCharacter>;
      _userProfile = results[2] as UserProfile;
      _groupUserProfile = results[3] as GroupUserProfile;
      _loading = false;
    });
  }

  /// 本群身份优先取群聊身份，缺省回退全局用户资料（不写盘、不绑定）。
  String get _userName {
    final name = _groupUserProfile.displayName.trim().isNotEmpty
        ? _groupUserProfile.displayName.trim()
        : _userProfile.nickname.trim();
    if (name.isEmpty || name == '未设置') return '我';
    return name;
  }

  String get _userAvatarPath => _groupUserProfile.avatarPath.trim().isNotEmpty
      ? _groupUserProfile.avatarPath.trim()
      : _userProfile.avatarPath.trim();

  Future<void> _openGroupIdentity() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupUserProfilePage(
          groupId: widget.groupId,
          groupName: _group?.name ?? '',
        ),
      ),
    );
    if (changed != true || !mounted) return;
    await _load();
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
      showDragHandle: true,
      backgroundColor: GroupVisuals.page,
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
                    child: ListView(
                      children: [
                        GroupMemberChoice(
                          name: _userName,
                          avatar: _UserMemberTile(
                            name: '我',
                            avatarPath: _userAvatarPath,
                          ),
                          selected: true,
                          locked: true,
                        ),
                        for (final character in _characters)
                          GroupMemberChoice(
                            key: ValueKey('manage-member-${character.id}'),
                            name: character.displayName,
                            avatar: _Avatar(character: character),
                            selected: selected.contains(character.id),
                            onTap: () => setSheetState(() {
                              if (selected.contains(character.id)) {
                                selected.remove(character.id);
                              } else {
                                selected.add(character.id);
                              }
                            }),
                          ),
                      ],
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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('群成员已更新')));
    }
  }

  Future<void> _save(GroupChat group) async {
    await _groupStorage.upsertGroup(group);
    if (!mounted) return;
    setState(() => _group = group);
  }

  Future<void> _clearMessages() async {
    final confirmed = await _confirm(
      '清空聊天记录',
      '清空后无法恢复，确定继续吗？',
      confirmLabel: '清空',
    );
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
    final confirmed = await _confirm(
      '删除并退出群聊',
      '群聊和本地聊天记录都会被删除，且无法恢复。',
      confirmLabel: '删除并退出',
    );
    if (!confirmed) return;
    await _groupStorage.deleteGroup(widget.groupId);
    await GroupMessageStorageService(
      groupId: widget.groupId,
    ).deleteGroupDirectory();
    if (!mounted) return;
    Navigator.pop(context, 'deleted');
  }

  Future<bool> _confirm(
    String title,
    String content, {
    String confirmLabel = '确定',
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7A8288),
                ),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD64545),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(confirmLabel),
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
      backgroundColor: GroupVisuals.page,
      appBar: AppBar(
        title: const Text('群聊设置'),
        backgroundColor: GroupVisuals.page,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : group == null
          ? const Center(child: Text('群聊不存在'))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                14,
                14,
                14,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1B2028),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${group.members.length + 1} 人',
                            style: const TextStyle(
                              color: Color(0xFF8A9298),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 80 + MediaQuery.textScalerOf(context).scale(18),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _UserMemberTile(
                              name: _userName,
                              avatarPath: _userAvatarPath,
                              onTap: _openGroupIdentity,
                            ),
                            for (final member in group.members)
                              _MemberTile(
                                character: _character(member.characterId),
                              ),
                            _ManageMemberTile(onTap: _editMembers),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingTile(
                        key: const ValueKey('group-identity-entry'),
                        title: '我的群聊身份',
                        subtitle: '$_userName · 只在本群展示',
                        icon: Icons.badge_outlined,
                        onTap: _openGroupIdentity,
                      ),
                      const _InsetDivider(),
                      _SettingTile(
                        title: '群名称',
                        trailing: group.name,
                        onTap: _rename,
                      ),
                      const _InsetDivider(),
                      SwitchListTile(
                        title: const Text('消息免打扰'),
                        value: group.isMuted,
                        activeThumbColor: GroupVisuals.accent,
                        onChanged: (value) =>
                            _save(group.copyWith(isMuted: value)),
                      ),
                      const _InsetDivider(),
                      SwitchListTile(
                        title: const Text('置顶聊天'),
                        value: group.isPinned,
                        activeThumbColor: GroupVisuals.accent,
                        onChanged: (value) =>
                            _save(group.copyWith(isPinned: value)),
                      ),
                    ],
                  ),
                ),
                _SectionCard(
                  padding: EdgeInsets.zero,
                  child: _SettingTile(
                    title: '清空聊天记录',
                    subtitle: '仅清空本群的聊天记录',
                    icon: Icons.delete_sweep_outlined,
                    titleColor: const Color(0xFF886F4E),
                    onTap: _clearMessages,
                  ),
                ),
                _SectionCard(
                  padding: EdgeInsets.zero,
                  child: _SettingTile(
                    title: '删除并退出群聊',
                    titleColor: const Color(0xFFD64545),
                    centered: true,
                    onTap: _deleteGroup,
                  ),
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
      width: 66,
      child: Column(
        children: [
          _Avatar(character: item),
          const SizedBox(height: 6),
          Text(
            item?.displayName ?? '已移除',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF777F86), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 圆角卡片容器：统一设置页的视觉层级。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: GroupVisuals.card(),
      clipBehavior: Clip.antiAlias,
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

class _InsetDivider extends StatelessWidget {
  const _InsetDivider();

  @override
  Widget build(BuildContext context) => const Divider(
    height: 1,
    thickness: 1,
    indent: 16,
    color: Color(0xFFF1F4F6),
  );
}

/// 用户本人固定显示为群成员第一项；不会写入 group storage。
class _UserMemberTile extends StatelessWidget {
  const _UserMemberTile({
    required this.name,
    required this.avatarPath,
    this.onTap,
  });

  final String name;
  final String avatarPath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final path = avatarPath.trim();
    final file = path.isEmpty ? null : File(path);
    final hasImage = file?.existsSync() == true;
    return InkWell(
      key: const ValueKey('group-member-self'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 66,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE3E7E9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF9FC2D4), width: 1.4),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasImage
                  ? Image.file(file!, fit: BoxFit.cover)
                  : const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF7E8B92),
                      size: 26,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF3E5866),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 明确的成员管理入口（复用既有增删逻辑，不新建第二套页面）。
class _ManageMemberTile extends StatelessWidget {
  const _ManageMemberTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('group-member-manage'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 66,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCE5EA)),
              ),
              child: const Icon(
                Icons.group_add_outlined,
                color: Color(0xFF6F8FA3),
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '管理',
              style: TextStyle(color: Color(0xFF6F8FA3), fontSize: 12),
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(14),
        child: Image.file(File(path), width: 52, height: 52, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.auto_awesome_rounded,
        color: Color(0xFF7E8B92),
        size: 24,
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    super.key,
    required this.title,
    required this.onTap,
    this.trailing = '',
    this.subtitle,
    this.icon,
    this.titleColor = const Color(0xFF303340),
    this.centered = false,
  });
  final String title, trailing;
  final String? subtitle;
  final IconData? icon;
  final Color titleColor;
  final bool centered;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ListTile(
      onTap: onTap,
      leading: icon == null
          ? null
          : CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFFF0EDF7),
              child: Icon(icon, size: 21, color: GroupVisuals.accent),
            ),
      title: Text(
        title,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(color: titleColor, fontSize: 15),
      ),
      subtitle: subtitle == null && trailing.isEmpty
          ? null
          : Text(
              subtitle ?? trailing,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF777386),
                fontSize: 12,
                height: 1.5,
              ),
            ),
      trailing: centered
          ? null
          : const Icon(Icons.chevron_right_rounded, color: Color(0xFFAAA5B5)),
    ),
  );
}
