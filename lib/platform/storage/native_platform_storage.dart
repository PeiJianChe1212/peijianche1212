import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'platform_storage.dart';

class NativePlatformStorage implements PlatformStorage {
  NativePlatformStorage(this.rootPath);

  final String rootPath;
  static final Random _temporaryRandom = Random.secure();
  static int _temporaryCounter = 0;

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
  Future<String> readText(String key) =>
      _withSharingRetry(() => File(_path(key)).readAsString());
  @override
  Future<Uint8List> readBytes(String key) =>
      _withSharingRetry(() => File(_path(key)).readAsBytes());
  @override
  Future<void> writeText(String key, String value) =>
      _replaceBytes(key, utf8.encode(value));

  @override
  Future<void> writeBytes(String key, Uint8List value) =>
      _replaceBytes(key, value);

  @override
  Future<void> replaceTextSafely(String key, String value) =>
      writeText(key, value);

  Future<void> _replaceBytes(String key, List<int> value) async {
    final file = File(_path(key));
    await file.parent.create(recursive: true);
    // Counter separates overlapping operations; random suffix also separates
    // isolates/processes. Keep staging beside the target on the same volume.
    final nonce = List.generate(
      4,
      (_) =>
          _temporaryRandom.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
    final temporary = File(
      '${file.path}.$pid.${_temporaryCounter++}.$nonce.tmp',
    );
    try {
      await temporary.writeAsBytes(value, flush: true);
      await _withSharingRetry(() => temporary.rename(file.path));
    } finally {
      // Never delete the destination or another writer's staging file. A
      // concurrent directory deletion may already have removed this file.
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Preserve the original write/rename failure if cleanup cannot finish.
      }
    }
  }

  Future<T> _withSharingRetry<T>(Future<T> Function() operation) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } on FileSystemException catch (error) {
        // Windows can briefly deny either a read or replacement while another
        // operation holds a handle. Never delete the target to unlock it.
        // Permanent errors still propagate within a bounded time.
        if (!Platform.isWindows ||
            ![5, 32, 33].contains(error.osError?.errorCode) ||
            attempt >= 5) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 10 * (1 << attempt)));
      }
    }
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
