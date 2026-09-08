import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'platform_storage.dart';

/// IndexedDB storage. Business JSON is split by logical path; revisions stay
/// in metadata and are checked in the same transaction as each replacement.
final class WebIndexedDbPlatformStorage implements FailFastPlatformStorage {
  WebIndexedDbPlatformStorage._(this.namespace, this._database);

  static const databaseName = 'peilink_local';
  static const databaseVersion = 1;
  static const objectStoreName = 'entries';

  final String namespace;
  final IDBDatabase _database;
  final Map<String, int> _observedRevisions = {};

  static Future<WebIndexedDbPlatformStorage> open(String namespace) async {
    final indexedDb = globalContext.getProperty<JSAny?>('indexedDB'.toJS);
    if (indexedDb == null) {
      throw UnsupportedError('当前浏览器不支持 IndexedDB，无法保存 PeiLink 数据。');
    }
    try {
      final request = (indexedDb as IDBFactory).open(
        databaseName,
        databaseVersion,
      );
      request.onupgradeneeded = ((Event _) {
        final database = request.result as IDBDatabase;
        if (!database.objectStoreNames.contains(objectStoreName)) {
          database.createObjectStore(objectStoreName);
        }
      }).toJS;
      final database = await _request(request) as IDBDatabase;
      return WebIndexedDbPlatformStorage._(
        _normalizeNamespace(namespace),
        database,
      );
    } catch (error) {
      throw PlatformStorageOpenException('无法打开 PeiLink 浏览器数据库。', error);
    }
  }

