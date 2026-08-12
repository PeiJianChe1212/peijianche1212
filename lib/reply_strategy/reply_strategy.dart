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
  String toPromptSection() {
    final lengthRule = length == StrategyLength.short
        ? '本轮属于明确的短回复场景，可以用 1 到 2 句自然回应。'
        : '普通聊天默认组织成 2 到 5 句：回应用户内容，补充一点角色自身反应或状态，再按需要自然延续；不要因为用户只发一句就只回一句。';
    return '''【Reply Strategy｜仅控制表达方向】
goal=${goal.key}
tone=${tone.name}
length=${length.name}
question=$question
response_shape=${shape.key}
structure=${shape.structure}
$lengthRule
按照以上结构组织本轮表达；不要复述策略字段，不要把策略当作回复正文。''';
  }
}
