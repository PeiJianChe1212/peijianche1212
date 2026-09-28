import '../models/ai_character.dart';
import '../models/chat_image_scene_intent.dart';
import '../models/chat_message.dart';
import '../models/peilink_character_visual_profile.dart';
import '../models/peilink_visual_intent.dart';
import 'chat_image_intent_service.dart';
import 'chat_image_storage_service.dart';
import 'image_generation_service.dart';
import 'peilink_character_visual_profile_service.dart';
import 'peilink_image_prompt_builder.dart';

class ChatGeneratedImage {
  const ChatGeneratedImage({
    required this.imagePath,
    required this.internalPrompt,
  });

  final String imagePath;

  /// Transient provider input. Never persist this on a [ChatMessage].
  final String internalPrompt;
}

class ChatImageGenerationService {
  ChatImageGenerationService({
    ImageGenerationService? imageGenerationService,
    ChatImageStorageService? imageStorageService,
    PeiLinkCharacterVisualProfileService? visualProfileService,
  }) : _imageGenerationService =
           imageGenerationService ?? ImageGenerationService(),
       _imageStorageService =
           imageStorageService ?? const ChatImageStorageService(),
       _visualProfileService =
           visualProfileService ?? const PeiLinkCharacterVisualProfileService();

  final ImageGenerationService _imageGenerationService;
  final ChatImageStorageService _imageStorageService;
  final PeiLinkCharacterVisualProfileService _visualProfileService;
  static const ChatImageIntentService _intentService = ChatImageIntentService();

  Future<ChatGeneratedImage> generate({
    required String userRequest,
    required AiCharacter character,
    List<ChatMessage> recentMessages = const [],
  }) async {
    final intent = _intentService.resolve(
      userRequest: userRequest,
      characterId: character.id,
      recentMessages: recentMessages,
    );
    final visualProfile =
        intent.characterPresence == ChatCharacterPresence.required
        ? await _visualProfileService.loadForCharacter(character)
        : null;
    final prompt = buildPrompt(intent: intent, visualProfile: visualProfile);
    final targetDirectory = await _imageStorageService.imageDirectory();
    final imagePath = await _imageGenerationService.generateAndSave(
      prompt: prompt,
      targetDirectory: targetDirectory,
      negativePrompt: '文字、水印、二维码、海报排版、错误肢体、多余手指、人物五官崩坏',
    );
    return ChatGeneratedImage(imagePath: imagePath, internalPrompt: prompt);
  }

  static String buildPrompt({
    required ChatImageSceneIntent intent,
    PeiLinkCharacterVisualProfile? visualProfile,
  }) {
    final profiles = visualProfile == null
        ? const <String, PeiLinkCharacterVisualProfile>{}
        : {visualProfile.characterId: visualProfile};
    return PeiLinkImagePromptBuilder.build(
      intent: PeiLinkVisualIntent(
        subject: switch (intent.subject) {
          ChatImageSubject.object => PeiLinkVisualSubject.object,
          ChatImageSubject.environment => PeiLinkVisualSubject.environment,
          ChatImageSubject.selfie => PeiLinkVisualSubject.selfie,
          ChatImageSubject.outfit => PeiLinkVisualSubject.outfit,
          ChatImageSubject.character => PeiLinkVisualSubject.character,
          ChatImageSubject.characterDetail => PeiLinkVisualSubject.character,
          ChatImageSubject.characterObject => PeiLinkVisualSubject.character,
          ChatImageSubject.ambient => PeiLinkVisualSubject.other,
          ChatImageSubject.other => PeiLinkVisualSubject.other,
        },
        characterPresence:
            intent.characterPresence == ChatCharacterPresence.required
            ? PeiLinkCharacterPresence.required
            : PeiLinkCharacterPresence.none,
        visualFocus: intent.visualFocus,
        mood: intent.mood,
        requiredCharacterIds: intent.requiredCharacterIds,
        includeEyes: intent.characterPresence == ChatCharacterPresence.required,
        includeClothing:
            intent.characterPresence == ChatCharacterPresence.required,
        includeBodyProportions:
            intent.characterPresence == ChatCharacterPresence.required,
        compositionHint: switch (intent.subject) {
          ChatImageSubject.characterDetail =>
            '角色本人必须出现在画面中；用户指定的身体或外貌局部是主要视觉焦点，环境只作陪衬，不得用空房间、床、衣物或器材替代人物。采用自然、克制的生活摄影构图。',
          ChatImageSubject.characterObject =>
            '角色本人和指定物品必须同时清晰出现，准确表现用户要求的持有、佩戴、摆放或互动关系，不得退化为纯物品图。采用自然生活记录构图。',
          ChatImageSubject.character =>
            '角色本人必须作为清晰的主要视觉主体出现，不得用环境或物品替代；保持自然生活记录感，不做宣传写真。',
          _ => '',
        },
      ),
      context: PeiLinkVisualContext(characterProfiles: profiles),
    );
  }

  void dispose() {
    _imageGenerationService.dispose();
  }
}
