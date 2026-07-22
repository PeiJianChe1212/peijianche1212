import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/activity_status.dart';
import '../models/life_trace.dart';
import '../services/activity_service.dart';
import '../services/presence_service.dart';
import '../services/initiative_service.dart';
import '../services/life_trace_service.dart';
import '../services/settings_storage_service.dart';
import '../services/today_service.dart';
import 'chat_page.dart';
import 'memory_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'today_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final SettingsStorageService _settingsStorage = SettingsStorageService();
  final ActivityService _activityService = const ActivityService();
  final PresenceService _presenceService = const PresenceService();
  final TodayService _todayService = TodayService();
  final InitiativeService _initiativeService = InitiativeService();
  final LifeTraceService _lifeTraceService = LifeTraceService();

  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int _unreadCount = 0;
  List<LifeTrace> _recentTraces = const [];
  ChatSettings _settings = const ChatSettings(
    openingMessage: '回来了？今天过得怎么样。',
    conversationMode: 'basic',
    temperature: 0.72,
    replyLength: 'standard',
    initiative: 0.58,
    intimacy: 0.52,
    tsundere: 0.62,
    proactiveEnabled: true,
    lateNightMessages: true,
    maxProactivePerDay: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refreshInitiative();
    _recordCurrentActivity();
    _loadRecentTraces();
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

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsStorage.loadSettings();
      if (!mounted) return;
      setState(() => _settings = settings);
    } catch (error) {
      debugPrint('桌面加载设置失败：$error');
    }
  }

  Future<void> _saveSettings({
    required String openingMessage,
    required String conversationMode,
    required double temperature,
    required String replyLength,
    required double initiative,
    required double intimacy,
    required double tsundere,
    required bool proactiveEnabled,
    required bool lateNightMessages,
    required int maxProactivePerDay,
  }) async {
    final settings = ChatSettings(
      openingMessage: openingMessage.trim().isEmpty
          ? '回来了？今天过得怎么样。'
          : openingMessage.trim(),
      conversationMode: conversationMode,
      temperature: temperature.clamp(0.55, 0.90).toDouble(),
      replyLength: replyLength,
      initiative: initiative.clamp(0, 1).toDouble(),
      intimacy: intimacy.clamp(0, 1).toDouble(),
      tsundere: tsundere.clamp(0, 1).toDouble(),
      proactiveEnabled: proactiveEnabled,
      lateNightMessages: lateNightMessages,
      maxProactivePerDay: maxProactivePerDay.clamp(0, 4).toInt(),
    );
    await _settingsStorage.saveSettings(settings);
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _openChat() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatPage()),
    );
    await _loadSettings();
    await _refreshInitiative();
    await _loadRecentTraces();
  }

  Future<void> _openMemory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MemoryPage()),
    );
  }

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          openingMessage: _settings.openingMessage,
          conversationMode: _settings.conversationMode,
          temperature: _settings.temperature,
          replyLength: _settings.replyLength,
          initiative: _settings.initiative,
          intimacy: _settings.intimacy,
          tsundere: _settings.tsundere,
          proactiveEnabled: _settings.proactiveEnabled,
          lateNightMessages: _settings.lateNightMessages,
          maxProactivePerDay: _settings.maxProactivePerDay,
          onSaveSettings: _saveSettings,
        ),
      ),
    );
    await _loadSettings();
  }

  Future<void> _refreshInitiative({DateTime? now}) async {
    try {
      await _initiativeService.maybeLeaveMessage(now: now);
      final unread = await _initiativeService.unreadCount();
      if (!mounted) return;
      setState(() => _unreadCount = unread);
      await _loadRecentTraces();
    } catch (error) {
      debugPrint('主动联系检查失败：$error');
    }
  }

  Future<void> _loadRecentTraces() async {
    try {
      final traces = await _lifeTraceService.loadRecent(limit: 3);
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

  ActivityStatus get _activity => _activityService.current(now: _now);

  String get _greeting =>
      _presenceService.homeGreeting(now: _now, activity: _activity);

  Future<void> _recordCurrentActivity({DateTime? now}) async {
    try {
      final time = now ?? DateTime.now();
      await _todayService.recordActivity(
        _activityService.current(now: time),
        now: time,
      );
    } catch (error) {
      debugPrint('记录 Today 失败：$error');
    }
  }

  Future<void> _showActivityDetails() async {
    final activity = _activity;
    await _todayService.recordActivity(activity, now: _now);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TodayPage(currentActivity: activity)),
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
                      greeting: _greeting,
                      activity: _activity,
                      onChat: _openChat,
                      onActivityTap: _showActivityDetails,
                    ),
                    const SizedBox(height: 18),
                    _TodayPanel(now: _now),
                    const SizedBox(height: 14),
                    _RecentTracePanel(traces: _recentTraces),
                    const SizedBox(height: 22),
                    _AppGrid(
                      onChat: _openChat,
                      onProfile: _openProfile,
                      onMemory: _openMemory,
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
    required this.greeting,
    required this.activity,
    required this.onChat,
    required this.onActivityTap,
  });

  final String greeting;
  final ActivityStatus activity;
  final VoidCallback onChat;
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
    _imageScale = Tween<double>(
      begin: 1.025,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
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

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.91,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Material(
          color: const Color(0xFFE9E7E3),
          child: InkWell(
            onTap: widget.onChat,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ScaleTransition(
                  scale: _imageScale,
                  child: Image.asset(
                    'assets/images/pei_hero_flower.jpg',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.12),
                    errorBuilder: (_, _, _) => const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFDDE4E9),
                            Color(0xFF536675),
                            Color(0xFF18232D),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
                  bottom: 22,
                  child: FadeTransition(
                    opacity: _contentFade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '裴简澈',
                          style: TextStyle(
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
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.20),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '继续聊天',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 5),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white,
                                size: 13,
                              ),
                            ],
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
    required this.onProfile,
    required this.onMemory,
    required this.onSettings,
    required this.unreadCount,
  });

  final VoidCallback onChat;
  final VoidCallback onProfile;
  final VoidCallback onMemory;
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
          label: '聊天',
          background: const LinearGradient(
            colors: [Color(0xFF80B4D0), Color(0xFF426F89)],
          ),
          onTap: onChat,
          badgeCount: unreadCount,
        ),
        _DesktopAppIcon(
          icon: Icons.person_rounded,
          label: '我',
          background: const LinearGradient(
            colors: [Color(0xFFD6A6B8), Color(0xFF8B6074)],
          ),
          onTap: onProfile,
        ),
        _DesktopAppIcon(
          icon: Icons.memory_rounded,
          label: '记忆',
          background: const LinearGradient(
            colors: [Color(0xFF9E91C5), Color(0xFF62557E)],
          ),
          onTap: onMemory,
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
          label: 'Moments',
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
