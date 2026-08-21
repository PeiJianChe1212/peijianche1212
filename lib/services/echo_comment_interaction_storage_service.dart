import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/echo_comment_interaction.dart';

class EchoCommentInteractionStorageService {
  static const String _fileName = 'echo_comment_interactions.json';
  static const int _maxInteractions = 300;
  static const int _maxCandidates = 80;

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<EchoCommentInteraction>> loadInteractions() async {
    final data = await _load();
    final raw = data['interactions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(EchoCommentInteraction.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<List<EchoLifeOpportunityCandidate>> loadCandidates({
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final data = await _load();
    final raw = data['lifeOpportunityCandidates'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(EchoLifeOpportunityCandidate.fromJson)
        .where((item) => item.id.isNotEmpty && item.expiresAt.isAfter(time))
        .toList();
  }

  Future<void> add({
    required EchoCommentInteraction interaction,
    EchoLifeOpportunityCandidate? candidate,
  }) async {
    final interactions = List<EchoCommentInteraction>.from(
      await loadInteractions(),
    );
    if (!interactions.any((item) => item.id == interaction.id)) {
      interactions.insert(0, interaction);
    }

    final candidates = List<EchoLifeOpportunityCandidate>.from(
      await loadCandidates(),
    );
    if (candidate != null &&
        !candidates.any(
          (item) =>
              item.id == candidate.id ||
              item.sourceInteractionId == candidate.sourceInteractionId,
        )) {
      candidates.insert(0, candidate);
    }
    await _save(
      interactions.take(_maxInteractions).toList(),
      candidates.take(_maxCandidates).toList(),
    );
  }

  Future<void> removeForEchoIds(Set<String> echoIds) async {
    if (echoIds.isEmpty) return;
    final interactions = List<EchoCommentInteraction>.from(
      await loadInteractions(),
    );
    final removedInteractionIds = interactions
        .where((item) => echoIds.contains(item.echoId))
        .map((item) => item.id)
        .toSet();
    interactions.removeWhere((item) => echoIds.contains(item.echoId));
    final candidates =
        List<EchoLifeOpportunityCandidate>.from(await loadCandidates())
          ..removeWhere(
            (item) => removedInteractionIds.contains(item.sourceInteractionId),
          );
    await _save(interactions, candidates);
  }

  Future<void> _save(
    List<EchoCommentInteraction> interactions,
    List<EchoLifeOpportunityCandidate> candidates,
  ) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'interactions': interactions.map((item) => item.toJson()).toList(),
        'lifeOpportunityCandidates': candidates
            .map((item) => item.toJson())
            .toList(),
      }),
      flush: true,
    );
  }

  Future<Map<String, dynamic>> _load() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return {};
    }
  }
}
