import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/ai_character.dart';
import '../models/echo_comment.dart';
import '../models/echo_comment_reply_task.dart';
import '../models/echo_item.dart';
import 'character_registry_service.dart';
import 'echo_comment_reply_service.dart';
import 'echo_comment_interaction_service.dart';
import 'echo_comment_reply_task_storage_service.dart';
import 'echo_comment_storage_service.dart';
import 'echo_storage_service.dart';

/// Echo 发布者对自动评论最多自动回应一次，避免评论区演变成无限对话。
class AutoEchoCommentReplyService {
  final EchoCommentReplyTaskStorageService _tasks =
      EchoCommentReplyTaskStorageService();
  final CharacterRegistryService _registry = CharacterRegistryService();

  Future<void> scheduleFor({
    required EchoItem echo,
    required EchoComment comment,
    DateTime? now,
  }) async {
    if (echo.characterId == 'peilink_user_echo' ||
        comment.authorId == echo.characterId ||
        comment.replyToCommentId != null) {
      return;
    }
    final time = now ?? DateTime.now();
    final seed = _score('${echo.id}|${comment.id}|reply');
    final shouldReply = echo.isFromSharedExperience || seed % 100 < 46;
    final task = EchoCommentReplyTask(
      id: 'echo_reply_task_${comment.id}',
      echoId: echo.id,
      echoOwnerId: echo.characterId,
      parentCommentId: comment.id,
      publisherId: echo.characterId,
      scheduledAt: time.add(Duration(minutes: 8 + seed % 83)),
      createdAt: time,
      status: shouldReply
          ? EchoCommentReplyTaskStatus.pending
          : EchoCommentReplyTaskStatus.skipped,
      skipReason: shouldReply ? '' : '发布者看到了，但没有必要逐条回复',
    );
    await _tasks.add(task);
    debugPrint(
      '[EchoComment] 发布者回复判断 echoId=${echo.id} '
      'publisherId=${echo.characterId} commentId=${comment.id} '
      'scheduled=$shouldReply',
    );
  }

  Future<void> checkAll({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final tasks = await _tasks.loadAll();
    for (final task in tasks.where((item) =>
        item.status == EchoCommentReplyTaskStatus.pending &&
        !item.scheduledAt.isAfter(time))) {
      await _execute(task, now: time);
    }
    await _tasks.prune(now: time);
  }

  Future<void> _execute(
    EchoCommentReplyTask task, {
    required DateTime now,
  }) async {
    final characters = await _registry.loadCharacters();
    final publisher = _findCharacter(characters, task.publisherId);
    final echo = await _findEcho(task.echoOwnerId, task.echoId);
    if (publisher == null || echo == null) {
      await _skip(task, '发布者或 Echo 已不存在');
      return;
    }

    final storage = EchoCommentStorageService(ownerId: task.echoOwnerId);
    final comments = await storage.loadForEcho(task.echoId);
    final parent = _findComment(comments, task.parentCommentId);
    if (parent == null || parent.isDeleted) {
      await _skip(task, '原评论已不存在');
      return;
    }
    if (comments.any((item) =>
        item.replyToCommentId == parent.id &&
        item.authorId == publisher.id &&
        item.sourceType == EchoCommentSourceType.autoReply)) {
      await _skip(task, '发布者已经回复过这条评论');
      return;
    }

    final service = EchoCommentReplyService(character: publisher);
    try {
      final content = await service.generateReply(
        echo: echo,
        targetComment: parent,
        existingComments: comments,
      );
      final reply = EchoComment(
          id: 'auto_reply_${now.microsecondsSinceEpoch}_${publisher.id}',
          echoId: echo.id,
          authorType: EchoCommentAuthorType.character,
          authorId: publisher.id,
          authorNameSnapshot: publisher.displayName,
          authorAvatarSnapshot: publisher.avatarPath,
          content: content,
          createdAt: now,
          replyToCommentId: parent.id,
          replyToAuthorId: parent.authorId,
          replyToAuthorNameSnapshot: parent.authorNameSnapshot,
          sourceType: EchoCommentSourceType.autoReply,
          relatedLifeEventId: echo.sourceLifeEventId,
          relatedRelationshipId: parent.relatedRelationshipId,
          metadata: {
            'replyTaskId': task.id,
            'automaticDepth': 1,
          },
        );
      await storage.add(reply);
      await EchoCommentInteractionService().record(
        echo: echo,
        comment: reply,
        parentComment: parent,
      );
      await _tasks.update(
        task.copyWith(
          status: EchoCommentReplyTaskStatus.published,
          publishedAt: now,
          attempts: task.attempts + 1,
          lastError: '',
        ),
      );
      debugPrint(
        '[EchoComment] 发布者自动回复成功 echoId=${echo.id} '
        'publisherId=${publisher.id} commentId=${parent.id}',
      );
    } catch (error) {
      final attempts = task.attempts + 1;
      final terminal = attempts >= 2;
      await _tasks.update(
        task.copyWith(
          status: terminal
              ? EchoCommentReplyTaskStatus.failed
              : EchoCommentReplyTaskStatus.pending,
          scheduledAt:
              terminal ? task.scheduledAt : now.add(const Duration(hours: 1)),
          attempts: attempts,
          lastError: error.toString(),
        ),
      );
      debugPrint(
        '[EchoComment] 发布者自动回复失败 echoId=${echo.id} '
        'publisherId=${publisher.id} attempts=$attempts error=$error',
      );
    } finally {
      service.dispose();
    }
  }

  Future<EchoItem?> _findEcho(String ownerId, String echoId) async {
    final items = await EchoStorageService(characterId: ownerId).loadItems();
    for (final item in items) {
      if (item.id == echoId) return item;
    }
    return null;
  }

  AiCharacter? _findCharacter(List<AiCharacter> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  EchoComment? _findComment(List<EchoComment> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _skip(
    EchoCommentReplyTask task,
    String reason,
  ) async {
    await _tasks.update(
      task.copyWith(
        status: EchoCommentReplyTaskStatus.skipped,
        skipReason: reason,
      ),
    );
  }

  int _score(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + unit);
    }
    return max(0, hash);
  }
}
