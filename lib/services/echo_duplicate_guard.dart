import '../models/echo_item.dart';
import 'character_registry_service.dart';
import 'echo_storage_service.dart';

class EchoDuplicateCheck {
  const EchoDuplicateCheck({
    required this.isDuplicate,
    this.matchedContent = '',
    this.scope = '',
    this.similarity = 0,
  });

  final bool isDuplicate;
  final String matchedContent;
  final String scope;
  final double similarity;
}

/// Lightweight, API-free duplicate protection for system-generated Echoes.
class EchoDuplicateGuard {
  const EchoDuplicateGuard();

  static const int sameCharacterLimit = 12;
  static const int publicFeedLimit = 25;
  static const double sameCharacterThreshold = .72;
  static const double publicFeedThreshold = .9;

  Future<T?> acceptOrRetryOnce<T>({
    required T initial,
    required Future<bool> Function(T value) isDuplicate,
    required Future<T?> Function() retry,
  }) async {
    if (!await isDuplicate(initial)) return initial;
    final second = await retry();
    if (second == null || await isDuplicate(second)) return null;
    return second;
  }

  Future<EchoDuplicateCheck> check({
    required String content,
    required String characterId,
  }) async {
    final own = await EchoStorageService(characterId: characterId).loadItems();
    final sameCharacter = checkAgainst(
      content: content,
      items: own.take(sameCharacterLimit),
      threshold: sameCharacterThreshold,
      scope: 'same_character',
    );
    if (sameCharacter.isDuplicate) return sameCharacter;

    final characters = await CharacterRegistryService().loadCharacters();
    final ownerIds = <String>{
      'peilink_user_echo',
      ...characters.map((item) => item.id),
    }..remove(characterId);
    final timelines = await Future.wait(
      ownerIds.map((id) => EchoStorageService(characterId: id).loadItems()),
    );
    final publicItems = timelines.expand((items) => items).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return checkAgainst(
      content: content,
      items: publicItems.take(publicFeedLimit),
      threshold: publicFeedThreshold,
      scope: 'public_feed',
    );
  }

  EchoDuplicateCheck checkAgainst({
    required String content,
    required Iterable<EchoItem> items,
    required double threshold,
    required String scope,
  }) {
    final normalized = normalize(content);
    if (normalized.isEmpty) return const EchoDuplicateCheck(isDuplicate: false);
    for (final item in items) {
      final old = normalize(item.content);
      if (old.isEmpty) continue;
      final score = similarityOfNormalized(normalized, old);
      if (score >= threshold) {
        return EchoDuplicateCheck(
          isDuplicate: true,
          matchedContent: item.content,
          scope: scope,
          similarity: score,
        );
      }
    }
    return const EchoDuplicateCheck(isDuplicate: false);
  }

  String normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s，。！？、,.!?;；:：\-—“”‘’（）()【】\[\]{}<>《》_]'),
    '',
  );

  double similarity(String first, String second) =>
      similarityOfNormalized(normalize(first), normalize(second));

  double similarityOfNormalized(String first, String second) {
    if (first.isEmpty || second.isEmpty) return 0;
    if (first == second) return 1;
    final lengthRatio = first.length < second.length
        ? first.length / second.length
        : second.length / first.length;
    if (lengthRatio < .55) return 0;
    final left = _bigrams(first);
    final right = _bigrams(second);
    if (left.isEmpty || right.isEmpty) return 0;
    final dice =
        2 * left.intersection(right).length / (left.length + right.length);
    final leftCharacters = first.split('').toSet();
    final rightCharacters = second.split('').toSet();
    final characterDice =
        2 *
        leftCharacters.intersection(rightCharacters).length /
        (leftCharacters.length + rightCharacters.length);
    final longest = first.length > second.length ? first.length : second.length;
    final edit = 1 - _editDistance(first, second) / longest;
    final structural = [
      dice,
      characterDice,
      edit,
    ].reduce((best, value) => value > best ? value : best);
    return structural * .85 + lengthRatio * .15;
  }

  int _editDistance(String first, String second) {
    var previous = List<int>.generate(second.length + 1, (index) => index);
    for (var row = 1; row <= first.length; row++) {
      final current = <int>[row];
      for (var column = 1; column <= second.length; column++) {
        final substitution =
            previous[column - 1] +
            (first.codeUnitAt(row - 1) == second.codeUnitAt(column - 1)
                ? 0
                : 1);
        final insertion = current[column - 1] + 1;
        final deletion = previous[column] + 1;
        current.add(
          substitution < insertion
              ? (substitution < deletion ? substitution : deletion)
              : (insertion < deletion ? insertion : deletion),
        );
      }
      previous = current;
    }
    return previous.last;
  }

  Set<String> _bigrams(String value) {
    if (value.length < 2) return {value};
    return {
      for (var index = 0; index < value.length - 1; index++)
        value.substring(index, index + 2),
    };
  }
}
