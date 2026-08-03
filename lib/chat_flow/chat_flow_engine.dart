import '../context_builder/context_build_result.dart';
import '../context_builder/conversation_context.dart';
import '../models/chat_message.dart';
import 'chat_flow_plan.dart';
import 'reply_intent.dart';

class ChatFlowEngine {
  const ChatFlowEngine({this.defaultQuestionDesire = 0.22});

  /// 默认值刻意保持较低；它是回复策略，不是模型采样参数。
  final double defaultQuestionDesire;

  ChatFlowPlan plan(
    ConversationContext conversation, {
    bool isInCooldown = false,
  }) {
    final messages = conversation.messages;
    final lastUser = _lastWhere(messages, (message) => message.role == 'user');
    final lastAssistant = _lastWhere(
      messages,
      (message) => message.role == 'assistant',
    );
    final assistantMessages = messages
        .where((message) => message.role == 'assistant')
        .toList();
    final previousAssistantAskedQuestion =
        lastAssistant != null && _containsQuestion(lastAssistant.content);
    final forbidChoiceQuestion = assistantMessages.reversed
        .take(2)
        .any((message) => _containsChoiceQuestion(message.content));

    var questionDesire = defaultQuestionDesire.clamp(0.0, 1.0).toDouble();
    if (previousAssistantAskedQuestion) questionDesire *= 0.25;
    if (forbidChoiceQuestion) questionDesire = 0;
    if (isInCooldown) questionDesire = 0;

    final intent = _selectIntent(
      userText: lastUser?.content ?? '',
      assistantTurnCount: assistantMessages.length,
      previousAssistantAskedQuestion: previousAssistantAskedQuestion,
      forbidChoiceQuestion: forbidChoiceQuestion,
      questionDesire: questionDesire,
    );
    return ChatFlowPlan(
      intent: intent,
      questionDesire: questionDesire,
      previousAssistantAskedQuestion: previousAssistantAskedQuestion,
      forbidChoiceQuestion: forbidChoiceQuestion,
    );
  }

  ContextBuildResult apply({
    required ContextBuildResult context,
    required ChatFlowPlan plan,
  }) {
    if (context.messages.isEmpty) return context;
    final messages = context.messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    final system = messages.first;
    final original = system['content']?.toString() ?? context.systemPrompt;
    final prompt = '$original\n\n${plan.toPromptSection()}';
    system['content'] = prompt;

    // ignore: avoid_print
    print(
      '[ChatFlowEngine] intent=${plan.intent.name}, '
      'questionDesire=${plan.questionDesire.toStringAsFixed(2)}, '
      'forbidChoice=${plan.forbidChoiceQuestion}',
    );
    return ContextBuildResult(messages: messages, systemPrompt: prompt);
  }

  ReplyIntent _selectIntent({
    required String userText,
    required int assistantTurnCount,
    required bool previousAssistantAskedQuestion,
    required bool forbidChoiceQuestion,
    required double questionDesire,
  }) {
    final text = userText.trim();
    if (_expressesFatigueOrDistress(text)) return ReplyIntent.care;
    if (_invitesNaturalEnding(text)) return ReplyIntent.endNaturally;
    if (previousAssistantAskedQuestion) return ReplyIntent.response;
    if (assistantTurnCount > 0 && assistantTurnCount % 7 == 0) {
      return ReplyIntent.tease;
    }
    if (assistantTurnCount > 0 && assistantTurnCount % 4 == 0) {
      return ReplyIntent.share;
    }
    if (!forbidChoiceQuestion &&
        questionDesire >= 0.2 &&
        assistantTurnCount > 0 &&
        assistantTurnCount % 6 == 0) {
      return ReplyIntent.askQuestion;
    }
    return assistantTurnCount.isEven
        ? ReplyIntent.response
        : ReplyIntent.continueChat;
  }

  static ChatMessage? _lastWhere(
    List<ChatMessage> messages,
    bool Function(ChatMessage message) test,
  ) {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (test(messages[index])) return messages[index];
    }
    return null;
  }

  static bool _containsQuestion(String text) =>
      RegExp(r'[？?]|(吗|么|嘛|呢)[。！!~～]*$').hasMatch(text.trim());

  static bool _containsChoiceQuestion(String text) {
    final hasChoiceWords = RegExp(
      r'还是|或者|是否|要不要|是不是|有没有|能不能|想不想|选一个|二选一',
    ).hasMatch(text);
    return hasChoiceWords;
  }

  static bool _expressesFatigueOrDistress(String text) =>
      RegExp(r'累|疲惫|困死|难受|不舒服|压力|烦|崩溃|委屈|难过').hasMatch(text);

  static bool _invitesNaturalEnding(String text) =>
      RegExp(r'^(嗯+|好+|知道了|行吧|去吧|晚安|先这样|不聊了|回头聊)[。！!~～]*$').hasMatch(text);
}
