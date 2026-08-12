enum ResponseShape {
  briefAcknowledgement,
  emotionalSupport,
  casualChat,
  directExplanation,
  intimateExpression,
  naturalClose,
}

extension ResponseShapeStrategy on ResponseShape {
  String get key => switch (this) {
    ResponseShape.briefAcknowledgement => 'brief_acknowledgement',
    ResponseShape.emotionalSupport => 'emotional_support',
    ResponseShape.casualChat => 'casual_chat',
    ResponseShape.directExplanation => 'direct_explanation',
    ResponseShape.intimateExpression => 'intimate_expression',
    ResponseShape.naturalClose => 'natural_close',
  };

  String get structure => switch (this) {
    ResponseShape.briefAcknowledgement => '接住用户表达；补充一点角色反应或状态；自然承接',
    ResponseShape.emotionalSupport => '回应情绪；具体关心；补充陪伴或角色反应',
    ResponseShape.casualChat => '回应具体内容；轻松交流；自然延伸一点',
    ResponseShape.directExplanation => '直接回应核心；必要说明；简短收束',
    ResponseShape.intimateExpression => '接住情绪；自然表达亲密；补充真实反应',
    ResponseShape.naturalClose => '简短回应；自然结束',
  };
}
