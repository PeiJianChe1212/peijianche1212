import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/context_builder/temporal_context.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/services/context_builder.dart';

void main() {
  group('TemporalContext season mapping', () {
    final cases = <DateTime, TemporalSeason>{
      DateTime(2026, 1, 15): TemporalSeason.winter,
      DateTime(2026, 3, 15): TemporalSeason.spring,
      DateTime(2026, 6, 15): TemporalSeason.summer,
      DateTime(2026, 9, 15): TemporalSeason.autumn,
      DateTime(2026, 12, 15): TemporalSeason.winter,
      DateTime(2026, 2, 28): TemporalSeason.winter,
      DateTime(2026, 3, 1): TemporalSeason.spring,
      DateTime(2026, 5, 31): TemporalSeason.spring,
      DateTime(2026, 6, 1): TemporalSeason.summer,
      DateTime(2026, 8, 31): TemporalSeason.summer,
      DateTime(2026, 9, 1): TemporalSeason.autumn,
      DateTime(2026, 11, 30): TemporalSeason.autumn,
      DateTime(2026, 12, 1): TemporalSeason.winter,
    };

    for (final entry in cases.entries) {
      test('${entry.key.toIso8601String()} maps to ${entry.value.label}', () {
        expect(TemporalContext(localTime: entry.key).season, entry.value);
      });
    }
  });

  test('fixed request time produces compact season facts without weather', () {
    final prompt = ContextBuilder.build(
      task: ContextTask.chat,
      settings: CharacterSettings.genericDefaults(),
      now: DateTime(2026, 8, 27, 1, 23),
    );

    expect(prompt, contains('2026-08-27'));
    expect(prompt, contains('当前时间：01:23'));
    expect(prompt, contains('当前时段：深夜'));
    expect(prompt, contains('当前月份：8月'));
    expect(prompt, contains('当前季节：夏季'));
    expect(prompt, contains('不代表实时天气'));
    expect(prompt, isNot(contains('实时温度')));
    expect(prompt, isNot(contains('正在下雨')));
    expect(prompt, isNot(contains('正在下雪')));
    expect(prompt, isNot(contains('当前晴天')));
  });

  test('southern mapping stays available without changing prompt wording', () {
    final context = TemporalContext(
      localTime: DateTime(2026, 8, 27),
      hemisphere: TemporalHemisphere.southern,
    );
    expect(context.season, TemporalSeason.winter);
    expect(context.toPromptSection(), isNot(contains('北半球')));
    expect(context.toPromptSection(), isNot(contains('南半球')));
  });

  test('temporal facts refresh outside the stable context cache', () {
    ContextBuilder.clearCache();
    final settings = CharacterSettings.genericDefaults();
    final beforeMidnight = ContextBuilder.build(
      task: ContextTask.chat,
      settings: settings,
      now: DateTime(2026, 8, 31, 23, 50),
    );
    final afterMidnight = ContextBuilder.build(
      task: ContextTask.chat,
      settings: settings,
      now: DateTime(2026, 9, 1, 1),
    );

    expect(beforeMidnight, contains('2026-08-31'));
    expect(beforeMidnight, contains('当前季节：夏季'));
    expect(afterMidnight, contains('2026-09-01'));
    expect(afterMidnight, contains('当前季节：秋季'));
    expect(afterMidnight, contains('当前时段：深夜'));
  });
}
