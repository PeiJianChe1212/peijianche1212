import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';
import '../models/group_user_profile.dart';
import 'user_profile_storage_service.dart';

/// 群聊身份的独立存储：`group_chats/<groupId>/user_profile.json`
///
/// 与 messages.json、group_chats.json 完全分离；旧群没有该文件时按默认值
/// 回退，不要求迁移。
class GroupUserProfileStorageService {
  const GroupUserProfileStorageService({required this.groupId});

  final String groupId;

  Future<Directory> _groupDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final groupDirectory = Directory('${directory.path}/group_chats/$groupId');
    if (!await groupDirectory.exists()) {
      await groupDirectory.create(recursive: true);
    }
    return groupDirectory;
  }

  Future<File> _file() async {
    final directory = await _groupDirectory();
    return File('${directory.path}/user_profile.json');
  }

  /// 只读取已持久化的内容（不叠加全局用户资料）。
  Future<GroupUserProfile> load() async {
    final fallback = GroupUserProfile(groupId: groupId);
    try {
      final file = await _file();
      if (!await file.exists()) return fallback;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return fallback;
      return GroupUserProfile.fromJson(decoded, groupId: groupId);
    } catch (_) {
      return fallback;
    }
  }

  /// 展示用：缺省字段按全局 UserProfile 回退，但不写盘、不绑定。
  Future<GroupUserProfile> loadResolved() async {
    final stored = await load();
    if (stored.isEmpty) {
      final user = await UserProfileStorageService().loadProfile();
      return stored.copyWith(
        displayName: user.nickname.trim(),
        avatarPath: user.avatarPath.trim(),
      );
    }
    return stored;
  }

  Future<void> save(GroupUserProfile profile) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }

  /// 头像副本保存在群目录下，避免依赖外部临时路径。
  Future<String> saveAvatarCopy(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return '';
    final directory = await _groupDirectory();
    final avatarDirectory = Directory('${directory.path}/profile');
    if (!await avatarDirectory.exists()) {
      await avatarDirectory.create(recursive: true);
    }
    final extension = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.png';
    final target = File('${avatarDirectory.path}/avatar$extension');
    for (final file in avatarDirectory.listSync().whereType<File>()) {
      if (file.path != target.path) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    await source.copy(target.path);
    return target.path;
  }
}
