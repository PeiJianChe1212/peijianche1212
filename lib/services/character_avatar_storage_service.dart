import 'dart:io';
import 'dart:typed_data';

import '../platform/media/media_store.dart';
import '../platform/media/media_store_factory.dart';
import 'character_scope_service.dart';

class CharacterAvatarStorageService {
  const CharacterAvatarStorageService({this.mediaStore});

  final MediaStore? mediaStore;
  MediaStore get _media => mediaStore ?? createDefaultMediaStore();

  Future<String> saveAvatar({
    required String characterId,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('选择的头像文件不存在。');
    }

    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
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
    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
    final target = File('${directory.path}/avatar.png');
    await _removeFilesWithPrefix(directory, 'avatar.', exceptPath: target.path);
    return _media.saveBytes(target.path, bytes);
  }

  Future<String> savePendingAvatarBytes({
    required String characterId,
    required Uint8List bytes,
  }) async {
    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
    final target = File('${directory.path}/pending_avatar.png');
    return _media.saveBytes(target.path, bytes);
  }

  Future<String> acceptPendingAvatar({required String characterId}) async {
    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
    final pending = File('${directory.path}/pending_avatar.png');
    if (!await pending.exists()) throw StateError('待确认头像不存在。');
    final bytes = await _media.readBytes(pending.path);
    final path = await saveAvatarBytes(characterId: characterId, bytes: bytes);
    await _media.delete(pending.path);
    return path;
  }

  Future<String> acceptPendingSocialAvatar({
    required String characterId,
  }) async {
    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
    final pending = File('${directory.path}/pending_avatar.png');
    if (!await pending.exists()) throw StateError('待确认头像不存在。');
    final bytes = await _media.readBytes(pending.path);
    final target = File(
      '${directory.path}/social_avatar_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    final path = await _media.saveBytes(target.path, bytes);
    await _media.delete(pending.path);
    return path;
  }

  Future<String> saveSocialAvatarBytes({
    required String characterId,
    required Uint8List bytes,
  }) async {
    final directory = await CharacterScopeService(characterId).avatarDirectory();
    final target = File('${directory.path}/social_avatar.png');
    await _removeFilesWithPrefix(
      directory,
      'social_avatar',
      exceptPath: target.path,
    );
    return _media.saveBytes(target.path, bytes);
  }

  Future<void> clearPendingAvatar(String characterId) async {
    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
    final pending = File('${directory.path}/pending_avatar.png');
    if (await _media.exists(pending.path)) await _media.delete(pending.path);
  }

  Future<String> savePortrait({
    required String characterId,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('选择的角色图片不存在。');
    }

    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
    final extension = _extensionOf(source.path);
    final target = File('${directory.path}/portrait$extension');
    await _removeFilesWithPrefix(
      directory,
      'portrait.',
      exceptPath: target.path,
    );
    await source.copy(target.path);
    return target.path;
  }

  Future<String> savePortraitBytes({
    required String characterId,
    required Uint8List bytes,
  }) async {
    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
    final target = File('${directory.path}/portrait.png');
    await _removeFilesWithPrefix(
      directory,
      'portrait.',
      exceptPath: target.path,
    );
    return _media.saveBytes(target.path, bytes);
  }

  Future<void> removeAvatar(String characterId) async {
    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
    if (!await directory.exists()) return;
    await _removeFilesWithPrefix(directory, 'avatar.');
  }

  Future<void> removePortrait(String characterId) async {
    final directory = await CharacterScopeService(
      characterId,
    ).avatarDirectory();
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
