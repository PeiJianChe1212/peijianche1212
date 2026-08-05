import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_red_packet_opportunity.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/red_packet_data.dart';
import 'package:peijianche_app/services/ai_red_packet_opportunity_service.dart';

void main() {
  const service = AiRedPacketOpportunityService();

  test('birthday creates a special-event opportunity', () {
    final result = service.detectCandidate([
      ChatMessage(role: 'user', content: '今天是我生日'),
    ]);

    expect(result.shouldSendRedPacket, isTrue);
    expect(result.kind, AiRedPacketOpportunityKind.specialEvent);
  });

  test('low mood creates a comfort opportunity', () {
    final result = service.detectCandidate([
      ChatMessage(role: 'user', content: '今天心情不好，有点失落'),
    ]);

    expect(result.shouldSendRedPacket, isTrue);
    expect(result.kind, AiRedPacketOpportunityKind.comfort);
  });

  test('model decides opportunity but cannot control the amount', () async {
    late List<Map<String, dynamic>> request;
    final result = await service.evaluate(
      messages: [ChatMessage(role: 'user', content: '我的手机摔坏了')],
      complete: (messages) async {
        request = messages;
        return '''{"shouldSendRedPacket":true,"reason":"offer support","kind":"comfort","amount":999999}''';
      },
    );

    expect(result.shouldSendRedPacket, isTrue);
    expect(request.first['content'], contains('system controls money'));
    expect(service.amountInCents(result), inInclusiveRange(5000, 20000));
  });

  test(
    'special-event amount is system-controlled between 200 and 520 yuan',
    () {
      const opportunity = AiRedPacketOpportunity(
        shouldSendRedPacket: true,
        reason: 'birthday',
        kind: AiRedPacketOpportunityKind.specialEvent,
      );

      expect(
        service.amountInCents(opportunity),
        inInclusiveRange(20000, 52000),
      );
      expect(service.amountInCents(opportunity) % 100, 0);
    },
  );

  test('recent AI red packet prevents repeated sends', () async {
    var modelCalled = false;
    final result = await service.evaluate(
      messages: [
        ChatMessage(role: 'user', content: '我很难过'),
        ChatMessage(
          role: 'assistant',
          content: '',
          source: 'ai_red_packet_opportunity',
          type: MessageType.redPacket,
          redPacket: const RedPacketData(
            amount: 5000,
            message: '给你的',
            senderId: 'character-a',
            receiverId: 'user',
          ),
        ),
      ],
      complete: (_) async {
        modelCalled = true;
        return '{}';
      },
    );

    expect(result.shouldSendRedPacket, isFalse);
    expect(modelCalled, isFalse);
  });

  test('ordinary chat does not call the opportunity model', () async {
    var modelCalled = false;
    final result = await service.evaluate(
      messages: [ChatMessage(role: 'user', content: '今天天气不错')],
      complete: (_) async {
        modelCalled = true;
        return '{}';
      },
    );

    expect(result.shouldSendRedPacket, isFalse);
    expect(modelCalled, isFalse);
  });
}
