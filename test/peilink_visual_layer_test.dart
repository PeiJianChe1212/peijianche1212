import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/chat_image_scene_intent.dart';
import 'package:peijianche_app/models/echo_image_intent.dart';
import 'package:peijianche_app/models/peilink_character_visual_profile.dart';
import 'package:peijianche_app/models/peilink_visual_intent.dart';
import 'package:peijianche_app/services/chat_image_generation_service.dart';
import 'package:peijianche_app/services/chat_image_intent_service.dart';
import 'package:peijianche_app/services/echo_image_prompt.dart';
import 'package:peijianche_app/services/peilink_image_prompt_builder.dart';

void main() {
  const chatIntent = ChatImageIntentService();
  const profile = CharacterProfile(
    characterId: 'role-a',
    gender: '男',
    age: '二十多岁',
    height: '高挑',
    bodyType: '匀称',
    overallAppearance: '银白短发，轮廓清晰',
    hairColor: '银白色',
    eyes: '蓝色',
    clothingStyle: '简洁深色日常服装',
    specialMarks: '左眼下浅痣',
    backgroundStory: '不应进入视觉资料',
    personalityDescription: '也不应进入视觉资料',
  );
  final visualProfile = PeiLinkCharacterVisualProfile.fromProfile(profile);

  test('Chat selfie requires the current character', () {
    final result = chatIntent.resolve(
      userRequest: '自拍一张给我看看',
      characterId: 'role-a',
    );
    expect(result.subject, ChatImageSubject.selfie);
    expect(result.characterPresence, ChatCharacterPresence.required);
    expect(result.requiredCharacterIds, ['role-a']);
  });

  test('Chat desktop request stays person-free', () {
    final result = chatIntent.resolve(
      userRequest: '拍一下你桌面上现在看到的东西',
      characterId: 'role-a',
    );
    expect(result.subject, ChatImageSubject.object);
    expect(result.characterPresence, ChatCharacterPresence.none);
    expect(result.requiredCharacterIds, isEmpty);
  });

  test('Chat outfit requires character and clothing facts', () {
    final result = chatIntent.resolve(
      userRequest: '看看你今天穿什么',
      characterId: 'role-a',
    );
    final prompt = ChatImageGenerationService.buildPrompt(
      intent: result,
      visualProfile: visualProfile,
    );
    expect(result.subject, ChatImageSubject.outfit);
    expect(prompt, contains('简洁深色日常服装'));
  });

  test('Echo and Chat share exactly the same selected visual facts', () {
    const echoIntent = EchoImageIntent(
      shouldGenerateImage: true,
      subjectType: EchoImageSubjectType.selfie,
      characterPresence: EchoCharacterPresence.required,
      visualFocus: '角色本人自拍',
      mood: '轻松',
      requiredCharacterIds: ['role-a'],
    );
    final echoPrompt = EchoImagePrompt.build(
      intent: echoIntent,
      characterProfile: profile,
    );
    final chatPrompt = ChatImageGenerationService.buildPrompt(
      intent: const ChatImageSceneIntent(
        subject: ChatImageSubject.selfie,
        characterPresence: ChatCharacterPresence.required,
        visualFocus: '角色本人自拍',
        requiredCharacterIds: ['role-a'],
      ),
      visualProfile: visualProfile,
    );
    for (final fact in ['银白色', '银白短发', '蓝色', '左眼下浅痣']) {
      expect(echoPrompt, contains(fact));
      expect(chatPrompt, contains(fact));
    }
    expect(echoPrompt, isNot(contains('不应进入视觉资料')));
    expect(chatPrompt, isNot(contains('不应进入视觉资料')));
  });

  test('person-free prompts never inject character appearance', () {
    final prompt = ChatImageGenerationService.buildPrompt(
      intent: const ChatImageSceneIntent(
        subject: ChatImageSubject.object,
        characterPresence: ChatCharacterPresence.none,
        visualFocus: '桌上的杯子与文件',
      ),
      visualProfile: visualProfile,
    );
    expect(prompt, contains('画面中不出现人物'));
    expect(prompt, isNot(contains('银白色')));
  });

  test('multi-character prompts load only requiredCharacterIds', () {
    const other = PeiLinkCharacterVisualProfile(
      characterId: 'role-b',
      hairColor: '黑色',
    );
    final prompt = PeiLinkImagePromptBuilder.build(
      intent: const PeiLinkVisualIntent(
        subject: PeiLinkVisualSubject.group,
        characterPresence: PeiLinkCharacterPresence.required,
        visualFocus: '两名明确参与者的合照',
        requiredCharacterIds: ['role-a'],
        includeEyes: true,
      ),
      context: PeiLinkVisualContext(
        characterProfiles: {'role-a': visualProfile, 'role-b': other},
      ),
    );
    expect(prompt, contains('银白色'));
    expect(prompt, isNot(contains('黑色')));
  });

  test('the public default style is shared and avoids photoreal people', () {
    final prompt = PeiLinkImagePromptBuilder.build(
      intent: const PeiLinkVisualIntent(
        subject: PeiLinkVisualSubject.environment,
        characterPresence: PeiLinkCharacterPresence.none,
        visualFocus: '窗边的雨',
      ),
    );
    expect(prompt, contains(PeiLinkImagePromptBuilder.defaultStyle));
    expect(prompt, contains('避免真人摄影'));
    expect(prompt, contains('无文字、无水印'));
  });
}
