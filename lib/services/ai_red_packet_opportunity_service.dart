import 'dart:convert';

import '../models/ai_red_packet_opportunity.dart';
import '../models/chat_message.dart';

typedef OpportunityCompletion =
    Future<String> Function(List<Map<String, dynamic>> messages);

class AiRedPacketOpportunityService {
  const AiRedPacketOpportunityService();

  Future<AiRedPacketOpportunity> evaluate({
    required List<ChatMessage> messages,
    required OpportunityCompletion complete,
  }) async {
    final candidate = detectCandidate(messages);
    if (!candidate.shouldSendRedPacket || _recentlySent(messages)) {
      return const AiRedPacketOpportunity.none();
    }

    try {
      final raw = await complete(_buildDecisionMessages(messages));
      return parseDecision(raw, fallback: candidate);
    } catch (_) {
      return candidate;
    }
  }

  AiRedPacketOpportunity detectCandidate(List<ChatMessage> messages) {
    final latest = messages
        .where(
          (message) =>
              message.role == 'user' && message.isVisibleInConversationContext,
        )
        .lastOrNull;
    if (latest == null) return const AiRedPacketOpportunity.none();

    final text = latest.content.toLowerCase();
    if (_containsAny(text, const [
      '生日',
      'birthday',
      '纪念日',
      'anniversary',
      '考试通过',
      '录取',
    ])) {
      return const AiRedPacketOpportunity(
        shouldSendRedPacket: true,
        reason: '用户提到了值得庆祝的特殊事件',
        kind: AiRedPacketOpportunityKind.specialEvent,
        futureGiftIntent: 'celebration',
      );
    }
    if (_containsAny(text, const [
      '想买',
      '买不起',
      '缺钱',
      '攒钱',
      '坏了',
      '摔坏',
      '维修',
      '难过',
      '心情不好',
      '崩溃',
      '委屈',
      '失落',
      '不舒服',
      '生病',
      '发烧',
      '头疼',
      '肚子疼',
      'sick',
      'sad',
    ])) {
      return const AiRedPacketOpportunity(
        shouldSendRedPacket: true,
        reason: '用户正在经历需要安慰或实际关心的情况',
        kind: AiRedPacketOpportunityKind.comfort,
        futureGiftIntent: 'care',
      );
    }
    return const AiRedPacketOpportunity.none();
  }

  AiRedPacketOpportunity parseDecision(
    String raw, {
    required AiRedPacketOpportunity fallback,
  }) {
    try {
      var value = raw.trim();
      value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      value = value.replaceFirst(RegExp(r'\s*```$'), '');
      final start = value.indexOf('{');
      final end = value.lastIndexOf('}');
      if (start < 0 || end < start) return fallback;
      final json = jsonDecode(value.substring(start, end + 1));
      if (json is! Map || json['shouldSendRedPacket'] != true) {
        return const AiRedPacketOpportunity.none();
      }
      final reason = json['reason']?.toString().trim() ?? '';
      final kind = json['kind']?.toString() == 'specialEvent'
          ? AiRedPacketOpportunityKind.specialEvent
          : fallback.kind;
      return AiRedPacketOpportunity(
        shouldSendRedPacket: true,
        reason: reason.isEmpty ? fallback.reason : reason,
        kind: kind,
        futureGiftIntent: fallback.futureGiftIntent,
      );
    } catch (_) {
      return fallback;
    }
  }

  int amountInCents(AiRedPacketOpportunity opportunity) {
    if (!opportunity.shouldSendRedPacket) return 0;
    final special = opportunity.kind == AiRedPacketOpportunityKind.specialEvent;
    final minYuan = special ? 200 : 50;
    final maxYuan = special ? 520 : 200;
    final seed = opportunity.reason.codeUnits.fold<int>(
      0,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    return (minYuan + seed % (maxYuan - minYuan + 1)) * 100;
  }

  List<Map<String, dynamic>> _buildDecisionMessages(
    List<ChatMessage> messages,
  ) {
    final recent = messages
        .where((message) => message.isVisibleInConversationContext)
        .toList();
    final tail = recent.length > 8 ? recent.sublist(recent.length - 8) : recent;
    final transcript = tail
        .map((message) => '${message.role}: ${message.content}')
        .join('\n');
    return [
      const {
        'role': 'system',
        'content':
            '''Decide whether this is a natural moment for the character to send a red packet.
Return JSON only: {"shouldSendRedPacket":true|false,"reason":"...","kind":"comfort|specialEvent"}.
Suitable moments include birthdays, meaningful celebrations, purchase needs, broken belongings, low mood, or illness.
Be conservative. Do not choose, suggest, or mention any amount. The system controls money.
Do not add a gift, shop item, currency, or relationship reward.''',
      },
      {'role': 'user', 'content': transcript},
    ];
  }

  bool _recentlySent(List<ChatMessage> messages) {
    return messages.reversed
        .take(12)
        .any(
          (message) =>
              message.role == 'assistant' &&
              message.type == MessageType.redPacket &&
              message.source == 'ai_red_packet_opportunity',
        );
  }

  bool _containsAny(String text, List<String> keywords) =>
      keywords.any(text.contains);
}

extension<T> on Iterable<T> {
  T? get lastOrNull {
    if (isEmpty) return null;
    return last;
  }
}
