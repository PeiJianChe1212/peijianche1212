import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/activity_status.dart';
import '../models/ai_character.dart';
import '../models/life_trace.dart';
import '../services/activity_context_service.dart';
import '../services/activity_service.dart';
import '../services/auto_echo_comment_service.dart';
import '../services/auto_echo_service.dart';
import '../services/character_registry_service.dart';
import '../services/home_character_storage_service.dart';
import '../services/initiative_service.dart';
import '../services/life_trace_service.dart';
import '../services/presence_service.dart';
import '../services/today_service.dart';
import '../services/world_tick_service.dart';
import '../widgets/home/home_glass.dart';
import '../widgets/home/home_visual_tokens.dart';
import 'chat_page.dart';
import 'peilink/character_detail_page.dart';
import 'peilink/peilink_echo_page.dart';
import 'peilink/peilink_home_page.dart';
import 'settings_page.dart';
import 'today_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const Duration _motionDuration = HomeVisualTokens.motionPage;

  final ActivityService _activityService = const ActivityService();
  final PresenceService _presenceService = const PresenceService();
  final CharacterRegistryService _characterRegistry =
      CharacterRegistryService();
  final HomeCharacterStorageService _homeCharacterStorage =
      HomeCharacterStorageService();
  final WorldTickService _worldTickService = WorldTickService();
  final AutoEchoService _autoEchoService = AutoEchoService();
  final AutoEchoCommentService _autoEchoCommentService =
      AutoEchoCommentService();
  final PageController _pageController = PageController();

  Timer? _clockTimer;
  Timer? _echoCommentTimer;
  DateTime _now = DateTime.now();
  ActivityStatus? _resolvedActivity;
  int _unreadCount = 0;
  int _pageIndex = 0;
  List<LifeTrace> _recentTraces = const [];
  AiCharacter _homeCharacter = AiCharacter.peiJianChe();
  bool _homeCharacterLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _advanceWorld(markForeground: true);
    _refreshInitiative();
    _recordCurrentActivity();
    _loadRecentTraces();
    _loadHomeCharacter();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() => _now = now);
      await _recordCurrentActivity(now: now);
      await _refreshInitiative(now: now);
      await _loadRecentTraces();
    });
    _echoCommentTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      try {
        await _autoEchoCommentService.checkAll(now: DateTime.now());
      } catch (error) {
        debugPrint('检查 Echo 评论任务失败：$error');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _echoCommentTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _advanceWorld(markForeground: true);
    }
  }

  Future<void> _advanceWorld({bool markForeground = false}) async {
    try {
      final report = await _worldTickService.advance(
        markForeground: markForeground,
      );
      if (!mounted) return;
      // AutoEcho has its own two-hour guard. Check even when the world tick was
      // recently advanced so an empty/new timeline cannot miss its fallback.
      await _autoEchoService.checkAll(now: report.tickAt);
      await _autoEchoCommentService.checkAll(now: report.tickAt);
      if (report.executed &&
          (report.crossedTimePeriod || report.crossedDayBoundary)) {
        setState(() => _now = report.tickAt);
        await _recordCurrentActivity(now: report.tickAt);
        await _loadRecentTraces();
      }
    } catch (error) {
      debugPrint('推进 PeiLink 世界失败：$error');
    }
  }

  Future<void> _loadHomeCharacter() async {
    try {
      final character = await _homeCharacterStorage.loadCharacter();
      if (!mounted) return;
      setState(() {
        _homeCharacter = character;
        _resolvedActivity = null;
        _homeCharacterLoading = false;
      });
      await _recordCurrentActivity();
      await _refreshInitiative();
      await _loadRecentTraces();
    } catch (error) {
      debugPrint('加载首页展示角色失败：$error');
      if (!mounted) return;
      setState(() => _homeCharacterLoading = false);
    }
  }

  Future<void> _openHomeCharacter() async {
    await _characterRegistry.setActiveCharacter(_homeCharacter.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CharacterDetailPage()),
    );
    await _loadHomeCharacter();
  }

  Future<void> _chooseHomeCharacter() async {
    final characters = await _characterRegistry.loadCharacters();
    if (!mounted) return;
    final selected = await showModalBottomSheet<AiCharacter>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HomeCharacterPicker(
        characters: characters,
        selectedId: _homeCharacter.id,
      ),
    );
    if (selected == null) return;
    await _homeCharacterStorage.saveCharacterId(selected.id);
    if (!mounted) return;
    setState(() {
      _homeCharacter = selected;
      _resolvedActivity = null;
    });
    await _characterRegistry.setActiveCharacter(selected.id);
    await _recordCurrentActivity();
    await _refreshInitiative();
    await _loadRecentTraces();
  }

  Future<void> _openPeiLink() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PeiLinkHomePage()),
    );
    await _refreshInitiative();
    await _loadRecentTraces();
  }

  Future<void> _openChat() async {
    await _characterRegistry.setActiveCharacter(_homeCharacter.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatPage()),
    );
    await _refreshInitiative();
    await _loadRecentTraces();
  }

  Future<void> _openEcho() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeiLinkEchoPage(character: _homeCharacter),
      ),
    );
    await _loadRecentTraces();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  Future<void> _refreshInitiative({DateTime? now}) async {
    try {
      final service = InitiativeService(characterId: _homeCharacter.id);
      await service.maybeLeaveMessage(now: now);
      final unread = await service.unreadCount();
      if (!mounted) return;
      setState(() => _unreadCount = unread);
      await _loadRecentTraces();
    } catch (error) {
      debugPrint('主动联系检查失败：$error');
    }
  }

  Future<void> _loadRecentTraces() async {
    try {
      final traces = await LifeTraceService(
        characterId: _homeCharacter.id,
      ).loadRecent(limit: 4);
      if (!mounted) return;
      setState(() => _recentTraces = traces);
    } catch (error) {
      debugPrint('加载生活痕迹失败：$error');
    }
  }

  String get _timeText =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  String get _dateText {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${_now.month}月${_now.day}日  ${weekdays[_now.weekday - 1]}';
  }

  ActivityStatus get _activity =>
      _resolvedActivity ??
      _activityService.current(now: _now, characterId: _homeCharacter.id);

  String get _greeting =>
      _presenceService.homeGreeting(now: _now, activity: _activity);

  Future<ActivityStatus> _refreshActivity({DateTime? now}) async {
    final time = now ?? DateTime.now();
    try {
      final activity = await ActivityContextService(
        characterId: _homeCharacter.id,
      ).resolve(now: time);
      if (mounted) setState(() => _resolvedActivity = activity);
      return activity;
    } catch (error) {
      debugPrint('刷新首页生活状态失败：$error');
      return _activityService.current(
        now: time,
        characterId: _homeCharacter.id,
      );
    }
  }

  Future<void> _recordCurrentActivity({DateTime? now}) async {
    try {
      final time = now ?? DateTime.now();
      final activity = await _refreshActivity(now: time);
      await TodayService(
        characterId: _homeCharacter.id,
      ).recordActivity(activity, now: time);
    } catch (error) {
      debugPrint('记录 Today 失败：$error');
    }
  }

  Future<void> _showActivityDetails() async {
    final activity = _activity;
    await TodayService(
      characterId: _homeCharacter.id,
    ).recordActivity(activity, now: _now);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodayPage(
          currentActivity: activity,
          characterId: _homeCharacter.id,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _now = DateTime.now());
    await _loadRecentTraces();
  }

  void _showPlaceholder(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label 先住在桌面里，功能以后再搬进来。')));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _CharacterDesktopPage(
        character: _homeCharacter,
        loading: _homeCharacterLoading,
        greeting: _greeting,
        activity: _activity,
        unreadCount: _unreadCount,
        onOpenCharacter: _openHomeCharacter,
        onChooseCharacter: _chooseHomeCharacter,
        onActivityTap: _showActivityDetails,
        onChat: _openChat,
        onCall: () => _showPlaceholder('电话'),
        onEcho: _openEcho,
      ),
      _LifeDesktopPage(
        now: _now,
        activity: _activity,
        traces: _recentTraces,
        onActivityTap: _showActivityDetails,
      ),
      _AppsDesktopPage(
        unreadCount: _unreadCount,
        onPeiLink: _openPeiLink,
        onSettings: _openSettings,
        onPlaceholder: _showPlaceholder,
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF10151D),
        body: Stack(
          children: [
            const Positioned.fill(child: _DesktopBackground()),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: HomeVisualTokens.statusBarPadding,
                    child: _DesktopStatusBar(time: _timeText),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: pages.length,
                      onPageChanged: (value) =>
                          setState(() => _pageIndex = value),
                      itemBuilder: (_, index) => AnimatedSwitcher(
                        duration: _motionDuration,
                        child: KeyedSubtree(
                          key: ValueKey('${_homeCharacter.id}-$index'),
                          child: pages[index],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 10),
                    child: _PageIndicator(
                      count: pages.length,
                      currentIndex: _pageIndex,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterDesktopPage extends StatelessWidget {
  const _CharacterDesktopPage({
    required this.character,
    required this.loading,
    required this.greeting,
    required this.activity,
    required this.unreadCount,
    required this.onOpenCharacter,
    required this.onChooseCharacter,
    required this.onActivityTap,
    required this.onChat,
    required this.onCall,
    required this.onEcho,
  });

  final AiCharacter character;
  final bool loading;
  final String greeting;
  final ActivityStatus activity;
  final int unreadCount;
  final VoidCallback onOpenCharacter;
  final VoidCallback onChooseCharacter;
  final VoidCallback onActivityTap;
  final VoidCallback onChat;
  final VoidCallback onCall;
  final VoidCallback onEcho;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: HomeVisualTokens.motionPage,
      curve: HomeVisualTokens.motionEmphasizedCurve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _CharacterHeroCard(
            character: character,
            loading: loading,
            onTap: onOpenCharacter,
          ),
          Positioned(
            top: 24,
            left: 22,
            right: 22,
            child: _AiDesktopHeader(
              loading: loading,
              onChooseCharacter: onChooseCharacter,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CharacterLifePanel(
                  character: character,
                  greeting: greeting,
                  activity: activity,
                  onTap: onOpenCharacter,
                  onActivityTap: onActivityTap,
                ),
                const SizedBox(height: 11),
                _QuickActionDock(
                  actions: [
                    _QuickAction(
                      icon: Icons.chat_bubble_rounded,
                      label: '聊天',
                      caption: '继续陪伴',
                      badgeCount: unreadCount,
                      onTap: onChat,
                    ),
                    _QuickAction(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Echo',
                      caption: '他的回声',
                      assetPath: 'assets/images/app_icons/echo.png',
                      onTap: onEcho,
                    ),
                    _QuickAction(
                      icon: Icons.call_rounded,
                      label: '电话',
                      caption: '未来开放',
                      onTap: onCall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiDesktopHeader extends StatelessWidget {
  const _AiDesktopHeader({
    required this.loading,
    required this.onChooseCharacter,
  });

  final bool loading;
  final VoidCallback onChooseCharacter;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFB7DBEA),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0xFF8DC7E1), blurRadius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'PEILINK · AI DESKTOP',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.15,
                      shadows: const [
                        Shadow(color: Color(0x99000000), blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '此刻，有人在这里生活',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.35,
                  shadows: [Shadow(color: Color(0xB3000000), blurRadius: 14)],
                ),
              ),
            ],
          ),
        ),
        _RoundGlassButton(
          icon: Icons.person_search_rounded,
          tooltip: '切换角色',
          onTap: loading ? null : onChooseCharacter,
        ),
      ],
    );
  }
}

class _LifeDesktopPage extends StatelessWidget {
  const _LifeDesktopPage({
    required this.now,
    required this.activity,
    required this.traces,
    required this.onActivityTap,
  });

  final DateTime now;
  final ActivityStatus activity;
  final List<LifeTrace> traces;
  final VoidCallback onActivityTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: HomeVisualTokens.motionPage,
      curve: HomeVisualTokens.motionEmphasizedCurve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '生活世界',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '观察他正在经历的今天',
                        style: TextStyle(
                          color: Color(0x7AFFFFFF),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _LifeLiveIndicator(isSleeping: activity.isSleeping),
              ],
            ),
            const SizedBox(height: 16),
            _TodayWorldCard(now: now, activity: activity, onTap: onActivityTap),
            const SizedBox(height: 18),
            const _LifeSectionHeader(
              eyebrow: 'TODAY',
              title: '今日生活',
              caption: '不是记录，是正在发生',
            ),
            const SizedBox(height: 10),
            _TodayLifeFragment(
              now: now,
              activity: activity,
              onTap: onActivityTap,
            ),
            const SizedBox(height: 18),
            const _LifeSectionHeader(
              eyebrow: 'TRACES',
              title: '最近痕迹',
              caption: '世界留下的轻微回声',
            ),
            const SizedBox(height: 10),
            _LifeTimeline(traces: traces),
            const SizedBox(height: 18),
            const _LifeSectionHeader(
              eyebrow: 'WORLD',
              title: '世界状态',
              caption: '他此刻所处的环境',
            ),
            const SizedBox(height: 10),
            _WorldEnvironmentCard(activity: activity),
          ],
        ),
      ),
    );
  }
}

