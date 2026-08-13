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
import 'peilink/ai_creation_center_page.dart';
import 'peilink/peilink_echo_page.dart';
import 'peilink/peilink_home_page.dart';
import 'settings_page.dart';
import 'today_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialHasVisibleCharacter});

  final bool? initialHasVisibleCharacter;

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
  AiCharacter _homeCharacter = AiCharacter.placeholder();
  bool _homeCharacterLoading = true;
  bool _hasVisibleCharacter = false;

  static final AiCharacter _emptyCharacter = AiCharacter(
    id: 'empty',
    characterName: '暂无角色',
    remark: '',
    relationship: '暂无关系',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
  static const ActivityStatus _emptyActivity = ActivityStatus(
    id: 'waiting',
    label: '等待连接',
    emoji: '',
    detail: '',
    promptGuidance: '',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialHasVisibleCharacter == false) {
      _homeCharacterLoading = false;
    } else {
      _loadHomeCharacter();
    }
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      if (!_hasVisibleCharacter) return;
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
      final characters = await _characterRegistry.loadCharacters();
      if (!mounted) return;
      if (characters.isEmpty) {
        setState(() {
          _hasVisibleCharacter = false;
          _homeCharacterLoading = false;
        });
        return;
      }
      final character = await _homeCharacterStorage.loadCharacter();
      if (!mounted) return;
      setState(() {
        _homeCharacter = character;
        _hasVisibleCharacter = true;
        _resolvedActivity = null;
        _homeCharacterLoading = false;
      });
      await _advanceWorld(markForeground: true);
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
    await _openChatForCharacter(_homeCharacter);
  }

  Future<void> _chooseHomeCharacter() async {
    final characters = await _characterRegistry.loadCharacters();
    if (!mounted) return;
    if (characters.isEmpty) {
      await _openCharacterCreation();
      return;
    }
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

  Future<void> _openChat() async {
    if (!_hasVisibleCharacter) {
      await _openPeiLink();
      return;
    }
    final characters = await _characterRegistry.loadCharacters();
    if (!mounted) return;
    if (characters.isEmpty) {
      await _openPeiLink();
      return;
    }
    final activeId = await _characterRegistry.loadActiveCharacterId();
    final recentCharacter = characters.firstWhere(
      (character) => character.id == activeId,
      orElse: () => _homeCharacter,
    );
    await _openChatForCharacter(recentCharacter);
  }

  Future<void> _openPeiLink() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PeiLinkHomePage()),
    );
    await _refreshInitiative();
    await _loadRecentTraces();
  }

  Future<void> _openChatForCharacter(AiCharacter character) async {
    await _characterRegistry.setActiveCharacter(character.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatPage(backDestinationBuilder: (_) => const PeiLinkHomePage()),
      ),
    );
    await _refreshInitiative();
    await _loadRecentTraces();
  }

  Future<void> _openCharacterCreation() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiCreationCenterPage()),
    );
    if (!mounted) return;
    await _loadHomeCharacter();
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
    if (!_hasVisibleCharacter) return;
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
    if (!_hasVisibleCharacter) return;
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
    if (!_hasVisibleCharacter) return;
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
    if (!_hasVisibleCharacter) return;
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

  void _openLifeDesktop() {
    _pageController.animateToPage(
      1,
      duration: HomeVisualTokens.motionPage,
      curve: HomeVisualTokens.motionEmphasizedCurve,
    );
  }

  void _showPlaceholder(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label 先住在桌面里，功能以后再搬进来。')));
  }

  @override
  Widget build(BuildContext context) {
    final hasCharacter = _hasVisibleCharacter || _homeCharacterLoading;
    final desktopCharacter = hasCharacter ? _homeCharacter : _emptyCharacter;
    final desktopActivity = hasCharacter ? _activity : _emptyActivity;
    final pages = <Widget>[
      _CharacterDesktopPage(
        character: desktopCharacter,
        loading: _homeCharacterLoading,
        hasCharacter: hasCharacter,
        greeting: hasCharacter ? _greeting : '暂无动态',
        activity: desktopActivity,
        unreadCount: _unreadCount,
        traces: hasCharacter ? _recentTraces : const [],
        onOpenCharacter: hasCharacter ? _openHomeCharacter : () {},
        onChooseCharacter: hasCharacter
            ? _chooseHomeCharacter
            : _openCharacterCreation,
        onActivityTap: _showActivityDetails,
        onChat: _openChat,
        onCall: () => _showPlaceholder('电话'),
        onEcho: _openEcho,
        onOpenLife: _openLifeDesktop,
      ),
      _LifeDesktopPage(
        now: _now,
        activity: desktopActivity,
        hasCharacter: hasCharacter,
        traces: hasCharacter ? _recentTraces : const [],
        onActivityTap: _showActivityDetails,
        onAnniversaryTap: () => _showPlaceholder('\u7eaa\u5ff5\u65e5'),
        onRecentTap: _openEcho,
        onSettingsTap: _openSettings,
        onAppTap: _showPlaceholder,
      ),
      _AppsDesktopPage(
        unreadCount: _unreadCount,
        onPeiLink: _openPeiLink,
        onSettings: _openSettings,
        onPlaceholder: _showPlaceholder,
      ),
    ];

    final overlayStyle =
        (_pageIndex == 0
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: _pageIndex == 0
                  ? Brightness.light
                  : Brightness.dark,
            );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: HomeVisualTokens.backgroundMiddle,
        body: Stack(
          children: [
            const Positioned.fill(child: _DesktopBackground()),
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => _pageIndex = value),
                itemBuilder: (_, index) => AnimatedSwitcher(
                  duration: _motionDuration,
                  child: KeyedSubtree(
                    key: ValueKey(
                      '${hasCharacter ? _homeCharacter.id : 'empty'}-$index',
                    ),
                    child: pages[index],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 8,
              child: IgnorePointer(
                child: _PageIndicator(
                  count: pages.length,
                  currentIndex: _pageIndex,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Retained only as a rollback-safe fallback; the live no-role path now uses
// the original character desktop with placeholder data.
// ignore: unused_element
class _EmptyCharacterDesktopPage extends StatelessWidget {
  const _EmptyCharacterDesktopPage({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('ai-world-empty-desktop'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF526573),
                  Color(0xFF1A2730),
                  Color(0xFF080D12),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Image.asset(
                          'assets/images/brand/peilink_logo_lockup.png',
                          height: 42,
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                      IconButton.filledTonal(
                        key: const ValueKey('ai-world-create-plus'),
                        onPressed: onCreate,
                        tooltip: '创建 AI',
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const Text(
                    'AI WORLD  ·  等待连接',
                    style: TextStyle(color: Colors.white60, fontSize: 11.5),
                  ),
                  const Spacer(),
                  _EmptyDesktopCard(height: 116),
                  const SizedBox(height: 9),
                  _EmptyDesktopCard(height: 72),
                  const SizedBox(height: 9),
                  Container(
                    height: 76,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        TextButton.icon(
                          key: const ValueKey('ai-world-create-entry'),
                          onPressed: onCreate,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('创建 AI'),
                        ),
                        const Icon(Icons.waves_rounded, color: Colors.white30),
                        const Icon(Icons.call_rounded, color: Colors.white30),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDesktopCard extends StatelessWidget {
  const _EmptyDesktopCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
    );
  }
}

// Retained only as a rollback-safe fallback; the live no-role path now uses
// the complete PeiLink Life page.
// ignore: unused_element
class _EmptyLifeDesktopPage extends StatelessWidget {
  const _EmptyLifeDesktopPage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: const ValueKey('ai-world-empty-life'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PeiLink Life',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 28),
            for (final title in const ['纪念日', '世界状态', '最近动态']) ...[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                height: 86,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _CharacterDesktopPage extends StatelessWidget {
  const _CharacterDesktopPage({
    required this.character,
    required this.hasCharacter,
    required this.loading,
    required this.greeting,
    required this.activity,
    required this.unreadCount,
    required this.traces,
    required this.onOpenCharacter,
    required this.onChooseCharacter,
    required this.onActivityTap,
    required this.onChat,
    required this.onCall,
    required this.onEcho,
    required this.onOpenLife,
  });

  final AiCharacter character;
  final bool hasCharacter;
  final bool loading;
  final String greeting;
  final ActivityStatus activity;
  final int unreadCount;
  final List<LifeTrace> traces;
  final VoidCallback onOpenCharacter;
  final VoidCallback onChooseCharacter;
  final VoidCallback onActivityTap;
  final VoidCallback onChat;
  final VoidCallback onCall;
  final VoidCallback onEcho;
  final VoidCallback onOpenLife;

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
            top: MediaQuery.paddingOf(context).top + 12,
            left: 22,
            right: 22,
            child: _AiDesktopHeader(
              loading: loading,
              hasCharacter: hasCharacter,
              onChooseCharacter: onChooseCharacter,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: MediaQuery.paddingOf(context).bottom + 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CharacterLifePanel(
                  character: character,
                  hasCharacter: hasCharacter,
                  greeting: greeting,
                  activity: activity,
                  onTap: onOpenCharacter,
                  onActivityTap: onActivityTap,
                  traces: traces,
                ),
                const SizedBox(height: 9),
                _TodayWorldSummary(
                  activity: activity,
                  traces: traces,
                  onTap: onOpenLife,
                ),
                const SizedBox(height: 9),
                _QuickActionDock(
                  actions: [
                    _QuickAction(
                      key: const ValueKey('ai-world-chat-entry'),
                      icon: Icons.chat_bubble_rounded,
                      label: '聊天',
                      caption: '继续交流',
                      badgeCount: unreadCount,
                      onTap: onChat,
                    ),
                    _QuickAction(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Echo',
                      caption: '他的生活回声',
                      assetPath: 'assets/images/app_icons/echo.png',
                      onTap: onEcho,
                    ),
                    _QuickAction(
                      icon: Icons.call_rounded,
                      label: '电话',
                      caption: '未来能力',
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
    required this.hasCharacter,
    required this.onChooseCharacter,
  });

  final bool loading;
  final bool hasCharacter;
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
              Image.asset(
                'assets/images/brand/peilink_logo_lockup.png',
                height: 42,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: 2),
              const Text(
                'AI WORLD  ·  运行中  ·  世界状态：平稳',
                style: TextStyle(
                  color: Color(0xAFFFFFFF),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.65,
                  shadows: [Shadow(color: Color(0x66000000), blurRadius: 10)],
                ),
              ),
            ],
          ),
        ),
        _RoundGlassButton(
          key: const ValueKey('ai-world-create-entry'),
          icon: hasCharacter ? Icons.person_search_rounded : Icons.add_rounded,
          tooltip: hasCharacter ? '切换角色' : '创建 AI',
          onTap: loading ? null : onChooseCharacter,
        ),
      ],
    );
  }
}

class _TodayWorldSummary extends StatelessWidget {
  const _TodayWorldSummary({
    required this.activity,
    required this.traces,
    required this.onTap,
  });

  final ActivityStatus activity;
  final List<LifeTrace> traces;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayCount = traces.where((trace) {
      final value = trace.occurredAt;
      return value.year == now.year &&
          value.month == now.month &&
          value.day == now.day;
    }).length;
    return HomeGlassButton(
      onTap: onTap,
      borderRadius: 19,
      tint: const Color(0xFFF0EDFA),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.public_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '今日世界',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${activity.isSleeping ? '静谧' : '平稳'} · ${todayCount == 0 ? '等待新的故事发生' : '$todayCount 条新动态'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontSize: 10.5,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.56),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _LifeDesktopPage extends StatelessWidget {
  const _LifeDesktopPage({
    required this.now,
    required this.activity,
    required this.hasCharacter,
    required this.traces,
    required this.onActivityTap,
    required this.onAnniversaryTap,
    required this.onRecentTap,
    required this.onSettingsTap,
    required this.onAppTap,
  });

  final DateTime now;
  final ActivityStatus activity;
  final bool hasCharacter;
  final List<LifeTrace> traces;
  final VoidCallback onActivityTap;
  final VoidCallback onAnniversaryTap;
  final VoidCallback onRecentTap;
  final VoidCallback onSettingsTap;
  final ValueChanged<String> onAppTap;

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
        padding: EdgeInsets.fromLTRB(
          18,
          MediaQuery.paddingOf(context).top + 12,
          18,
          MediaQuery.paddingOf(context).bottom + 42,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PEILINK LIFE',
                        style: TextStyle(
                          color: HomeVisualTokens.inkPrimary,
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '你的 AI 生活世界',
                        style: TextStyle(
                          color: HomeVisualTokens.inkSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Image.asset(
                  'assets/images/brand/peilink_butterfly.png',
                  width: 35,
                  height: 35,
                  fit: BoxFit.contain,
                  opacity: const AlwaysStoppedAnimation(0.82),
                ),
                const SizedBox(width: 8),
                _LifeLiveIndicator(isSleeping: activity.isSleeping),
              ],
            ),
            const SizedBox(height: 14),
            _LifeClockWidget(
              now: now,
              activity: activity,
              onTap: onActivityTap,
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _AnniversaryWidget(
                      now: now,
                      hasCharacter: hasCharacter,
                      onTap: onAnniversaryTap,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: _WorldStatusWidget(
                      activity: activity,
                      onTap: onActivityTap,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _RecentLifeWidget(
              traces: traces,
              hasCharacter: hasCharacter,
              onTap: onRecentTap,
            ),
            const SizedBox(height: 13),
            _LifeAppsWidget(onSettingsTap: onSettingsTap, onAppTap: onAppTap),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

class _LifeClockWidget extends StatelessWidget {
  const _LifeClockWidget({
    required this.now,
    required this.activity,
    required this.onTap,
  });

  final DateTime now;
  final ActivityStatus activity;
  final VoidCallback onTap;

  String get _weekday =>
      const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][now.weekday - 1];
  String get _time =>
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return _LifeWidgetShell(
      onTap: onTap,
      tint: const Color(0xFFF3F1FB),
      child: SizedBox(
        height: 126,
        child: Stack(
          children: [
            Positioned(
              right: -12,
              top: -24,
              child: Opacity(
                opacity: 0.26,
                child: Image.asset(
                  'assets/images/brand/peilink_butterfly.png',
                  width: 132,
                  height: 132,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 16, 18, 15),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(
                              now.hour >= 18 || now.hour < 6
                                  ? Icons.nightlight_round
                                  : Icons.wb_sunny_outlined,
                              color: HomeVisualTokens.brandBlue,
                              size: 19,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${now.month}月${now.day}日',
                              style: const TextStyle(
                                color: HomeVisualTokens.inkPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$_weekday · ${activity.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HomeVisualTokens.inkSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                        const Spacer(),
                        const _LifeWidgetHint(
                          label: '\u4eca\u65e5\u65e5\u5386',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 126,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _time,
                            style: const TextStyle(
                              color: HomeVisualTokens.inkPrimary,
                              fontSize: 43,
                              height: 1,
                              fontWeight: FontWeight.w300,
                              letterSpacing: -1.8,
                            ),
                          ),
                          const SizedBox(height: 9),
                          const Text(
                            'PEILINK WORLD TIME',
                            style: TextStyle(
                              color: HomeVisualTokens.inkTertiary,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
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

class _AnniversaryWidget extends StatelessWidget {
  const _AnniversaryWidget({
    required this.now,
    required this.hasCharacter,
    required this.onTap,
  });

  final DateTime now;
  final bool hasCharacter;
  final VoidCallback onTap;

  int get _daysLeft {
    final today = DateTime(now.year, now.month, now.day);
    var target = DateTime(now.year, 1, 17);
    if (!target.isAfter(today)) target = DateTime(now.year + 1, 1, 17);
    return target.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    return _LifeWidgetShell(
      onTap: onTap,
      tint: const Color(0xFFF7F0F8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 13, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LifeWidgetTitle(icon: Icons.favorite_rounded, title: '纪念日'),
            const SizedBox(height: 13),
            Text(
              hasCharacter ? '相遇纪念日' : '暂无纪念关系',
              style: TextStyle(
                color: HomeVisualTokens.inkSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hasCharacter ? '$_daysLeft' : '--',
                  style: const TextStyle(
                    color: HomeVisualTokens.inkPrimary,
                    fontSize: 35,
                    height: 1,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 3),
                  child: Text(
                    '天',
                    style: TextStyle(
                      color: HomeVisualTokens.inkSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              '每一天都值得被记住',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: HomeVisualTokens.inkTertiary,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldStatusWidget extends StatelessWidget {
  const _WorldStatusWidget({required this.activity, required this.onTap});

  final ActivityStatus activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _LifeWidgetShell(
      onTap: onTap,
      tint: const Color(0xFFEEF4FA),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 13, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LifeWidgetTitle(icon: Icons.public_rounded, title: '世界状态'),
            const SizedBox(height: 13),
            const Text(
              'PeiLink World',
              style: TextStyle(
                color: HomeVisualTokens.inkSecondary,
                fontSize: 10.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              activity.isSleeping ? '夜间安静运行中' : '世界稳定运行中',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HomeVisualTokens.inkPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                _WorldMetric(icon: Icons.cloud_outlined, label: '柔和'),
                const SizedBox(width: 9),
                _WorldMetric(
                  icon: activity.isSleeping
                      ? Icons.dark_mode_outlined
                      : Icons.bolt_rounded,
                  label: activity.isSleeping ? '静谧' : '活跃',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentLifeWidget extends StatelessWidget {
  const _RecentLifeWidget({
    required this.traces,
    required this.hasCharacter,
    required this.onTap,
  });

  final List<LifeTrace> traces;
  final bool hasCharacter;
  final VoidCallback onTap;

  String _timeText(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes.clamp(1, 59)}分钟前';
    }
    if (difference.inHours < 24) return '${difference.inHours}小时前';
    return '${value.month}/${value.day}';
  }

  @override
  Widget build(BuildContext context) {
    final visible = traces.take(3).toList();
    return _LifeWidgetShell(
      onTap: onTap,
      tint: const Color(0xFFF2F1FA),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 13, 12),
        child: Column(
          children: [
            const Row(
              children: [
                Expanded(
                  child: _LifeWidgetTitle(
                    icon: Icons.auto_awesome_rounded,
                    title: '最近动态',
                  ),
                ),
                _LifeWidgetHint(label: '进入 Echo'),
              ],
            ),
            const SizedBox(height: 9),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  hasCharacter ? '他的生活还没有开始记录\n等待新的故事发生' : '暂无生活记录\n等待新的故事发生',
                  style: const TextStyle(
                    color: HomeVisualTokens.inkSecondary,
                    fontSize: 11,
                  ),
                ),
              )
            else
              for (var index = 0; index < visible.length; index++) ...[
                _RecentLifeRow(
                  trace: visible[index],
                  timeText: _timeText(visible[index].occurredAt),
                ),
                if (index != visible.length - 1) const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _LifeAppsWidget extends StatelessWidget {
  const _LifeAppsWidget({required this.onSettingsTap, required this.onAppTap});

  final VoidCallback onSettingsTap;
  final ValueChanged<String> onAppTap;

  @override
  Widget build(BuildContext context) {
    final apps = [
      _AppEntry(
        '相册',
        Icons.photo_library_rounded,
        () => onAppTap('相册'),
        tint: const Color(0xFF8EA0F1),
        assetPath: 'assets/images/app_icons/gallery.png',
      ),
      _AppEntry(
        '音乐',
        Icons.headphones_rounded,
        () => onAppTap('音乐'),
        tint: const Color(0xFF9A8FE8),
        assetPath: 'assets/images/app_icons/music.png',
      ),
      _AppEntry(
        '礼物',
        Icons.card_giftcard_rounded,
        () => onAppTap('礼物'),
        tint: const Color(0xFFE2AFC5),
        assetPath: 'assets/images/app_icons/gift.png',
      ),
      _AppEntry(
        '日记',
        Icons.menu_book_rounded,
        () => onAppTap('日记'),
        tint: const Color(0xFFA18EE6),
        assetPath: 'assets/images/app_icons/diary.png',
      ),
      _AppEntry(
        '世界',
        Icons.public_rounded,
        () => onAppTap('世界'),
        tint: const Color(0xFF829CEB),
        assetPath: 'assets/images/app_icons/world.png',
      ),
      _AppEntry(
        '设置',
        Icons.settings_rounded,
        onSettingsTap,
        tint: const Color(0xFF8A91E9),
        assetPath: 'assets/images/app_icons/settings.png',
      ),
    ];
    return HomeGlass(
      level: HomeGlassLevel.card,
      borderRadius: 27,
      tint: const Color(0xFFF3F1F9),
      surfaceOpacity: 0.34,
      padding: const EdgeInsets.fromLTRB(11, 13, 11, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: _LifeWidgetTitle(icon: Icons.apps_rounded, title: '生活应用'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final app in apps)
                Expanded(child: _LifeDesktopApp(entry: app)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LifeDesktopApp extends StatelessWidget {
  const _LifeDesktopApp({required this.entry});
  final _AppEntry entry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _AppIconSurface(entry: entry, size: 43, iconSize: 20),
              const SizedBox(height: 6),
              Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(
                  color: HomeVisualTokens.inkPrimary,
                  fontSize: 9.5,
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

class _LifeWidgetShell extends StatelessWidget {
  const _LifeWidgetShell({
    required this.onTap,
    required this.tint,
    required this.child,
  });
  final VoidCallback onTap;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HomeGlassButton(
      onTap: onTap,
      level: HomeGlassLevel.card,
      borderRadius: 25,
      tint: tint,
      child: child,
    );
  }
}

class _LifeWidgetTitle extends StatelessWidget {
  const _LifeWidgetTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: HomeVisualTokens.brandViolet, size: 15),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: HomeVisualTokens.inkPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LifeWidgetHint extends StatelessWidget {
  const _LifeWidgetHint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: HomeVisualTokens.inkTertiary,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(width: 2),
        const Icon(
          Icons.chevron_right_rounded,
          color: HomeVisualTokens.inkTertiary,
          size: 14,
        ),
      ],
    );
  }
}

class _WorldMetric extends StatelessWidget {
  const _WorldMetric({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: HomeVisualTokens.brandBlue, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HomeVisualTokens.inkSecondary,
                fontSize: 9.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentLifeRow extends StatelessWidget {
  const _RecentLifeRow({required this.trace, required this.timeText});
  final LifeTrace trace;
  final String timeText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 31,
          height: 31,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.58),
            shape: BoxShape.circle,
          ),
          child: Text(trace.emoji, style: const TextStyle(fontSize: 15)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trace.title.trim().isEmpty ? '留下了一条生活动态' : trace.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomeVisualTokens.inkPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                trace.detail.trim().isEmpty ? '生活世界刚刚有了新的回声' : trace.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomeVisualTokens.inkSecondary,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          timeText,
          style: const TextStyle(
            color: HomeVisualTokens.inkTertiary,
            fontSize: 9,
          ),
        ),
      ],
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

  _AppEntry _app(
    String label,
    IconData icon,
    String asset,
    Color tint,
    VoidCallback onTap, {
    int badge = 0,
  }) => _AppEntry(
    label,
    icon,
    onTap,
    tint: tint,
    assetPath: asset,
    badgeCount: badge,
  );

  @override
  Widget build(BuildContext context) {
    final coreApps = <_AppEntry>[
      _app(
        'PeiLink',
        Icons.chat_bubble_rounded,
        'assets/images/brand/peilink_app_icon_1024.png',
        const Color(0xFF8394EC),
        onPeiLink,
        badge: unreadCount,
      ),
      _app(
        '相机',
        Icons.camera_alt_rounded,
        'assets/images/app_icons/camera.png',
        const Color(0xFF8EA0F1),
        () => onPlaceholder('相机'),
      ),
      _app(
        '相册',
        Icons.photo_library_rounded,
        'assets/images/app_icons/gallery.png',
        const Color(0xFF9A8FE8),
        () => onPlaceholder('相册'),
      ),
      _app(
        '音乐',
        Icons.headphones_rounded,
        'assets/images/app_icons/music.png',
        const Color(0xFF7F96EA),
        () => onPlaceholder('音乐'),
      ),
    ];
    final lifeApps = <_AppEntry>[
      _app(
        '日记',
        Icons.menu_book_rounded,
        'assets/images/app_icons/diary.png',
        const Color(0xFFA18EE6),
        () => onPlaceholder('日记'),
      ),
      _app(
        '礼物',
        Icons.card_giftcard_rounded,
        'assets/images/app_icons/gift.png',
        const Color(0xFFE2AFC5),
        () => onPlaceholder('礼物'),
      ),
      _app(
        '世界',
        Icons.public_rounded,
        'assets/images/app_icons/world.png',
        const Color(0xFF829CEB),
        () => onPlaceholder('世界'),
      ),
      _app(
        '设置',
        Icons.settings_rounded,
        'assets/images/app_icons/settings.png',
        const Color(0xFF8A91E9),
        onSettings,
      ),
    ];
    final futureApps = <_AppEntry>[
      _AppEntry(
        '地图',
        Icons.map_rounded,
        () => onPlaceholder('地图'),
        tint: const Color(0xFF91A1D8),
        locked: true,
      ),
      _AppEntry(
        '更多',
        Icons.auto_awesome_rounded,
        () => onPlaceholder('更多'),
        tint: const Color(0xFF9B8CE5),
        locked: true,
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
        key: const ValueKey('ai-world-apps-page'),
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          22,
          MediaQuery.paddingOf(context).top + 14,
          22,
          MediaQuery.paddingOf(context).bottom + 46,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '应用空间',
                        style: TextStyle(
                          color: HomeVisualTokens.inkPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'AI OS DESKTOP',
                        style: TextStyle(
                          color: HomeVisualTokens.inkTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                Image.asset(
                  'assets/images/brand/peilink_butterfly.png',
                  width: 34,
                  height: 34,
                  opacity: const AlwaysStoppedAnimation(0.78),
                ),
              ],
            ),
            const SizedBox(height: 26),
            _DesktopIconGroup(title: '核心应用', entries: coreApps),
            const SizedBox(height: 27),
            _DesktopIconGroup(title: '生活工具', entries: lifeApps),
            const SizedBox(height: 27),
            _DesktopIconGroup(title: '未来空间', entries: futureApps),
          ],
        ),
      ),
    );
  }
}

class _DesktopIconGroup extends StatelessWidget {
  const _DesktopIconGroup({required this.title, required this.entries});
  final String title;
  final List<_AppEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: const TextStyle(
              color: HomeVisualTokens.inkSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: entries.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisExtent: 92,
            crossAxisSpacing: 9,
          ),
          itemBuilder: (_, index) => _DesktopAppIcon(entry: entries[index]),
        ),
      ],
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
                    opacity: 0.22,
                  ),
                ),
                Positioned(
                  top: 230 - (drift * 14),
                  left: -150 + (drift * 18),
                  child: _AmbientOrb(
                    size: 310,
                    color: HomeVisualTokens.ambientViolet,
                    opacity: 0.16,
                  ),
                ),
                Positioned(
                  bottom: -105 + (drift * 16),
                  right: -120,
                  child: _AmbientOrb(
                    size: 290,
                    color: HomeVisualTokens.ambientWarm,
                    opacity: 0.12,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.15, -0.65),
                        radius: 1.05,
                        colors: [
                          Colors.white.withValues(alpha: 0.42),
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
    final path = character.backgroundImage.trim();

    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
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
          key: const ValueKey('ai-world-character-card'),
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
                      Color(0x3D050A11),
                      Color(0x05050A11),
                      Color(0x1206111A),
                      Color(0xB5070C14),
                      Color(0xE8070B12),
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
                          Color(0x5C050911),
                          Color(0x24050911),
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
    required this.hasCharacter,
    required this.greeting,
    required this.activity,
    required this.onTap,
    required this.onActivityTap,
    required this.traces,
  });

  final AiCharacter character;
  final bool hasCharacter;
  final String greeting;
  final ActivityStatus activity;
  final VoidCallback onTap;
  final VoidCallback onActivityTap;
  final List<LifeTrace> traces;

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
      tint: const Color(0xFFF4F0FA),
      blurSigma: 30,
      surfaceOpacity: 0.145,
      shadows: const [
        BoxShadow(
          color: Color(0x30070A12),
          blurRadius: 32,
          offset: Offset(0, 16),
        ),
        BoxShadow(
          color: Color(0x3CFFFFFF),
          blurRadius: 22,
          offset: Offset(0, -4),
        ),
      ],
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 17, 14),
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
                                    fontSize: 24,
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
                                child: Text(
                                  hasCharacter ? '在线' : '等待连接',
                                  style: const TextStyle(
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
                const SizedBox(height: 11),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.075),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
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
                      Expanded(
                        child: _LifeStatusItem(
                          label: '最近痕迹',
                          value: traces.isEmpty
                              ? '还没有留下新动态'
                              : traces.first.title,
                          accent: Color(0xFF9FCBE6),
                        ),
                      ),
                      _LifeStatusDivider(),
                      Expanded(
                        child: _LifeStatusItem(
                          label: '关系',
                          value: _relationshipLabel ?? '正在建立连接',
                          accent: Color(0xFFC1B4E9),
                        ),
                      ),
                    ],
                  ),
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
        fontSize: 12.5,
        height: 1.3,
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
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(2),
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
              fontSize: 8.5,
              letterSpacing: 0.2,
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
                    fontSize: 10.5,
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
    super.key,
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
        constraints: const BoxConstraints(maxWidth: 354),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x36090B14),
                blurRadius: 38,
                offset: Offset(0, 19),
              ),
              BoxShadow(
                color: Color(0x48FFFFFF),
                blurRadius: 26,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: HomeGlass(
            level: HomeGlassLevel.main,
            borderRadius: 30,
            tint: const Color(0xFFF7F3FC),
            surfaceOpacity: 0.225,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
            child: SizedBox(
              height: 82,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    Expanded(child: actions[index]),
                    if (index != actions.length - 1)
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(vertical: 14),
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    super.key,
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
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            tint.withValues(alpha: 0.48),
                            tint.withValues(alpha: 0.16),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
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
                          ? Icon(icon, color: Colors.white, size: 20)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Image.asset(
                                assetPath!,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
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
                        fontSize: 8.5,
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
            color: HomeVisualTokens.inkSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
    this.locked = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color tint;
  final int badgeCount;
  final String? assetPath;
  final bool locked;
}

class _DesktopAppIcon extends StatelessWidget {
  const _DesktopAppIcon({required this.entry});

  final _AppEntry entry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor: entry.tint.withValues(alpha: 0.10),
        highlightColor: HomeVisualTokens.brandBlue.withValues(alpha: 0.06),
        child: SizedBox(
          width: double.infinity,
          height: 80,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 53,
                  height: 53,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.56),
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [
                      BoxShadow(
                        color: entry.tint.withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: _AppIconSurface(entry: entry, size: 43, iconSize: 21),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HomeVisualTokens.inkPrimary,
                    fontSize: 10.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
        : DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(size * 0.30),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.86),
                width: 0.8,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(size * 0.055),
              child: Opacity(
                opacity: 0.82,
                child: Image.asset(
                  entry.assetPath!,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => _FutureAppPlaceholder(
                    tint: entry.tint,
                    icon: entry.icon,
                    iconSize: iconSize,
                  ),
                ),
              ),
            ),
          );

    final displayedImage = entry.assetPath == null
        ? image
        : ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.30),
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
                    color: const Color(0xFF697294).withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: displayedImage,
            ),
          ),
          if (entry.locked)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  boxShadow: HomeVisualTokens.buttonShadow,
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 11,
                  color: HomeVisualTokens.brandViolet,
                ),
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
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 6,
            right: 7,
            child: Icon(
              Icons.star_rounded,
              color: tint.withValues(alpha: 0.48),
              size: 6,
            ),
          ),
          Positioned(
            left: 7,
            bottom: 8,
            child: Icon(
              Icons.star_rounded,
              color: HomeVisualTokens.brandBlue.withValues(alpha: 0.36),
              size: 4,
            ),
          ),
          Icon(icon, color: tint.withValues(alpha: 0.72), size: iconSize),
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
            color: index == currentIndex
                ? HomeVisualTokens.brandBlue
                : HomeVisualTokens.inkTertiary.withValues(alpha: 0.34),
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
