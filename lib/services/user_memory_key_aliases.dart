/// Retrieval-only hints for common stable facts supported by extraction.
/// Exact key groups keep unknown keys and broad keys such as `喜欢` unchanged.
/// Hints are neither persisted nor added to the prompt.
abstract final class UserMemoryKeyAliases {
  static double relevance(String key, String query) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    final text = query.toLowerCase();
    // A topic mentioned in a document or a general question is not enough to
    // introduce a personal fact (e.g. "这张图片是什么颜色").
    if (!RegExp(
      r'我|喜欢|偏好|最爱|忌口|习惯|爱好|称呼|\b(my|me|favorite|favourite|prefer)\b',
    ).hasMatch(text)) {
      return 0;
    }
    for (final group in _groups) {
      if (group.keys.contains(normalized) && group.topic.hasMatch(text)) {
        return 0.32;
      }
    }
    return 0;
  }

  static final _groups = <_KeyAliasGroup>[
    _KeyAliasGroup(
      'favoritecolor favouritecolor colorpreference colourpreference 喜欢的颜色 最喜欢的颜色 颜色偏好',
      r'颜色|\b(colou?r|colou?rs)\b',
    ),
    _KeyAliasGroup(
      'favoritefood favouritefood foodpreference 喜欢的食物 最喜欢的食物 食物偏好',
      r'食物|吃什么|爱吃|喜欢吃|\b(food|foods|eat)\b',
    ),
    _KeyAliasGroup(
      'favoritedrink favouritedrink drinkpreference beveragepreference 喜欢的饮品 偏好饮品 饮品 饮品偏好',
      r'饮品|饮料|喝什么|爱喝|喜欢喝|\b(drink|drinks|beverage|beverages)\b',
    ),
    _KeyAliasGroup(
      'favoritegame favouritegame gamepreference gamingpreference 游戏偏好 喜欢的游戏',
      r'游戏|\b(game|games|gaming)\b',
    ),
    _KeyAliasGroup(
      'hobby hobbies interests 爱好 兴趣 兴趣爱好',
      r'爱好|兴趣|\b(hobby|hobbies|interests)\b',
    ),
    _KeyAliasGroup(
      'dietaryrestriction dietaryrestrictions 忌口 饮食禁忌',
      r'忌口|禁忌|不吃|不能吃|\b(dietary|restrictions|avoid)\b',
    ),
    _KeyAliasGroup(
      'habit habits workhabit workhabits 习惯 工作习惯',
      r'习惯|\b(habit|habits|routine)\b',
    ),
    _KeyAliasGroup(
      'name nickname preferredname callname 姓名 昵称 称呼',
      r'姓名|名字|昵称|称呼|叫什么|怎么叫|\b(name|nickname|call)\b',
    ),
  ];
}

class _KeyAliasGroup {
  _KeyAliasGroup(String keys, String topic)
    : keys = keys.split(' ').toSet(),
      topic = RegExp(topic);

  final Set<String> keys;
  final RegExp topic;
}
