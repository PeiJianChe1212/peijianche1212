import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_user_profile.dart';

void main() {
  test('旧七字段在无综合描述时安全合并', () {
    final profile = CharacterUserProfile.fromJson({
      'userName': '念念',
      'age': '25',
      'identity': '独立媒体人',
      'relationship': '恋人',
      'callName': '小念头',
      'world': '现代都市',
      'description': '希望他记得我喜欢猫',
    }, characterId: 'role_a');

    expect(profile.gender, isEmpty);
    expect(profile.effectiveDescription, contains('年龄：25'));
    expect(profile.effectiveDescription, contains('角色对我的称呼：小念头'));
    expect(profile.effectiveDescription, contains('所在世界：现代都市'));
    expect(profile.effectiveDescription, contains('补充：希望他记得我喜欢猫'));
  });

  test('新 description 优先，保存时仍保留旧字段', () {
    const profile = CharacterUserProfile(
      characterId: 'role_a',
      userName: '念念',
      gender: '女',
      age: '25',
      identity: '旧身份',
      description: '旧补充',
      personaDescription: '这是新的统一设定描述。',
    );

    expect(profile.effectiveDescription, '这是新的统一设定描述。');
    expect(profile.toJson()['age'], '25');
    expect(profile.toJson()['identity'], '旧身份');
    expect(profile.toJson()['gender'], '女');
    expect(profile.toJson()['description'], '旧补充');
  });
}
