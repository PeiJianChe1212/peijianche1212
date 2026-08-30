import 'package:flutter/material.dart';

import '../../models/anniversary_item.dart';
import '../../models/special_day.dart';
import '../../services/anniversary_storage_service.dart';
import '../../services/special_day_service.dart';
import '../../theme/app_theme_background.dart';
import '../../widgets/home/home_glass.dart';
import '../../widgets/home/home_visual_tokens.dart';

class PeiLinkCalendarPage extends StatefulWidget {
  const PeiLinkCalendarPage({
    super.key,
    this.initialDate,
    this.initialAnniversaries,
  });
  final DateTime? initialDate;
  final List<AnniversaryItem>? initialAnniversaries;

  @override
  State<PeiLinkCalendarPage> createState() => _PeiLinkCalendarPageState();
}

class _PeiLinkCalendarPageState extends State<PeiLinkCalendarPage> {
  late DateTime _selectedDate;
  late DateTime _visibleMonth;
  late List<AnniversaryItem> _anniversaries;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(initial.year, initial.month, initial.day);
    _visibleMonth = DateTime(initial.year, initial.month);
    _anniversaries = widget.initialAnniversaries ?? const [];
    if (widget.initialAnniversaries == null) _load();
  }

  Future<void> _load() async {
    final items = await AnniversaryStorageService().loadAll();
    if (mounted) setState(() => _anniversaries = items);
  }

  String get _weekday => const [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ][_selectedDate.weekday - 1];

  List<DateTime> get _monthCells {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    return List.generate(42, (i) => start.add(Duration(days: i)));
  }

  void _changeMonth(int delta) => setState(() {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    _selectedDate = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
  });

  @override
  Widget build(BuildContext context) {
    final selectedDays = SpecialDayService.daysFor(
      _selectedDate,
      anniversaries: _anniversaries,
    );
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Column(
            children: [
              Text('日历'),
              Text(
                '日期与重要日子',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: HomeVisualTokens.inkTertiary,
                ),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
          children: [
            HomeGlass(
              level: HomeGlassLevel.main,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_visibleMonth.year}年${_visibleMonth.month}月',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: HomeVisualTokens.inkPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '上个月',
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: '下个月',
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                        Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: HomeVisualTokens.inkSecondary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 42,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisExtent: 43,
                        ),
                    itemBuilder: (context, index) {
                      final date = _monthCells[index];
                      return _CalendarDayCell(
                        date: date,
                        inMonth: date.month == _visibleMonth.month,
                        selected: DateUtils.isSameDay(date, _selectedDate),
                        today: DateUtils.isSameDay(date, DateTime.now()),
                        days: SpecialDayService.daysFor(
                          date,
                          anniversaries: _anniversaries,
                        ),
                        onTap: () => setState(() => _selectedDate = date),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _DayDetailCard(
              date: _selectedDate,
              weekday: _weekday,
              days: selectedDays,
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.days,
    required this.onTap,
  });
  final DateTime date;
  final bool inMonth;
  final bool selected;
  final bool today;
  final List<SpecialDay> days;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final featured = days.firstOrNull;
    return Semantics(
      button: true,
      label:
          '${date.year}年${date.month}月${date.day}日${featured == null ? '' : ' ${featured.name}'}',
      child: InkWell(
        key: ValueKey('calendar-day-${date.year}-${date.month}-${date.day}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: selected
                  ? HomeVisualTokens.brandViolet
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: today && !selected
                  ? Border.all(color: HomeVisualTokens.brandBlue)
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : inMonth
                        ? HomeVisualTokens.inkPrimary
                        : HomeVisualTokens.inkTertiary.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (featured != null)
                  Positioned(
                    right: 1,
                    top: 0,
                    child: Text(
                      featured.marker,
                      style: TextStyle(
                        color: selected ? Colors.white : null,
                        fontSize: 7,
                        height: 1,
                      ),
                    ),
                  ),
                if (days.length > 1)
                  Positioned(
                    bottom: 2,
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white
                            : HomeVisualTokens.brandBlue,
                        shape: BoxShape.circle,
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

class _DayDetailCard extends StatelessWidget {
  const _DayDetailCard({
    required this.date,
    required this.weekday,
    required this.days,
  });
  final DateTime date;
  final String weekday;
  final List<SpecialDay> days;

  @override
  Widget build(BuildContext context) {
    return HomeGlass(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEAFB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${date.day}',
                  style: const TextStyle(
                    color: Color(0xFF665B91),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${date.year}年${date.month}月${date.day}日',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: HomeVisualTokens.inkPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      weekday,
                      style: const TextStyle(
                        fontSize: 11,
                        color: HomeVisualTokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (days.isNotEmpty) ...[
            const SizedBox(height: 15),
            for (var i = 0; i < days.length; i++) ...[
              _SpecialDayDetail(day: days[i]),
              if (i != days.length - 1) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _SpecialDayDetail extends StatelessWidget {
  const _SpecialDayDetail({required this.day});
  final SpecialDay day;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: day.isMemorial ? const Color(0xFFF1F1F3) : const Color(0xFFF5F1FC),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(day.marker, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                day.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: HomeVisualTokens.inkPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                day.shortMessage,
                style: const TextStyle(
                  fontSize: 11,
                  color: HomeVisualTokens.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
