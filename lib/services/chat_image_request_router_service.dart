import 'dart:convert';

import '../models/chat_message.dart';
import 'multimodal_service.dart';

enum ChatImageIntent { normalChat, generateImage }

class ChatImageRequestDecision {
  const ChatImageRequestDecision({
    required this.intent,
    this.reason = '',
  });

  final ChatImageIntent intent;
  final String reason;

  bool get shouldGenerateImage => intent == ChatImageIntent.generateImage;
}

/// 判断用户此刻是在普通聊天，还是确实要求角色发送一张图片。
///
/// 先用本地规则处理非常明确的说法，只有模糊表达才调用多模态模型，
/// 既避免漏掉“给我看看你今天吃了什么”，也不会让每句聊天都额外消耗一次 API。
class ChatImageRequestRouterService {
  ChatImageRequestRouterService({MultimodalService? multimodalService})
      : _multimodalService = multimodalService ?? MultimodalService(),
        _ownsService = multimodalService == null;

  final MultimodalService _multimodalService;
  final bool _ownsService;

  Future<ChatImageRequestDecision> decide({
    required String userText,
    required List<ChatMessage> recentMessages,
  }) async {
    final text = _normalize(userText);
    if (text.isEmpty) {
      return const ChatImageRequestDecision(
        intent: ChatImageIntent.normalChat,
        reason: '空消息',
      );
    }

    if (_isClearlyImageRequest(text)) {
      return const ChatImageRequestDecision(
        intent: ChatImageIntent.generateImage,
        reason: '明确要求查看、拍摄或生成图片',
      );
    }

    if (_isClearlyNormalChat(text)) {
      return const ChatImageRequestDecision(
        intent: ChatImageIntent.normalChat,
        reason: '只是询问或讨论图片，并未要求发送图片',
      );
    }

    if (!_containsVisualCue(text)) {
      return const ChatImageRequestDecision(
        intent: ChatImageIntent.normalChat,
        reason: '没有图片意图线索',
      );
    }

    try {
      final context = _buildContext(recentMessages);
      final raw = await _multimodalService.classifyImageRequest(
        userText: userText,
        recentConversation: context,
      );
      final parsed = _parseDecision(raw);
      if (parsed != null) return parsed;
    } catch (_) {
      // 路由判断失败时不影响正常聊天，回退到本地规则。
    }

    return ChatImageRequestDecision(
      intent: _fallbackAmbiguousDecision(text),
      reason: '语义判断失败后的本地回退',
    );
  }

  bool _isClearlyImageRequest(String text) {
    const directPhrases = <String>[
      '画一张',
      '画张',
      '生成一张',
      '生成张',
      '生成图片',
      '生图',
      '来一张',
      '来张图',
      '发张图',
      '发一张图',
      '发图给我',
      '发张照片',
      '发一张照片',
      '照片发我',
      '拍张照片',
      '拍一张照片',
      '拍给我看',
      '拍来看看',
      '给我拍',
      '现场图',
      '画下来',
      '做成图片',
      '给我看看你现在',
      '给我看你现在',
      '想看你现在',
      '让我看看你现在',
      '看看你那边',
      '给我看看你那边',
      '发来看看',
      '照片呢',
      '图片呢',
      '图呢',
    ];
    if (directPhrases.any(text.contains)) return true;

    final requestPatterns = <RegExp>[
      RegExp(r'(给我|让我|想|要)看(看)?你.{0,10}(吃|穿|做|在|那边|窗外|周围|今天|现在)'),
      RegExp(r'(给我|让我)看(看)?.{0,12}(照片|图片|样子|现场|画面)'),
      RegExp(r'(拍|照|画|生成).{0,10}(给我|看看|发来|发我)'),
      RegExp(r'(有没有|有没).{0,6}(照片|图片|图|现场照)'),
    ];
    return requestPatterns.any((pattern) => pattern.hasMatch(text));
  }

  bool _isClearlyNormalChat(String text) {
    const normalPhrases = <String>[
      '你看过这张图吗',
      '你喜欢这张图吗',
      '这张图好看吗',
      '照片好看吗',
      '图片好看吗',
      '怎么拍照',
      '怎么画',
      '会画画吗',
    ];
    return normalPhrases.any(text.contains);
  }

  bool _containsVisualCue(String text) {
    const cues = <String>[
      '看',
      '照片',
      '图片',
      '图',
      '拍',
      '画',
      '现场',
      '样子',
      '长什么',
      '窗外',
    ];
    return cues.any(text.contains);
  }

  ChatImageIntent _fallbackAmbiguousDecision(String text) {
    final hasRequestWord = text.contains('给我') ||
        text.contains('让我') ||
        text.contains('发') ||
        text.contains('拍') ||
        text.endsWith('呢');
    final hasVisualWord = text.contains('看') ||
        text.contains('照片') ||
        text.contains('图片') ||
        text.contains('图');
    return hasRequestWord && hasVisualWord
        ? ChatImageIntent.generateImage
        : ChatImageIntent.normalChat;
  }

  ChatImageRequestDecision? _parseDecision(String raw) {
    var value = raw.trim();
    value = value.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
    value = value.replaceAll(RegExp(r'\s*```$'), '');
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start < 0 || end <= start) return null;

    final decoded = jsonDecode(value.substring(start, end + 1));
    if (decoded is! Map) return null;
    final intent = decoded['intent']?.toString().trim().toLowerCase();
    final reason = decoded['reason']?.toString().trim() ?? '';
    if (intent == 'generate_image') {
      return ChatImageRequestDecision(
        intent: ChatImageIntent.generateImage,
        reason: reason,
      );
    }
    if (intent == 'normal_chat') {
      return ChatImageRequestDecision(
        intent: ChatImageIntent.normalChat,
        reason: reason,
      );
    }
    return null;
  }

  String _buildContext(List<ChatMessage> messages) {
    final visible = messages
        .where((message) =>
            message.role == 'user' || message.role == 'assistant')
        .toList();
    final recent = visible.length > 6
        ? visible.sublist(visible.length - 6)
        : visible;
    return recent.map((message) {
      final speaker = message.role == 'user' ? '用户' : '角色';
      final content = message.type == MessageType.image
          ? '[图片] ${message.content}'
          : message.content;
      return '$speaker：$content';
    }).join('\n');
  }

  String _normalize(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('？', '?');

  void dispose() {
    if (_ownsService) _multimodalService.dispose();
  }
}
