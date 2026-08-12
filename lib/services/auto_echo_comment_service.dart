import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/ai_character.dart';
import '../models/character_relationship.dart';
import '../models/echo_comment.dart';
import '../models/echo_comment_task.dart';
import '../models/echo_item.dart';
import 'character_registry_service.dart';
import 'character_relationship_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'auto_echo_comment_reply_service.dart';
import 'echo_comment_generation_service.dart';
import 'echo_comment_diversity_service.dart';
import 'echo_relationship_engine_service.dart';
import 'echo_comment_interaction_service.dart';
import 'echo_comment_interaction_policy.dart';
import 'echo_comment_storage_service.dart';
import 'echo_comment_task_storage_service.dart';
import 'echo_storage_service.dart';
import 'user_profile_storage_service.dart';

class AutoEchoCommentReport {
  const AutoEchoCommentReport({
    required this.scheduled,
    required this.published,
    required this.skipped,
    required this.failed,
  });

  final int scheduled;
  final int published;
  final int skipped;
  final int failed;
}

/// Echo 自动评论的统一入口。
///
/// 发布时只安排任务；到期后再调用模型生成，避免所有角色同一时间出现。
class AutoEchoCommentService {
  static const String userEchoOwnerId = 'peilink_user_echo';
  static const int _maxCommentsPerEcho = 2;
  static const int _dailyLimitPerCharacter = 3;
  static const Duration _commentCooldown = Duration(hours: 4);
  static bool _running = false;

  final CharacterRegistryService _registry = CharacterRegistryService();
  final CharacterRelationshipStorageService _relationshipStorage =
      CharacterRelationshipStorageService();
  final EchoCommentTaskStorageService _taskStorage =
      EchoCommentTaskStorageService();
  final EchoCommentInteractionPolicy _policy =
      const EchoCommentInteractionPolicy();
  final EchoCommentDiversityService _diversity =
      const EchoCommentDiversityService();
  final AutoEchoCommentReplyService _replyService =
      AutoEchoCommentReplyService();

  Future<AutoEchoCommentReport> checkAll({DateTime? now}) async {
    if (_running) {
      return const AutoEchoCommentReport(
        scheduled: 0,
        published: 0,
        skipped: 0,
        failed: 0,
      );
    }
    _running = true;
    try {
      final time = now ?? DateTime.now();
      final scheduled = await discoverUnscheduledEchoes(now: time);
      final execution = await _publishDue(now: time);
      await _replyService.checkAll(now: time);
      await _taskStorage.prune(now: time);
      return AutoEchoCommentReport(
        scheduled: scheduled,
        published: execution.published,
        skipped: execution.skipped,
        failed: execution.failed,
      );
    } finally {
      _running = false;
    }
  }

