import 'reply_intent.dart';

class ChatFlowPlan {
  const ChatFlowPlan({
    required this.intent,
    required this.questionDesire,
    required this.previousAssistantAskedQuestion,
    required this.forbidChoiceQuestion,
  });

  final ReplyIntent intent;
  final double questionDesire;
  final bool previousAssistantAskedQuestion;
  final bool forbidChoiceQuestion;

  bool get shouldAvoidQuestion =>
      intent != ReplyIntent.askQuestion || questionDesire < 0.15;

  String toPromptSection() {
    final questionRule = shouldAvoidQuestion
        ? '本轮不要为了推进而提问。先接住用户的话，可以陈述、分享、安慰或自然停住。'
        : '只有问题确实比陈述更自然时，才允许提出一个简短问题。';
    final previousQuestionRule = previousAssistantAskedQuestion
        ? '上一轮角色已经提问，本轮优先回应用户的答案，不要紧接着抛出新问题。'
        : '';
    final choiceRule = forbidChoiceQuestion
        ? '本轮禁止生成“还是”“是否”“要不要”等二选一或选择题结构。'
        : '避免不必要的二选一问题。';

    return '''【Chat Flow｜本轮回复节奏】
回复意图：${intent.label}
Question Desire：${questionDesire.toStringAsFixed(2)}（越低越不应提问）
$questionRule
$previousQuestionRule
$choiceRule
允许只回复自然短句；不要求每轮开启新话题或强行推进聊天。''';
  }
}
