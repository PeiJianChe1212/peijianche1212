import 'dart:math' as math;

import '../models/life_moment.dart';
import 'life_moment_storage_service.dart';

class InitiativeLifeContext {
  const InitiativeLifeContext({
    required this.message,
    required this.momentId,
  });

  final String message;
  final String momentId;
}

class InitiativeLifeContextService {
  InitiativeLifeContextService({required this.characterId});

  final String characterId;

  Future<InitiativeLifeContext?> build({
    required DateTime now,
    required Set<String> excludedMomentIds,
  }) async {
    final items = await LifeMomentStorageService(
      characterId: characterId,
    ).loadItems();

    final earliest = now.subtract(const Duration(hours: 36));
    final candidates = items
        .where((item) => item.occurredAt.isAfter(earliest))
        .where((item) => !excludedMomentIds.contains(item.id))
        .where(_hasUsableContent)
        .toList();

    if (candidates.isEmpty) return null;

    // 不总挑最新一条，避免每次主动消息都围着同一件事转。
    final seed = now.day + now.hour + now.minute ~/ 10;
    final pickIndex = seed % math.min(candidates.length, 3);
    final moment = candidates[pickIndex];
    final message = _messageFor(moment, seed: seed);
    if (message.isEmpty) return null;

    return InitiativeLifeContext(
      message: message,
      momentId: moment.id,
    );
  }

  bool _hasUsableContent(LifeMomentCandidate item) {
    return item.detail.trim().isNotEmpty ||
        item.shareHook.trim().isNotEmpty ||
        item.event.trim().isNotEmpty;
  }

  String _messageFor(LifeMomentCandidate item, {required int seed}) {
    final detail = _clean(item.detail);
    final hook = _clean(item.shareHook);
    final event = _clean(item.event);

    final core = detail.isNotEmpty
        ? detail
        : hook.isNotEmpty
            ? hook
            : event;
    if (core.isEmpty) return '';

    final normalized = _trimSentence(core, maxLength: 48);
    final endings = <String>[
      '$normalized。刚才忽然想跟你说一声。',
      '$normalized。你今天有没有碰到什么有意思的事？',
      '$normalized。想到你大概会有话说。',
    ];
    return endings[seed % endings.length];
  }

  String _clean(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'^[“”\s]+|[“”\s]+$'), '')
        .replaceAll(RegExp(r'[。！？!?]+$'), '');
  }

  String _trimSentence(String value, {required int maxLength}) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength).trim()}…';
  }
}
