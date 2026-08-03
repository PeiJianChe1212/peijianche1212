enum ReplyGoal {
  acknowledge,
  comfort,
  share,
  tease,
  romance,
  explain,
  continueChat,
  close,
}

extension ReplyGoalKey on ReplyGoal {
  /// `continue` 是 Dart 保留字，因此代码使用 continueChat，对外仍输出 continue。
  String get key => switch (this) {
    ReplyGoal.acknowledge => 'acknowledge',
    ReplyGoal.comfort => 'comfort',
    ReplyGoal.share => 'share',
    ReplyGoal.tease => 'tease',
    ReplyGoal.romance => 'romance',
    ReplyGoal.explain => 'explain',
    ReplyGoal.continueChat => 'continue',
    ReplyGoal.close => 'close',
  };
}
