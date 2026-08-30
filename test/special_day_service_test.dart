import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/anniversary_item.dart';
import 'package:peijianche_app/models/special_day.dart';
import 'package:peijianche_app/services/special_day_service.dart';

void main() {
  String? festival(DateTime date) => SpecialDayService.systemDaysFor(date)
      .where((day) => day.type == SpecialDayType.traditionalFestival)
      .firstOrNull
      ?.name;

  test('农历节日在多个年份使用真实公历日期', () {
    final cases = <DateTime, String>{
      DateTime(2024, 2, 10): '春节',
      DateTime(2025, 1, 29): '春节',
      DateTime(2026, 2, 17): '春节',
      DateTime(2024, 6, 10): '端午节',
      DateTime(2025, 5, 31): '端午节',
      DateTime(2026, 6, 19): '端午节',
      DateTime(2024, 8, 10): '七夕',
      DateTime(2025, 8, 29): '七夕',
      DateTime(2026, 8, 19): '七夕',
      DateTime(2024, 8, 18): '中元节',
      DateTime(2025, 9, 6): '中元节',
      DateTime(2026, 8, 27): '中元节',
      DateTime(2024, 9, 17): '中秋节',
      DateTime(2025, 10, 6): '中秋节',
      DateTime(2026, 9, 25): '中秋节',
    };
    for (final entry in cases.entries) {
      expect(festival(entry.key), entry.value, reason: '${entry.key}');
    }
  });

  test('固定纪念日使用克制 memorial 类型', () {
    for (final entry in <DateTime, String>{
      DateTime(2026, 7, 7): '七七事变纪念日',
      DateTime(2026, 9, 18): '九一八事变纪念日',
      DateTime(2026, 12, 13): '南京大屠杀死难者国家公祭日',
    }.entries) {
      final day = SpecialDayService.systemDaysFor(entry.key).first;
      expect(day.name, entry.value);
      expect(day.type, SpecialDayType.memorialDay);
      expect(day.marker, '◆');
    }
  });

  test('用户纪念日与系统节日同日时完整保留并按优先级排序', () {
    final anniversary = AnniversaryItem(
      id: 'ours',
      title: '我们的纪念日',
      date: DateTime(2020, 8, 19),
      repeatType: AnniversaryRepeatType.yearly,
      isPinned: true,
      createdAt: DateTime(2020, 8, 19),
    );
    final days = SpecialDayService.daysFor(
      DateTime(2026, 8, 19),
      anniversaries: [anniversary],
    );
    expect(days.map((day) => day.name), containsAll(['我们的纪念日', '七夕']));
    expect(days.first.name, '我们的纪念日');
  });

  test('World Status 覆盖普通日、节日、纪念日和重大纪念日', () {
    expect(
      SpecialDayService.worldStatusFor(DateTime(2026, 8, 20, 1)).headline,
      '世界平稳运行中',
    );
    expect(
      SpecialDayService.worldStatusFor(DateTime(2026, 8, 19, 20)).title,
      '七夕',
    );
    expect(
      SpecialDayService.worldStatusFor(DateTime(2026, 9, 25, 20)).title,
      '中秋节',
    );
    expect(
      SpecialDayService.worldStatusFor(DateTime(2026, 9, 18)).isMemorial,
      isTrue,
    );
    expect(
      SpecialDayService.worldStatusFor(DateTime(2026, 12, 13)).headline,
      '今日应当铭记',
    );
    final anniversary = AnniversaryItem(
      id: 'important',
      title: '重要的一天',
      date: DateTime(2020, 8, 20),
      repeatType: AnniversaryRepeatType.yearly,
      isPinned: true,
      createdAt: DateTime(2020, 8, 20),
    );
    expect(
      SpecialDayService.worldStatusFor(
        DateTime(2026, 8, 20),
        anniversaries: [anniversary],
      ).headline,
      '今天是值得记住的日子 ♥',
    );
  });

  test('跨午夜后按新日期重新计算 World Status', () {
    final before = SpecialDayService.worldStatusFor(
      DateTime(2026, 9, 17, 23, 59),
    );
    final after = SpecialDayService.worldStatusFor(DateTime(2026, 9, 18, 0, 1));
    expect(before.isMemorial, isFalse);
    expect(after.isMemorial, isTrue);
    expect(after.title, '九一八事变纪念日');
  });
}