  Future<int> scheduleForEcho(EchoItem echo, {DateTime? now}) async {
    if (!echo.commentsEnabled) return 0;
    final time = now ?? DateTime.now();
    if (await _taskStorage.hasTaskForEcho(echo.id)) return 0;

    final characters = await _registry.loadCharacters();
    final author = _findCharacter(characters, echo.characterId);
    final relationships = await _relationshipStorage.ensureForCharacters(
      characters,
    );
    final candidates = <_Candidate>[];

    for (final commenter in characters) {
      if (commenter.id == echo.characterId) continue;
      final relationship = author == null
          ? null
          : _findRelationship(relationships, author.id, commenter.id);
      final baseReason = _candidateReason(
        echo: echo,
        author: author,
        relationship: relationship,
      );
      if (baseReason == null) {
        debugPrint(
          '[EchoComment] ${commenter.displayName}跳过：尚无可见关系 '
          'echoId=${echo.id} commenterId=${commenter.id}',
        );
        continue;
      }
      final settings = await CharacterSettingsStorageService(
        characterId: commenter.id,
      ).loadSettings();
      final decision = _policy.evaluate(
        echo: echo,
        commenter: commenter,
        settings: settings,
        relationship: relationship,
        now: time,
      );
      if (!decision.shouldComment) {
        debugPrint(
          '[EchoComment] ${commenter.displayName}跳过：${decision.reason} '
          'echoId=${echo.id} commenterId=${commenter.id} '
          'type=${decision.contentType.name} '
          'relevance=${decision.relevance} state=${decision.activityLabel}',
        );
        continue;
      }
      candidates.add(
        _Candidate(
          character: commenter,
          relationship: relationship,
          reason: '$baseReason；${decision.reason}',
          score:
              _stableScore('${echo.id}|${commenter.id}') -
              decision.relevance * 100000,
        ),
      );
    }

    candidates.sort((a, b) => a.score.compareTo(b.score));
    final selected = candidates.take(_maxCommentsPerEcho).toList();
    if (selected.isEmpty) {
      await _taskStorage.addAll([
        EchoCommentTask(
          id: 'echo_comment_task_${echo.id}_no_candidate',
          echoId: echo.id,
          echoOwnerId: echo.characterId,
          commenterId: '__no_candidate__',
          scheduledAt: time,
          createdAt: time,
          status: EchoCommentTaskStatus.skipped,
          skipReason: '当前没有具备可见关系的候选角色',
          triggerReason: '候选检查完成',
        ),
      ]);
      return 0;
    }

    debugPrint(
      '[EchoComment] Echo 发布成功 echoId=${echo.id} '
      'publisherId=${echo.characterId}',
    );
    debugPrint(
      '[EchoComment] 候选角色：'
      '${selected.map((item) => item.character.displayName).join('、')}',
    );

    final tasks = <EchoCommentTask>[];
    for (var index = 0; index < selected.length; index++) {
      final candidate = selected[index];
      final delay = _naturalDelay(
        echoId: echo.id,
        commenterId: candidate.character.id,
        order: index,
      );
      final scheduledAt = time.add(delay);
      tasks.add(
        EchoCommentTask(
          id: 'echo_comment_task_${echo.id}_${candidate.character.id}',
          echoId: echo.id,
          echoOwnerId: echo.characterId,
          commenterId: candidate.character.id,
          scheduledAt: scheduledAt,
          createdAt: time,
          triggerReason: candidate.reason,
        ),
      );
      debugPrint(
        '[EchoComment] ${candidate.character.displayName}计划评论：'
        '${scheduledAt.toIso8601String()} echoId=${echo.id} '
        'commenterId=${candidate.character.id} '
        'relationship=${candidate.relationship?.stage.label ?? '用户关系'} '
        'reason=${candidate.reason}',
      );
    }
    await _taskStorage.addAll(tasks);
    return tasks.length;
  }

