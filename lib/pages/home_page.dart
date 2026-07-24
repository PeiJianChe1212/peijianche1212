import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/activity_status.dart';
import '../models/ai_character.dart';
import '../models/life_trace.dart';
import '../services/activity_context_service.dart';
import '../services/activity_service.dart';
import '../services/character_registry_service.dart';
import '../services/home_character_storage_service.dart';
import '../services/presence_service.dart';
import '../services/initiative_service.dart';
import '../services/life_trace_service.dart';
import '../services/today_service.dart';
import 'peilink/character_detail_page.dart';
import 'peilink/peilink_home_page.dart';
import 'settings_page.dart';
import 'today_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ActivityService _activityService = const ActivityService();
  final PresenceService _presenceService = const PresenceService();
  final CharacterRegistryService _characterRegistry = CharacterRegistryService();
  final HomeCharacterStorageService _homeCharacterStorage =
      HomeCharacterStorageService();

  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  ActivityStatus? _resolvedActivity;
  int _unreadCount = 0;
  List<LifeTrace> _recentTraces = const [];
  AiCharacter _homeCharacter = AiCharacter.peiJianChe();
  bool _homeCharacterLoading = true;
  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
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
    await _loadRecentTraces();
  }

  Future<void> _chooseHomeCharacter() async {
    final characters = await _characterRegistry.loadCharacters();
    if (!mounted) return;

    final selected = await showModalBottomSheet<AiCharacter>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _HomeCharacterPicker(
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
      final traces = await LifeTraceService(characterId: _homeCharacter.id).loadRecent(limit: 3);
      if (!mounted) return;
      setState(() => _recentTraces = traces);
    } catch (error) {
      debugPrint('加载生活痕迹失败：$error');
    }
  }

  String get _timeText {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get _dateText {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${_now.month}月${_now.day}日  ${weekdays[_now.weekday - 1]}';
  }

  ActivityStatus get _activity =>
      _resolvedActivity ??
      _activityService.current(
        now: _now,
        characterId: _homeCharacter.id,
      );

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
      await TodayService(characterId: _homeCharacter.id).recordActivity(
        activity,
        now: time,
      );
    } catch (error) {
      debugPrint('记录 Today 失败：$error');
    }
  }

  Future<void> _showActivityDetails() async {
    final activity = _activity;
    await TodayService(characterId: _homeCharacter.id)
        .recordActivity(activity, now: _now);
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

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF10151D),
        body: SafeArea(
          child: Stack(
            children: [
              const Positioned.fill(child: _DesktopBackground()),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DesktopStatusBar(time: _timeText),
                    const SizedBox(height: 14),
                    _DateHeader(time: _timeText, date: _dateText),
                    const SizedBox(height: 18),
                    _PeiHeroCard(
                      character: _homeCharacter,
                      loading: _homeCharacterLoading,
                      greeting: _greeting,
                      activity: _activity,
                      onOpenCharacter: _openHomeCharacter,
                      onChooseCharacter: _chooseHomeCharacter,
                      onActivityTap: _showActivityDetails,
                    ),
                    const SizedBox(height: 18),
                    _TodayPanel(now: _now),
                    const SizedBox(height: 14),
                    _RecentTracePanel(traces: _recentTraces),
                    const SizedBox(height: 22),
                    _AppGrid(
                      onChat: _openPeiLink,
                      onSettings: _openSettings,
                      unreadCount: _unreadCount,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopBackground extends StatelessWidget {
  const _DesktopBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26384A), Color(0xFF121923), Color(0xFF090D13)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7E9DB5).withValues(alpha: 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopStatusBar extends StatelessWidget {
  const _DesktopStatusBar({required this.time});

  final String time;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          time,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        const Icon(
          Icons.signal_cellular_alt_rounded,
          color: Colors.white,
          size: 17,
        ),
        const SizedBox(width: 6),
        const Icon(Icons.wifi_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 6),
        const Icon(Icons.battery_full_rounded, color: Colors.white, size: 20),
      ],
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.time, required this.date});

  final String time;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 44,
            height: 1,
            fontWeight: FontWeight.w300,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          date,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _PeiHeroCard extends StatefulWidget {
  const _PeiHeroCard({
    required this.character,
    required this.loading,
    required this.greeting,
    required this.activity,
    required this.onOpenCharacter,
    required this.onChooseCharacter,
    required this.onActivityTap,
  });

  final AiCharacter character;
  final bool loading;
  final String greeting;
  final ActivityStatus activity;
  final VoidCallback onOpenCharacter;
  final VoidCallback onChooseCharacter;
  final VoidCallback onActivityTap;

  @override
  State<_PeiHeroCard> createState() => _PeiHeroCardState();
}

class _PeiHeroCardState extends State<_PeiHeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _imageScale;
  late final Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _imageScale = Tween<double>(begin: 1.025, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _contentFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _characterImage() {
    final path = widget.character.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.12),
      );
    }
    if (widget.character.isBuiltIn) {
      return Image.asset(
        'assets/images/pei_hero_flower.jpg',
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.12),
        errorBuilder: (_, _, _) => _fallbackImage(),
      );
    }
    return _fallbackImage();
  }

  Widget _fallbackImage() {
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
    return AspectRatio(
      aspectRatio: 0.91,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Material(
          color: const Color(0xFFE9E7E3),
          child: InkWell(
            onTap: widget.loading ? null : widget.onOpenCharacter,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ScaleTransition(scale: _imageScale, child: _characterImage()),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x12000000),
                        Colors.transparent,
                        Color(0x33000000),
                        Color(0xE80A1118),
                      ],
                      stops: [0, 0.38, 0.62, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 18,
                  left: 18,
                  child: FadeTransition(
                    opacity: _contentFade,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: widget.loading ? null : widget.onChooseCharacter,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.24),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 18,
                  right: 18,
                  child: FadeTransition(
                    opacity: _contentFade,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: widget.onActivityTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 8,
                                color: Color(0xFF9ED5B4),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                widget.activity.displayText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 25,
                  child: FadeTransition(
                    opacity: _contentFade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.character.characterName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          widget.greeting,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.90),
                            fontSize: 16,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
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

class _RecentTracePanel extends StatelessWidget {
  const _RecentTracePanel({required this.traces});

  final List<LifeTrace> traces;

  String _timeText(DateTime value) {
    final now = DateTime.now();
    if (now.year == value.year && now.month == value.month && now.day == value.day) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    return '${value.month}/${value.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: Colors.white.withValues(alpha: 0.80), size: 19),
              const SizedBox(width: 8),
              Text('最近留下的痕迹', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          if (traces.isEmpty)
            Text('这里还很安静。', style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 13))
          else
            ...traces.map((trace) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(width: 42, child: Text(_timeText(trace.occurredAt), style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 11))),
                  Text(trace.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(trace.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.84), fontSize: 13.5))),
                ],
              ),
            )),
        ],
      ),
    );
  }
}

