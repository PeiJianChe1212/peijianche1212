import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/chat_image_scene_intent.dart';
import 'package:peijianche_app/models/chat_message.dart';
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

  test('Chat explicit character request requires the current character', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看你',
      characterId: 'role-a',
    );
    expect(result.subject, ChatImageSubject.character);
    expect(result.characterPresence, ChatCharacterPresence.required);
    expect(result.requiredCharacterIds, ['role-a']);
  });

  test('Chat body detail keeps the character and requested focus', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看老公腹肌',
      characterId: 'role-a',
    );
    final prompt = ChatImageGenerationService.buildPrompt(
      intent: result,
      visualProfile: visualProfile,
    );
    expect(result.subject, ChatImageSubject.characterDetail);
    expect(result.characterPresence, ChatCharacterPresence.required);
    expect(prompt, contains('腹肌'));
    expect(prompt, contains('角色本人必须出现'));
    expect(prompt, isNot(contains('画面中不出现人物')));
    expect(prompt, contains('匀称'));
    expect(prompt, contains('蓝色'));
  });

  test('Chat hand and earring requests are character details', () {
    for (final request in ['看看你的手', '给我看看新耳钉']) {
      final result = chatIntent.resolve(
        userRequest: request,
        characterId: 'role-a',
      );
      expect(result.subject, ChatImageSubject.characterDetail);
      expect(result.characterPresence, ChatCharacterPresence.required);
    }
  });

  test('Chat character object request preserves both subjects', () {
    for (final request in ['你拿着花给我看看', '把花放在腹肌边上给我看看']) {
      final result = chatIntent.resolve(
        userRequest: request,
        characterId: 'role-a',
      );
      final prompt = ChatImageGenerationService.buildPrompt(
        intent: result,
        visualProfile: visualProfile,
      );
      expect(result.subject, ChatImageSubject.characterObject);
      expect(result.characterPresence, ChatCharacterPresence.required);
      expect(prompt, contains('花'));
      expect(prompt, contains('角色本人和指定物品必须同时清晰出现'));
      expect(prompt, isNot(contains('画面中不出现人物')));
    }
  });

  test('Chat room request remains person-free', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看你房间',
      characterId: 'role-a',
    );
    expect(result.subject, ChatImageSubject.environment);
    expect(result.characterPresence, ChatCharacterPresence.none);
  });

  test('Chat pure flower request remains person-free', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看那束花',
      characterId: 'role-a',
    );
    expect(result.subject, ChatImageSubject.object);
    expect(result.characterPresence, ChatCharacterPresence.none);
  });

  test('Chat follow-up resolves outfit from recent conversation', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看',
      characterId: 'role-a',
      recentMessages: [
        ChatMessage(role: 'assistant', content: '我刚换了件新衬衫。'),
        ChatMessage(role: 'user', content: '给我看看'),
      ],
    );
    expect(result.subject, ChatImageSubject.outfit);
    expect(result.characterPresence, ChatCharacterPresence.required);
  });

  test('Chat follow-up resolves environment from recent conversation', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看',
      characterId: 'role-a',
      recentMessages: [
        ChatMessage(role: 'assistant', content: '窗外下雪了。'),
        ChatMessage(role: 'user', content: '给我看看'),
      ],
    );
    expect(result.subject, ChatImageSubject.environment);
    expect(result.characterPresence, ChatCharacterPresence.none);
  });

  test('contextual character details retain person and exact visual focus', () {
    for (final scenario in const [
      ('最近腹肌练得还不错。', '给我看看嘛', '腹肌'),
      ('新打了个耳钉。', '看看', '耳钉'),
      ('手上沾了点颜料。', '让我看看', '手上'),
    ]) {
      final result = chatIntent.resolve(
        userRequest: scenario.$2,
        characterId: 'role-a',
        recentMessages: [ChatMessage(role: 'assistant', content: scenario.$1)],
      );
      final prompt = ChatImageGenerationService.buildPrompt(
        intent: result,
        visualProfile: visualProfile,
      );
      expect(result.subject, ChatImageSubject.characterDetail);
      expect(result.characterPresence, ChatCharacterPresence.required);
      expect(result.visualFocus, contains(scenario.$3));
      expect(prompt, contains(scenario.$3));
      expect(prompt, isNot(contains('画面中不出现人物')));
    }
  });

  test('contextual character state can require the character', () {
    final result = chatIntent.resolve(
      userRequest: '让我看看',
      characterId: 'role-a',
      recentMessages: [ChatMessage(role: 'assistant', content: '我现在这样挺狼狈的。')],
    );
    expect(result.subject, ChatImageSubject.character);
    expect(result.characterPresence, ChatCharacterPresence.required);
  });

  test('contextual character-object retains person object and relation', () {
    for (final context in ['我正拿着你送的花。', '猫现在趴我怀里。']) {
      final result = chatIntent.resolve(
        userRequest: '给我看看嘛',
        characterId: 'role-a',
        recentMessages: [ChatMessage(role: 'assistant', content: context)],
      );
      final prompt = ChatImageGenerationService.buildPrompt(
        intent: result,
        visualProfile: visualProfile,
      );
      expect(result.subject, ChatImageSubject.characterObject);
      expect(result.characterPresence, ChatCharacterPresence.required);
      expect(result.visualFocus, contains(context.replaceAll('。', '')));
      expect(prompt, contains('角色本人和指定物品必须同时清晰出现'));
      expect(prompt, isNot(contains('画面中不出现人物')));
    }
  });

  test(
    'follow-up particles preserve outfit environment and object behavior',
    () {
      for (final scenario in const [
        ('我刚换了件新衬衫。', ChatImageSubject.outfit, ChatCharacterPresence.required),
        ('窗外下雪了。', ChatImageSubject.environment, ChatCharacterPresence.none),
        ('我买了束花。', ChatImageSubject.object, ChatCharacterPresence.none),
      ]) {
        final result = chatIntent.resolve(
          userRequest: '给我看看嘛',
          characterId: 'role-a',
          recentMessages: [
            ChatMessage(role: 'assistant', content: scenario.$1),
          ],
        );
        expect(result.subject, scenario.$2);
        expect(result.characterPresence, scenario.$3);
      }
    },
  );

  test('nearest effective visual context wins over older context', () {
    final detail = chatIntent.resolve(
      userRequest: '给我看看嘛',
      characterId: 'role-a',
      recentMessages: [
        ChatMessage(role: 'assistant', content: '窗外下雪了。'),
        ChatMessage(role: 'assistant', content: '我最近腹肌练出来了。'),
      ],
    );
    expect(detail.subject, ChatImageSubject.characterDetail);
    expect(detail.visualFocus, contains('腹肌'));

    final outfit = chatIntent.resolve(
      userRequest: '看看',
      characterId: 'role-a',
      recentMessages: [
        ChatMessage(role: 'assistant', content: '我买了束花。'),
        ChatMessage(role: 'assistant', content: '我刚换了件衬衫。'),
      ],
    );
    expect(outfit.subject, ChatImageSubject.outfit);
    expect(outfit.characterPresence, ChatCharacterPresence.required);
  });

  test('explicit visual subject overrides contextual environment', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看你的手',
      characterId: 'role-a',
      recentMessages: [ChatMessage(role: 'assistant', content: '窗外下雪了。')],
    );
    expect(result.subject, ChatImageSubject.characterDetail);
    expect(result.characterPresence, ChatCharacterPresence.required);
  });

  test('particle follow-up without visual context remains ambient', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看嘛',
      characterId: 'role-a',
      recentMessages: [ChatMessage(role: 'assistant', content: '今天过得还不错。')],
    );
    expect(result.subject, ChatImageSubject.ambient);
    expect(result.characterPresence, ChatCharacterPresence.none);
  });

  test('Chat follow-up prefers the nearest relevant context', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看',
      characterId: 'role-a',
      recentMessages: [
        ChatMessage(role: 'assistant', content: '我买了一束花。'),
        ChatMessage(role: 'user', content: '外面怎么样？'),
        ChatMessage(role: 'assistant', content: '窗外下雪了。'),
        ChatMessage(role: 'user', content: '给我看看'),
      ],
    );
    expect(result.subject, ChatImageSubject.environment);
    expect(result.visualFocus, contains('窗外下雪了'));
  });

  test('Chat subjectless follow-up remains ambient and person-free', () {
    final result = chatIntent.resolve(
      userRequest: '给我看看',
      characterId: 'role-a',
      recentMessages: [
        ChatMessage(role: 'assistant', content: '今天过得还不错。'),
        ChatMessage(role: 'user', content: '给我看看'),
      ],
    );
    expect(result.subject, ChatImageSubject.ambient);
    expect(result.characterPresence, ChatCharacterPresence.none);
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
