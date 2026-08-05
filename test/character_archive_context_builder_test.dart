import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/context_builder/character_archive_context_builder.dart';
import 'package:peijianche_app/models/character_archive.dart';

void main() {
  const archive = CharacterArchive(
    characterId: 'pei',
    values: {
      'whenUnhappy': '先安静陪伴',
      'dailyState': '工作日很忙',
      'languageHabits': '句子简短',
      'collections': '旧唱片',
      'childhoodExperience': '在海边长大',
      'moneyView': '重视安全感，不铺张',
      'era': '现代',
    },
  );

  test('疲惫聊天只选择情感、日常和语言分类', () {
    final prompt = const CharacterArchiveContextBuilder().build(
      archive: archive,
      latestUserMessage: '今天工作好累。',
    );

    expect(prompt, contains('先安静陪伴'));
    expect(prompt, contains('工作日很忙'));
    expect(prompt, contains('句子简短'));
    expect(prompt, isNot(contains('旧唱片')));
    expect(prompt, isNot(contains('在海边长大')));
    expect(prompt, isNot(contains('现代')));
  });

  test('童年问题只选择成长经历', () {
    final prompt = const CharacterArchiveContextBuilder().build(
      archive: archive,
      latestUserMessage: '你小时候是什么样？',
    );

    expect(prompt, contains('在海边长大'));
    expect(prompt, isNot(contains('工作日很忙')));
    expect(prompt, isNot(contains('重视安全感')));
  });

  test('金钱问题选择价值观', () {
    final prompt = const CharacterArchiveContextBuilder().build(
      archive: archive,
      latestUserMessage: '你怎么看钱？',
    );

    expect(prompt, contains('重视安全感，不铺张'));
    expect(prompt, isNot(contains('在海边长大')));
  });

  test('长档案被限制在预算内且不是 JSON', () {
    final prompt = const CharacterArchiveContextBuilder(maxCharacters: 500)
        .build(
          archive: CharacterArchive(
            characterId: 'long',
            values: {'whenUnhappy': '很长的资料' * 1000},
          ),
          latestUserMessage: '今天很累',
        );

    expect(prompt.length, lessThanOrEqualTo(500));
    expect(prompt, isNot(contains('"whenUnhappy"')));
  });
}
