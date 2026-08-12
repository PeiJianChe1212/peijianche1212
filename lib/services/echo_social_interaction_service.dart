import '../models/ai_character.dart';
import '../models/character_relationship.dart';
import '../models/echo_comment.dart';
import '../models/echo_item.dart';
import 'auto_echo_comment_service.dart';
import 'character_registry_service.dart';
import 'character_relationship_storage_service.dart';
import 'echo_comment_storage_service.dart';
import 'echo_comment_diversity_service.dart';
import 'echo_interaction_stats_service.dart';
import 'echo_relationship_engine_service.dart';

/// Unified post-publish entry point: Echo -> save -> social feedback.
class EchoSocialInteractionService {
  const EchoSocialInteractionService();

  static const int _dailyCharacterLimit = 3;
  static const _relationshipEngine = EchoRelationshipEngineService();
  static const _diversity = EchoCommentDiversityService();

  Future<void> generateForEcho(EchoItem echo, {DateTime? now}) async {
    if (!echo.commentsEnabled) return;
    final time = now ?? DateTime.now();
    final storage = EchoCommentStorageService(ownerId: echo.characterId);
    final existing = await storage.loadForEcho(echo.id);
    if (existing.any((item) => item.metadata['socialSeed'] == true)) return;

    final characters = await CharacterRegistryService().loadCharacters();
    final relationships = await CharacterRelationshipStorageService()
        .ensureForCharacters(characters);
    final author = _findCharacter(characters, echo.characterId);
    final seed = _hash('${echo.id}|${echo.content}');
    final target = 3 + seed % 6;
    final desiredCharacters = (target * .4).round();
    final generated = <EchoComment>[];
    final usedStyles = existing
        .map((item) => item.commentStyle)
        .whereType<EchoCommentStyle>()
        .toSet();

    if (author != null && desiredCharacters > 0) {
      final candidates = <_CharacterCandidate>[];
      for (final commenter in characters) {
        if (commenter.id == author.id) continue;
        if (existing.any((item) => item.authorId == commenter.id)) continue;
        if (!await _withinDailyLimit(commenter.id, characters, time)) continue;
        final relationship = _findRelationship(
          relationships,
          author.id,
          commenter.id,
        );
        final tendency = _relationshipEngine.evaluate(
          author: author,
          commenter: commenter,
          relationship: relationship,
          now: time,
        );
        final roll = _hash('${echo.id}|${commenter.id}|relationship') % 1000;
        if (roll >= (tendency.probability * 1000).round()) continue;
        candidates.add(
          _CharacterCandidate(
            character: commenter,
            relationship: relationship,
            tendency: tendency,
            score: tendency.intimacy * 1000 - roll,
          ),
        );
      }
      candidates.sort((a, b) => b.score.compareTo(a.score));
      for (final candidate in candidates.take(desiredCharacters)) {
        final style = _diversity.chooseStyle(
          seed: '${echo.id}|${candidate.character.id}',
          used: usedStyles,
          relationshipKind: candidate.tendency.kind,
        );
        final comment = _characterComment(
          echo,
          candidate,
          time,
          generated.length,
          style,
          [...existing, ...generated].map((item) => item.content).toList(),
        );
        generated.add(comment);
        usedStyles.add(style);
      }
    }

    final visitorCount = target - generated.length;
    for (var index = 0; index < visitorCount; index++) {
      final style = _diversity.chooseStyle(
        seed: '${echo.id}|visitor|$index',
        used: usedStyles,
        virtualVisitor: true,
      );
      final comment = _visitorComment(
        echo,
        seed,
        index,
        time,
        style,
        [...existing, ...generated].map((item) => item.content).toList(),
      );
      generated.add(comment);
      usedStyles.add(style);
    }
    await storage.saveAll([...existing, ...generated]);
    await EchoInteractionStatsService(ownerId: echo.characterId).createForEcho(
      echo,
      commentCount: existing.length + generated.length,
      hasRelationship: generated.any(
        (item) => item.commentType == EchoCommentType.aiCharacter,
      ),
    );

    // Keep the existing delayed AI generation path for later, richer replies.
    // Its own duplicate and daily-limit guards remain authoritative.
    await AutoEchoCommentService().scheduleForEcho(echo, now: time);
  }