  static Future<JSAny?> _request(IDBRequest request) {
    final completer = Completer<JSAny?>.sync();
    request.onsuccess = ((Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          request.error ?? StateError('IndexedDB request failed'),
        );
      }
    }).toJS;
    return completer.future;
  }

  static Future<void> _completed(IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    void fail(Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          transaction.error ?? StateError('IndexedDB transaction failed'),
        );
      }
    }

    transaction.onerror = fail.toJS;
    transaction.onabort = fail.toJS;
    return completer.future;
  }

  static String _normalizeNamespace(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'peilink_user';
    if (normalized.contains('/') || normalized.contains('::')) {
      throw ArgumentError.value(value, 'namespace', 'Invalid namespace');
    }
    return normalized;
  }

  String _logicalKey(String key) {
    final clean = key.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
    if (clean.split('/').any((part) => part == '..') || clean.contains('::')) {
      throw ArgumentError.value(key, 'key', 'Key must stay inside namespace');
    }
    return clean;
  }

  String _databaseKey(String key) => '$namespace::${_logicalKey(key)}';

  Map<String, Object?> _record(JSAny? value, String key) {
    final dartValue = value?.dartify();
    if (dartValue is! Map) {
      throw PlatformStorageCorruptedException('浏览器存储记录损坏：$key');
    }
    final record = Map<String, Object?>.from(dartValue);
    if (record['revision'] is! num || record['payloadType'] is! String) {
      throw PlatformStorageCorruptedException('浏览器存储元数据损坏：$key');
    }
    record['revision'] = (record['revision']! as num).toInt();
    return record;
  }

  Future<JSAny?> _get(String key, {bool observe = true}) async {
    final logical = _logicalKey(key);
    try {
      final transaction = _database.transaction(
        objectStoreName.toJS,
        'readonly',
      );
      final completion = _completed(transaction);
      final value = await _request(
        transaction
            .objectStore(objectStoreName)
            .get(_databaseKey(logical).toJS),
      );
      await completion;
      if (value != null && observe) {
        _observedRevisions[logical] =
            _record(value, logical)['revision']! as int;
      }
      return value;
    } catch (error) {
      if (error is PlatformStorageException) rethrow;
      throw PlatformStorageTransactionException('读取浏览器存储失败：$logical', error);
    }
  }

  Future<void> _put(String key, String type, Object payload) async {
    final logical = _logicalKey(key);
    final expectedRevision = _observedRevisions[logical];
    try {
      final transaction = _database.transaction(
        objectStoreName.toJS,
        'readwrite',
      );
      final completion = _completed(transaction);
      final store = transaction.objectStore(objectStoreName);
      final currentValue = await _request(
        store.get(_databaseKey(logical).toJS),
      );
      final current = currentValue == null
          ? null
          : _record(currentValue, logical);
      final currentRevision = current?['revision'] as int? ?? 0;
      if (expectedRevision != null && currentRevision != expectedRevision) {
        transaction.abort();
        try {
          await completion;
        } catch (_) {}
        throw PlatformStorageConflictException(
          '数据已在其他标签页更新，请重新加载后再保存：$logical',
        );
      }
      await _request(
        store.put(
          <String, Object?>{
            'payloadType': type,
            'payload': payload,
            'revision': currentRevision + 1,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          }.jsify(),
          _databaseKey(logical).toJS,
        ),
      );
      await completion;
      _observedRevisions[logical] = currentRevision + 1;
    } catch (error) {
      if (error is PlatformStorageConflictException ||
          error is PlatformStorageCorruptedException) {
        rethrow;
      }
      if (error.toString().contains('QuotaExceededError')) {
        throw PlatformStorageQuotaException('浏览器存储空间不足，数据未保存。', error);
      }
      throw PlatformStorageTransactionException('写入浏览器存储失败：$logical', error);
    }
  }

  @override
  String reference(String key) =>
      'indexeddb://$databaseName/$objectStoreName/${_databaseKey(key)}';

  @override
  Future<bool> exists(String key) async => await _get(key) != null;

  @override
  Future<String> readText(String key) async {
    final record = _record(await _get(key), key);
    if (record['payloadType'] != 'text' || record['payload'] is! String) {
      throw PlatformStorageCorruptedException('浏览器文本记录损坏：$key');
    }
    return record['payload']! as String;
  }

  @override
  Future<Uint8List> readBytes(String key) async {
    final record = _record(await _get(key), key);
    final payload = record['payload'];
    if (record['payloadType'] != 'bytes' || payload is! List) {
      throw PlatformStorageCorruptedException('浏览器二进制记录损坏：$key');
    }
    return Uint8List.fromList(
      payload.cast<num>().map((value) => value.toInt()).toList(),
    );
  }

  @override
  Future<void> writeText(String key, String value) => _put(key, 'text', value);
  @override
  Future<void> writeBytes(String key, Uint8List value) =>
      _put(key, 'bytes', value.toList());
  @override
  Future<void> replaceTextSafely(String key, String value) =>
      _put(key, 'text', value);

  @override
  Future<void> delete(String key, {bool recursive = false}) async {
    final logical = _logicalKey(key);
    try {
      final transaction = _database.transaction(
        objectStoreName.toJS,
        'readwrite',
      );
      final completion = _completed(transaction);
      final store = transaction.objectStore(objectStoreName);
      if (recursive) {
        final result = await _request(store.getAllKeys());
        final keys = (result?.dartify() as List? ?? const <Object?>[]).map(
          (value) => value.toString(),
        );
        final target = _databaseKey(logical);
        for (final candidate in keys) {
          if (candidate == target || candidate.startsWith('$target/')) {
            store.delete(candidate.toJS);
          }
        }
      } else {
        store.delete(_databaseKey(logical).toJS);
      }
      await completion;
      _observedRevisions.removeWhere(
        (candidate, _) =>
            candidate == logical || candidate.startsWith('$logical/'),
      );
    } catch (error) {
      throw PlatformStorageTransactionException('删除浏览器存储失败：$logical', error);
    }
  }

  @override
  Future<List<PlatformStorageEntry>> list(
    String key, {
    bool recursive = false,
  }) async {
    final logical = _logicalKey(key);
    final namespacePrefix = '$namespace::';
    final prefix = logical.isEmpty ? namespacePrefix : '$namespace::$logical/';
    final entries = <PlatformStorageEntry>[];
    final containers = <String>{};
    try {
      final transaction = _database.transaction(
        objectStoreName.toJS,
        'readonly',
      );
      final completion = _completed(transaction);
      final result = await _request(
        transaction.objectStore(objectStoreName).getAllKeys(),
      );
      await completion;
      final keys = (result?.dartify() as List? ?? const <Object?>[]).map(
        (value) => value.toString(),
      );
      for (final databaseKey in keys) {
        if (!databaseKey.startsWith(prefix)) continue;
        final relative = databaseKey.substring(namespacePrefix.length);
        final remainder = databaseKey.substring(prefix.length);
        if (!recursive && remainder.contains('/')) {
          final container =
              '${logical.isEmpty ? '' : '$logical/'}${remainder.split('/').first}';
          if (containers.add(container)) {
            entries.add(
              PlatformStorageEntry(key: container, isContainer: true),
            );
          }
        } else {
          entries.add(PlatformStorageEntry(key: relative, isContainer: false));
        }
      }
      return entries;
    } catch (error) {
      throw PlatformStorageTransactionException('列举浏览器存储失败：$logical', error);
    }
  }
}
