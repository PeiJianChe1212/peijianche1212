import 'package:flutter/material.dart';

import '../../services/calendar_holiday_service.dart';
import '../../theme/app_theme_background.dart';

class PeiLinkCalendarPage extends StatefulWidget {
  const PeiLinkCalendarPage({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<PeiLinkCalendarPage> createState() => _PeiLinkCalendarPageState();
}

class _PeiLinkCalendarPageState extends State<PeiLinkCalendarPage> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(initial.year, initial.month, initial.day);
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

  @override
  Widget build(BuildContext context) {
    final holiday = CalendarHolidayService.labelFor(_selectedDate);
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('日历'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
              ),
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
                currentDate: DateTime.now(),
                onDateChanged: (value) => setState(() {
                  _selectedDate = value;
                }),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEAFB),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      '${_selectedDate.day}',
                      style: const TextStyle(
                        color: Color(0xFF665B91),
                        fontSize: 20,
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
                          '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          holiday == null ? _weekday : '$_weekday · $holiday',
                          style: const TextStyle(color: Color(0xFF8B8497)),
                        ),
                      ],
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
