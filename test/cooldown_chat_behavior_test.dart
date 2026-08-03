import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/chat_flow/chat_flow_engine.dart';
import 'package:peijianche_app/chat_flow/reply_intent.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/context_builder/cooldown_context.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/prompt_composer/prompt_composer.dart';
import 'package:peijianche_app/prompt_composer/prompt_context.dart';
import 'package:peijianche_app/reply_strategy/reply_strategy.dart';
import 'package:peijianche_app/reply_strategy/reply_strategy_engine.dart';
import 'package:peijianche_app/services/relationship_cooldown_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'cooldown_chat_behavior_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documentsDirectory.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await documentsDirectory.delete(recursive: true);
  });

  test('normal state leaves chat flow and reply strategy unchanged', () {
    final conversation = _questionTurnConversation();
    const flowEngine = ChatFlowEngine();
    const strategyEngine = ReplyStrategyEngine();

    final originalFlow = flowEngine.plan(conversation);
    final normalFlow = flowEngine.plan(conversation, isInCooldown: false);
    final originalStrategy = strategyEngine.plan(
      conversation: conversation,
      flow: originalFlow,
    );
    final normalStrategy = strategyEngine.plan(
      conversation: conversation,
      flow: normalFlow,
      isInCooldown: false,
    );

    expect(normalFlow.intent, originalFlow.intent);
    expect(normalFlow.questionDesire, originalFlow.questionDesire);
    expect(normalStrategy.length, originalStrategy.length);
    expect(normalStrategy.question, originalStrategy.question);
    expect(normalStrategy.tone, originalStrategy.tone);
  });

  test('cooldown lowers reply length and disables active questions', () {
    final conversation = _questionTurnConversation();
    final flow = const ChatFlowEngine().plan(conversation, isInCooldown: true);
    final strategy = const ReplyStrategyEngine().plan(
      conversation: conversation,
      flow: flow,
      isInCooldown: true,
    );

    expect(flow.intent, isNot(ReplyIntent.askQuestion));
    expect(flow.questionDesire, 0);
    expect(strategy.length, StrategyLength.short);
    expect(strategy.question, isFalse);
    expect(strategy.tone, ReplyTone.natural);
  });

  test('cooldown context is composed independently after base context', () {
    const base = ContextBuildResult(
      messages: [
        {'role': 'system', 'content': 'character context'},
        {'role': 'user', 'content': '你好'},
      ],
      systemPrompt: 'character context',
    );
    const cooldown = CooldownContext(isInCooldown: true);

    final result = PromptComposer(baseContext: base)
        .addContext(PromptContext.cooldown(cooldown.toPromptSection()))
        .addContext(PromptContext.chatFlow('CHAT_FLOW'))
        .compose();

    expect(result.systemPrompt, startsWith('character context'));
    expect(result.systemPrompt, contains('Currently in cooldown.'));
    expect(
      result.systemPrompt.indexOf('Currently in cooldown.'),
      lessThan(result.systemPrompt.indexOf('CHAT_FLOW')),
    );
  });

  test('expired cooldown automatically restores normal behavior', () async {
    final service = RelationshipCooldownService(characterId: 'pei');
    await service.enterCooldown(
      const Duration(hours: 1),
      now: DateTime.utc(2026, 8, 3, 10),
    );
    final active = await service.isInCooldown(
      now: DateTime.utc(2026, 8, 3, 10, 30),
    );
    final expired = await service.isInCooldown(
      now: DateTime.utc(2026, 8, 3, 11),
    );

    expect(active, isTrue);
    expect(expired, isFalse);
    final normalFlow = const ChatFlowEngine().plan(
      _questionTurnConversation(),
      isInCooldown: expired,
    );
    expect(normalFlow.questionDesire, greaterThan(0));
  });

  test('different character states produce different chat behavior', () async {
    final now = DateTime.utc(2026, 8, 3, 10);
    final pei = RelationshipCooldownService(characterId: 'pei_jian_che');
    final che = RelationshipCooldownService(characterId: 'che_yun_qian');
    await pei.enterCooldown(const Duration(hours: 2), now: now);

    final peiCooldown = await pei.isInCooldown(
      now: DateTime.utc(2026, 8, 3, 11),
    );
    final cheCooldown = await che.isInCooldown(
      now: DateTime.utc(2026, 8, 3, 11),
    );
    final conversation = _questionTurnConversation();
    final peiFlow = const ChatFlowEngine().plan(
      conversation,
      isInCooldown: peiCooldown,
    );
    final cheFlow = const ChatFlowEngine().plan(
      conversation,
      isInCooldown: cheCooldown,
    );

    expect(peiCooldown, isTrue);
    expect(cheCooldown, isFalse);
    expect(peiFlow.questionDesire, 0);
    expect(cheFlow.questionDesire, greaterThan(0));
  });
}

ConversationContext _questionTurnConversation() {
  final messages = <ChatMessage>[];
  for (var index = 0; index < 6; index++) {
    messages
      ..add(ChatMessage(role: 'user', content: '第 $index 轮'))
      ..add(ChatMessage(role: 'assistant', content: '普通回应 $index'));
  }
  messages.add(ChatMessage(role: 'user', content: '继续聊聊'));
  return ConversationContext(messages);
}
