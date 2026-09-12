import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_profile.dart';
import '../../services/character_registry_service.dart';
import '../../services/developer_environment_service.dart';
import '../../services/user_profile_storage_service.dart';
import '../../theme/app_theme_background.dart';
import '../../theme/app_dimensions.dart';
import '../../theme/app_text_styles.dart';
import 'ai_creation_center_page.dart';
import 'character_management_page.dart';
import 'create_group_chat_page.dart';
import 'echo_compose_page.dart';
import 'peilink_chats_page.dart';
import 'relationship_hub_page.dart';
import 'peilink_echo_page.dart';
import 'peilink_guide_page.dart';
import 'peilink_profile_drawer.dart';

class PeiLinkHomePage extends StatefulWidget {
  const PeiLinkHomePage({super.key});

  @override
  State<PeiLinkHomePage> createState() => _PeiLinkHomePageState();
}

class _PeiLinkHomePageState extends State<PeiLinkHomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _profileStorage = UserProfileStorageService();

  int _currentIndex = 0;
  int _contactsRevision = 0;
  int _chatsRevision = 0;
  int _echoRevision = 0;
  UserProfile _profile = const UserProfile();
  bool _physicalUiEnabled = false;

  static const _titles = ['PeiLink', '羁绊', 'Echo'];

  List<Widget> get _pages => [
    PeiLinkChatsPage(key: ValueKey(_chatsRevision)),
    RelationshipHubPage(key: ValueKey(_contactsRevision)),
    PeiLinkEchoPage(
      key: ValueKey('peilink-echo-$_echoRevision'),
      showPublicTimeline: true,
      embedded: true,
    ),
  ];

  static const int _echoTabIndex = 2;

  bool get _isEchoTab => _currentIndex == _echoTabIndex;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPhysicalUiAccess();
  }

  Future<void> _loadPhysicalUiAccess() async {
    final enabled = await DeveloperEnvironmentService().isEnabled();
    if (mounted) setState(() => _physicalUiEnabled = enabled);
  }

  Future<void> _loadProfile() async {
    final profile = await _profileStorage.loadProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  Future<void> _showCreateMenu() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AiCreationCenterPage()),
    );
    if (changed == true && mounted) {
      setState(() {
        _contactsRevision += 1;
        _chatsRevision += 1;
      });
    }
  }

  Future<void> _openGuide() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ThemeBackgroundContainer(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('Guide'),
              centerTitle: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
            ),
            body: const PeiLinkGuidePage(),
          ),
        ),
      ),
    );
  }

  /// Echo tab entry: the current user's own Echo space.
  Future<void> _openMyEcho() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const PeiLinkEchoPage()),
    );
    if (!mounted) return;
    setState(() => _echoRevision += 1);
  }

  Future<void> _openMyEchoFromDrawer() async {
    Navigator.pop(context);
    await _openMyEcho();
  }

  /// Echo tab entry: publish an Echo as the current user.
  Future<void> _publishEcho() async {
    final created = await openUserEchoCompose(context, _profile);
    if (!mounted || !created) return;
    setState(() => _echoRevision += 1);
  }

  /// 消息首页入口：创建群聊，复用既有创建页，不新增第二套实现。
  Future<void> _openCreateGroup() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupChatPage()),
    );
    if (!mounted) return;
    setState(() => _chatsRevision += 1);
  }

  Future<void> _openCharacterManagementFromDrawer() async {
    Navigator.pop(context);
    final registry = CharacterRegistryService();
    final characters = await registry.loadCharacters();
    if (!mounted || characters.isEmpty) return;
    final activeId = await registry.loadActiveCharacterId();
    if (!mounted) return;
    final character = characters.firstWhere(
      (item) => item.id == activeId,
      orElse: () => characters.first,
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterManagementPage(characterId: character.id),
      ),
    );
    if (!mounted) return;
    setState(() {
      _contactsRevision += 1;
      _chatsRevision += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final avatarPath = _profile.avatarPath.trim();
    final avatarFile = avatarPath.isEmpty ? null : File(avatarPath);
    final hasAvatar = avatarFile?.existsSync() == true;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: ThemeBackgroundContainer(
        child: Scaffold(
          key: _scaffoldKey,
          extendBody: true,
          backgroundColor: Colors.transparent,
          drawer: PeiLinkProfileDrawer(
            onOpenCharacterManagement: _openCharacterManagementFromDrawer,
            onOpenMyEcho: _openMyEchoFromDrawer,
            onProfileChanged: (profile) {
              if (mounted) setState(() => _profile = profile);
            },
          ),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.68),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            centerTitle: true,
            leadingWidth: 58,
            leading: Padding(
              padding: const EdgeInsets.only(left: 14, top: 7, bottom: 7),
              child: InkWell(
                key: const ValueKey('peilink-profile-entry'),
                borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
                onTap: _isEchoTab
                    ? _openMyEcho
                    : () => _scaffoldKey.currentState?.openDrawer(),
                child: ClipOval(
                  child: Container(
                    color: const Color(0xFFE3E7E9),
                    child: hasAvatar
                        ? Image.file(avatarFile!, fit: BoxFit.cover)
                        : const Icon(
                            Icons.person_rounded,
                            size: 24,
                            color: Color(0xFF7E8B92),
                          ),
                  ),
                ),
              ),
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  key: const ValueKey('peilink-guide-entry'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: _openGuide,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/brand/peilink_butterfly.png',
                          width: 20,
                          height: 20,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _titles[_currentIndex],
                          style: AppTextStyles.pageTitle,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_physicalUiEnabled) ...[
                  const SizedBox(height: 1),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 10),
                      SizedBox(width: 4),
                      Text(
                        'AI World · 已连接',
                        style: TextStyle(
                          color: Color(0xFF71828B),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              if (_currentIndex == 0)
                PopupMenuButton<String>(
                  key: const ValueKey('peilink-create-entry'),
                  tooltip: '新建',
                  padding: EdgeInsets.zero,
                  offset: const Offset(0, 44),
                  color: Colors.white,
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (value) {
                    if (value == 'character') _showCreateMenu();
                    if (value == 'group') _openCreateGroup();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'character',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF6F79A8),
                        ),
                        title: Text('创建角色'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'group',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.groups_2_outlined,
                          color: Color(0xFFF2994A),
                        ),
                        title: Text('创建群聊'),
                      ),
                    ),
                  ],
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: Color(0xFF171717),
                    size: 25,
                  ),
                )
              else
                IconButton(
                  key: const ValueKey('peilink-create-entry'),
                  onPressed: _isEchoTab ? _publishEcho : _showCreateMenu,
                  tooltip: _isEchoTab ? '发布 Echo' : '创建',
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: Color(0xFF171717),
                    size: 25,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: IndexedStack(index: _currentIndex, children: _pages),
          bottomNavigationBar: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              0,
              14,
              8 + MediaQuery.paddingOf(context).bottom,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.76),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x29152D3D),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: _PeiLinkNavigationBar(
                    currentIndex: _currentIndex,
                    onChanged: (index) => setState(() => _currentIndex = index),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeiLinkNavigationBar extends StatelessWidget {
  const _PeiLinkNavigationBar({
    required this.currentIndex,
    required this.onChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, '消息'),
    (Icons.favorite_border_rounded, Icons.favorite_rounded, '羁绊'),
    (Icons.graphic_eq_rounded, Icons.waves_rounded, 'Echo'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDimensions.bottomNavigationHeight,
      child: Row(
        children: List.generate(_items.length, (index) {
          final item = _items[index];
          final selected = index == currentIndex;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('peilink-tab-$index'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onChanged(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 210),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFDDE8FA).withValues(alpha: 0.86)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      border: selected
                          ? Border.all(color: const Color(0x80FFFFFF))
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? item.$2 : item.$1,
                          size: AppDimensions.bottomNavigationIcon,
                          color: selected
                              ? const Color(0xFF526DA5)
                              : const Color(0xFF66737B),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: selected
                                ? const Color(0xFF405B91)
                                : const Color(0xFF66737B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