  EchoComment _characterComment(
    EchoItem echo,
    _CharacterCandidate candidate,
    DateTime time,
    int index,
    EchoCommentStyle style,
    List<String> existingContents,
  ) {
    final content = _diversity.createTemplate(
      echo: echo,
      style: style,
      seed: '${echo.id}|${candidate.character.id}',
      existing: existingContents,
      relationshipKind: candidate.tendency.kind,
    );
    return EchoComment(
      id: 'social_ai_${echo.id}_${candidate.character.id}',
      echoId: echo.id,
      authorType: EchoCommentAuthorType.character,
      authorId: candidate.character.id,
      authorNameSnapshot: candidate.character.displayName,
      authorAvatarSnapshot: candidate.character.avatarPath,
      content: content,
      createdAt: time.add(Duration(minutes: 2 + index * 3)),
      sourceType: EchoCommentSourceType.autoCharacter,
      commentType: EchoCommentType.aiCharacter,
      commentStyle: style,
      relatedRelationshipId: candidate.relationship?.id ?? '',
      metadata: {
        'socialSeed': true,
        'relationshipKind': candidate.tendency.kind.name,
        'relationshipTone': candidate.tendency.tone,
        'commentStyle': style.name,
        'virtualLikeCount': 4 + _hash('$content|likes') % 18,
      },
    );
  }

  EchoComment _visitorComment(
    EchoItem echo,
    int seed,
    int index,
    DateTime time,
    EchoCommentStyle style,
    List<String> existingContents,
  ) {
    const names = ['青屿', '晚风来信', '南枝', '山茶', '一页', '路过人间', '小满', '木槿'];
    final slot = (seed + index * 7).abs();
    final content = _diversity.createTemplate(
      echo: echo,
      style: style,
      seed: '${echo.id}|visitor|$index',
      existing: existingContents,
    );
    return EchoComment(
      id: 'social_virtual_${echo.id}_$index',
      echoId: echo.id,
      authorType: EchoCommentAuthorType.world,
      authorId: 'virtual_user_${slot % names.length}_$index',
      authorNameSnapshot: names[slot % names.length],
      content: content,
      createdAt: time.add(Duration(minutes: 4 + index * 5)),
      sourceType: EchoCommentSourceType.lifeEventTriggered,
      commentType: EchoCommentType.virtualUser,
      commentStyle: style,
      metadata: {
        'socialSeed': true,
        'commentStyle': style.name,
        'virtualLikeCount': 1 + _hash('${echo.id}|visitor|$index') % 12,
      },
    );
  }

  Future<bool> _withinDailyLimit(
    String commenterId,
    List<AiCharacter> characters,
    DateTime now,
  ) async {
    final start = DateTime(now.year, now.month, now.day);
    var count = 0;
    for (final ownerId in <String>[
      AutoEchoCommentService.userEchoOwnerId,
      ...characters.map((item) => item.id),
    ]) {
      final comments = await EchoCommentStorageService(
        ownerId: ownerId,
      ).loadAll();
      count += comments
          .where(
            (item) =>
                item.authorId == commenterId &&
                item.commentType == EchoCommentType.aiCharacter &&
                !item.createdAt.isBefore(start),
          )
          .length;
    }
    return count < _dailyCharacterLimit;
  }

  AiCharacter? _findCharacter(List<AiCharacter> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  CharacterRelationship? _findRelationship(
    List<CharacterRelationship> items,
    String first,
    String second,
  ) {
    final id = CharacterRelationship.buildId(first, second);
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  int _hash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 37 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

class _CharacterCandidate {
  const _CharacterCandidate({
    required this.character,
    required this.relationship,
    required this.tendency,
    required this.score,
  });
  final AiCharacter character;
  final CharacterRelationship? relationship;
  final EchoCommentTendency tendency;
  final int score;
}
