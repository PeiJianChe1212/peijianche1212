import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_archive.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/services/character_prompt_preview_service.dart';

void main() {
  test('preview uses new structured data and omits empty fields', () {
    final preview = CharacterPromptPreviewService.compose(
      settings: CharacterSettings.defaults().copyWith(
        characterName: '旧名字',
        coreProfile: '旧人设',
      ),
      profile: const CharacterProfile(
        characterId: 'preview',
        name: '新版名字',
        age: '28',
        overallAppearance: '银白短发',
        personalityTags: '克制',
        personalityDescription: '对亲近的人温柔',
        upbringing: '在海边长大',
        relationship: '恋人',
      ),
      archive: const CharacterArchive(
        characterId: 'preview',
        values: {
          'likes': '黑咖啡',
          'importantPrinciples': '守信',
          'languageHabits': '简短自然',
        },
      ),
      userProfilePrompt: '用户称呼：念念',
      memory: '【已确认记忆】\n- 喜欢雨天',
    );

    expect(preview, contains('【角色资料】'));
    expect(preview, contains('角色名称：新版名字'));
    expect(preview, contains('【外貌设定】'));
    expect(preview, contains('性格描述：对亲近的人温柔'));
    expect(preview, contains('成长经历：在海边长大'));
    expect(preview, contains('喜好与习惯：喜欢：黑咖啡'));
    expect(preview, contains('语言习惯：简短自然'));
    expect(preview, contains('用户称呼：念念'));
    expect(preview, contains('喜欢雨天'));
    expect(preview, isNot(contains('性别：')));
    expect(preview, isNot(contains('旧人设')));
  });
}
