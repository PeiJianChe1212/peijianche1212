import 'package:flutter/foundation.dart';

import '../models/echo_comment.dart';
import '../models/echo_comment_interaction.dart';
import '../models/echo_item.dart';
import '../models/shared_experience.dart';
import 'character_registry_service.dart';
import 'echo_comment_interaction_storage_service.dart';
import 'shared_experience_storage_service.dart';

class EchoCommentInteractionService {
  static const String _userId = 'peilink_user';

  final EchoCommentInteractionStorageService _storage =
      EchoCommentInteractionStorageService();
  final SharedExperienceStorageService _experienceStorage =
      SharedExperienceStorageService();
  final CharacterRegistryService _registry = CharacterRegistryService();

  Future<void> record({
    required EchoItem echo,
    required EchoComment comment,
    EchoComment? parentComment,
  }) async {
    try {
      await _record(echo: echo, comment: comment, parentComment: parentComment);
    } catch (error) {
      // 关系写回永远不能反过来导致评论发布失败。
      debugPrint(
        '[EchoCommentLink] 写回失败但保留评论 echoId=${echo.id} '
        'commentId=${comment.id} error=$error',
      );
    }
  }

  Future<void> _record({
    required EchoItem echo,
    required EchoComment comment,
    EchoComment? parentComment,
  }) async {
    if (comment.isDeleted ||
        comment.sourceType == EchoCommentSourceType.manualCharacterDebug ||
        comment.authorType == EchoCommentAuthorType.system ||
        comment.authorType == EchoCommentAuthorType.world) {
      return;
    }

    final actorId = comment.authorId.trim().isEmpty
        ? _userId
        : comment.authorId.trim();
    final targetId = parentComment?.authorId.trim().isNotEmpty == true
        ? parentComment!.authorId.trim()
        : _echoOwnerActorId(echo.characterId);
    if (actorId == targetId || targetId.isEmpty) return;

    final combined = [
      echo.content,
      parentComment?.content ?? '',
      comment.content,
    ].join(' ');
    final tone = _toneOf(combined);
    final importance = _importance(
      echo: echo,
      comment: comment,
      parentComment: parentComment,
      tone: tone,
    );
    if (importance < 45) {
      debugPrint(
        '[EchoCommentLink] 跳过轻量评论 echoId=${echo.id} '
        'commentId=${comment.id} importance=$importance',
      );
      return;
    }

    final interactionId = 'echo_interaction_${comment.id}';
    final futureCandidate = _buildFutureCandidate(
      interactionId: interactionId,
      echo: echo,
      comment: comment,
      parentComment: parentComment,
      actorId: actorId,
      targetId: targetId,
      dialogueText: '${parentComment?.content ?? ''} ${comment.content}',
    );
    final interaction = EchoCommentInteraction(
      id: interactionId,
      echoId: echo.id,
      commentId: comment.id,
      parentCommentId: parentComment?.id ?? '',
      actorId: actorId,
      targetId: targetId,
      summary: _summary(echo, comment, parentComment, tone),
      tone: tone,
      importance: importance,
      createdAt: comment.createdAt,
      relatedLifeEventId: comment.relatedLifeEventId.isNotEmpty
          ? comment.relatedLifeEventId
          : echo.sourceLifeEventId,
      relatedRelationshipId: comment.relatedRelationshipId,
      futureCandidateId: futureCandidate?.id ?? '',
      metadata: {
        'sourceType': comment.sourceType.name,
        'echoOwnerId': echo.characterId,
        'hasParentReply': parentComment != null,
      },
    );
    await _storage.add(interaction: interaction, candidate: futureCandidate);
    if (actorId != _userId && targetId != _userId) {
      await _writeRelationshipExperience(
        interaction: interaction,
        actorId: actorId,
        targetId: targetId,
        tone: tone,
      );
    }
    debugPrint(
      '[EchoCommentLink] 重要互动已记录 echoId=${echo.id} '
      'actorId=$actorId targetId=$targetId importance=$importance '
      'lifeCandidate=${futureCandidate != null}',
    );
  }

  int _importance({
    required EchoItem echo,
    required EchoComment comment,
    required EchoComment? parentComment,
    required EchoCommentInteractionTone tone,
  }) {
    var score = 12;
    if (echo.sourceLifeEventId.isNotEmpty) score += 16;
    if (echo.sourceSharedExperienceId.isNotEmpty) score += 20;
    if (parentComment != null) score += 14;
    if (comment.content.trim().length >= 8) score += 8;
    score += switch (tone) {
      EchoCommentInteractionTone.support => 22,
      EchoCommentInteractionTone.concern => 24,
      EchoCommentInteractionTone.celebration => 20,
      EchoCommentInteractionTone.invitation => 28,
      EchoCommentInteractionTone.neutral => 0,
    };
    if (_containsAny(echo.content, [
      '第一次',
      '终于',
      '获奖',
      '夺冠',
      '完成',
      '毕业',
      '生日',
      '纪念日',
    ])) {
      score += 14;
    }
    return score.clamp(0, 100).toInt();
  }