class _TodayPanel extends StatelessWidget {
  const _TodayPanel({required this.now});

  final DateTime now;

  int get _daysUntilAnniversary {
    var anniversary = DateTime(now.year, 1, 17);
    final today = DateTime(now.year, now.month, now.day);
    if (!anniversary.isAfter(today)) {
      anniversary = DateTime(now.year + 1, 1, 17);
    }
    return anniversary.difference(today).inDays;
  }

  String get _dayPart {
    if (now.hour < 6) return '深夜';
    if (now.hour < 11) return '早晨';
    if (now.hour < 14) return '中午';
    if (now.hour < 18) return '下午';
    if (now.hour < 23) return '晚上';
    return '深夜';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 17),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.today_outlined,
                color: Colors.white.withValues(alpha: 0.82),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '今天',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _dayPart,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.46),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _TodayItem(
                  icon: Icons.favorite_border_rounded,
                  value: '1 · 17',
                  caption: '距纪念日还有 $_daysUntilAnniversary 天',
                ),
              ),
              Container(
                width: 1,
                height: 42,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: Colors.white.withValues(alpha: 0.10),
              ),
              const Expanded(
                child: _TodayItem(
                  icon: Icons.cloud_outlined,
                  value: '天气待接入',
                  caption: '以后会显示实时天气',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayItem extends StatelessWidget {
  const _TodayItem({
    required this.icon,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.70), size: 22),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.44),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({
    required this.onChat,
    required this.onSettings,
    required this.unreadCount,
  });

  final VoidCallback onChat;
  final VoidCallback onSettings;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 22,
      crossAxisSpacing: 10,
      childAspectRatio: 0.76,
      children: [
        _DesktopAppIcon(
          icon: Icons.chat_bubble_rounded,
          label: 'PeiLink',
          background: const LinearGradient(
            colors: [Color(0xFF80B4D0), Color(0xFF426F89)],
          ),
          onTap: onChat,
          badgeCount: unreadCount,
        ),
        const _DesktopAppIcon(
          icon: Icons.photo_library_outlined,
          label: '相册',
          background: LinearGradient(
            colors: [Color(0xFFC69A91), Color(0xFF875E59)],
          ),
        ),
        const _DesktopAppIcon(
          icon: Icons.camera_alt_outlined,
          label: 'Echo',
          background: LinearGradient(
            colors: [Color(0xFF8FB7AA), Color(0xFF4F786D)],
          ),
        ),
        _DesktopAppIcon(
          icon: Icons.settings_rounded,
          label: '设置',
          background: const LinearGradient(
            colors: [Color(0xFFADB7C0), Color(0xFF66727C)],
          ),
          onTap: onSettings,
        ),
      ],
    );
  }
}

class _DesktopAppIcon extends StatelessWidget {
  const _DesktopAppIcon({
    required this.icon,
    required this.label,
    required this.background,
    this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final Gradient background;
  final VoidCallback? onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:
          onTap ??
          () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$label 还在建设中。')));
          },
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: background,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: Icon(icon, color: Colors.white, size: 30)),
                if (badgeCount > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE84F5F),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