class _AppsDesktopPage extends StatelessWidget {
  const _AppsDesktopPage({
    required this.unreadCount,
    required this.onPeiLink,
    required this.onSettings,
    required this.onPlaceholder,
  });

  final int unreadCount;
  final VoidCallback onPeiLink;
  final VoidCallback onSettings;
  final ValueChanged<String> onPlaceholder;

  @override
  Widget build(BuildContext context) {
    final peiLink = _AppEntry(
      'PeiLink',
      Icons.chat_bubble_rounded,
      onPeiLink,
      tint: const Color(0xFF80B9D7),
      assetPath: 'assets/images/app_icons/peilink.png',
      badgeCount: unreadCount,
    );
    final lifeApps = <_AppEntry>[
      _AppEntry(
        '相机',
        Icons.camera_alt_rounded,
        () => onPlaceholder('相机'),
        tint: const Color(0xFFD7A7B3),
        assetPath: 'assets/images/app_icons/camera.png',
      ),
      _AppEntry(
        '相册',
        Icons.photo_library_rounded,
        () => onPlaceholder('相册'),
        tint: const Color(0xFFA8C9B6),
        assetPath: 'assets/images/app_icons/gallery.png',
      ),
      _AppEntry(
        '音乐',
        Icons.headphones_rounded,
        () => onPlaceholder('音乐'),
        tint: const Color(0xFFB6A8DA),
        assetPath: 'assets/images/app_icons/music.png',
      ),
    ];
    final systemApps = <_AppEntry>[
      _AppEntry(
        '设置',
        Icons.settings_rounded,
        onSettings,
        tint: const Color(0xFFAABBC8),
        assetPath: 'assets/images/app_icons/settings.png',
      ),
      _AppEntry(
        '日记',
        Icons.menu_book_rounded,
        () => onPlaceholder('日记'),
        tint: const Color(0xFFD0B28E),
        assetPath: 'assets/images/app_icons/diary.png',
      ),
      _AppEntry(
        '礼物',
        Icons.card_giftcard_rounded,
        () => onPlaceholder('礼物'),
        tint: const Color(0xFFD49AAE),
        assetPath: 'assets/images/app_icons/gift.png',
      ),
    ];
    final futureApps = <_AppEntry>[
      _AppEntry(
        '世界',
        Icons.public_rounded,
        () => onPlaceholder('世界'),
        tint: const Color(0xFF82B7BC),
        assetPath: 'assets/images/app_icons/world.png',
      ),
      _AppEntry(
        '更多',
        Icons.auto_awesome_rounded,
        () => onPlaceholder('更多'),
        tint: const Color(0xFFA68BD4),
      ),
    ];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: HomeVisualTokens.motionPage,
      curve: HomeVisualTokens.motionEmphasizedCurve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '应用空间',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '通往 AI 世界各处的小门',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.46),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 17),
            _PeiLinkAppPortal(entry: peiLink),
            const SizedBox(height: 18),
            _AppSection(
              title: '生活',
              caption: '记录与感受',
              icon: Icons.favorite_border_rounded,
              entries: lifeApps,
            ),
            const SizedBox(height: 13),
            _AppSection(
              title: '系统',
              caption: '管理这个世界',
              icon: Icons.tune_rounded,
              entries: systemApps,
            ),
            const SizedBox(height: 13),
            _AppSection(
              title: '未来',
              caption: '等待开启的空间',
              icon: Icons.auto_awesome_outlined,
              entries: futureApps,
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopBackground extends StatefulWidget {
  const _DesktopBackground();

  @override
  State<_DesktopBackground> createState() => _DesktopBackgroundState();
}

class _DesktopBackgroundState extends State<_DesktopBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: HomeVisualTokens.motionAmbient,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HomeVisualTokens.backgroundTop,
              HomeVisualTokens.backgroundMiddle,
              HomeVisualTokens.backgroundBottom,
            ],
            stops: [0, 0.52, 1],
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final drift = _controller.value;
            return Stack(
              children: [
                Positioned(
                  top: -118 + (drift * 18),
                  right: -82 + (drift * 10),
                  child: _AmbientOrb(
                    size: 300,
                    color: HomeVisualTokens.ambientBlue,
                    opacity: 0.16,
                  ),
                ),
                Positioned(
                  top: 230 - (drift * 14),
                  left: -150 + (drift * 18),
                  child: _AmbientOrb(
                    size: 310,
                    color: HomeVisualTokens.ambientViolet,
                    opacity: 0.085,
                  ),
                ),
                Positioned(
                  bottom: -105 + (drift * 16),
                  right: -120,
                  child: _AmbientOrb(
                    size: 290,
                    color: HomeVisualTokens.ambientWarm,
                    opacity: 0.07,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.15, -0.65),
                        radius: 1.05,
                        colors: [
                          Colors.white.withValues(alpha: 0.035),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 54, sigmaY: 54),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopStatusBar extends StatelessWidget {
  const _DesktopStatusBar({required this.time});

  final String time;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
        shadows: [Shadow(color: Color(0x52000000), blurRadius: 7)],
      ),
      child: IconTheme(
        data: IconThemeData(
          color: Colors.white.withValues(alpha: 0.92),
          size: 17,
          shadows: const [Shadow(color: Color(0x52000000), blurRadius: 7)],
        ),
        child: Row(
          children: [
            Text(time),
            const Spacer(),
            const Icon(Icons.signal_cellular_alt_rounded, size: 16),
            const SizedBox(width: 5),
            const Icon(Icons.wifi_rounded, size: 17),
            const SizedBox(width: 5),
            const Icon(Icons.battery_full_rounded, size: 19),
          ],
        ),
      ),
    );
  }
}

