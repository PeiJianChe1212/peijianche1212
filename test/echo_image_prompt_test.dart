import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/echo_image_intent.dart';
import 'package:peijianche_app/models/echo_item.dart';
import 'package:peijianche_app/models/life_moment.dart';
import 'package:peijianche_app/services/echo_image_intent_service.dart';
import 'package:peijianche_app/services/echo_image_prompt.dart';

void main() {
  test('legacy single imagePath is promoted into current imagePaths', () {
    final item = EchoItem.fromJson({
      'id': 'legacy-image',
      'characterId': 'role',
      'content': '旧图片',
      'createdAt': '2026-08-21T00:00:00.000Z',
      'imagePath': '/legacy/echo.jpg',
    });
    expect(item.imagePath, '/legacy/echo.jpg');
    expect(item.imagePaths, ['/legacy/echo.jpg']);
  });
  const resolver = EchoImageIntentService();

  LifeMomentCandidate moment({
    String scene = '家里的桌边',
    required String event,
    String detail = '',
    String feeling = '平静',
  }) => LifeMomentCandidate(
    id: 'moment-1',
    decisionId: 'decision-1',
    scene: scene,
    event: event,
    detail: detail,
    feeling: feeling,
    shareHook: '想随手记录',
    occurredAt: DateTime(2026),
  );

  EchoImageIntent intent(LifeMomentCandidate value) => resolver.resolve(
    moment: value,
    characterId: 'character-1',
    suggestedByMoment: true,
  );

  test('coffee daily life focuses on drink and table without a character', () {
    final result = intent(moment(event: '喝了一杯咖啡', detail: '咖啡有点苦'));
    expect(result.subjectType, EchoImageSubjectType.food);
    expect(result.characterPresence, EchoCharacterPresence.none);
    expect(result.visualFocus, contains('食物或饮品'));
  });

  test('work material focuses on files and computer, not a portrait', () {
    final result = intent(moment(event: '整理工作资料', detail: '文件被手机压在桌角'));
    expect(result.subjectType, EchoImageSubjectType.workStudy);
    expect(result.characterPresence, EchoCharacterPresence.none);
  });

  test('weather feeling defaults to the environment without a character', () {
    final result = intent(
      moment(scene: '窗边', event: '看见窗外下雨', feeling: '有点发呆'),
    );
    expect(result.subjectType, EchoImageSubjectType.environment);
    expect(result.characterPresence, EchoCharacterPresence.none);
  });

  test('selfie requires a character and stable visual identity', () {
    final result = intent(moment(event: '对着镜子拍了一张自拍'));
    expect(result.subjectType, EchoImageSubjectType.selfie);
    expect(result.characterPresence, EchoCharacterPresence.required);
    expect(result.requiredCharacterIds, ['character-1']);
  });

  test('outfit display requires a character as the visual subject', () {
    final result = intent(moment(event: '记录今天的穿搭展示'));
    expect(result.subjectType, EchoImageSubjectType.outfit);
    expect(result.characterPresence, EchoCharacterPresence.required);
  });

  test('an ordinary beach moment does not force a face or person', () {
    final result = intent(moment(scene: '海边', event: '吹了一下午风'));
    expect(result.subjectType, EchoImageSubjectType.scenery);
    expect(result.characterPresence, EchoCharacterPresence.none);
  });

  test('no-person prompt excludes every character profile field', () {
    final result = intent(moment(event: '桌上的咖啡有点苦'));
    final prompt = EchoImagePrompt.build(
      intent: result,
      characterProfile: const CharacterProfile(
        characterId: 'character-1',
        overallAppearance: '银发蓝眼',
        backgroundStory: '秘密背景故事',
        personalityDescription: '安静克制',
      ),
    );
    expect(prompt, contains('画面中不出现人物'));
    expect(prompt, isNot(contains('银发蓝眼')));
    expect(prompt, isNot(contains('秘密背景故事')));
    expect(prompt, isNot(contains('安静克制')));
  });

  test('person prompt injects only necessary visual facts', () {
    final result = intent(moment(event: '拍了一张自拍'));
    final prompt = EchoImagePrompt.build(
      intent: result,
      characterProfile: const CharacterProfile(
        characterId: 'character-1',
        gender: '男',
        age: '二十多岁',
        overallAppearance: '轮廓清晰',
        hairColor: '银白色',
        eyes: '蓝色',
        clothingStyle: '简洁日常',
        backgroundStory: '不能进入图片的背景故事',
        worldview: '不能进入图片的世界观',
      ),
    );
    expect(prompt, contains('银白色'));
    expect(prompt, contains('蓝色'));
    expect(prompt, isNot(contains('简洁日常')));
    expect(prompt, isNot(contains('不能进入图片的背景故事')));
    expect(prompt, isNot(contains('不能进入图片的世界观')));
  });

  test('outfit prompt may use existing clothing style', () {
    final result = intent(moment(event: '今天的穿搭展示'));
    final prompt = EchoImagePrompt.build(
      intent: result,
      characterProfile: const CharacterProfile(
        characterId: 'character-1',
        clothingStyle: '简洁的深色日常服装',
      ),
    );
    expect(prompt, contains('简洁的深色日常服装'));
  });

  test('short Echo copy does not affect a Moment-based image prompt', () {
    final result = intent(moment(scene: '商店柜台', event: '看见一只颜色很好看的杯子'));
    final prompt = EchoImagePrompt.build(intent: result);
    expect(result.shouldGenerateImage, isTrue);
    expect(prompt, contains('事实依据'));
    expect(prompt, contains('半写实 2.5D'));
  });

  test('Moment may keep an Echo text-only without forcing an image', () {
    final result = resolver.resolve(
      moment: moment(event: '桌上放着一杯咖啡'),
      characterId: 'character-1',
      suggestedByMoment: false,
    );
    expect(result.shouldGenerateImage, isFalse);
    expect(EchoImagePrompt.build(intent: result), isEmpty);
  });

  test('image failure remains an image state and does not require a retry', () {
    expect(
      echoImageStatus(
        prompt: 'valid prompt',
        imagePath: '',
        generationFailed: true,
      ),
      'failed',
    );
  });

  test('legacy image fields survive without migration or rewriting', () {
    final item = EchoItem.fromJson({
      'id': 'legacy-echo',
      'characterId': 'character-1',
      'content': '旧动态',
      'createdAt': DateTime(2025).toIso8601String(),
      'sourceType': 'aiGenerated',
      'imagePaths': ['/old/image.jpg'],
      'imagePrompt': 'old prompt',
      'imageStatus': 'generated',
      'imagePath': '/old/image.jpg',
    });
    expect(item.imagePaths, ['/old/image.jpg']);
    expect(item.imagePrompt, 'old prompt');
    expect(item.imageStatus, 'generated');
    expect(item.imagePath, '/old/image.jpg');
  });
}
