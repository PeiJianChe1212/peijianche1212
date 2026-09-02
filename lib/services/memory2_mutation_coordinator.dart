import 'dart:async';

/// Serializes Memory 2.0 read-modify-write operations per character.
///
/// Different characters use independent queues and can still mutate in parallel.
class Memory2MutationCoordinator {
  Memory2MutationCoordinator._();

  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  static Future<T> runExclusive<T>(
    String characterId,
    Future<T> Function() action,
  ) async {
    final key = characterId.trim();
    final previous = _tails[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _tails[key] = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_tails[key], gate.future)) {
        _tails.remove(key);
      }
    }
  }
}
