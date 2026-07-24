import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/ai_character.dart';
import '../models/life_moment.dart';
import 'character_scope_service.dart';
import 'life_engine_service.dart';

class LifeEventPoolService {
  LifeEventPoolService({
    required this.character,
    http.Client? client,
  }) : _lifeEngine = LifeEngineService(
          character: character,
          client: client,
        );

  final AiCharacter character;
  final LifeEngineService _lifeEngine;

  Future<File> _file() {
    return CharacterScopeService(character.id).dataFile(
      'life_event_pool.json',
    );
  }

  Future<List<LifeMomentCandidate>> getCandidates({
    int count = 4,
    Set<String> excludeIds = const {},
  }) async {
    final safeCount = count.clamp(2, 6).toInt();
    var state = await _loadState();
    var available = _availableItems(
      state,
      excludeIds: excludeIds,
    );

    final poolIsOld = state.generatedAt == null ||
        DateTime.now().difference(state.generatedAt!).inHours >= 8;
    if (available.length < safeCount || poolIsOld) {
      final generated = await _lifeEngine.generateCandidates(count: 6);
      state = _mergeGenerated(state, generated);
      await _saveState(state);
      available = _availableItems(
        state,
        excludeIds: excludeIds,
      );
    }

    if (available.isEmpty) {
      throw const FormatException('生活事件池暂时没有可用片段。');
    }

    return available.take(safeCount).toList();
  }

  Future<void> markUsed(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final state = await _loadState();
    final usedIds = <String>{...state.usedIds, cleanId};
    final existingIds = state.items.map((item) => item.id).toSet();
    usedIds.removeWhere((item) => !existingIds.contains(item));

    await _saveState(
      state.copyWith(usedIds: usedIds),
    );
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }

  List<LifeMomentCandidate> _availableItems(
    _LifeEventPoolState state, {
    required Set<String> excludeIds,
  }) {
    final expiry = DateTime.now().subtract(const Duration(hours: 36));
    final blocked = <String>{...state.usedIds, ...excludeIds};

    final items = state.items
        .where((item) => item.occurredAt.isAfter(expiry))
        .where((item) => !blocked.contains(item.id))
        .toList();
    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items;
  }

  _LifeEventPoolState _mergeGenerated(
    _LifeEventPoolState current,
    List<LifeMomentCandidate> generated,
  ) {
    final merged = <LifeMomentCandidate>[];
    final fingerprints = <String>{};

    for (final item in [...generated, ...current.items]) {
      final fingerprint = _fingerprint(item);
      if (fingerprint.isEmpty || !fingerprints.add(fingerprint)) continue;
      merged.add(item);
      if (merged.length >= 30) break;
    }

    final ids = merged.map((item) => item.id).toSet();
    final used = current.usedIds.where(ids.contains).toSet();

    return _LifeEventPoolState(
      generatedAt: DateTime.now(),
      items: merged,
      usedIds: used,
    );
  }

  String _fingerprint(LifeMomentCandidate item) {
    final value = '${item.event}|${item.detail}'
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？、,.!?：:；;（）()]'), '');
    return value.length <= 70 ? value : value.substring(0, 70);
  }

  Future<_LifeEventPoolState> _loadState() async {
    final file = await _file();
    if (!await file.exists()) return const _LifeEventPoolState();

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const _LifeEventPoolState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _LifeEventPoolState();
      return _LifeEventPoolState.fromJson(decoded);
    } catch (_) {
      return const _LifeEventPoolState();
    }
  }

  Future<void> _saveState(_LifeEventPoolState state) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(state.toJson()),
      flush: true,
    );
  }

  void dispose() {
    _lifeEngine.dispose();
  }
}

class _LifeEventPoolState {
  const _LifeEventPoolState({
    this.generatedAt,
    this.items = const [],
    this.usedIds = const {},
  });

  final DateTime? generatedAt;
  final List<LifeMomentCandidate> items;
  final Set<String> usedIds;

  _LifeEventPoolState copyWith({
    DateTime? generatedAt,
    List<LifeMomentCandidate>? items,
    Set<String>? usedIds,
  }) {
    return _LifeEventPoolState(
      generatedAt: generatedAt ?? this.generatedAt,
      items: items ?? this.items,
      usedIds: usedIds ?? this.usedIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt?.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'usedIds': usedIds.toList(),
      };

  factory _LifeEventPoolState.fromJson(Map<dynamic, dynamic> json) {
    final rawItems = json['items'];
    final rawUsedIds = json['usedIds'];
    return _LifeEventPoolState(
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(LifeMomentCandidate.fromJson)
              .where((item) => item.event.isNotEmpty)
              .toList()
          : const [],
      usedIds: rawUsedIds is List
          ? rawUsedIds
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
          : const {},
    );
  }
}
