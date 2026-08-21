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
        ? '本轮属于明确的短回复场景，可以用 1 到 2 句自然回应；一句话本身信息已经足够时不要硬加内容。'
        : '按真人聊天节奏动态决定长度：约 60% 使用 1 到 2 句，约 30% 使用 3 到 5 句，只有剧情、强情绪或重要事件等约 10% 的场景才展开成长回复。普通聊天以 1 到 3 句为主，不要固定成同一种段落。';
    return '''【Reply Strategy｜仅控制表达方向】
goal=${goal.key}
tone=${tone.name}
length=${length.name}
question=$question
response_shape=${shape.key}
structure=${shape.structure}
$lengthRule
普通聊天先直接回应用户。除简单确认、接梗、明确短答或自然结束外，再自然补充至少一个有信息的维度：当前状态、轻量生活细节、角色观点、情绪反馈或相关延续。
短回复也要有内容密度，不能长期停在“回答一句”或“回答一句加反问”。反问不能作为唯一的内容延展；如果近期回复已经连续用问句收尾，本轮优先用陈述、分享或接梗继续。
可以自然提到“刚刚、今天、本来、正准备、刚看到、想到、等会儿”等生活时间线，但只能补充轻量日常细节，不得为了陪伴感虚构重大事件、重要承诺或未提供的世界事实。
【Reply Segments】
你正在生成聊天消息流，不是一整段文章。表达只有一个简短信息点时输出一个气泡；有2到3个自然信息点时，优先拆成2到3个气泡。普通聊天约70%输出1到3个气泡，约20%输出3到5个气泡，只有特殊剧情或强情绪等少数场景才允许更多。
多个气泡之间必须只使用分隔符 <|PEILINK_MSG|>，例如：刚忙完。<|PEILINK_MSG|>本来想休息一下。<|PEILINK_MSG|>结果先看到你的消息了。
不要输出JSON、数组、编号或“消息1”等标签。简单回应、接梗、玩笑和“嗯”“哈哈”“知道了”保持单气泡；不要为了拆分而刷屏，也不要把一句完整的话从中间切断。
按照以上结构组织本轮表达；不要复述策略字段，不要把策略当作回复正文。''';
  }
}
