import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/chat_message.dart';
import '../models/memory_extraction_result.dart';

class Memory2ExtractionRequest {
  const Memory2ExtractionRequest({
    required this.characterName,
    required this.userName,
    required this.messages,
    this.existingEventHints = const [],
    this.existingUserHints = const [],
    this.legacyHints = const [],
  });

  final String characterName;
  final String userName;
  final List<ChatMessage> messages;
  final List<String> existingEventHints;
  final List<String> existingUserHints;
  final List<String> legacyHints;
}

abstract interface class Memory2ExtractionGateway {
  Future<MemoryExtractionResult> extract(Memory2ExtractionRequest request);
}

class Memory2ModelExtractor implements Memory2ExtractionGateway {
  Memory2ModelExtractor({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<MemoryExtractionResult> extract(
    Memory2ExtractionRequest request,
  ) async {
    final provider = await ModelHub(client: _client).chatProvider();
    final allowedMessageIds = request.messages.map((item) => item.id).toSet();
    final raw = await provider.complete(
      messages: buildMessages(request),
      temperature: 0.1,
      maxTokens: 900,
      topP: 0.8,
      acceptStructuredReasoningFallback: true,
    );
    return parse(raw, allowedMessageIds: allowedMessageIds);
  }

  List<Map<String, dynamic>> buildMessages(Memory2ExtractionRequest request) =>
      [
        {'role': 'system', 'content': _systemPrompt(request)},
        {'role': 'user', 'content': _transcript(request)},
      ];

  MemoryExtractionResult parse(
    String raw, {
    required Set<String> allowedMessageIds,
  }) {
    final extracted = _extractSingleJsonObject(raw);
    final decoded = jsonDecode(extracted.json);
    if (decoded is! Map ||
        !decoded.containsKey('eventMemories') ||
        !decoded.containsKey('userMemories') ||
        decoded['eventMemories'] is! List ||
        decoded['userMemories'] is! List) {
      throw MemoryExtractionParseException(
        'Memory 2.0 提取结果必须显式包含两个数组字段',
        shape: extracted.shape,
      );
    }

    final events = (decoded['eventMemories'] as List)
        .whereType<Map>()
        .map((item) {
          final sources = _validSources(
            item['sourceMessageIds'],
            allowedMessageIds,
          );
          return ExtractedEventMemory(
            content: _text(item['content']),
            sourceMessageIds: sources,
            occurredAt: DateTime.tryParse(_text(item['occurredAt'])),
          );
        })
        .where(
          (item) => item.content.isNotEmpty && item.sourceMessageIds.isNotEmpty,
        )
        .take(6)
        .toList();
    final users = (decoded['userMemories'] as List)
        .whereType<Map>()
        .map((item) {
          final sources = _validSources(
            item['sourceMessageIds'],
            allowedMessageIds,
          );
          return ExtractedUserMemory(
            key: _text(item['key']),
            value: _text(item['value']),
            sourceMessageIds: sources,
          );
        })
        .where(
          (item) =>
              item.key.isNotEmpty &&
              item.value.isNotEmpty &&
              item.sourceMessageIds.isNotEmpty,
        )
        .take(10)
        .toList();
    return MemoryExtractionResult(
      eventMemories: events,
      userMemories: users,
      rawResponseShape: extracted.shape,
      parseOutcome: 'success',
    );
  }

  _ExtractedJson _extractSingleJsonObject(String raw) {
    final value = raw.trim();
    final fenced = RegExp(
      r'^```(?:[a-zA-Z0-9_-]+)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(value);
    final searchValue = fenced?.group(1)?.trim() ?? value;
    final objects = _topLevelJsonObjects(searchValue);
    if (objects.length != 1) {
      throw const MemoryExtractionParseException(
        'Memory 2.0 提取结果必须只包含一个完整 JSON 对象',
        shape: MemoryExtractionRawResponseShape.invalid,
      );
    }
    final json = objects.single;
    try {
      if (jsonDecode(json) is! Map) {
        throw const FormatException('not an object');
      }
    } catch (_) {
      throw const MemoryExtractionParseException(
        'Memory 2.0 提取结果不是合法 JSON 对象',
        shape: MemoryExtractionRawResponseShape.invalid,
      );
    }
    final shape = fenced != null
        ? MemoryExtractionRawResponseShape.fencedJson
        : searchValue == json
        ? MemoryExtractionRawResponseShape.pureJson
        : MemoryExtractionRawResponseShape.wrappedJson;
    return _ExtractedJson(json, shape);
  }

  List<String> _topLevelJsonObjects(String value) {
    final result = <String>[];
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;
    for (var index = 0; index < value.length; index++) {
      final char = value[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"' && depth > 0) {
        inString = true;
      } else if (char == '{') {
        if (depth == 0) start = index;
        depth++;
      } else if (char == '}' && depth > 0) {
        depth--;
        if (depth == 0 && start >= 0) {
          final candidate = value.substring(start, index + 1);
          try {
            if (jsonDecode(candidate) is Map) result.add(candidate);
          } catch (_) {
            // Invalid candidates are not repaired or interpreted.
          }
          start = -1;
        }
      }
    }
    return result;
  }

  String _systemPrompt(Memory2ExtractionRequest request) {
    final existing = <String>[
      if (request.existingEventHints.isNotEmpty)
        '已有事件记忆（只用于避免明显重复）：\n${request.existingEventHints.map((item) => '- $item').join('\n')}',
      if (request.existingUserHints.isNotEmpty)
        '已有用户认识（只用于避免明显重复）：\n${request.existingUserHints.map((item) => '- $item').join('\n')}',
      if (request.legacyHints.isNotEmpty)
        '旧记忆只读提示（不得复制或改写）：\n${request.legacyHints.map((item) => '- $item').join('\n')}',
    ].join('\n\n');
    return '''
你是 PeiLink Memory 2.0 的事实提取器，不进行角色扮演。
当前角色：${request.characterName}
当前用户：${request.userName}

从本批对话中提取两类内容：
1. eventMemories：用户与当前角色共同发生、共同讨论并形成完整互动的具体经历。它不要求是重大人生事件；只要用户以后可能自然提起“上次那件事”，就值得保存。它不是逐句摘要，连续话题应合成一个事件。例如用户买了一盆蓝色绣球，与角色讨论摆放位置后决定放在电脑桌旁，应保存为一条完整 EventMemory。不得把角色幻想或未出现的事情写成经历。
2. userMemories：用户明确表达、可在未来持续适用的稳定喜好、不喜欢、禁忌、习惯、工作生活方式、关系信息或互动偏好。明确的长期游戏偏好和工作习惯应保存。例如“我喜欢拿铁，不喜欢美式”是典型可保存 UserMemory；“我更喜欢剧情和 PVE，不喜欢 PVP”也应保存。不得从模糊表达推断健康、身份、家庭、关系或私密事实。

忽略闲聊、笑声、天气、一次性饮食、临时情绪、无意义问答和角色单方面编造的内容。
sourceMessageIds 只能使用对话中方括号标出的真实消息 ID。没有可靠来源的内容不要输出。
只返回 JSON，不要 Markdown、reason、importance、confidence、解释或思考过程：
{"eventMemories":[{"content":"...","sourceMessageIds":["..."],"occurredAt":null}],"userMemories":[{"key":"...","value":"...","sourceMessageIds":["..."]}]}
没有内容时两个数组都返回空数组。
${existing.isEmpty ? '' : '\n$existing'}
'''
        .trim();
  }

  String _transcript(Memory2ExtractionRequest request) => request.messages
      .map((message) {
        final speaker = message.role == 'user'
            ? request.userName
            : request.characterName;
        return '[id=${message.id}] $speaker：${message.content.trim()}';
      })
      .join('\n');

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static List<String> _validSources(dynamic raw, Set<String> allowed) {
    if (raw is! List) return const [];
    return raw
        .map(_text)
        .where((item) => item.isNotEmpty && allowed.contains(item))
        .toSet()
        .toList();
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class _ExtractedJson {
  const _ExtractedJson(this.json, this.shape);
  final String json;
  final MemoryExtractionRawResponseShape shape;
}