class _CharacterHeroCard extends StatelessWidget {
  const _CharacterHeroCard({
    required this.character,
    required this.loading,
    required this.onTap,
  });

  final AiCharacter character;
  final bool loading;
  final VoidCallback onTap;

  Widget _sourceImage({required BoxFit fit, required Alignment alignment}) {
    final portraitPath = character.portraitPath.trim();
    final avatarPath = character.avatarPath.trim();
    final path = portraitPath.isNotEmpty && File(portraitPath).existsSync()
        ? portraitPath
        : avatarPath;

    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    if (character.isBuiltIn) {
      return Image.asset(
        'assets/images/pei_hero_flower.jpg',
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFDDE4E9), Color(0xFF536675), Color(0xFF18232D)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_awesome_rounded,
          color: Colors.white70,
          size: 72,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'home-character-${character.id}',
      child: Material(
        color: const Color(0xFFE9E7E3),
        child: InkWell(
          onTap: loading ? null : onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: HomeVisualTokens.motionHero,
                switchInCurve: HomeVisualTokens.motionEmphasizedCurve,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 1.035, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(character.id),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform.scale(
                        scale: 1.08,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: _sourceImage(
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                      _sourceImage(
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x59050A11),
                      Color(0x0D050A11),
                      Color(0x1F06111A),
                      Color(0xD9070C14),
                      Color(0xFA070B12),
                    ],
                    stops: [0, 0.22, 0.48, 0.76, 1],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 190,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x8A050911),
                          Color(0x3D050911),
                          Colors.transparent,
                        ],
                        stops: [0, 0.48, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterLifePanel extends StatelessWidget {
  const _CharacterLifePanel({
    required this.character,
    required this.greeting,
    required this.activity,
    required this.onTap,
    required this.onActivityTap,
  });

  final AiCharacter character;
  final String greeting;
  final ActivityStatus activity;
  final VoidCallback onTap;
  final VoidCallback onActivityTap;

  String? get _relationshipLabel {
    final relationship = character.relationship.trim();
    const emptyLabels = {'未设置', '暂未设置', '未填写'};
    if (relationship.isEmpty || emptyLabels.contains(relationship)) return null;
    return relationship;
  }

  @override
  Widget build(BuildContext context) {
    return HomeGlass(
      level: HomeGlassLevel.main,
      borderRadius: 25,
      tint: const Color(0xFFB6A9D6),
      blurSigma: 30,
      surfaceOpacity: 0.075,
      shadows: const [
        BoxShadow(
          color: Color(0x52000000),
          blurRadius: 28,
          offset: Offset(0, 14),
        ),
        BoxShadow(
          color: Color(0x179F91C8),
          blurRadius: 18,
          offset: Offset(0, -3),
        ),
      ],
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CharacterAvatar(character: character),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  character.characterName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFB58BD3,
                                  ).withValues(alpha: 0.24),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFD9B7EF,
                                    ).withValues(alpha: 0.26),
                                  ),
                                ),
                                child: const Text(
                                  '在线',
                                  style: TextStyle(
                                    color: Color(0xFFF2DFFF),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          if (_relationshipLabel case final relationship?)
                            Row(
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 74,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      relationship,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.68,
                                        ),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _CharacterStatusText(text: greeting),
                                ),
                              ],
                            )
                          else
                            _CharacterStatusText(text: greeting),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.48),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: _LifeStatusItem(
                        label: '当前状态',
                        value: activity.displayText,
                        accent: const Color(0xFFE1B3D9),
                        onTap: onActivityTap,
                      ),
                    ),
                    _LifeStatusDivider(),
                    const Expanded(
                      child: _LifeStatusItem(
                        label: '最近活动',
                        value: '整理生活资料',
                        accent: Color(0xFF9FCBE6),
                      ),
                    ),
                    _LifeStatusDivider(),
                    const Expanded(
                      child: _LifeStatusItem(
                        label: '今日心情',
                        value: '平静',
                        accent: Color(0xFFC1B4E9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterStatusText extends StatelessWidget {
  const _CharacterStatusText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.66),
        fontSize: 11.5,
      ),
    );
  }
}

