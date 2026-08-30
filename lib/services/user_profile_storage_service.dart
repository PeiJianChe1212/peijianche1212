import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/user_profile.dart';

class UserProfileStorageService {
  Future<File> _profileFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/user_profile.json');
  }

  Future<UserProfile> loadProfile() async {
    final file = await _profileFile();
    if (!await file.exists()) {
      const defaults = UserProfile();
      await saveProfile(defaults);
      return defaults;
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const UserProfile();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const UserProfile();
      var profile = UserProfile.fromJson(decoded);
      if (PeiLinkRuntime.build == PeiLinkBuild.user) {
        final sanitized = _removeLegacyDeveloperValues(profile);
        if (sanitized.toJson().toString() != profile.toJson().toString()) {
          await saveProfile(sanitized);
          profile = sanitized;
        }
      }
      return profile;
    } catch (_) {
      return const UserProfile();
    }
  }

  UserProfile _removeLegacyDeveloperValues(UserProfile profile) =>
      profile.copyWith(
        nickname: profile.nickname == '念念' ? '未设置' : profile.nickname,
        peiLinkId: profile.peiLinkId == '一只小狐念' ? '未设置' : profile.peiLinkId,
        peiCallName: profile.peiCallName == '念念' ? '未填写' : profile.peiCallName,
        identity: profile.identity == '裴简澈的恋人' ? '未填写' : profile.identity,
      );

  Future<void> saveProfile(UserProfile profile) async {
    final file = await _profileFile();
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }

  Future<String> saveAvatarCopy(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return '';

    final directory = await getApplicationDocumentsDirectory();
    final avatarDirectory = Directory('${directory.path}/profile');
    if (!await avatarDirectory.exists()) {
      await avatarDirectory.create(recursive: true);
    }

    final extension = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.jpg';
    final target = File('${avatarDirectory.path}/avatar$extension');

    for (final file in avatarDirectory.listSync().whereType<File>()) {
      if (file.path != target.path && file.path.contains('avatar.')) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    await source.copy(target.path);
    return target.path;
  }
}