  EchoCommentInteractionTone _toneOf(String text) {
    if (_containsAny(text, ['下次', '一起', '带我', '约', '有空', '改天'])) {
      return EchoCommentInteractionTone.invitation;
    }
    if (_containsAny(text, ['恭喜', '祝贺', '厉害', '夺冠', '获奖', '庆祝'])) {
      return EchoCommentInteractionTone.celebration;
    }
    if (_containsAny(text, ['还好吗', '没事吧', '注意', '休息', '别硬撑', '担心'])) {
      return EchoCommentInteractionTone.concern;
    }
    if (_containsAny(text, ['支持', '陪你', '我在', '加油', '辛苦了'])) {
      return EchoCommentInteractionTone.support;
    }
    return EchoCommentInteractionTone.neutral;
  }

  EchoLifeOpportunityCandidate? _buildFutureCandidate({
    required String interactionId,
    required EchoItem echo,
    required EchoComment comment,
    required EchoComment? parentComment,
    required String actorId,
    required String targetId,
    required String dialogueText,
  }) {
    // 只有角色之间已经形成“一方提出、另一方回复”的行动共识，才进入候选。
    // 单条玩笑、用户参与或调试评论都不能直接安排角色生活。
    if (parentComment == null ||
        parentComment.authorType != EchoCommentAuthorType.character ||
        comment.authorType != EchoCommentAuthorType.character ||
        actorId == _userId ||
        targetId == _userId ||
        !_containsAny(dialogueText, ['下次', '一起', '带我', '约', '有空', '改天'])) {
      return null;
    }
    final time = comment.createdAt;
    return EchoLifeOpportunityCandidate(
      id: 'echo_life_candidate_${comment.id}',
      characterIdA: actorId,
      characterIdB: targetId,
      reason: '双方在 Echo 评论中形成了可继续考虑的共同活动意向',
      suggestedActivity: _activityFrom(dialogueText),
      createdAt: time,
      expiresAt: time.add(const Duration(days: 14)),
      sourceInteractionId: interactionId,
    );
  }

  Future<void> _writeRelationshipExperience({
    required EchoCommentInteraction interaction,
    required String actorId,
    required String targetId,
    required EchoCommentInteractionTone tone,
  }) async {
    final characters = await _registry.loadCharacters();
    String nameOf(String id) {
      for (final item in characters) {
        if (item.id == id) return item.displayName;
      }
      return id;
    }

    final experience = SharedExperience(
      id: 'shared_echo_comment_${interaction.commentId}',
      participantIds: [actorId, targetId],
      participantNames: [nameOf(actorId), nameOf(targetId)],
      type: switch (tone) {
        EchoCommentInteractionTone.support ||
        EchoCommentInteractionTone.concern => SharedExperienceType.help,
        EchoCommentInteractionTone.celebration =>
          SharedExperienceType.celebration,
        _ => SharedExperienceType.conversation,
      },
      summary: interaction.summary,
      detail: '来源：Echo 评论互动',
      occurredAt: interaction.createdAt,
      createdAt: DateTime.now(),
      sourceLifeEventId: interaction.relatedLifeEventId,
      importance: interaction.importance >= 75 ? 3 : 2,
      relationshipOpportunityId: interaction.futureCandidateId,
    );
    await _experienceStorage.saveIfAbsent(experience);
  }

  String _activityFrom(String text) {
    if (_containsAny(text, ['旅行', '出发', '景点', '地方', '带我'])) {
      return '在双方时间合适时考虑一次共同出行';
    }
    if (_containsAny(text, ['吃', '餐厅', '饭', '甜品', '咖啡'])) {
      return '找一个双方都有空的时间一起吃点东西';
    }
    if (_containsAny(text, ['比赛', '训练', '现场'])) {
      return '在不影响训练或工作的前提下共同参与相关活动';
    }
    return '在合适时延续评论中提到的共同活动';
  }

  String _summary(
    EchoItem echo,
    EchoComment comment,
    EchoComment? parent,
    EchoCommentInteractionTone tone,
  ) {
    final action = switch (tone) {
      EchoCommentInteractionTone.support => '表达了支持',
      EchoCommentInteractionTone.concern => '表达了关心',
      EchoCommentInteractionTone.celebration => '回应了重要进展',
      EchoCommentInteractionTone.invitation => '谈到了未来共同活动',
      EchoCommentInteractionTone.neutral => '进行了有意义的公开互动',
    };
    return parent == null
        ? '在 Echo“${_short(echo.content)}”下$action：${_short(comment.content)}'
        : '围绕 Echo“${_short(echo.content)}”形成回复，$action：'
              '${_short(parent.content)} / ${_short(comment.content)}';
  }

  String _echoOwnerActorId(String ownerId) =>
      ownerId == 'peilink_user_echo' ? _userId : ownerId;

  String _short(String value) {
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.length <= 36 ? text : '${text.substring(0, 36)}…';
  }

  bool _containsAny(String text, List<String> keywords) {
    final lower = text.toLowerCase();
    return keywords.any((item) => lower.contains(item.toLowerCase()));
  }
}
