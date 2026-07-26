import 'dart:io';
import 'dart:typed_data';

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
    await _removeFilesWithPrefix(directory, 'avatar.', exceptPath: target.path);
    await source.copy(target.path);
    return target.path;
  }

  Future<String> saveAvatarBytes({
    required String characterId,
    required Uint8List bytes,
  }) async {
    final directory =
        await CharacterScopeService(characterId).avatarDirectory();
    final target = File('${directory.path}/avatar.png');
    await _removeFilesWithPrefix(directory, 'avatar.', exceptPath: target.path);
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<String> savePortrait({
    required String characterId,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('选择的角色图片不存在。');
    }

    final directory =
        await CharacterScopeService(characterId).avatarDirectory();
    final extension = _extensionOf(source.path);
    final target = File('${directory.path}/portrait$extension');
    await _removeFilesWithPrefix(directory, 'portrait.', exceptPath: target.path);
    await source.copy(target.path);
    return target.path;
  }

  Future<void> removeAvatar(String characterId) async {
    final directory =
        await CharacterScopeService(characterId).avatarDirectory();
    if (!await directory.exists()) return;
    await _removeFilesWithPrefix(directory, 'avatar.');
  }

  Future<void> removePortrait(String characterId) async {
    final directory =
        await CharacterScopeService(characterId).avatarDirectory();
    if (!await directory.exists()) return;
    await _removeFilesWithPrefix(directory, 'portrait.');
  }

  Future<void> _removeFilesWithPrefix(
    Directory directory,
    String prefix, {
    String? exceptPath,
  }) async {
    if (!await directory.exists()) return;
    for (final file in directory.listSync().whereType<File>()) {
      final name = file.path.split(Platform.pathSeparator).last;
      if (name.startsWith(prefix) && file.path != exceptPath) {
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
