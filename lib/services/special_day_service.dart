import 'package:lunar/lunar.dart';

import '../context_builder/temporal_context.dart';
import '../models/anniversary_item.dart';
import '../models/special_day.dart';

abstract final class SpecialDayService {
  static const _modern = <(int, int, String, String, String)>[
    (1, 1, '元旦', '新', '新的一年，平安顺意。'),
    (2, 14, '情人节', '♥', '愿真心被温柔珍惜。'),
    (3, 8, '妇女节', '花', '致敬每一份独立与光芒。'),
    (5, 1, '劳动节', '劳', '致敬认真生活的人。'),
    (5, 4, '青年节', '青', '保持热爱，奔赴山海。'),
    (6, 1, '儿童节', '童', '愿童心常在。'),
    (9, 10, '教师节', '师', '感谢每一次耐心引领。'),
    (10, 1, '国庆节', '国', '祝福祖国。'),
    (12, 25, '圣诞节', '🎄', '愿冬日有温暖相伴。'),
  ];

  static const _memorials = <(int, int, String, String)>[
    (7, 7, '七七事变纪念日', '铭记历史，珍爱和平。'),
    (9, 18, '九一八事变纪念日', '勿忘历史，吾辈自强。'),
    (12, 13, '南京大屠杀死难者国家公祭日', '铭记历史，珍爱和平。'),
  ];

  static List<SpecialDay> systemDaysFor(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final result = <SpecialDay>[];

    for (final item in _memorials) {
      if (day.month == item.$1 && day.day == item.$2) {
        result.add(
          SpecialDay(
            id: 'memorial_${item.$1}_${item.$2}',
            name: item.$3,
            type: SpecialDayType.memorialDay,
            marker: '◆',
            shortMessage: item.$4,
            priority: 500,
          ),
        );
      }
    }

    final lunar = Lunar.fromDate(day);
    final lunarMonth = lunar.getMonth();
    final lunarDay = lunar.getDay();
    if (lunarMonth > 0) {
      final traditional = switch ((lunarMonth, lunarDay)) {
        (1, 1) => ('春节', '🧧', '新岁已至，愿平安团圆。'),
        (1, 15) => ('元宵节', '🏮', '灯火映团圆。'),
        (5, 5) => ('端午节', '舟', '端午安康。'),
        (7, 7) => ('七夕', '♥', '今夕有些特别。'),
        (7, 15) => ('中元节', '灯', '宜念故人，敬过往。'),
        (8, 15) => ('中秋节', '月', '中秋已至，愿共此团圆。'),
        (9, 9) => ('重阳节', '菊', '重阳敬老，平安登高。'),
        _ => null,
      };
      if (traditional != null) {
        result.add(
          SpecialDay(
            id: 'lunar_${lunarMonth}_$lunarDay',
            name: traditional.$1,
            type: SpecialDayType.traditionalFestival,
            marker: traditional.$2,
            shortMessage: traditional.$3,
            priority: 300,
          ),
        );
      }
    }
    if (lunar.getJieQi() == '清明') {
      result.add(
        const SpecialDay(
          id: 'jieqi_qingming',
          name: '清明节',
          type: SpecialDayType.traditionalFestival,
          marker: '柳',
          shortMessage: '慎终追远，清明寄思。',
          priority: 310,
        ),
      );
    }

    for (final item in _modern) {
      if (day.month == item.$1 && day.day == item.$2) {
        result.add(
          SpecialDay(
            id: 'modern_${item.$1}_${item.$2}',
            name: item.$3,
            type: SpecialDayType.modernFestival,
            marker: item.$4,
            shortMessage: item.$5,
            priority: 200,
          ),
        );
      }
    }
    result.sort((a, b) => b.priority.compareTo(a.priority));
    return result;
  }

  static List<SpecialDay> daysFor(
    DateTime date, {
    Iterable<AnniversaryItem> anniversaries = const [],
  }) {
    final result = systemDaysFor(date);
    for (final item in anniversaries) {
      if (_anniversaryOccursOn(item, date)) {
        result.add(
          SpecialDay(
            id: 'anniversary_${item.id}',
            name: item.title,
            type: SpecialDayType.userAnniversary,
            marker: '♥',
            shortMessage: '这是你亲自收藏的重要日子。',
            priority: item.isPinned ? 400 : 250,
            anniversary: item,
          ),
        );
      }
    }
    result.sort((a, b) => b.priority.compareTo(a.priority));
    return result;
  }

  static WorldStatusContent worldStatusFor(
    DateTime date, {
    Iterable<AnniversaryItem> anniversaries = const [],
  }) {
    final temporal = TemporalContext(localTime: date);
    final days = daysFor(date, anniversaries: anniversaries);
    final featured = days.firstOrNull;
    if (featured == null) {
      return WorldStatusContent(
        headline: '世界平稳运行中',
        title: '${temporal.season.label} · ${temporal.timePeriod}',
        detail: '普通的一天',
        isMemorial: false,
      );
    }
    if (featured.isMemorial) {
      return WorldStatusContent(
        headline: '今日应当铭记',
        title: featured.name,
        detail: featured.shortMessage,
        isMemorial: true,
      );
    }
    if (featured.isUserAnniversary) {
      return WorldStatusContent(
        headline: '今天是值得记住的日子 ♥',
        title: featured.name,
        detail: '${temporal.season.label} · ${temporal.timePeriod}',
        isMemorial: false,
      );
    }
    return WorldStatusContent(
      headline: '今日有些特别 ${featured.marker}',
      title: featured.name,
      detail: '${temporal.season.label} · ${temporal.timePeriod}',
      isMemorial: false,
    );
  }

  static bool _anniversaryOccursOn(AnniversaryItem item, DateTime date) {
    if (item.repeatType == AnniversaryRepeatType.yearly) {
      return item.date.month == date.month && item.date.day == date.day;
    }
    return item.date.year == date.year &&
        item.date.month == date.month &&
        item.date.day == date.day;
  }
}