  Future<int> discoverUnscheduledEchoes({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final characters = await _registry.loadCharacters();
    final ownerIds = <String>[
      userEchoOwnerId,
      ...characters.map((item) => item.id),
    ];
    var scheduled = 0;
    for (final ownerId in ownerIds) {
      final echoes = await EchoStorageService(characterId: ownerId).loadItems();
      for (final echo in echoes.take(30)) {
        if (echo.createdAt.isBefore(time.subtract(const Duration(hours: 24)))) {
          continue;
        }
        scheduled += await scheduleForEcho(echo, now: time);
      }
    }
    return scheduled;
  }

  Future<_ExecutionCount> _publishDue({required DateTime now}) async {
    final tasks = await _taskStorage.loadAll();
    final due = tasks
        .where(
          (item) =>
              item.status == EchoCommentTaskStatus.pending &&
              !item.scheduledAt.isAfter(now),
        )
        .toList();
    var published = 0;
    var skipped = 0;
    var failed = 0;

    for (final task in due) {
      final result = await _execute(task, now: now);
      switch (result) {
        case EchoCommentTaskStatus.published:
          published++;
          break;
        case EchoCommentTaskStatus.skipped:
          skipped++;
          break;
        case EchoCommentTaskStatus.failed:
          failed++;
          break;
        case EchoCommentTaskStatus.pending:
          break;
      }
    }
    return _ExecutionCount(
      published: published,
      skipped: skipped,
      failed: failed,
    );
  }

  Future<EchoCommentTaskStatus> _execute(
    EchoCommentTask task, {
    required DateTime now,
  }) async {
    final characters = await _registry.loadCharacters();
    final commenter = _findCharacter(characters, task.commenterId);
    final echo = await _findEcho(task.echoOwnerId, task.echoId);
    if (commenter == null || echo == null) {
      await _skip(task, '角色或 Echo 已不存在');
      return EchoCommentTaskStatus.skipped;
    }

    final commentStorage = EchoCommentStorageService(ownerId: task.echoOwnerId);
    final comments = await commentStorage.loadForEcho(task.echoId);
    if (comments.any(
      (item) =>
          item.authorId == commenter.id &&
          item.sourceType != EchoCommentSourceType.manualCharacterDebug,
    )) {
      await _skip(task, '该角色已经评论过这条 Echo');
      return EchoCommentTaskStatus.skipped;
    }
    if (comments
            .where(
              (item) =>
                  item.authorType == EchoCommentAuthorType.character &&
                  item.sourceType != EchoCommentSourceType.manualCharacterDebug,
            )
            .length >=
        _maxCommentsPerEcho) {
      await _skip(task, '本条 Echo 已达到自动评论上限');
      return EchoCommentTaskStatus.skipped;
    }
    if (!await _withinDailyLimit(commenter.id, characters, now)) {
      await _skip(task, '角色今日自动评论已达上限');
      return EchoCommentTaskStatus.skipped;
    }
    if (!await _cooldownPassed(commenter.id, characters, now)) {
      final postponed = task.copyWith(
        scheduledAt: now.add(const Duration(hours: 1)),
        lastError: '',
      );
      await _taskStorage.update(postponed);
      debugPrint(
        '[EchoComment] ${commenter.displayName}延后：评论冷却中 '
        'echoId=${echo.id} commenterId=${commenter.id}',
      );
      return EchoCommentTaskStatus.pending;
    }

    final author = _findCharacter(characters, echo.characterId);
    final relationship = author == null
        ? null
        : await _relationshipStorage.find(author.id, commenter.id);
    final settings = await CharacterSettingsStorageService(
      characterId: commenter.id,
    ).loadSettings();
    final decision = _policy.evaluate(
      echo: echo,
      commenter: commenter,
      settings: settings,
      relationship: relationship,
      now: now,
    );
    if (!decision.shouldComment) {
      await _skip(task, '执行时重新判断跳过：${decision.reason}');
      return EchoCommentTaskStatus.skipped;
    }
    final userProfile = await UserProfileStorageService().loadProfile();
    final authorName =
        author?.displayName ??
        (echo.characterId == userEchoOwnerId
            ? userProfile.nickname
            : 'Echo 发布者');
    final generator = EchoCommentGenerationService();
    final usedStyles = comments
        .map((item) => item.commentStyle)
        .whereType<EchoCommentStyle>()
        .toSet();
    final relationshipKind =
        relationship?.stage == CharacterRelationshipStage.friend
        ? EchoRelationshipKind.friend
        : EchoRelationshipKind.acquaintance;
    final commentStyle = _diversity.chooseStyle(
      seed: '${echo.id}|${commenter.id}|delayed',
      used: usedStyles,
      relationshipKind: relationshipKind,
    );
    try {
      debugPrint(
        '[EchoComment] 开始生成评论 echoId=${echo.id} '
        'publisherId=${echo.characterId} commenterId=${commenter.id} '
        'reason=${task.triggerReason} model=true fallback=false',
      );
      final content = await generator.generate(
        commenter: commenter,
        authorName: authorName,
        echo: echo,
        existingComments: comments,
        relationship: relationship,
        triggerReason: task.triggerReason,
        contentType: echo.lifeType.name,
        activityLabel: decision.activityLabel,
        styleHint:
            '${decision.styleHint}\n本次评论风格：${_diversity.instruction(commentStyle)}。不得改成其他类型，也不得重复已有评论观点。',
      );
      final comment = EchoComment(
        id: 'auto_comment_${now.microsecondsSinceEpoch}_${commenter.id}',
        echoId: echo.id,
        authorType: EchoCommentAuthorType.character,
        authorId: commenter.id,
        authorNameSnapshot: commenter.displayName,
        authorAvatarSnapshot: commenter.avatarPath,
        content: content,
        createdAt: now,
        sourceType: EchoCommentSourceType.autoCharacter,
        commentType: EchoCommentType.aiCharacter,
        commentStyle: commentStyle,
        relatedLifeEventId: echo.sourceLifeEventId,
        relatedRelationshipId: relationship?.id ?? '',
        metadata: {
          'taskId': task.id,
          'triggerReason': task.triggerReason,
          if (echo.sourceSharedExperienceId.isNotEmpty)
            'sourceSharedExperienceId': echo.sourceSharedExperienceId,
        },
      );
      await commentStorage.add(comment);
      await EchoCommentInteractionService().record(
        echo: echo,
        comment: comment,
      );
      await _replyService.scheduleFor(echo: echo, comment: comment, now: now);
      await _taskStorage.update(
        task.copyWith(
          status: EchoCommentTaskStatus.published,
          publishedAt: now,
          attempts: task.attempts + 1,
          lastError: '',
        ),
      );
      debugPrint(
        '[EchoComment] 评论发布成功 echoId=${echo.id} '
        'publisherId=${echo.characterId} commenterId=${commenter.id}',
      );
      return EchoCommentTaskStatus.published;
    } catch (error) {
      final attempts = task.attempts + 1;
      final terminal = attempts >= 2;
      await _taskStorage.update(
        task.copyWith(
          status: terminal
              ? EchoCommentTaskStatus.failed
              : EchoCommentTaskStatus.pending,
          scheduledAt: terminal
              ? task.scheduledAt
              : now.add(const Duration(hours: 1)),
          attempts: attempts,
          lastError: error.toString(),
        ),
      );
      debugPrint(
        '[EchoComment] 评论生成失败 echoId=${echo.id} '
        'commenterId=${commenter.id} attempts=$attempts error=$error',
      );
      return terminal
          ? EchoCommentTaskStatus.failed
          : EchoCommentTaskStatus.pending;
    } finally {
      generator.dispose();
    }
  }

  Future<bool> _withinDailyLimit(
    String commenterId,
    List<AiCharacter> characters,
    DateTime now,
  ) async {
    final start = DateTime(now.year, now.month, now.day);
    var count = 0;
    for (final ownerId in <String>[
      userEchoOwnerId,
      ...characters.map((item) => item.id),
    ]) {
      final comments = await EchoCommentStorageService(
        ownerId: ownerId,
      ).loadAll();
      count += comments.where((item) {
        return item.authorId == commenterId &&
            item.sourceType == EchoCommentSourceType.autoCharacter &&
            !item.createdAt.isBefore(start);
      }).length;
    }
    return count < _dailyLimitPerCharacter;
  }

  Future<bool> _cooldownPassed(
    String commenterId,
    List<AiCharacter> characters,
    DateTime now,
  ) async {
    DateTime? latest;
    for (final ownerId in <String>[
      userEchoOwnerId,
      ...characters.map((item) => item.id),
    ]) {
      final comments = await EchoCommentStorageService(
        ownerId: ownerId,
      ).loadAll();
      for (final item in comments) {
        if (item.authorId != commenterId ||
            item.sourceType != EchoCommentSourceType.autoCharacter) {
          continue;
        }
        if (latest == null || item.createdAt.isAfter(latest)) {
          latest = item.createdAt;
        }
      }
    }
    return latest == null || now.difference(latest) >= _commentCooldown;
  }

  Future<EchoItem?> _findEcho(String ownerId, String echoId) async {
    final echoes = await EchoStorageService(characterId: ownerId).loadItems();
    for (final echo in echoes) {
      if (echo.id == echoId) return echo;
    }
    return null;
  }

  String? _candidateReason({
    required EchoItem echo,
    required AiCharacter? author,
    required CharacterRelationship? relationship,
  }) {
    if (echo.characterId == userEchoOwnerId) return '用户发布的 Echo';
    if (author == null || relationship == null) return null;
    if (relationship.stage == CharacterRelationshipStage.aware &&
        !echo.isFromSharedExperience) {
      return null;
    }
    if (echo.isFromSharedExperience) return '共同生活事件相关';
    return '已建立${relationship.stage.label}关系';
  }

  Duration _naturalDelay({
    required String echoId,
    required String commenterId,
    required int order,
  }) {
    final seed = _stableScore('$echoId|$commenterId|delay');
    final minutes = 5 + seed % 176 + order * 23;
    return Duration(minutes: minutes.clamp(5, 240).toInt());
  }

  Future<void> _skip(EchoCommentTask task, String reason) async {
    await _taskStorage.update(
      task.copyWith(status: EchoCommentTaskStatus.skipped, skipReason: reason),
    );
    debugPrint(
      '[EchoComment] 跳过：$reason echoId=${task.echoId} '
      'commenterId=${task.commenterId}',
    );
  }

  CharacterRelationship? _findRelationship(
    List<CharacterRelationship> items,
    String firstId,
    String secondId,
  ) {
    final id = CharacterRelationship.buildId(firstId, secondId);
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  AiCharacter? _findCharacter(List<AiCharacter> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  int _stableScore(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + unit);
    }
    return max(0, hash);
  }
}

class _Candidate {
  const _Candidate({
    required this.character,
    required this.relationship,
    required this.reason,
    required this.score,
  });

  final AiCharacter character;
  final CharacterRelationship? relationship;
  final String reason;
  final int score;
}

class _ExecutionCount {
  const _ExecutionCount({
    required this.published,
    required this.skipped,
    required this.failed,
  });

  final int published;
  final int skipped;
  final int failed;
}
