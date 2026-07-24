import '../models/chat_message.dart';
import '../models/character_settings.dart';
import 'chat_image_storage_service.dart';
import 'image_generation_service.dart';
import 'multimodal_service.dart';

class ChatGeneratedImage {
  const ChatGeneratedImage({
    required this.imagePath,
    required this.prompt,
  });

  final String imagePath;
  final String prompt;
}

class ChatImageGenerationService {
  ChatImageGenerationService({
    MultimodalService? multimodalService,
    ImageGenerationService? imageGenerationService,
    ChatImageStorageService? imageStorageService,
  }) : _multimodalService = multimodalService ?? MultimodalService(),
       _imageGenerationService =
           imageGenerationService ?? ImageGenerationService(),
       _imageStorageService =
           imageStorageService ?? const ChatImageStorageService();

  final MultimodalService _multimodalService;
  final ImageGenerationService _imageGenerationService;
  final ChatImageStorageService _imageStorageService;

  Future<ChatGeneratedImage> generate({
    required String userRequest,
    required CharacterSettings characterSettings,
    List<ChatMessage> recentMessages = const [],
  }) async {
    final scene = _buildScene(userRequest, recentMessages);
    final prompt = await _multimodalService.buildImagePrompt(
      scene: scene,
      purpose: '聊天中由${characterSettings.characterName}发给用户的图片',
      visualStyle: _buildVisualStyle(characterSettings),
    );
    final targetDirectory = await _imageStorageService.imageDirectory();
    final imagePath = await _imageGenerationService.generateAndSave(
      prompt: prompt,
      targetDirectory: targetDirectory,
      negativePrompt: '文字、水印、二维码、海报排版、错误肢体、多余手指、人物五官崩坏',
    );
    return ChatGeneratedImage(imagePath: imagePath, prompt: prompt);
  }

  String _buildScene(String userRequest, List<ChatMessage> messages) {
    final visible = messages
        .where((message) =>
            message.role == 'user' || message.role == 'assistant')
        .toList();
    final recent = visible.length > 8
        ? visible.sublist(visible.length - 8)
        : visible;
    final context = recent.map((message) {
      final speaker = message.role == 'user' ? '用户' : '角色';
      final content = message.type == MessageType.image
          ? '[图片] ${message.content}'
          : message.content;
      return '$speaker：$content';
    }).join('\n');

    return '''
用户当前要求：$userRequest
最近对话背景：
$context

请根据最近对话补全用户省略的信息。例如用户追问“照片呢”，应从上一轮对话判断要拍什么。不要把“角色说已经发图”的文字描述当成真实图片。
''';
  }

  String _buildVisualStyle(CharacterSettings settings) {
    return '''
角色：${settings.characterName}
角色简介：${settings.introduction}
人物核心设定：${settings.coreProfile}
图片应符合角色自己的审美和当前请求。若用户没有明确要求人物出镜，优先生成环境、物品、食物、背影或第一人称随手拍，避免硬塞人物正脸。若需要角色本人出镜，保持成年感、自然姿态和稳定外貌，不做海报，不加文字。
''';
  }

  void dispose() {
    _multimodalService.dispose();
    _imageGenerationService.dispose();
  }
}
