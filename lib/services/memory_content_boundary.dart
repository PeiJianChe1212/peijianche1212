import 'dart:convert';

import '../models/chat_message.dart';
import '../models/memory_extraction_result.dart';

/// Local input context and provenance checks, not another classification model.
class MemoryContentBoundary {
  static List<String> labels(ChatMessage message) {
    if (message.type == MessageType.system || message.role == 'system') {
      return ['系统性内容'];
    }
    if (message.role == 'assistant') return ['assistant 回复'];
    final text = message.content;
    final labels = <String>[];
    if (message.type == MessageType.image) labels.add('图片配文');
    if (RegExp(
      r'```|\b(import\s+(?:dart:|package:)|void\s+main|class\s+\w+|def\s+\w+|print\s*\(|Widget\s+build)|分析.{0,8}(?:代码|程序)|开发资料|系统提示词',
      caseSensitive: false,
    ).hasMatch(text)) {
      labels.add('代码/开发内容');
    }
    if (RegExp(r'朋友说|他说|她说|别人说|引用|转述|^\s*>|^\s*[“「『]').hasMatch(text)) {
      labels.add('引用内容');
    }
    if (RegExp(
      r'新闻[:：]|报道称|据.{0,12}报道|以下.{0,8}(?:文章|资料)|粘贴.{0,8}(?:文章|资料)|文章[:：]|资料[:：]',
    ).hasMatch(text)) {
      labels.add('粘贴资料/文章');
    }
    if (RegExp(
      r'创建角色|角色设定|虚构人物|虚构角色|写.{0,4}小说|小说人物|人设[:：]|设定[:：]',
    ).hasMatch(text)) {
      labels.add('虚构角色设定');
    }
    if (labels.isEmpty) labels.add('用户消息（是否为本人陈述须依语境）');
    return labels;
  }

  static bool canSupportUserFact(ChatMessage message) {
    if (message.role != 'user' ||
        !message.isVisibleInConversationContext ||
        message.content.trim().isEmpty) {
      return false;
    }
    final tags = labels(message);
    return !tags.any(
      (tag) =>
          const ['系统性内容', '代码/开发内容', '引用内容', '粘贴资料/文章', '虚构角色设定'].contains(tag),
    );
  }

  static String describe(ChatMessage message, String speaker) => jsonEncode({
    'id': message.id,
    'speaker': speaker,
    'role': message.role,
    'type': message.type.name,
    'context': labels(message),
    'content': message.content.trim(),
    if (message.type == MessageType.image &&
        (message.metadata['visionDescription']?.toString().trim().isNotEmpty ??
            false))
      'AI图片视觉描述（不是用户本人陈述）': message.metadata['visionDescription'].toString(),
  });

  static MemoryExtractionResult grounded(
    MemoryExtractionResult result,
    List<ChatMessage> messages,
  ) {
    final allIds = messages.map((m) => m.id).toSet();
    final userIds = messages.where(canSupportUserFact).map((m) => m.id).toSet();
    bool valid(List<String> ids) =>
        ids.isNotEmpty && ids.every(allIds.contains);
    return MemoryExtractionResult(
      eventMemories: result.eventMemories
          .where((m) => valid(m.sourceMessageIds))
          .toList(),
      userMemories: result.userMemories
          .where(
            (m) =>
                valid(m.sourceMessageIds) &&
                m.sourceMessageIds.any(userIds.contains),
          )
          .toList(),
      rawResponseShape: result.rawResponseShape,
      parseOutcome: result.parseOutcome,
    );
  }

  static int sourceCharacters(ChatMessage message) =>
      message.content.length +
      (message.type == MessageType.image
          ? (message.metadata['visionDescription']?.toString().length ?? 0)
          : 0);
}
