import 'dart:io';
import 'dart:typed_data';

import 'platform_storage.dart';

class NativePlatformStorage implements PlatformStorage {
  NativePlatformStorage(this.rootPath);

  final String rootPath;

  String _path(String key) {
    final clean = key.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
    if (clean.split('/').any((part) => part == '..')) {
      throw ArgumentError.value(
        key,
        'key',
        'Storage key must stay inside root',
      );
    }
    return clean.isEmpty
        ? rootPath
        : '$rootPath/${clean.replaceAll('/', Platform.pathSeparator)}';
  }

  @override
  String reference(String key) => _path(key);
  @override
  Future<bool> exists(String key) => File(_path(key)).exists();
  @override
  Future<String> readText(String key) => File(_path(key)).readAsString();
  @override
  Future<Uint8List> readBytes(String key) => File(_path(key)).readAsBytes();
  @override
  Future<void> writeText(String key, String value) async {
    final file = File(_path(key));
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  @override
  Future<void> writeBytes(String key, Uint8List value) async {
    final file = File(_path(key));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(value, flush: true);
  }

  @override
  Future<void> replaceTextSafely(String key, String value) async {
    final file = File(_path(key));
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String key, {bool recursive = false}) async {
    final path = _path(key);
    if (recursive) {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    }
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<PlatformStorageEntry>> list(
    String key, {
    bool recursive = false,
  }) async {
    final directory = Directory(_path(key));
    if (!await directory.exists()) return const [];
    final result = <PlatformStorageEntry>[];
    await for (final entity in directory.list(recursive: recursive)) {
      var relative = entity.path
          .substring(rootPath.length)
          .replaceAll('\\', '/');
      relative = relative.replaceFirst(RegExp(r'^/+'), '');
      result.add(
        PlatformStorageEntry(key: relative, isContainer: entity is Directory),
      );
    }
    return result;
  }
}
