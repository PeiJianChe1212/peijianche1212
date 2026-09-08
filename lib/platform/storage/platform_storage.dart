import 'dart:typed_data';

class PlatformStorageEntry {
  const PlatformStorageEntry({required this.key, required this.isContainer});

  final String key;
  final bool isContainer;
}

abstract interface class PlatformStorage {
  String reference(String key);

  Future<bool> exists(String key);
  Future<String> readText(String key);
  Future<Uint8List> readBytes(String key);
  Future<void> writeText(String key, String value);
  Future<void> writeBytes(String key, Uint8List value);

  /// Replaces the complete value without exposing a partially written value.
  Future<void> replaceTextSafely(String key, String value);

  Future<void> delete(String key, {bool recursive = false});
  Future<List<PlatformStorageEntry>> list(String key, {bool recursive = false});
}

/// Marker for adapters where a read/open failure must never be interpreted as
/// missing user data by legacy tolerant readers.
abstract interface class FailFastPlatformStorage implements PlatformStorage {}

sealed class PlatformStorageException implements Exception {
  const PlatformStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class PlatformStorageOpenException extends PlatformStorageException {
  const PlatformStorageOpenException(super.message, [super.cause]);
}

final class PlatformStorageTransactionException
    extends PlatformStorageException {
  const PlatformStorageTransactionException(super.message, [super.cause]);
}

final class PlatformStorageQuotaException extends PlatformStorageException {
  const PlatformStorageQuotaException(super.message, [super.cause]);
}

final class PlatformStorageCorruptedException extends PlatformStorageException {
  const PlatformStorageCorruptedException(super.message, [super.cause]);
}

final class PlatformStorageConflictException extends PlatformStorageException {
  const PlatformStorageConflictException(super.message, [super.cause]);
}

class UnsupportedPlatformStorage implements PlatformStorage {
  const UnsupportedPlatformStorage([this.message = '当前平台尚未实现 PeiLink 存储。']);

  final String message;

  Never _unsupported() => throw UnsupportedError(message);

  @override
  String reference(String key) => _unsupported();
  @override
  Future<bool> exists(String key) async => _unsupported();
  @override
  Future<String> readText(String key) async => _unsupported();
  @override
  Future<Uint8List> readBytes(String key) async => _unsupported();
  @override
  Future<void> writeText(String key, String value) async => _unsupported();
  @override
  Future<void> writeBytes(String key, Uint8List value) async => _unsupported();
  @override
  Future<void> replaceTextSafely(String key, String value) async =>
      _unsupported();
  @override
  Future<void> delete(String key, {bool recursive = false}) async =>
      _unsupported();
  @override
  Future<List<PlatformStorageEntry>> list(
    String key, {
    bool recursive = false,
  }) async => _unsupported();
}
