import 'dart:io';

import 'character_scope_service.dart';

class CharacterAvatarStorageService {
  const CharacterAvatarStorageService();

  Future<String> saveAvatar({
    required String characterId,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('选择的头像文件不存在。');
    }

    final directory =
        await CharacterScopeService(characterId).avatarDirectory();
    final extension = _extensionOf(source.path);
    final target = File('${directory.path}/avatar$extension');

    for (final file in directory.listSync().whereType<File>()) {
      if (file.path != target.path &&
          file.path.split(Platform.pathSeparator).last.startsWith('avatar.')) {
        await file.delete();
      }
    }

    await source.copy(target.path);
    return target.path;
  }

  Future<void> removeAvatar(String characterId) async {
    final directory =
        await CharacterScopeService(characterId).avatarDirectory();
    if (!await directory.exists()) return;

    for (final file in directory.listSync().whereType<File>()) {
      if (file.path.split(Platform.pathSeparator).last.startsWith('avatar.')) {
        await file.delete();
      }
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
        ? extension
        : '.jpg';
  }
}
