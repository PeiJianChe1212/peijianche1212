import '../models/character_settings.dart';
import '../models/character_archive.dart';
import '../models/character_profile.dart';
import '../models/user_profile.dart';

/// Character Context 的输入。
///
/// 角色固定设定、用户设定、聊天规则和风格样本统一由这一层承载。
class CharacterContext {
  const CharacterContext({
    required this.settings,
    required this.userProfile,
    this.profile,
    this.archive,
    this.styleExamples = '',
  });

  final CharacterSettings settings;
  final UserProfile userProfile;
  final CharacterProfile? profile;
  final CharacterArchive? archive;
  final String styleExamples;
}
