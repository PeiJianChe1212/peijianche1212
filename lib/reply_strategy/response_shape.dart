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
    ResponseShape.briefAcknowledgement => '接住用户表达；可以到此停住',
    ResponseShape.emotionalSupport => '回应情绪；一句关心；可选分享',
    ResponseShape.casualChat => '回应；轻松交流；可选延伸',
    ResponseShape.directExplanation => '直接回应核心；必要说明；简短收束',
    ResponseShape.intimateExpression => '接住情绪；自然表达亲密；不过度展开',
    ResponseShape.naturalClose => '简短回应；自然结束',
  };
}
