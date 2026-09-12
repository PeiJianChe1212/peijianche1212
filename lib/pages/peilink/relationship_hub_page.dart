import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/relationship_group.dart';
import '../../services/character_registry_service.dart';
import '../../services/echo_storage_service.dart';
import '../../services/relationship_group_storage_service.dart';
import '../../services/relationship_growth_service.dart';
import '../../theme/app_theme_background.dart';
import 'ai_creation_center_page.dart';
import 'peilink_echo_page.dart';

class RelationshipHubPage extends StatefulWidget {
  const RelationshipHubPage({super.key});
  @override
  State<RelationshipHubPage> createState() => _RelationshipHubPageState();
}

class _RelationshipHubPageState extends State<RelationshipHubPage> {
  final _registry = CharacterRegistryService();
  final _storage = RelationshipGroupStorageService();
  List<_Role> _roles = const [];
  RelationshipGroupCollection _collection = const RelationshipGroupCollection();
  String _filter = 'all';
  String? _groupId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final characters = await _registry.loadCharacters();
    final collection = await _storage.load();
    final roles = <_Role>[];
    for (final character in characters) {
      final echoes = await EchoStorageService(
        characterId: character.id,
      ).loadItems();
      final growth = await RelationshipGrowthService(
        characterId: character.id,
      ).loadOrCreate(metAt: character.createdAt);
      final echo = echoes.firstOrNull;
      roles.add(
        _Role(
          character: character,
          level: growth.levelFor(),
          stage: growth.stageFor(),
          progress: growth.nextLevelExperienceFor() == 0
              ? 1
              : growth.currentExperienceFor() / growth.nextLevelExperienceFor(),
          state: echo?.characterState.trim().isNotEmpty == true
              ? echo!.characterState.trim()
              : '安静生活中',
          activity: echo == null
              ? '暂时没有新的生活动态'
              : '${_relativeTime(echo.createdAt)}更新了 Echo',
          activityAt: echo?.createdAt ?? character.createdAt,
        ),
      );
    }
    roles.sort((a, b) => b.activityAt.compareTo(a.activityAt));
    if (!mounted) return;
    setState(() {
      _roles = roles;
      _collection = collection;
      _loading = false;
    });
  }

  List<_Role> get _visible {
    if (_groupId != null) {
      final group = _collection.groups
          .where((item) => item.id == _groupId)
          .firstOrNull;
      return group == null
          ? []
          : _roles
                .where((item) => group.characterIds.contains(item.character.id))
                .toList();
    }
    if (_filter == 'favorite') {
      return _roles
          .where(
            (item) =>
                _collection.favoriteCharacterIds.contains(item.character.id),
          )
          .toList();
    }
    if (_filter == 'recent') {
      return _roles
          .where(
            (item) => DateTime.now().difference(item.activityAt).inDays < 7,
          )
          .toList();
    }
    return _roles;
  }

  Future<void> _open(_Role role) async {
    await _registry.setActiveCharacter(role.character.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeiLinkEchoPage(character: role.character),
      ),
    );
    await _load();
  }

  Future<void> _favorite(String id) async {
    final ids = [..._collection.favoriteCharacterIds];
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    _collection = RelationshipGroupCollection(
      groups: _collection.groups,
      favoriteCharacterIds: ids,
    );
    await _storage.save(_collection);
    if (mounted) setState(() {});
  }

  Future<void> _newGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：冒险伙伴'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final group = RelationshipGroup(
      id: 'group_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      emoji: '✨',
    );
    _collection = RelationshipGroupCollection(
      groups: [..._collection.groups, group],
      favoriteCharacterIds: _collection.favoriteCharacterIds,
    );
    await _storage.save(_collection);
    if (mounted) setState(() {});
  }

  Future<void> _renameGroup(RelationshipGroup group) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改分组名称'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == group.name) return;
    _collection = RelationshipGroupCollection(
      groups: _collection.groups
          .map((item) => item.id == group.id ? item.copyWith(name: name) : item)
          .toList(),
      favoriteCharacterIds: _collection.favoriteCharacterIds,
    );
    await _storage.save(_collection);
    if (mounted) setState(() {});
  }

  Future<void> _assign(_Role role) async {
    if (_collection.groups.isEmpty) {
      await _newGroup();
      if (_collection.groups.isEmpty) return;
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '移动到分组',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ..._collection.groups.map(
              (item) => ListTile(
                leading: Text(item.emoji),
                title: Text(item.name),
                onTap: () => Navigator.pop(context, item.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final groups = _collection.groups.map((group) {
      final ids = [...group.characterIds]..remove(role.character.id);
      if (group.id == selected) ids.add(role.character.id);
      return group.copyWith(characterIds: ids);
    }).toList();
    _collection = RelationshipGroupCollection(
      groups: groups,
      favoriteCharacterIds: _collection.favoriteCharacterIds,
    );
    await _storage.save(_collection);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ThemeBackgroundContainer(
    child: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 116),
              children: [
                _RecentPanel(roles: _roles.take(5).toList(), onTap: _open),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final tab in const [
                      ('all', '全部'),
                      ('favorite', '特别关注'),
                      ('recent', '最近互动'),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: Text(tab.$2),
                            selected: _filter == tab.$1,
                            onSelected: (_) => setState(() {
                              _filter = tab.$1;
                              _groupId = null;
                            }),
                            showCheckmark: false,
                            side: BorderSide.none,
                            selectedColor: const Color(0xFFE7DAFF),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      _groupId == null
                          ? '我的分组'
                          : (_collection.groups
                                    .where((item) => item.id == _groupId)
                                    .firstOrNull
                                    ?.name ??
                                '分组'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _groupId == null
                        ? TextButton.icon(
                            onPressed: _newGroup,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('新建分组'),
                          )
                        : TextButton(
                            onPressed: () => setState(() => _groupId = null),
                            child: const Text('返回'),
                          ),
                  ],
                ),
                if (_groupId == null && _filter == 'all') ...[
                  _GroupTile(
                    emoji: '💜',
                    name: '特别关注',
                    count: _collection.favoriteCharacterIds.length,
                    onTap: () => setState(() => _filter = 'favorite'),
                  ),
                  ..._collection.groups.map(
                    (item) => _GroupTile(
                      emoji: item.emoji,
                      name: item.name,
                      count: item.characterIds.length,
                      onTap: () => setState(() => _groupId = item.id),
                      onLongPress: () => _renameGroup(item),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 14, 2, 8),
                    child: Text(
                      '全部角色',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                if (_visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Text(
                        '这里还没有角色',
                        style: TextStyle(color: Color(0xFF756B80)),
                      ),
                    ),
                  ),
                ..._visible.map(
                  (role) => _RoleCard(
                    role: role,
                    favorite: _collection.favoriteCharacterIds.contains(
                      role.character.id,
                    ),
                    onTap: () => _open(role),
                    onFavorite: () => _favorite(role.character.id),
                    onAssign: () => _assign(role),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AiCreationCenterPage(),
                      ),
                    );
                    if (changed == true) await _load();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加角色'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: const Color(0xFF7650C7),
                    side: const BorderSide(color: Color(0xFFCDBAEF)),
                  ),
                ),
              ],
            ),
          ),
  );
}

class _Role {
  const _Role({
    required this.character,
    required this.level,
    required this.stage,
    required this.progress,
    required this.state,
    required this.activity,
    required this.activityAt,
  });
  final AiCharacter character;
  final int level;
  final String stage;
  final double progress;
  final String state;
  final String activity;
  final DateTime activityAt;
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({required this.roles, required this.onTap});
  final List<_Role> roles;
  final ValueChanged<_Role> onTap;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _glass(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('最近互动', style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(
              '${roles.length} 位角色',
              style: const TextStyle(color: Color(0xFF81778E), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (roles.isEmpty)
          const Text('创建角色后，最近互动会显示在这里')
        else
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: roles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (_, index) {
                final role = roles[index];
                return InkWell(
                  onTap: () => onTap(role),
                  child: SizedBox(
                    width: 58,
                    child: Column(
                      children: [
                        _Avatar(role.character, 27),
                        const SizedBox(height: 6),
                        Text(
                          role.character.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.emoji,
    required this.name,
    required this.count,
    required this.onTap,
    this.onLongPress,
  });
  final String emoji;
  final String name;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: _glass(16),
        child: ListTile(
          onTap: onTap,
          onLongPress: onLongPress,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Text(emoji, style: const TextStyle(fontSize: 22)),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$count', style: const TextStyle(color: Color(0xFF8C8299))),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
    required this.onAssign,
  });
  final _Role role;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onAssign;
  @override
  Widget build(BuildContext context) {
    final relation = role.character.relationship.trim().isEmpty
        ? '伙伴'
        : role.character.relationship.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _glass(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onAssign,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(role.character, 30),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            role.character.displayName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _Tag(relation),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Lv.${role.level}  ${role.stage}',
                      style: const TextStyle(
                        color: Color(0xFF8150D8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value: role.progress.clamp(0, 1),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4),
                      backgroundColor: const Color(0xFFE8E1F1),
                      color: const Color(0xFFA36AE8),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '状态：${role.state}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      '最近：${role.activity}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF777185),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onFavorite,
                icon: Icon(
                  favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: favorite
                      ? const Color(0xFFD58AE8)
                      : const Color(0xFFB2A8BD),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFE9DEFF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFF7147BE), fontSize: 11),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.character, this.radius);
  final AiCharacter character;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final file = File(character.avatarPath);
    final valid = character.avatarPath.isNotEmpty && file.existsSync();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE8DDF5),
      backgroundImage: valid ? FileImage(file) : null,
      child: valid
          ? null
          : const Icon(Icons.person_rounded, color: Color(0xFF8466A8)),
    );
  }
}

BoxDecoration _glass(double radius) => BoxDecoration(
  color: Colors.white.withValues(alpha: .68),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: Colors.white.withValues(alpha: .9)),
  boxShadow: const [
    BoxShadow(color: Color(0x142D1B50), blurRadius: 18, offset: Offset(0, 7)),
  ],
);
String _relativeTime(DateTime time) {
  final value = DateTime.now().difference(time);
  if (value.inMinutes < 1) return '刚刚';
  if (value.inHours < 1) return '${value.inMinutes}分钟前';
  if (value.inDays < 1) return '${value.inHours}小时前';
  if (value.inDays == 1) return '昨天';
  return '${value.inDays}天前';
}
