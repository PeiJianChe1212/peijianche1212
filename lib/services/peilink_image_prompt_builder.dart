import '../models/peilink_character_visual_profile.dart';
import '../models/peilink_visual_intent.dart';

class PeiLinkImagePromptBuilder {
  const PeiLinkImagePromptBuilder._();

  static const defaultStyle = '半写实 2.5D、高级 CG、轻插画质感；自然生活摄影构图，空间和材质可信，光影自然。';

  static String build({
    required PeiLinkVisualIntent intent,
    PeiLinkVisualContext context = const PeiLinkVisualContext(),
  }) {
    if (intent.visualFocus.trim().isEmpty) return '';
    final sections = <String>[
      '【图片主体】\n${intent.visualFocus.trim()}',
      if (intent.mood.trim().isNotEmpty)
        '【画面氛围】\n用构图、光影和环境表达“${intent.mood.trim()}”，不额外编造天气、时间、共同经历或剧情物件。',
      '【人物出镜】\n${_presenceRule(intent.characterPresence)}',
    ];

    if (intent.characterPresence == PeiLinkCharacterPresence.required) {
      final facts = <String>[];
      for (final id in intent.requiredCharacterIds.toSet()) {
        final profile = context.characterProfiles[id];
        facts.add(
          profile == null
              ? '角色 $id：外观保持中性、非具体化，不新增发色、发型、瞳色、纹身、首饰或特殊服装。'
              : _visualFacts(
                  profile,
                  includeEyes: intent.includeEyes,
                  includeClothing: intent.includeClothing,
                  includeBodyProportions: intent.includeBodyProportions,
                ),
        );
      }
      sections.add(
        '【必要角色视觉资料】\n${facts.where((value) => value.trim().isNotEmpty).join('\n\n')}',
      );
    }

    sections.add(
      '''
【构图与视觉风格】
${intent.compositionHint.trim().isEmpty ? '生活记录式构图，优先第一视角、观察视角和自然的不完整构图，不做电影海报、游戏宣传立绘或明星写真。' : intent.compositionHint.trim()}
$defaultStyle
避免真人摄影、照片级真实人脸、纯日漫平涂、Q 版、儿童插画和宣传海报式构图。无文字、无水印、无二维码。

【事实边界】
只使用上面的主体、场景和角色视觉事实；不得改变发色、瞳色和稳定外貌，不新增纹身、关键首饰或共同经历。为完成画面补充的普通环境细节保持中性，且不得反向成为 PeiLink 世界事实。
'''
          .trim(),
    );
    return sections.join('\n\n');
  }

  static String _presenceRule(
    PeiLinkCharacterPresence presence,
  ) => switch (presence) {
    PeiLinkCharacterPresence.none => '画面中不出现人物，不出现正脸、背影或人物剪影；只记录环境、物品或景色。',
    PeiLinkCharacterPresence.optional =>
      '人物不是必需主体；优先无人画面。如确有构图必要，只允许远景、背影、手部或被环境遮挡的局部人物。',
    PeiLinkCharacterPresence.required =>
      '只允许 requiredCharacterIds 中的角色出镜；人物需要出现，但仅自拍、穿搭或明确人物主题可成为中心，其他情况优先手部、背影、局部侧脸、镜面局部或人物远景。',
  };

  static String _visualFacts(
    PeiLinkCharacterVisualProfile profile, {
    required bool includeEyes,
    required bool includeClothing,
    required bool includeBodyProportions,
  }) => <String>[
    '角色 ID：${profile.characterId}',
    if (profile.gender.isNotEmpty) '性别：${profile.gender}',
    if (profile.ageAppearance.isNotEmpty) '年龄感：${profile.ageAppearance}',
    if (includeBodyProportions && profile.height.isNotEmpty)
      '身高：${profile.height}',
    if (includeBodyProportions && profile.bodyType.isNotEmpty)
      '体型：${profile.bodyType}',
    if (profile.overallAppearance.isNotEmpty)
      '稳定外貌：${profile.overallAppearance}',
    if (profile.hairColor.isNotEmpty) '发色：${profile.hairColor}',
    if (profile.hairStyle.isNotEmpty) '发型：${profile.hairStyle}',
    if (includeEyes && profile.eyeColor.isNotEmpty) '瞳色：${profile.eyeColor}',
    if (profile.stableMarks.isNotEmpty) '关键稳定特征：${profile.stableMarks}',
    if (includeClothing && profile.clothingStyle.isNotEmpty)
      '已有穿衣风格：${profile.clothingStyle}',
  ].join('\n');
}
