import 'dart:io';

import '../platform/media/media_store.dart';
import '../platform/media/media_store_factory.dart';
import 'character_scope_service.dart';

/// 将聊天中选择的图片复制到角色自己的长期目录。
///
/// image_picker 返回的路径可能只是系统临时文件，不能直接拿来长期保存。
class ChatImageStorageService {
  const ChatImageStorageService({this.characterId, this.mediaStore});

  final String? characterId;
  final MediaStore? mediaStore;
  MediaStore get _media => mediaStore ?? createDefaultMediaStore();

  Future<Directory> imageDirectory() async {
    final characterDirectory = await CharacterScopeService(
      characterId,
    ).characterDirectory();
    final directory = Directory('${characterDirectory.path}/chat_images');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String> saveImage({
    required String sourcePath,
    required String messageId,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('选择的图片已经不存在。');
    }

    final imageDirectory = await this.imageDirectory();

    final extension = _extensionOf(sourcePath);
    final target = File(
      '${imageDirectory.path}/${messageId}_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    return _media.saveBytes(target.path, await source.readAsBytes());
  }

  Future<void> deleteImage(String path) async {
    if (path.trim().isEmpty) return;
    if (!await _media.exists(path)) return;
    try {
      await _media.delete(path);
    } catch (_) {
      // 图片清理失败不应阻断聊天回溯或重置。
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    const supported = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
    return supported.contains(extension) ? extension : '.jpg';
  }
}
