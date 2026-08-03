/// Relationship Context 的输入。
///
/// 第一阶段仅接入现有关系、共享世界和多角色协议，不改变其生成逻辑。
class RelationshipContext {
  const RelationshipContext({
    this.echoContext = '',
    this.sharedWorldContext = '',
    this.relationshipState = '',
    this.socialProtocol = '',
  });

  final String echoContext;
  final String sharedWorldContext;
  final String relationshipState;
  final String socialProtocol;

  String buildPromptSection() =>
      '$echoContext\n\n$sharedWorldContext\n\n$relationshipState\n\n$socialProtocol';
}