class _CharacterAvatar extends StatelessWidget {
  const _CharacterAvatar({required this.character});

  final AiCharacter character;

  Widget _image() {
    final avatarPath = character.avatarPath.trim();
    if (avatarPath.isNotEmpty && File(avatarPath).existsSync()) {
      return Image.file(
        File(avatarPath),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      );
    }
    if (character.isBuiltIn) {
      return Image.asset(
        'assets/images/pei_avatar.jpg',
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.12),
        filterQuality: FilterQuality.high,
      );
    }
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.12),
      child: const Icon(
        Icons.auto_awesome_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 43,
      height: 43,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.42),
        boxShadow: const [BoxShadow(color: Color(0x52000000), blurRadius: 12)],
      ),
      child: ClipOval(child: _image()),
    );
  }
}

class _LifeStatusItem extends StatelessWidget {
  const _LifeStatusItem({
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: accent, blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LifeStatusDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 9),
      color: Colors.white.withValues(alpha: 0.09),
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: HomeGlassButton(
        onTap: onTap,
        borderRadius: HomeVisualTokens.radiusButton,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      ),
    );
  }
}

class _QuickActionDock extends StatelessWidget {
  const _QuickActionDock({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 334),
        child: HomeGlass(
          level: HomeGlassLevel.main,
          borderRadius: 25,
          tint: const Color(0xFF9991C6),
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
          child: SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  Expanded(child: actions[index]),
                  if (index != actions.length - 1)
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.white.withValues(alpha: 0.075),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.badgeCount = 0,
    this.assetPath,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;
  final int badgeCount;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final tint = switch (label) {
      '聊天' => const Color(0xFF8FC8E8),
      '电话' => const Color(0xFFA4D5BC),
      'Echo' => const Color(0xFFC7B6EA),
      _ => Colors.white,
    };

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          splashColor: tint.withValues(alpha: 0.10),
          highlightColor: tint.withValues(alpha: 0.07),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            tint.withValues(alpha: 0.48),
                            tint.withValues(alpha: 0.16),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: tint.withValues(alpha: 0.13),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: assetPath == null
                          ? Icon(icon, color: Colors.white, size: 18)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                assetPath!,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.38),
                        fontSize: 8,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              if (badgeCount > 0)
                Positioned(top: 3, right: 8, child: _Badge(count: badgeCount)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LifeLiveIndicator extends StatelessWidget {
  const _LifeLiveIndicator({required this.isSleeping});

  final bool isSleeping;

  @override
  Widget build(BuildContext context) {
    final color = isSleeping
        ? const Color(0xFFB8AFE0)
        : const Color(0xFF9ED5B4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color, blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isSleeping ? '安静运行中' : '世界运行中',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.54),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TodayWorldCard extends StatelessWidget {
  const _TodayWorldCard({
    required this.now,
    required this.activity,
    required this.onTap,
  });

  final DateTime now;
  final ActivityStatus activity;
  final VoidCallback onTap;

  String get _weekday {
    const values = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return values[now.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return HomeGlassButton(
      onTap: onTap,
      level: HomeGlassLevel.main,
      borderRadius: 28,
      tint: const Color(0xFF87AFC8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${now.month}月${now.day}日',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$_weekday · 今日世界',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 52,
              color: Colors.white.withValues(alpha: 0.10),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_outlined,
                        color: Colors.white.withValues(alpha: 0.46),
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '天气与位置待接入',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.42),
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.34),
            ),
          ],
        ),
      ),
    );
  }
}

class _LifeSectionHeader extends StatelessWidget {
  const _LifeSectionHeader({
    required this.eyebrow,
    required this.title,
    required this.caption,
  });

