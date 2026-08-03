import 'dart:math';

import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/character_relationship.dart';
import '../models/echo_item.dart';
import '../models/echo_comment.dart';
import '../models/shared_experience.dart';
import 'ai_social_protocol_service.dart';
import 'character_registry_service.dart';
import 'character_relationship_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'echo_storage_service.dart';
import 'shared_experience_storage_service.dart';

/// 把真实共享经历自然延伸成一条角色 Echo 评论。
///
/// 本服务只处理“是否评论、由谁评论、评论写什么”，不负责修改关系阶段。
class RelationshipEchoCommentService {
  RelationshipEchoCommentService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
  }

  static const Duration _commentCooldown = Duration(hours: 6);

  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;

  final CharacterRegistryService _registry = CharacterRegistryService();
  final CharacterRelationshipStorageService _relationshipStorage =
      CharacterRelationshipStorageService();
  final SharedExperienceStorageService _experienceStorage =
      SharedExperienceStorageService();

  Future<EchoItem> tryAttachComment(EchoItem echo, {DateTime? now}) async {
    final time = now ?? DateTime.now();
    if (!echo.isFromSharedExperience) return echo;
    if (echo.comments.any(
      (item) =>
          item.authorType == EchoCommentAuthorType.character &&
          item.metadata['sourceSharedExperienceId'] ==
              echo.sourceSharedExperienceId,
    )) {
      return echo;
    }

    final experience = await _experienceStorage.findById(
      echo.sourceSharedExperienceId,
    );
    if (experience == null ||
        !experience.containsParticipant(echo.characterId)) {
      return echo;
    }

    final characters = await _registry.loadCharacters();
    final author = _findCharacter(characters, echo.characterId);
    if (author == null) return echo;

    final candidates = characters.where((character) {
      return character.id != author.id &&
          experience.containsParticipant(character.id);
    }).toList();
    if (candidates.isEmpty) return echo;

    candidates.sort(
      (a, b) =>
          _stableScore(echo.id, a.id).compareTo(_stableScore(echo.id, b.id)),
    );

    for (final commenter in candidates) {
      final relationship = await _relationshipStorage.find(
        author.id,
        commenter.id,
      );
      if (!_canCommentAtStage(relationship)) continue;
      if (!await _cooldownPassed(commenter.id, characters, time)) continue;
      if (!_passesChance(echo.id, commenter.id, relationship!.stage)) continue;

      final content = await _generateComment(
        author: author,
        commenter: commenter,
        relationship: relationship,
        experience: experience,
        echo: echo,
      );
      if (content.isEmpty) continue;

      final comment = EchoComment(
        id: 'relationship_comment_${time.microsecondsSinceEpoch}_${commenter.id}',
        echoId: echo.id,
        authorType: EchoCommentAuthorType.character,
        content: content,
        createdAt: time,
        authorId: commenter.id,
        authorNameSnapshot: commenter.displayName,
        authorAvatarSnapshot: commenter.avatarPath,
        sourceType: EchoCommentSourceType.relationshipTriggered,
        commentType: EchoCommentType.aiCharacter,
        relatedLifeEventId: echo.sourceLifeEventId,
        metadata: {'sourceSharedExperienceId': experience.id},
      );
      return echo.copyWith(comments: [...echo.comments, comment]);
    }

    return echo;
  }

  bool _canCommentAtStage(CharacterRelationship? relationship) {
    if (relationship == null || relationship.sharedEventCount < 1) return false;
    return relationship.stage != CharacterRelationshipStage.aware;
  }

  bool _passesChance(
    String echoId,
    String commenterId,
    CharacterRelationshipStage stage,
  ) {
    final threshold = switch (stage) {
      CharacterRelationshipStage.aware => 0,
      CharacterRelationshipStage.acquainted => 28,
      CharacterRelationshipStage.familiar => 38,
      CharacterRelationshipStage.cooperative => 45,
      CharacterRelationshipStage.friend => 52,
    };
    return _stableScore(echoId, commenterId) % 100 < threshold;
  }

  Future<bool> _cooldownPassed(
    String commenterId,
    List<AiCharacter> characters,
    DateTime now,
  ) async {
    DateTime? latest;
    for (final owner in characters) {
      final items = await EchoStorageService(characterId: owner.id).loadItems();
      for (final item in items) {
        for (final comment in item.comments) {
          if (comment.authorId != commenterId ||
              comment.metadata['sourceSharedExperienceId']
                      ?.toString()
                      .isEmpty !=
                  false) {
            continue;
          }
          if (latest == null || comment.createdAt.isAfter(latest)) {
            latest = comment.createdAt;
          }
        }
      }
    }
    return latest == null || now.difference(latest) >= _commentCooldown;
  }

  Future<String> _generateComment({
    required AiCharacter author,
    required AiCharacter commenter,
    required CharacterRelationship relationship,
    required SharedExperience experience,
    required EchoItem echo,
  }) async {
    try {
      final settings = await CharacterSettingsStorageService(
        characterId: commenter.id,
      ).loadSettings();
      final provider = await _modelHub.chatProvider();
      final raw = await provider.complete(
        messages: [
          {
            'role': 'system',
            'content':
                '''
你是${commenter.displayName}，正在 PeiLink 的 Echo 评论区给${author.displayName}留一句评论。

${AiSocialProtocolService.compactRules}

【你的角色性格】
${commenter.persona.trim()}

【双方关系】
阶段：${relationship.stage.label}
共同经历次数：${relationship.sharedEventCount}
关系备注：${relationship.note.trim().isEmpty ? '无' : relationship.note.trim()}

【已经真实发生的共享经历】
类型：${experience.type.label}
地点：${experience.location.trim().isEmpty ? '未记录' : experience.location.trim()}
事情：${experience.summary}
细节：${experience.detail.trim().isEmpty ? '无补充' : experience.detail.trim()}

【对方发布的 Echo】
${echo.content}

只写一条自然短评论，必须遵守：
1. 只依据共享经历和 Echo，不增加新事实。
2. 6 至 28 个汉字，最多一句，像真实朋友圈评论。
3. 符合你的说话方式，可以轻微吐槽，但不吃醋、不争宠、不阴阳怪气、不逼用户选择。
4. 不写动作括号、称呼前缀、引号、解释、系统说明、表情堆叠。
5. 不要写万能客套话，不要重复 Echo 原文。
只输出评论正文。
''',
          },
          {'role': 'user', 'content': '写评论。'},
        ],
        temperature: settings.temperature.clamp(0.58, 0.76).toDouble(),
        maxTokens: 80,
        topP: 0.86,
      );
      final cleaned = _clean(raw);
      if (cleaned.isNotEmpty) return cleaned;
    } catch (_) {
      // 评论属于轻量展示，模型失败时使用事实安全的短句兜底。
    }
    return _fallbackComment(experience, echo.id, commenter.id);
  }

  String _fallbackComment(
    SharedExperience experience,
    String echoId,
    String commenterId,
  ) {
    final options = switch (experience.type) {
      SharedExperienceType.encounter => ['原来你还记得。', '你倒是发得挺快。'],
      SharedExperienceType.conversation => ['这句你倒是记住了。', '重点被你挑走了。'],
      SharedExperienceType.cooperation => ['这次配合得还行。', '结果倒是没白忙。'],
      SharedExperienceType.help => ['举手之劳，也值得发。', '下次别这么客气。'],
      SharedExperienceType.celebration => ['这张留得不错。', '原来你拍了这张。'],
      SharedExperienceType.travel => ['这段路你倒没忘。', '下次记得提前说。'],
      SharedExperienceType.dailyLife => ['你动作倒挺快。', '这点小事也被你发了。'],
      SharedExperienceType.tension => ['这段就别添油加醋。', '看来你记得挺清楚。'],
      SharedExperienceType.other => ['原来你还记得。', '这张还行。'],
    };
    return options[_stableScore(echoId, commenterId) % options.length];
  }

  AiCharacter? _findCharacter(List<AiCharacter> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  int _stableScore(String first, String second) {
    var hash = 17;
    for (final unit in '$first|$second'.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + unit);
    }
    return max(0, hash);
  }

  String _clean(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(RegExp(r'^```(?:text)?\s*'), '');
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    value = value.replaceFirst(RegExp(r'^(评论|正文)\s*[:：]\s*'), '');
    if (value.length > 1 &&
        ((value.startsWith('“') && value.endsWith('”')) ||
            (value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    value = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (value.length > 32) value = value.substring(0, 32).trim();
    return value;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
