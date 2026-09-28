import 'dart:convert';
import 'turtle_soup_models.dart';
import 'turtle_soup_logic_profile.dart';

class TurtleSoupGuessRequest {
  const TurtleSoupGuessRequest({
    required this.puzzle,
    required this.guess,
    this.profile,
  });
  final TurtleSoupPuzzle puzzle;
  final String guess;
  final TurtleSoupLogicProfile? profile;
  Map<String, String> get criteria => {
    for (var i = 0; i < puzzle.requiredTruthPoints.length; i++)
      'p${i + 1}': puzzle.requiredTruthPoints[i],
    if (profile != null) ...{
      for (final f in profile!.facts.where(
        (f) => profile!.solveCriteria.requiredFactIds.contains(f.id),
      ))
        f.id: f.statement,
      for (final e in profile!.causalEdges.where(
        (e) => profile!.solveCriteria.requiredEdgeIds.contains(e.id),
      ))
        e.id:
            '${e.sourceFactIds.join('+')} ${e.relation.name} ${e.targetFactId}',
    },
  };
}

abstract interface class TurtleSoupGuessJudge {
  Future<bool> judgeGuess(TurtleSoupGuessRequest request);
}

/// Complete partition of known criteria; unknown IDs, contradictions and
/// inconsistent solved flags all fail closed. Text never reaches public UI.
bool parseTurtleSoupGuessDecision(String raw, Set<String> criteria) {
  try {
    final value = jsonDecode(raw.trim());
    if (value is! Map ||
        value.length != 4 ||
        value['solved'] is! bool ||
        value['contradiction'] is! bool ||
        value['coverage'] is! List ||
        value['missing'] is! List ||
        criteria.isEmpty) {
      return false;
    }
    final covered = value['coverage'] as List;
    final missing = value['missing'] as List;
    final all = [...covered, ...missing];
    if (all.any((id) => id is! String || !criteria.contains(id)) ||
        all.toSet().length != all.length ||
        all.length != criteria.length) {
      return false;
    }
    return value['solved'] == true &&
        value['contradiction'] == false &&
        missing.isEmpty;
  } catch (_) {
    return false;
  }
}
