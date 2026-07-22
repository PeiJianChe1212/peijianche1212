import 'package:flutter/material.dart';

import '../models/activity_status.dart';
import '../models/today_event.dart';
import '../services/today_service.dart';
import 'chat_page.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({required this.currentActivity, super.key});

  final ActivityStatus currentActivity;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final TodayService _todayService = TodayService();
  List<TodayEvent> _events = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _todayService.recordActivity(widget.currentActivity);
    final events = await _todayService.loadToday();
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  String _timeText(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get _dateText {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 · 星期${weekdays[now.weekday - 1]}';
  }

  Future<void> _openChat() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatPage()),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F1),
      appBar: AppBar(
        title: const Text('今天'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF5F4F1),
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                children: [
                  Text(
                    _dateText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.currentActivity.displayText,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.currentActivity.detail,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '今天留下的痕迹',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  if (_events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 42),
                      child: Center(
                        child: Text(
                          '今天还很安静。',
                          style: TextStyle(color: Colors.black38),
                        ),
                      ),
                    )
                  else
                    ..._events.map(
                      (event) => _TimelineCard(
                        event: event,
                        timeText: _timeText(event.occurredAt),
                        isCurrent: event.kind == 'activity' &&
                            event.id ==
                                _events.lastWhere(
                                  (item) => item.kind == 'activity',
                                  orElse: () => event,
                                ).id,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _openChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('去找他'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.event,
    required this.timeText,
    required this.isCurrent,
  });

  final TodayEvent event;
  final String timeText;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 17),
              child: Text(
                timeText,
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(top: 19),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent
                      ? const Color(0xFF2F6478)
                      : const Color(0xFFB7C1C5),
                ),
              ),
              Expanded(
                child: Container(width: 1, color: const Color(0xFFD9D9D5)),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 13),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8E7E3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${event.emoji} ${event.title}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    event.story,
                    style: const TextStyle(
                      color: Colors.black54,
                      height: 1.5,
                      fontSize: 14,
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
