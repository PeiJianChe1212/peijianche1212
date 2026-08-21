import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/user_profile.dart';

void main() {
  group('UserProfile compatibility', () {
    test('loads legacy data without the public birthday field', () {
      final profile = UserProfile.fromJson({
        'nickname': '小裴',
        'region': '上海',
        'birthday': '2000-01-02',
        'identity': '旧人设',
      });

      expect(profile.nickname, '小裴');
      expect(profile.region, '上海');
      expect(profile.profileBirthday, isEmpty);
      expect(profile.birthday, '2000-01-02');
      expect(profile.identity, '旧人设');
    });

    test('accepts legacy location as a region fallback', () {
      final profile = UserProfile.fromJson({'location': '杭州'});

      expect(profile.region, '杭州');
    });

    test('round-trips public birthday independently from persona birthday', () {
      const profile = UserProfile(
        profileBirthday: '1998-08-21',
        birthday: '秋天',
      );
      final restored = UserProfile.fromJson(profile.toJson());

      expect(restored.profileBirthday, '1998-08-21');
      expect(restored.birthday, '秋天');
      expect(restored.toPromptSection(), contains('生日：秋天'));
      expect(restored.toPromptSection(), isNot(contains('1998-08-21')));
    });
  });
}
