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
  UserProfile _profile = const UserProfile();
  bool _physicalUiEnabled = false;

  static const _titles = ['PeiLink', '羁绊', 'Echo'];

  List<Widget> get _pages => [
    PeiLinkChatsPage(key: ValueKey(_chatsRevision)),
    RelationshipHubPage(key: ValueKey(_contactsRevision)),
    const PeiLinkEchoPage(showPublicTimeline: true, embedded: true),
  ];

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
            onProfileChanged: (profile) {
              if (mounted) setState(() => _profile = profile);
            },
          ),
          appBar: AppBar(
            backgroundColor: const Color(0xEAF7F9FA),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            leadingWidth: 58,
            leading: Padding(
              padding: const EdgeInsets.only(left: 14, top: 7, bottom: 7),
              child: InkWell(
                key: const ValueKey('peilink-profile-entry'),
                borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
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
                Text(_titles[_currentIndex], style: AppTextStyles.pageTitle),
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
              IconButton(
                key: const ValueKey('peilink-guide-entry'),
                onPressed: _openGuide,
                tooltip: '阿澈 Guide',
                icon: Image.asset(
                  'assets/images/brand/peilink_butterfly.png',
                  width: 27,
                  height: 27,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                key: const ValueKey('peilink-create-entry'),
                onPressed: _showCreateMenu,
                tooltip: '创建',
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
                  child: SizedBox(
                    height: AppDimensions.bottomNavigationHeight,
                    child: BottomNavigationBar(
                      currentIndex: _currentIndex,
                      type: BottomNavigationBarType.fixed,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      selectedItemColor: const Color(0xFF3E809D),
                      unselectedItemColor: const Color(0xFF536068),
                      selectedFontSize: 11,
                      unselectedFontSize: 11,
                      iconSize: AppDimensions.bottomNavigationIcon,
                      onTap: (index) => setState(() => _currentIndex = index),
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.chat_bubble_outline_rounded),
                          activeIcon: Icon(Icons.chat_bubble_rounded),
                          label: '消息',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.people_outline_rounded),
                          activeIcon: Icon(Icons.people_rounded),
                          label: '羁绊',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.waves_outlined),
                          activeIcon: Icon(Icons.waves_rounded),
                          label: 'Echo',
                        ),
                      ],
                    ),
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
