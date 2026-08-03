import '../chat_flow/chat_flow_plan.dart';
import '../chat_flow/reply_intent.dart';
import '../context_builder/context_build_result.dart';
import '../context_builder/conversation_context.dart';
import '../models/chat_message.dart';
import 'reply_goal.dart';
import 'reply_strategy.dart';
import 'response_shape.dart';

class ReplyStrategyEngine {
  const ReplyStrategyEngine();

  ReplyStrategy plan({
    required ConversationContext conversation,
    required ChatFlowPlan flow,
    bool isInCooldown = false,
  }) {
    final userText = _lastUserText(conversation.messages);
    final goal = _selectGoal(userText, flow.intent);
    if (isInCooldown) {
      return ReplyStrategy(
        goal: goal,
        tone: ReplyTone.natural,
        length: StrategyLength.short,
        question: false,
        shape: _shapeFor(goal),
      );
    }
    final question =
        goal == ReplyGoal.continueChat &&
        !flow.shouldAvoidQuestion &&
        !flow.forbidChoiceQuestion;

    return ReplyStrategy(
      goal: goal,
      tone: _toneFor(goal),
      length: _lengthFor(goal),
      question: question,
      shape: _shapeFor(goal),
    );
  }

  ContextBuildResult apply({
    required ContextBuildResult context,
    required ReplyStrategy strategy,
  }) {
    if (context.messages.isEmpty) return context;
    final messages = context.messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    final system = messages.first;
    final original = system['content']?.toString() ?? context.systemPrompt;
    final prompt = '$original\n\n${strategy.toPromptSection()}';
    system['content'] = prompt;

    // ignore: avoid_print
    print(
      '[ReplyStrategyEngine] goal=${strategy.goal.key}, '
      'tone=${strategy.tone.name}, length=${strategy.length.name}, '
      'question=${strategy.question}',
    );
    return ContextBuildResult(messages: messages, systemPrompt: prompt);
  }

  ReplyGoal _selectGoal(String text, ReplyIntent intent) {
    if (_needsComfort(text)) return ReplyGoal.comfort;
    if (_invitesTeasing(text)) return ReplyGoal.tease;
    if (_asksForExplanation(text)) return ReplyGoal.explain;
    if (_invitesRomance(text)) return ReplyGoal.romance;

    return switch (intent) {
      ReplyIntent.response => ReplyGoal.acknowledge,
      ReplyIntent.share => ReplyGoal.share,
      ReplyIntent.care => ReplyGoal.comfort,
      ReplyIntent.tease => ReplyGoal.tease,
      ReplyIntent.continueChat ||
      ReplyIntent.askQuestion => ReplyGoal.continueChat,
      ReplyIntent.endNaturally => ReplyGoal.close,
    };
  }

  ReplyTone _toneFor(ReplyGoal goal) => switch (goal) {
    ReplyGoal.comfort => ReplyTone.gentle,
    ReplyGoal.tease => ReplyTone.playful,
    ReplyGoal.romance => ReplyTone.warm,
    ReplyGoal.explain => ReplyTone.clear,
    _ => ReplyTone.natural,
  };

  StrategyLength _lengthFor(ReplyGoal goal) => switch (goal) {
    ReplyGoal.explain ||
    ReplyGoal.share ||
    ReplyGoal.continueChat => StrategyLength.medium,
    _ => StrategyLength.short,
  };

  ResponseShape _shapeFor(ReplyGoal goal) => switch (goal) {
    ReplyGoal.acknowledge => ResponseShape.briefAcknowledgement,
    ReplyGoal.comfort => ResponseShape.emotionalSupport,
    ReplyGoal.share ||
    ReplyGoal.tease ||
    ReplyGoal.continueChat => ResponseShape.casualChat,
    ReplyGoal.romance => ResponseShape.intimateExpression,
    ReplyGoal.explain => ResponseShape.directExplanation,
    ReplyGoal.close => ResponseShape.naturalClose,
  };

  static String _lastUserText(List<ChatMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].role == 'user') return messages[index].content.trim();
    }
    return '';
  }

  static bool _needsComfort(String text) =>
      RegExp(r'累|疲惫|困死|难受|不舒服|压力|烦|崩溃|委屈|难过').hasMatch(text);

  static bool _invitesTeasing(String text) =>
      RegExp(r'哈哈|嘿嘿|笑死|你猜|逗你|才不告诉你').hasMatch(text);

  static bool _asksForExplanation(String text) =>
      RegExp(r'为什么|为啥|怎么回事|什么意思|你知道.*吗|解释|原因').hasMatch(text);

  static bool _invitesRomance(String text) =>
      RegExp(r'想你|爱你|喜欢你|抱抱|亲亲|想抱|想亲').hasMatch(text);
}
