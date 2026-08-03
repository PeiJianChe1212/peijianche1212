import 'reply_goal.dart';
import 'response_shape.dart';

enum ReplyTone { natural, gentle, playful, warm, clear }

enum StrategyLength { short, medium }

class ReplyStrategy {
  const ReplyStrategy({
    required this.goal,
    required this.tone,
    required this.length,
    required this.question,
    required this.shape,
  });

  final ReplyGoal goal;
  final ReplyTone tone;
  final StrategyLength length;
  final bool question;
  final ResponseShape shape;

  /// 只描述表达方向，不提供或生成具体回复文本。
  String toPromptSection() =>
      '''【Reply Strategy｜仅控制表达方向】
goal=${goal.key}
tone=${tone.name}
length=${length.name}
question=$question
response_shape=${shape.key}
structure=${shape.structure}
按照以上结构组织本轮表达；不要复述策略字段，不要把策略当作回复正文。''';
}
