import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';

void main() {
  const forbidden = <String>[
    '裴简澈',
    '老裴',
    '林念念',
    '念念',
    '一只小狐念',
    '12月12日',
    '1月17日',
    '银白短发',
  ];

  test('CharacterSettings.defaults is fully neutral and empty', () {
    final defaults = CharacterSettings.defaults();
    final neutral = CharacterSettings.genericDefaults();
    final json = defaults.toJson().toString();

    expect(defaults.characterName, neutral.characterName);
    expect(defaults.userCallName, isEmpty);
    expect(defaults.remark, isEmpty);
    expect(defaults.relation, isEmpty);
    expect(defaults.birthday, isEmpty);
    expect(defaults.anniversary, isEmpty);
    expect(defaults.introduction, isEmpty);
    expect(defaults.coreProfile, isEmpty);
    expect(defaults.behaviorStyle, isEmpty);
    expect(defaults.forbiddenRules, isEmpty);
    expect(defaults.exampleDialogues, isEmpty);

    for (final term in forbidden) {
      expect(
        json,
        isNot(contains(term)),
        reason: 'unexpected private term: $term',
      );
    }
  });
}
