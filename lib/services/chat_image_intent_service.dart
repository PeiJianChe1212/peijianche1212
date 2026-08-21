import '../models/chat_image_scene_intent.dart';
import '../models/chat_message.dart';

class ChatImageIntentService {
  const ChatImageIntentService();

  ChatImageSceneIntent resolve({
    required String userRequest,
    required String characterId,
    List<ChatMessage> recentMessages = const [],
  }) {
    final request = userRequest.replaceAll(RegExp(r'\s+'), '');
    final context = _isFollowUp(request)
        ? _context(userRequest, recentMessages)
        : request;
    if (_containsAny(context, const [
      '自拍',
      '拍你自己',
      '看看你本人',
      '看看你的样子',
      '你长什么样',
      '你的照片',
    ])) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.selfie,
        characterPresence: ChatCharacterPresence.required,
        visualFocus: '角色本人自然自拍，回应用户当前查看请求。事实依据：$userRequest',
        requiredCharacterIds: [characterId],
      );
    }
    if (_containsAny(context, const ['穿搭', '穿什么', '衣服上身', '今天穿', '今日着装'])) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.outfit,
        characterPresence: ChatCharacterPresence.required,
        visualFocus: '角色当前穿搭的自然生活记录。事实依据：$userRequest',
        requiredCharacterIds: [characterId],
      );
    }
    if (_containsAny(context, const [
      '桌上',
      '桌面',
      '看到的东西',
      '手边',
      '这个东西',
      '物品',
      '吃的',
      '喝的',
    ])) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.object,
        characterPresence: ChatCharacterPresence.none,
        visualFocus: '角色视角下当前明确提到的桌面、物品、食物或饮品。事实依据：$userRequest',
      );
    }
    if (_containsAny(context, const ['窗外', '周围', '那边', '环境', '现场', '看到的景色'])) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.environment,
        characterPresence: ChatCharacterPresence.none,
        visualFocus: '角色视角下当前明确提到的环境或景色。事实依据：$userRequest',
      );
    }
    return ChatImageSceneIntent(
      subject: ChatImageSubject.other,
      characterPresence: ChatCharacterPresence.none,
      visualFocus: '用户明确要求查看的环境、物品或生活现场，优先第一视角无人画面。事实依据：$userRequest',
    );
  }

  String _context(String request, List<ChatMessage> messages) {
    final visible = messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .toList();
    final recent = visible.length > 4
        ? visible.sublist(visible.length - 4)
        : visible;
    return '${recent.map((item) => item.content).join('，')}，$request'
        .replaceAll(RegExp(r'\s+'), '');
  }

  bool _containsAny(String value, List<String> keywords) =>
      keywords.any(value.contains);

  bool _isFollowUp(String value) =>
      const {'照片呢', '图片呢', '图呢', '发来看看', '给我看看'}.contains(value);
}
