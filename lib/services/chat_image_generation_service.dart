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
  const ChatGeneratedImage({required this.imagePath, required this.prompt});

  final String imagePath;
  final String prompt;
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
    return ChatGeneratedImage(imagePath: imagePath, prompt: prompt);
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
          ChatImageSubject.other => PeiLinkVisualSubject.other,
        },
        characterPresence:
            intent.characterPresence == ChatCharacterPresence.required
            ? PeiLinkCharacterPresence.required
            : PeiLinkCharacterPresence.none,
        visualFocus: intent.visualFocus,
        mood: intent.mood,
        requiredCharacterIds: intent.requiredCharacterIds,
        includeEyes: intent.subject == ChatImageSubject.selfie,
        includeClothing: intent.subject == ChatImageSubject.outfit,
        includeBodyProportions: intent.subject == ChatImageSubject.outfit,
      ),
      context: PeiLinkVisualContext(characterProfiles: profiles),
    );
  }

  void dispose() {
    _imageGenerationService.dispose();
  }
}
