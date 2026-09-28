import 'package:flutter/foundation.dart';

import '../../config/peilink_runtime.dart';
import '../../platform/storage/platform_storage.dart';

/// 按 sessionId 隔离的 Game Room 输入草稿持久化。
///
/// 草稿只用于「未发送的输入框文本」，不进入 Timeline、不发给任何模型、
/// 不进入 Character/User Context。发送成功或新局开始后立即清除。
class GameRoomDraftStore {
  GameRoomDraftStore({this.storage});

  static const _namespace = 'games/drafts';
  static final Map<String, Future<void>> _pendingMutations = {};
  final PlatformStorage? storage;

  Future<PlatformStorage> _store() =>
      storage == null ? PeiLinkRuntime.storage() : Future.value(storage);

  String _key(String sessionId) => '$_namespace/$sessionId.txt';

  /// 读取指定 session 的未发送草稿；不存在或为空时返回空串。
  Future<String> load(String sessionId) async {
    if (sessionId.isEmpty) return '';
    try {
      final store = await _store();
      final key = _key(sessionId);
      await _waitForPending(store, key);
      if (!await store.exists(key)) return '';
      return (await store.readText(key)).trim();
    } catch (error) {
      debugPrint('GameRoomDraftStore load failed: $error');
      return '';
    }
  }

  /// 轻量保存草稿；空文本等价于清除。
  Future<void> save(String sessionId, String text) async {
    if (sessionId.isEmpty) return;
    try {
      final store = await _store();
      final key = _key(sessionId);
      final trimmed = text.trim();
      await _enqueueMutation(store, key, () async {
        if (trimmed.isEmpty) {
          if (await store.exists(key)) await store.delete(key);
        } else {
          await store.replaceTextSafely(key, trimmed);
        }
      });
    } catch (error) {
      debugPrint('GameRoomDraftStore save failed: $error');
    }
  }

  /// 发送成功、新局开始或 session 结束后调用。
  Future<void> clear(String sessionId) async {
    if (sessionId.isEmpty) return;
    try {
      final store = await _store();
      final key = _key(sessionId);
      await _enqueueMutation(store, key, () async {
        if (await store.exists(key)) await store.delete(key);
      });
    } catch (error) {
      debugPrint('GameRoomDraftStore clear failed: $error');
    }
  }

  static String _operationId(PlatformStorage store, String key) =>
      store.reference(key);

  static Future<void> _waitForPending(PlatformStorage store, String key) async {
    final pending = _pendingMutations[_operationId(store, key)];
    if (pending != null) await pending;
  }

  static Future<void> _enqueueMutation(
    PlatformStorage store,
    String key,
    Future<void> Function() operation,
  ) async {
    final id = _operationId(store, key);
    final previous = _pendingMutations[id];
    // Start the first mutation immediately. Besides reducing the close/reopen
    // race window, this keeps real platform I/O observable in widget tests
    // whose fake clock does not advance a Future.value().then continuation.
    final current = previous == null
        ? Future<void>.sync(operation)
        : previous.catchError((_) {}).then((_) => operation());
    _pendingMutations[id] = current;
    try {
      await current;
    } finally {
      if (identical(_pendingMutations[id], current)) {
        _pendingMutations.remove(id);
      }
    }
  }
}
