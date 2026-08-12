import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/causal_node.dart';

class CausalGraphService {
  static const String _fileName = 'causal_graph.json';
  static const int _maxNodes = 1600;
  static const Duration _retention = Duration(days: 120);

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<CausalNode>> loadAll({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final file = await _file();
    if (!await file.exists()) return const [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final nodes = decoded
          .whereType<Map>()
          .map(CausalNode.fromJson)
          .where((node) => node.id.isNotEmpty)
          .where((node) => time.difference(node.occurredAt) <= _retention)
          .toList();
      nodes.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return nodes;
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsert(CausalNode node, {DateTime? now}) async {
    if (node.id.trim().isEmpty) return;
    final nodes = await loadAll(now: now);
    final updated = nodes.where((item) => item.id != node.id).toList()
      ..add(node);
    await _save(updated, now: now);
  }

  Future<void> upsertAll(Iterable<CausalNode> incoming, {DateTime? now}) async {
    final additions = incoming
        .where((node) => node.id.trim().isNotEmpty)
        .toList();
    if (additions.isEmpty) return;

    final nodes = await loadAll(now: now);
    final ids = additions.map((node) => node.id).toSet();
    final updated = nodes.where((node) => !ids.contains(node.id)).toList()
      ..addAll(additions);
    await _save(updated, now: now);
  }

  Future<CausalNode?> findById(String nodeId) async {
    final id = nodeId.trim();
    if (id.isEmpty) return null;
    final nodes = await loadAll();
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  Future<List<CausalNode>> traceAncestors(
    String nodeId, {
    int maxDepth = 8,
    int maxNodes = 40,
  }) async {
    final id = nodeId.trim();
    if (id.isEmpty) return const [];

    final all = await loadAll();
    final byId = {for (final node in all) node.id: node};
    final result = <CausalNode>[];
    final visited = <String>{};
    var frontier = <String>[id];

    for (
      var depth = 0;
      depth <= maxDepth && frontier.isNotEmpty && result.length < maxNodes;
      depth++
    ) {
      final next = <String>[];
      for (final currentId in frontier) {
        if (!visited.add(currentId)) continue;
        final node = byId[currentId];
        if (node == null) continue;
        result.add(node);
        next.addAll(node.parentIds);
        if (result.length >= maxNodes) break;
      }
      frontier = next;
    }
    return result;
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<void> _save(List<CausalNode> nodes, {DateTime? now}) async {
    final time = now ?? DateTime.now();
    final unique = <String, CausalNode>{};
    for (final node in nodes) {
      if (node.id.trim().isEmpty) continue;
      if (time.difference(node.occurredAt) > _retention) continue;
      unique[node.id] = node.copyWith(
        parentIds: node.parentIds
            .where((id) => id.trim().isNotEmpty && id != node.id)
            .toSet()
            .toList(),
      );
    }

    final kept = unique.values.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final file = await _file();
    await file.writeAsString(
      jsonEncode(kept.take(_maxNodes).map((node) => node.toJson()).toList()),
      flush: true,
    );
  }
}