  final String eyebrow;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: TextStyle(
                  color: const Color(0xFFA8CDE2).withValues(alpha: 0.62),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Text(
          caption,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.34),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _TodayLifeFragment extends StatelessWidget {
  const _TodayLifeFragment({
    required this.now,
    required this.activity,
    required this.onTap,
  });

  final DateTime now;
  final ActivityStatus activity;
  final VoidCallback onTap;

  int get _daysUntilAnniversary {
    var anniversary = DateTime(now.year, 1, 17);
    final today = DateTime(now.year, now.month, now.day);
    if (!anniversary.isAfter(today)) {
      anniversary = DateTime(now.year + 1, 1, 17);
    }
    return anniversary.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    return HomeGlassButton(
      onTap: onTap,
      level: HomeGlassLevel.card,
      borderRadius: 25,
      tint: const Color(0xFFA49AC6),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    activity.emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        activity.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.46),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.favorite_border_rounded,
                  color: Color(0xFFE3B5C7),
                  size: 16,
                ),
                const SizedBox(width: 7),
                Text(
                  '1 · 17',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '纪念日还有 $_daysUntilAnniversary 天',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.36),
                      fontSize: 10.5,
                    ),
                  ),
                ),
                Text(
                  '查看今天',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LifeTimeline extends StatelessWidget {
  const _LifeTimeline({required this.traces});

  final List<LifeTrace> traces;

  String _timeText(DateTime value) {
    final now = DateTime.now();
    if (now.year == value.year &&
        now.month == value.month &&
        now.day == value.day) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    return '${value.month}/${value.day}';
  }

  @override
  Widget build(BuildContext context) {
    return HomeGlass(
      level: HomeGlassLevel.card,
      borderRadius: 25,
      tint: const Color(0xFF88A9BC),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 13),
      child: traces.isEmpty
          ? Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '这里还很安静，生活正在慢慢发生。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.44),
                    fontSize: 12,
                  ),
                ),
              ],
            )
          : Column(
              children: List.generate(traces.length, (index) {
                final trace = traces[index];
                final isLast = index == traces.length - 1;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 39,
                        child: Text(
                          _timeText(trace.occurredAt),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.34),
                            fontSize: 10,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 23,
                        child: Column(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: const Color(0xFFAED2E4),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.34),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x558FC4DD),
                                    blurRadius: 7,
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 1,
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 2 : 15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    trace.emoji,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      trace.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.07,
                                      ),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      '已发生',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.40,
                                        ),
                                        fontSize: 8.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (trace.detail.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  trace.detail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.36),
                                    fontSize: 10.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
    );
  }
}

