/// Response Strategy Context 的第一阶段占位实现。
///
/// 当前继续承载原有时间、场景、活动、人格参数和回复长度规则。
class ResponseStrategyContext {
  const ResponseStrategyContext({
    required this.dynamicPrompt,
    required this.mediaRules,
  });

  final String dynamicPrompt;
  final String mediaRules;

  String buildPromptSection() => '$dynamicPrompt\n\n$mediaRules';
}
