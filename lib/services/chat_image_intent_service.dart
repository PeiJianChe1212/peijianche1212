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
    final explicitIntent = _classify(
      value: request,
      evidence: userRequest,
      characterId: characterId,
    );
    if (explicitIntent != null) return explicitIntent;

    if (_isFollowUp(request)) {
      final contextualIntent = _resolveFromContext(recentMessages, characterId);
      if (contextualIntent != null) return contextualIntent;
      return ChatImageSceneIntent(
        subject: ChatImageSubject.ambient,
        characterPresence: ChatCharacterPresence.none,
        visualFocus: '模糊的生活分享请求，优先角色视角下的自然环境、物品或生活现场。事实依据：$userRequest',
      );
    }

    return ChatImageSceneIntent(
      subject: ChatImageSubject.ambient,
      characterPresence: ChatCharacterPresence.none,
      visualFocus: '未明确要求人物出镜的自然生活分享，优先第一视角环境、物品或生活现场。事实依据：$userRequest',
    );
  }

  ChatImageSceneIntent? _classify({
    required String value,
    required String evidence,
    required String characterId,
  }) {
    if (_isCharacterObjectRequest(value)) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.characterObject,
        characterPresence: ChatCharacterPresence.required,
        visualFocus:
            '角色本人和用户指定物品必须同时出现，完整保留二者的动作、位置与关系；不得退化为纯物品或环境图。事实依据：$evidence',
        requiredCharacterIds: [characterId],
      );
    }
    if (_containsAny(value, const [
      '穿搭',
      '穿什么',
      '衣服上身',
      '今天穿',
      '今日着装',
      '这身衣服',
      '那件衣服',
      '新衬衫',
      '换了件衬衫',
      '换上衣服',
    ])) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.outfit,
        characterPresence: ChatCharacterPresence.required,
        visualFocus: '角色本人必须出现，当前穿搭是主要视觉焦点，不得用衣物静物或环境代替人物。事实依据：$evidence',
        requiredCharacterIds: [characterId],
      );
    }
    if (_containsAny(value, const [
      '腹肌',
      '身材',
      '肩膀',
      '肩部',
      '手臂',
      '胳膊',
      '手上',
      '手部',
      '我的手',
      '你的手',
      '我的眼睛',
      '你的眼睛',
      '眼睛给我看',
      '耳钉',
      '耳环',
      '头发',
      '发型',
      '脸给我看',
      '侧脸',
      '身体线条',
      '外貌',
    ])) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.characterDetail,
        characterPresence: ChatCharacterPresence.required,
        visualFocus:
            '角色本人必须出现，用户指定的身体或外貌细节是主要视觉焦点；不得用床、衣物、器材或其他环境元素代替人物主体。事实依据：$evidence',
        requiredCharacterIds: [characterId],
      );
    }
    if (_isCharacterRequest(value)) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.character,
        characterPresence: ChatCharacterPresence.required,
        visualFocus: '角色本人必须作为主要视觉主体清晰出现，不得用环境或物品代替。事实依据：$evidence',
        requiredCharacterIds: [characterId],
      );
    }
    if (_containsAny(value, const [
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
        visualFocus: '角色本人自然自拍，回应用户当前查看请求。事实依据：$evidence',
        requiredCharacterIds: [characterId],
      );
    }
    if (_containsAny(value, const [
      '房间',
      '卧室',
      '办公室',
      '窗外',
      '周围',
      '那边',
      '环境',
      '现场',
      '看到的景色',
      '下雪',
    ])) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.environment,
        characterPresence: ChatCharacterPresence.none,
        visualFocus: '角色视角下当前明确提到的环境或景色。事实依据：$evidence',
      );
    }
    if (_containsAny(value, const [
      '桌上',
      '桌面',
      '看到的东西',
      '手边',
      '这个东西',
      '物品',
      '吃的',
      '喝的',
      '花',
      '咖啡',
      '礼物',
      '买的东西',
    ])) {
      return ChatImageSceneIntent(
        subject: ChatImageSubject.object,
        characterPresence: ChatCharacterPresence.none,
        visualFocus: '角色视角下当前明确提到的物品、食物或饮品是主要视觉主体。事实依据：$evidence',
      );
    }
    return null;
  }

  ChatImageSceneIntent? _resolveFromContext(
    List<ChatMessage> messages,
    String characterId,
  ) {
    final visible = messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .toList();
    final recent = visible.length > 4
        ? visible.sublist(visible.length - 4)
        : visible;
    for (final message in recent.reversed) {
      final content = message.content.replaceAll(RegExp(r'\s+'), '');
      if (content.isEmpty || _isFollowUp(content)) continue;
      final result = _classify(
        value: content,
        evidence: message.content,
        characterId: characterId,
      );
      if (result != null) return result;
      if (_isContextualCharacterState(content)) {
        return ChatImageSceneIntent(
          subject: ChatImageSubject.character,
          characterPresence: ChatCharacterPresence.required,
          visualFocus: '角色本人当前的样子是主要视觉主体，不得用环境或物品代替。事实依据：${message.content}',
          requiredCharacterIds: [characterId],
        );
      }
    }
    return null;
  }

  bool _containsAny(String value, List<String> keywords) =>
      keywords.any(value.contains);

  bool _isCharacterRequest(String value) =>
      RegExp(r'(给我|让我|想)?看看你(本人|现在的样子|的样子)?[。！!？?呀啊吧嘛呢~～]*$').hasMatch(value) ||
      _containsAny(value, const ['发张你的照片', '给我看看本人', '让我看看你现在的样子']);

  bool _isCharacterObjectRequest(String value) {
    final hasRelation = _containsAny(value, const [
      '拿着',
      '捧着',
      '抱着',
      '戴上',
      '佩戴',
      '放在',
      '摆在',
      '靠在',
      '趴我怀里',
      '趴在我怀里',
      '在我怀里',
    ]);
    final hasObject = _containsAny(value, const [
      '花',
      '礼物',
      '猫',
      '耳环',
      '耳钉',
      '项链',
      '戒指',
      '眼镜',
      '咖啡',
    ]);
    return hasRelation && hasObject;
  }

  bool _isContextualCharacterState(String value) => _containsAny(value, const [
    '我刚洗完澡',
    '我刚洗完',
    '我现在这样',
    '我现在的样子',
    '我这样挺狼狈',
    '我现在挺狼狈',
    '我浑身湿',
  ]);

  bool _isFollowUp(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s，,。！!？?～~]+'), '');
    if (const {'照片呢', '图片呢', '图呢'}.contains(normalized)) {
      return true;
    }
    final withoutParticles = normalized.replaceFirst(RegExp(r'[嘛呀啊呗呢吧]+$'), '');
    return const {
      '照片',
      '图片',
      '图',
      '发来看看',
      '给我看看',
      '让我看看',
      '看看',
      '想看',
    }.contains(withoutParticles);
  }
}
