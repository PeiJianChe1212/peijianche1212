import '../models/character_user_profile.dart';
import '../models/memory_retrieval_result.dart';
import '../models/user_memory.dart';
import 'memory2_retriever.dart';

class Memory2ChatContextBuilder {
  const Memory2ChatContextBuilder._();

  static const int characterUserProfileCharacters = 800;

  static String build({
    required MemoryRetrievalResult retrieval,
    required CharacterUserProfile characterUserProfile,
  }) {
    final sections = <String>[
      retrieval.contextText.trim(),
      _currentFacts(retrieval),
      _characterUserProfile(characterUserProfile),
    ].where((item) => item.isNotEmpty).toList(growable: false);
    if (sections.isEmpty) return '';
    return '''【Memory 2.0｜仅作为已知事实，不得扩写】
冲突优先级：用户手写角色世界设定 > 关于用户的记忆 > 全局用户资料。
当前 active 用户事实优先于长期汇总（Summary）中的旧事实及历史事实。历史事实仅用于回答过去，不得当作当前状态；若无当前依据，不从历史推断现在。
Summary 是长期概括，可能滞后，其中使用“目前”“现在”等措辞也不代表已经更新。如果 Summary 与下方“当前用户事实”中的同一事实冲突，回答现在或当前的问题必须采用当前用户事实，不得采用冲突的 Summary 旧值。Summary 中不冲突的信息仍可使用；正确的过去与现在描述仍可用于回答历史问题。

${sections.join('\n\n')}''';
  }

  // Reaffirm only facts already selected by retrieval, not the whole store.
  // This labels authority without guessing which Summary sentences to delete.
  static String _currentFacts(MemoryRetrievalResult retrieval) {
    final lines = retrieval.selectedUserMemories
        .where((item) => item.status == UserMemoryStatus.active)
        .take(Memory2Retriever.maximumUserMemories)
        .map((item) {
          final text = item.displayText.trim();
          final limit = Memory2Retriever.userItemCharacters;
          return text.length <= limit
              ? text
              : '${text.substring(0, limit - 1).trimRight()}…';
        })
        .where((text) => text.isNotEmpty)
        .map((text) => '- 当前：$text')
        .toList(growable: false);
    if (lines.isEmpty) return '';
    return '【当前用户事实｜active，优先于 Summary 中的旧值】\n${lines.join('\n')}';
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
