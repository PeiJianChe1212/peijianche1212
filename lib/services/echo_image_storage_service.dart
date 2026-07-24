import 'dart:io';

import 'character_scope_service.dart';

class EchoImageStorageService {
  const EchoImageStorageService({this.characterId});

  final String? characterId;

  Future<String> saveImage({
    required String sourcePath,
    required String echoId,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('选择的图片已经不存在。');
    }

    final characterDirectory =
        await CharacterScopeService(characterId).characterDirectory();
    final imageDirectory = Directory('${characterDirectory.path}/echo_images');
    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }

    final extension = _extensionOf(sourcePath);
    final target = File(
      '${imageDirectory.path}/${echoId}_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await source.copy(target.path);
    return target.path;
  }

  Future<void> deleteImages(Iterable<String> paths) async {
    for (final path in paths) {
      if (path.trim().isEmpty) continue;
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // 图片清理失败不应阻断动态删除。
        }
      }
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    if (extension.length > 6) return '.jpg';
    return extension;
  }
}