class _WorldEnvironmentCard extends StatelessWidget {
  const _WorldEnvironmentCard({required this.activity});

  final ActivityStatus activity;

  @override
  Widget build(BuildContext context) {
    return HomeGlass(
      level: HomeGlassLevel.card,
      borderRadius: 25,
      tint: const Color(0xFF789BB0),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Expanded(
            child: _EnvironmentItem(
              icon: Icons.cloud_outlined,
              label: '天气',
              value: '待接入',
            ),
          ),
          _EnvironmentDivider(),
          const Expanded(
            child: _EnvironmentItem(
              icon: Icons.location_on_outlined,
              label: '地点',
              value: '待同步',
            ),
          ),
          _EnvironmentDivider(),
          Expanded(
            child: _EnvironmentItem(
              icon: activity.isSleeping
                  ? Icons.dark_mode_outlined
                  : Icons.air_rounded,
              label: '环境',
              value: activity.isSleeping ? '夜间安静' : '平稳流动',
            ),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentItem extends StatelessWidget {
  const _EnvironmentItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFB8D7E7), size: 19),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.36),
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EnvironmentDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _AppEntry {
  const _AppEntry(
    this.label,
    this.icon,
    this.onTap, {
    required this.tint,
    this.badgeCount = 0,
    this.assetPath,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color tint;
  final int badgeCount;
  final String? assetPath;
}

class _PeiLinkAppPortal extends StatelessWidget {
  const _PeiLinkAppPortal({required this.entry});

  final _AppEntry entry;

  @override
  Widget build(BuildContext context) {
    return HomeGlassButton(
      onTap: entry.onTap,
      level: HomeGlassLevel.main,
      borderRadius: 27,
      tint: entry.tint,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 16, 14),
        child: Row(
          children: [
            _AppIconSurface(entry: entry, size: 56, iconSize: 26),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PeiLink',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '连接角色、消息与共同世界',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.44),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withValues(alpha: 0.64),
                size: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppSection extends StatelessWidget {
  const _AppSection({
    required this.title,
    required this.caption,
    required this.icon,
    required this.entries,
  });

  final String title;
  final String caption;
  final IconData icon;
  final List<_AppEntry> entries;

  @override
  Widget build(BuildContext context) {
    return HomeGlass(
      level: HomeGlassLevel.card,
      borderRadius: 25,
      tint: const Color(0xFF8EA5B8),
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.64), size: 16),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.30),
                    fontSize: 9.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < entries.length; index++) ...[
                Expanded(child: _DesktopAppIcon(entry: entries[index])),
                if (index != entries.length - 1) const SizedBox(width: 10),
              ],
              for (var index = entries.length; index < 3; index++) ...[
                if (index != 0) const SizedBox(width: 10),
                const Expanded(child: SizedBox()),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopAppIcon extends StatelessWidget {
  const _DesktopAppIcon({required this.entry});

  final _AppEntry entry;

  @override
  Widget build(BuildContext context) {
    return HomeGlassButton(
      onTap: entry.onTap,
      level: HomeGlassLevel.button,
      borderRadius: 20,
      tint: entry.tint,
      child: SizedBox(
        width: double.infinity,
        height: 84,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AppIconSurface(entry: entry, size: 40, iconSize: 19),
              const SizedBox(height: 8),
              Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppIconSurface extends StatelessWidget {
  const _AppIconSurface({
    required this.entry,
    this.size = 44,
    this.iconSize = 21,
  });

  final _AppEntry entry;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final image = entry.assetPath == null
        ? _FutureAppPlaceholder(
            tint: entry.tint,
            icon: entry.icon,
            iconSize: iconSize,
          )
        : Image.asset(
            entry.assetPath!,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => _FutureAppPlaceholder(
              tint: entry.tint,
              icon: entry.icon,
              iconSize: iconSize,
            ),
          );

    final displayedImage = entry.assetPath == null
        ? image
        : ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.27),
            child: image,
          );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: entry.tint.withValues(alpha: 0.16),
                    blurRadius: 11,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: displayedImage,
            ),
          ),
          if (entry.badgeCount > 0)
            Positioned(
              top: -6,
              right: -6,
              child: _Badge(count: entry.badgeCount),
            ),
        ],
      ),
    );
  }
}

class _FutureAppPlaceholder extends StatelessWidget {
  const _FutureAppPlaceholder({
    required this.tint,
    required this.icon,
    required this.iconSize,
  });

  final Color tint;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.15,
          colors: [
            Colors.white.withValues(alpha: 0.30),
            tint.withValues(alpha: 0.68),
            const Color(0xFF443671).withValues(alpha: 0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 6,
            right: 7,
            child: Icon(
              Icons.star_rounded,
              color: Colors.white.withValues(alpha: 0.55),
              size: 6,
            ),
          ),
          Positioned(
            left: 7,
            bottom: 8,
            child: Icon(
              Icons.star_rounded,
              color: const Color(0xFFB8E5FF).withValues(alpha: 0.48),
              size: 4,
            ),
          ),
          Icon(icon, color: Colors.white, size: iconSize),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE84F5F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.currentIndex});

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: index == currentIndex ? 18 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: index == currentIndex ? 0.88 : 0.25,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _HomeCharacterPicker extends StatelessWidget {
  const _HomeCharacterPicker({
    required this.characters,
    required this.selectedId,
  });

  final List<AiCharacter> characters;
  final String selectedId;

  Widget _avatar(AiCharacter character) {
    final path = character.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    if (character.isBuiltIn) {
      return Image.asset(
        'assets/images/pei_avatar.jpg',
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.15),
      );
    }
    return const ColoredBox(
      color: Color(0xFFE5EBEE),
      child: Icon(Icons.auto_awesome_rounded, color: Color(0xFF647C8B)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFF7F7F7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择首页展示角色',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                itemCount: characters.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final character = characters[index];
                  final selected = character.id == selectedId;
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(context, character),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: _avatar(character),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Text(
                                character.characterName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF4D788B),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
