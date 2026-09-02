import '../models/character_user_profile.dart';
import '../models/memory_retrieval_result.dart';

class Memory2ChatContextBuilder {
  const Memory2ChatContextBuilder._();

  static const int characterUserProfileCharacters = 800;

  static String build({
    required MemoryRetrievalResult retrieval,
    required CharacterUserProfile characterUserProfile,
  }) {
    final sections = <String>[
      retrieval.contextText.trim(),
      _characterUserProfile(characterUserProfile),
    ].where((item) => item.isNotEmpty).toList(growable: false);
    if (sections.isEmpty) return '';
    return '''【Memory 2.0｜仅作为已知事实，不得扩写】
冲突优先级：用户手写角色世界设定 > 关于用户的记忆 > 全局用户资料。

${sections.join('\n\n')}''';
  }

  static String _characterUserProfile(CharacterUserProfile profile) {
    String line(String label, String value) {
      final clean = value.trim();
      if (clean.isEmpty || clean == '未填写' || clean == '未设置') return '';
      return '$label：$clean';
    }

    final lines = <String>[
      line('用户姓名', profile.userName),
      line('性别', profile.gender),
      line('角色对用户的称呼', profile.callName),
      line('角色与用户的关系', profile.relationship),
      line('用户身份', profile.identity),
      line('所在世界', profile.world),
      line('用户设定', profile.effectiveDescription),
    ].where((item) => item.isNotEmpty).join('\n');
    if (lines.isEmpty) return '';
    final text = '【用户手写角色世界设定｜最高优先级】\n$lines';
    if (text.length <= characterUserProfileCharacters) return text;
    return '${text.substring(0, characterUserProfileCharacters - 1).trimRight()}…';
  }
}
