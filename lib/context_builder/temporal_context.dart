enum TemporalHemisphere { northern, southern }

enum TemporalSeason {
  spring('春季'),
  summer('夏季'),
  autumn('秋季'),
  winter('冬季');

  const TemporalSeason(this.label);
  final String label;
}

/// Device-local date and time facts captured once for a model request.
///
/// PeiLink currently has no reliable structured country or hemisphere field,
/// so callers use the northern-hemisphere default. The parameter keeps the
/// mapping extensible without exposing that implementation detail to prompts.
class TemporalContext {
  const TemporalContext({
    required this.localTime,
    this.hemisphere = TemporalHemisphere.northern,
  });

  factory TemporalContext.now() => TemporalContext(localTime: DateTime.now());

  final DateTime localTime;
  final TemporalHemisphere hemisphere;

  TemporalSeason get season {
    final northernSeason = switch (localTime.month) {
      >= 3 && <= 5 => TemporalSeason.spring,
      >= 6 && <= 8 => TemporalSeason.summer,
      >= 9 && <= 11 => TemporalSeason.autumn,
      _ => TemporalSeason.winter,
    };
    if (hemisphere == TemporalHemisphere.northern) return northernSeason;
    return switch (northernSeason) {
      TemporalSeason.spring => TemporalSeason.autumn,
      TemporalSeason.summer => TemporalSeason.winter,
      TemporalSeason.autumn => TemporalSeason.spring,
      TemporalSeason.winter => TemporalSeason.summer,
    };
  }

  String get timePeriod => switch (localTime.hour) {
    >= 0 && < 5 => '深夜',
    >= 5 && < 8 => '清晨',
    >= 8 && < 12 => '上午',
    >= 12 && < 14 => '中午',
    >= 14 && < 18 => '下午',
    >= 18 && < 22 => '晚上',
    _ => '深夜',
  };

  String toPromptSection() {
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    return '''【Temporal Context｜现实时间】
当前日期：${localTime.year}-$month-$day
当前时间：$hour:$minute
当前时段：$timePeriod
当前月份：${localTime.month}月
当前季节：${season.label}
季节仅供生活常识参考，不代表实时天气；没有可靠事实时，不要虚构天气、气温或室内环境。''';
  }
}
