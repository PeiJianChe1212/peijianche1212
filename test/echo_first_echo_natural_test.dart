import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/echo_daily_life.dart';
import 'package:peijianche_app/models/echo_item.dart';
import 'package:peijianche_app/services/echo_daily_life_service.dart';

/// Focused coverage for the "first Echo must not be an onboarding template"
/// fix. Only the first Echo generation path is exercised here.
void main() {
  const service = EchoDailyLifeService();

  // The high-frequency onboarding clichés reported on device.
  const bannedPhrases = [
    '第一次来这里',
    '新的地方',
    '留个位置',
    '痕迹',
    '以后想到什么就记一点',
    '其他的以后慢慢说',
    '接下来的日子再慢慢补上',
    '先写下一小句',
    '落个脚',
    '这一刻开始',
  ];

  AiCharacter character(String id, {String persona = ''}) => AiCharacter(
    id: id,
    characterName: id,
    remark: '',
    createdAt: DateTime.utc(2026, 8, 21, 9, 30),
    persona: persona,
  );

  CharacterProfile profile({
    String occupation = '',
    String personalityTags = '',
    String location = '',
  }) => CharacterProfile(
    characterId: 'x',
    occupation: occupation,
    personalityTags: personalityTags,
    location: location,
  );

  List<EchoDailyLife> initialSamples(
    AiCharacter owner, {
    CharacterProfile? lifeProfile,
    DateTime? at,
  }) => [
    for (var variation = 0; variation < 16; variation++)
      service.create(
        character: owner,
        at: at ?? DateTime.utc(2026, 8, 21, 9, 30),
        profile: lifeProfile,
        initial: true,
        variation: variation,
      ),
  ];

  test('first Echo never falls back to the onboarding clichés', () {
    for (final id in ['alpha', 'beta', 'gamma', 'delta', 'epsilon']) {
      for (final sample in initialSamples(character(id))) {
        for (final phrase in bannedPhrases) {
          expect(
            sample.content.contains(phrase),
            isFalse,
            reason: '$id first Echo must not contain "$phrase": '
                '${sample.content}',
          );
        }
      }
    }
  });

  test('first Echo keeps the arrival marker for UI, state and statistics', () {
    final sample = service.create(
      character: character('alpha'),
      at: DateTime.utc(2026, 8, 21, 9, 30),
      initial: true,
    );
    expect(sample.kind, EchoDailyLifeKind.arrival);
    expect(sample.lifeType, EchoLifeType.arrival);
    expect(sample.sourceEvent, 'character_arrival');
    expect(sample.summary, '初次来到 PeiLink');
    expect(sample.content.trim(), isNotEmpty);
  });

  test('first Echo is not forced to open with a time-of-day lead', () {
    const leads = ['今天上午', '今天下午', '今天晚上', '今晚', '夜里', '夜还很深'];
    for (final hour in [5, 9, 12, 17, 20, 23]) {
      for (final sample in initialSamples(
        character('alpha'),
        at: DateTime.utc(2026, 8, 21, hour, 0),
      )) {
        for (final lead in leads) {
          expect(
            sample.content.startsWith(lead),
            isFalse,
            reason: 'hour $hour: ${sample.content}',
          );
        }
      }
    }
  });

  test('first Echo still reads character profile context', () {
    final samples = initialSamples(
      character('reader'),
      lifeProfile: profile(
        occupation: '图书编辑',
        personalityTags: '安静、专注',
        location: '杭州',
      ),
    );
    final joined = samples.map((item) => item.content).join('\n');
    // Occupation and interest detection drive the pool, so profile facts must
    // reach the first Echo even though the arrival marker is kept.
    expect(joined.contains('图书编辑') || joined.contains('阅读'), isTrue);
    expect(samples.map((item) => item.content).toSet().length, greaterThan(1));
  });

  test('different characters do not share one identical first Echo', () {
    final contents = [
      for (final id in ['alpha', 'beta', 'gamma', 'delta', 'epsilon'])
        service.create(
          character: character(id),
          at: DateTime.utc(2026, 8, 21, 9, 30),
          initial: true,
        ).content,
    ];
    expect(contents.toSet().length, greaterThan(1));
  });

  test('ordinary Echo generation is unchanged', () {
    final sample = service.create(
      character: character('alpha'),
      at: DateTime.utc(2026, 8, 21, 9, 30),
    );
    expect(sample.kind, isNot(EchoDailyLifeKind.arrival));
    expect(sample.summary, isNot('初次来到 PeiLink'));
    expect(sample.content.trim(), isNotEmpty);

    // Recent-summary exclusion still applies to ordinary Echoes.
    const excluded = ['记录普通时刻', '收尾日常事务'];
    final filtered = service.create(
      character: character('alpha'),
      at: DateTime.utc(2026, 8, 21, 9, 30),
      excludedSummaries: excluded,
    );
    expect(excluded.contains(filtered.summary), isFalse);
  });
}
