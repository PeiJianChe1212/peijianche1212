import 'package:http/http.dart' as http;

import '../ai/providers/volcengine_multimodal_provider.dart';
import 'api_settings_storage_service.dart';

class ImageUnderstandingResult {
  const ImageUnderstandingResult({required this.description});

  final String description;
}

class MultimodalService {
  MultimodalService({
    ApiSettingsStorageService? storage,
    http.Client? client,
  }) : _storage = storage ?? ApiSettingsStorageService(),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final ApiSettingsStorageService _storage;
  final http.Client _client;
  final bool _ownsClient;

  Future<ImageUnderstandingResult> understandForChat({
    required String imagePath,
    String userText = '',
  }) async {
    final settings = await _storage.loadSettings();
    final provider = VolcengineMultimodalProvider(
      settings: settings,
      client: _client,
    );

    final description = await provider.understandImage(
      imagePath: imagePath,
      systemPrompt: '''
你是 PeiLink 的视觉理解模块，只负责把图片中可靠可见的信息整理给角色聊天模型。
不要扮演角色，不要直接回复用户，不要编造图片之外的身份、地点、关系或情绪。
优先提取：主体、动作、环境、文字、食物/物品、画面氛围，以及用户最可能想聊的细节。
输出自然、简洁的中文描述，控制在 80 至 260 字。
''',
      instruction: userText.trim().isEmpty
          ? '请描述这张图片，并指出其中适合继续聊天的细节。'
          : '用户随图片说：“${userText.trim()}”。请结合这句话描述图片，并指出适合角色回应的重点。',
    );

    return ImageUnderstandingResult(description: description.trim());
  }


  Future<String> classifyImageRequest({
    required String userText,
    required String recentConversation,
  }) async {
    final settings = await _storage.loadSettings();
    final provider = VolcengineMultimodalProvider(
      settings: settings,
      client: _client,
    );

    return provider.completeText(
      systemPrompt: r'''
你是 PeiLink 的“图片请求路由器”，只判断用户此刻是否要求角色真正发送或生成一张图片。

判定为 generate_image：
- 用户要求拍照、发照片、发图、画一张、生成图片；
- 用户说“给我看看你今天吃了什么”“让我看看你现在那边”；
- 在上一轮角色说会拍或会发之后，用户追问“照片呢”“图呢”。

判定为 normal_chat：
- 用户只是问“你今天吃了什么”“你在干嘛”；
- 用户讨论某张图好不好看、询问拍照技巧；
- 用户说“看看”但语境明显不是索要图片。

只返回一个 JSON 对象，不要 Markdown，不要解释：
{"intent":"generate_image或normal_chat","reason":"不超过30字"}
''',
      instruction: '''
最近对话：
$recentConversation

用户最新消息：$userText
''',
      maxTokens: 120,
    );
  }

  Future<String> buildImagePrompt({
    required String scene,
    required String visualStyle,
    String purpose = 'Echo 生活配图',
  }) async {
    final settings = await _storage.loadSettings();
    final provider = VolcengineMultimodalProvider(
      settings: settings,
      client: _client,
    );

    return provider.completeText(
      systemPrompt: '''
你是 PeiLink 的图片描述整理模块。你的工作不是画图，而是把生活事件整理成一段可直接交给图片模型的中文自然语言提示词。
Echo 图片应像角色用手机随手拍下的真实生活照片，不是海报、宣传图或艺术展作品。
不要生成标题、解释、Markdown、参数表。不要擅自加入文字排版、水印或人物正脸。
''',
      instruction: '''
图片用途：$purpose
生活场景：$scene
角色摄影风格：$visualStyle

请输出一段完整、清楚、不过度堆砌词语的生图描述。应写明主体、环境、光线、构图和真实手机摄影感，并在结尾加入“无文字、无水印”。
''',
      maxTokens: 500,
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
