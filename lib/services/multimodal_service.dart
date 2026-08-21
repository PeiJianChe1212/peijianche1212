import 'package:http/http.dart' as http;

import '../ai/providers/volcengine_multimodal_provider.dart';
import '../models/character_settings.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'context_builder.dart';
import 'vision_router.dart';
import 'vision_settings_storage_service.dart';

class ImageUnderstandingResult {
  const ImageUnderstandingResult({required this.description});

  final String description;
}

class MultimodalService {
  MultimodalService({
    ApiSettingsStorageService? storage,
    VisionSettingsStorageService? visionStorage,
    VisionRouter? visionRouter,
    http.Client? client,
  }) : _storage = storage ?? ApiSettingsStorageService(),
       _visionStorage = visionStorage ?? VisionSettingsStorageService(),
       _visionRouter = visionRouter ?? VisionRouter(client: client),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final ApiSettingsStorageService _storage;
  final VisionSettingsStorageService _visionStorage;
  final VisionRouter _visionRouter;
  final http.Client _client;
  final bool _ownsClient;

  Future<ImageUnderstandingResult> understandForChat({
    required String imagePath,
    String userText = '',
    CharacterSettings? characterSettings,
  }) async {
    final apiSettings = await _storage.loadSettings();
    final visionSettings = await _visionStorage.loadSettings();
    final settings =
        characterSettings ??
        await CharacterSettingsStorageService().loadSettings();
    final provider = _visionRouter.resolve(
      visionSettings: visionSettings,
      chatSettings: apiSettings,
    );

    final description = await provider.understandImagePath(
      imagePath: imagePath,
      systemPrompt: ContextBuilder.build(
        task: ContextTask.multimodal,
        settings: settings,
        taskRules: '''
你是 PeiLink 的视觉理解模块，只负责把图片中可靠可见的信息整理给角色聊天模型。
不要扮演角色，不要直接回复用户，不要编造图片之外的身份、地点、关系或情绪。
优先提取主体、动作、环境、文字、食物或物品、画面氛围，以及最适合继续聊天的细节。
输出自然、简洁的中文描述，控制在 80 至 260 字。
''',
      ),
      instruction: userText.trim().isEmpty
          ? '请描述这张图片，并指出其中适合继续聊天的细节。'
          : '用户随图片说：“${userText.trim()}”。请结合这句话描述图片，并指出适合角色回应的重点。',
    );

    return ImageUnderstandingResult(description: description.trim());
  }

  Future<String> classifyImageRequest({
    required String userText,
    required String recentConversation,
    CharacterSettings? characterSettings,
  }) async {
    final apiSettings = await _storage.loadSettings();
    final settings =
        characterSettings ??
        await CharacterSettingsStorageService().loadSettings();
    final provider = VolcengineMultimodalProvider(
      settings: apiSettings,
      client: _client,
    );

    return provider.completeText(
      systemPrompt: ContextBuilder.build(
        task: ContextTask.imageRouting,
        settings: settings,
        taskRules: r'''
你是 PeiLink 的图片请求路由器，只判断用户此刻是否要求角色真正发送或生成一张图片。

判定为 generate_image：
- 用户要求拍照、发照片、发图、画一张或生成图片；
- 用户说“给我看看你今天吃了什么”“让我看看你现在那边”；
- 在上一轮角色说会拍或会发之后，用户追问“照片呢”“图呢”。

判定为 normal_chat：
- 用户只是询问角色在做什么或吃了什么；
- 用户讨论图片好不好看、询问拍照技巧；
- 用户说“看看”但语境明显不是索要图片。

只返回一个 JSON 对象，不要 Markdown，不要解释：
{"intent":"generate_image或normal_chat","reason":"不超过30字"}
''',
        recentConversation: recentConversation,
      ),
      instruction: '用户最新消息：$userText',
      maxTokens: 120,
    );
  }

  @Deprecated(
    'Use a scene Intent with PeiLinkImagePromptBuilder; image requests must use ImageGenerationService.',
  )
  Future<String> buildImagePrompt({
    required String scene,
    required String visualStyle,
    String purpose = 'Echo 生活配图',
    CharacterSettings? characterSettings,
  }) async {
    final apiSettings = await _storage.loadSettings();
    final settings =
        characterSettings ??
        await CharacterSettingsStorageService().loadSettings();
    final provider = VolcengineMultimodalProvider(
      settings: apiSettings,
      client: _client,
    );

    return provider.completeText(
      systemPrompt: ContextBuilder.build(
        task: ContextTask.image,
        settings: settings,
        extensionProfile: visualStyle,
        taskRules: '''
你是 PeiLink 的图片描述整理模块。你的工作不是画图，而是把已知生活事件整理成可直接交给图片模型的中文自然语言提示词。
图片应像角色用手机随手拍下的真实生活照片，不是海报、宣传图或艺术展作品。
不要输出标题、解释、Markdown、参数表，不要擅自加入文字排版或水印。
''',
        sourceFacts:
            '''
图片用途：$purpose
生活场景：$scene
''',
      ),
      instruction: '输出一段完整、清楚、不过度堆砌的生图描述。写明主体、环境、光线、构图和真实手机摄影感，并以“无文字、无水印”结尾。',
      maxTokens: 500,
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
