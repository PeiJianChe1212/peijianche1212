enum ReplyIntent {
  response,
  share,
  care,
  tease,
  continueChat,
  askQuestion,
  endNaturally,
}

extension ReplyIntentLabel on ReplyIntent {
  String get label => switch (this) {
    ReplyIntent.response => '回应用户',
    ReplyIntent.share => '分享自己',
    ReplyIntent.care => '关心陪伴',
    ReplyIntent.tease => '自然调侃',
    ReplyIntent.continueChat => '延续交流',
    ReplyIntent.askQuestion => '提出问题',
    ReplyIntent.endNaturally => '自然收尾',
  };
}
