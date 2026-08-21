import 'dart:convert';

import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/echo_item.dart';
import '../models/relationship_growth.dart';
import '../models/shared_experience.dart';
import 'character_scope_service.dart';
import 'character_registry_service.dart';
import 'echo_storage_service.dart';
import 'echo_duplicate_guard.dart';
import 'echo_social_interaction_service.dart';
import 'shared_experience_storage_service.dart';

class RelationshipGrowthMilestone {
  const RelationshipGrowthMilestone({
    required this.characterId,
    required this.level,
    required this.stage,
  });

  final String characterId;
  final int level;
  final String stage;
}

abstract class RelationshipGrowthMilestoneHook {
  Future<void> onMilestone(RelationshipGrowthMilestone milestone);
}

class RelationshipGrowthService {
  RelationshipGrowthService({
    required String characterId,
    this.config = RelationshipGrowthConfig.standard,
    List<RelationshipGrowthMilestoneHook>? milestoneHooks,
  }) : milestoneHooks =
           milestoneHooks ?? const [PeiLinkRelationshipGrowthMilestoneHook()],
       _characterId = characterId,
       _scope = CharacterScopeService(characterId);

  static const _fileName = 'relationship_growth.json';
  final String _characterId;
  final CharacterScopeService _scope;
  final RelationshipGrowthConfig config;
  final List<RelationshipGrowthMilestoneHook> milestoneHooks;

  Future<RelationshipGrowthProfile> loadOrCreate({DateTime? metAt}) async {
    final file = await _scope.dataFile(_fileName);
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final loaded = RelationshipGrowthProfile.fromJson(decoded);
          if (loaded.characterId.isNotEmpty) return loaded;
        }
      } catch (_) {}
    }
    final now = DateTime.now();
    final profile = RelationshipGrowthProfile(
      characterId: _characterId,
      totalExperience: 0,
      history: [
        RelationshipGrowthEvent(
          id: 'relationship_initialized',
          type: RelationshipGrowthEventType.initialized,
          title: '初次认识',
          detail: '关系成长记录从这里开始',
          experience: 0,
          occurredAt: metAt ?? now,
        ),
      ],
      gifts: const [],
      createdAt: metAt ?? now,
      updatedAt: now,
    );
    await save(profile);
    return profile;
  }

  Future<RelationshipGrowthProfile> synchronize({
    required List<ChatMessage> messages,
    required List<EchoItem> echoes,
    DateTime? metAt,
  }) async {
    var profile = await loadOrCreate(metAt: metAt);
    final existingIds = profile.history.map((item) => item.id).toSet();
    final additions = <RelationshipGrowthEvent>[];
    final visibleMessages =
        messages
            .where(
              (item) => !item.isRecalled && item.type != MessageType.system,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    const chatMilestones = <int, int>{1: 10, 20: 12, 50: 15, 100: 20};
    for (final entry in chatMilestones.entries) {
      final id = 'chat_milestone_${entry.key}';
      if (visibleMessages.length < entry.key || existingIds.contains(id)) {
        continue;
      }
      final time = visibleMessages[entry.key - 1].createdAt;
      additions.add(
        RelationshipGrowthEvent(
          id: id,
          type: RelationshipGrowthEventType.chat,
          title: entry.key == 1 ? '第一次聊天' : '持续交流 ${entry.key} 次',
          detail: '来自真实聊天记录',
          experience: entry.value,
          occurredAt: time,
        ),
      );
      existingIds.add(id);
    }

    for (final echo in echoes) {
      if (!echo.isLiked && !echo.isCollected) continue;
      final id = 'echo_interaction_${echo.id}';
      if (existingIds.contains(id)) continue;
      additions.add(
        RelationshipGrowthEvent(
          id: id,
          type: RelationshipGrowthEventType.echoInteraction,
          title: '第一次留下 Echo 互动',
          detail: echo.isLiked && echo.isCollected
              ? '点赞并收藏了一条动态'
              : echo.isLiked
              ? '点赞了一条动态'
              : '收藏了一条动态',
          experience: echo.isLiked && echo.isCollected ? 10 : 6,
          occurredAt: echo.createdAt,
        ),
      );
      existingIds.add(id);
    }

    if (additions.isEmpty) return profile;
    profile = await _append(profile, additions);
    return profile;
  }

  Future<RelationshipGrowthProfile> giveGift(
    RelationshipGiftType type, {
    DateTime? at,
  }) async {
    final profile = await loadOrCreate();
    final time = at ?? DateTime.now();
    final id = 'gift_${time.microsecondsSinceEpoch}';
    final gift = RelationshipGiftRecord(id: id, type: type, createdAt: time);
    final event = RelationshipGrowthEvent(
      id: 'growth_$id',
      type: RelationshipGrowthEventType.gift,
      title: '收到礼物：${type.label}',
      detail: '由用户赠送',
      experience: type.experience,
      occurredAt: time,
    );
    return _append(profile.copyWith(gifts: [...profile.gifts, gift]), [event]);
  }

  Future<RelationshipGrowthProfile> _append(
    RelationshipGrowthProfile profile,
    List<RelationshipGrowthEvent> additions,
  ) async {
    final previousLevel = profile.levelFor(config);
    final addedExperience = additions.fold<int>(
      0,
      (sum, item) => sum + item.experience,
    );
    final history = [...profile.history, ...additions]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final updated = profile.copyWith(
      totalExperience: profile.totalExperience + addedExperience,
      history: history,
      updatedAt: DateTime.now(),
    );
    await save(updated);
    final nextLevel = updated.levelFor(config);
    for (final level in const [10, 30, 50]) {
      if (previousLevel < level && nextLevel >= level) {
        final milestone = RelationshipGrowthMilestone(
          characterId: _characterId,
          level: level,
          stage: config.stageFor(level),
        );
        for (final hook in milestoneHooks) {
          try {
            await hook.onMilestone(milestone);
          } catch (_) {
            // Optional effects must not roll back persisted growth.
          }
        }
      }
    }
    return updated;
  }

  Future<void> save(RelationshipGrowthProfile profile) async {
    final file = await _scope.dataFile(_fileName);
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }
}

class PeiLinkRelationshipGrowthMilestoneHook
    implements RelationshipGrowthMilestoneHook {
  const PeiLinkRelationshipGrowthMilestoneHook();

  @override
  Future<void> onMilestone(RelationshipGrowthMilestone milestone) async {
    final characters = await CharacterRegistryService().loadCharacters();
    AiCharacter? character;
    for (final item in characters) {
      if (item.id == milestone.characterId) {
        character = item;
        break;
      }
    }
    if (character == null) return;
    final now = DateTime.now();
    if (milestone.level == 10) {
      await SharedExperienceStorageService().saveIfAbsent(
        SharedExperience(
          id: 'growth_milestone_10_${character.id}',
          participantIds: [character.id, 'peilink_user_echo'],
          participantNames: [character.characterName, '你'],
          type: SharedExperienceType.other,
          summary: '关系成长第一次抵达阶段节点',
          detail: '这是一条由真实等级变化产生的成长记录。',
          occurredAt: now,
          createdAt: now,
          importance: 2,
        ),
      );
      return;
    }
    if (milestone.level == 30) {
      const content = '走到新的关系阶段后，回头看见已经留下了一些真实的交流痕迹。把这一刻也记下来。';
      final duplicate = await const EchoDuplicateGuard().check(
        content: content,
        characterId: character.id,
      );
      if (duplicate.isDuplicate) return;
      final echo = EchoItem(
        id: 'growth_milestone_echo_30_${character.id}',
        characterId: character.id,
        content: content,
        createdAt: now,
        sourceType: EchoSourceType.futureAutoGenerated,
        lifeType: EchoLifeType.memory,
        sourceEvent: 'relationship_growth_milestone:30',
        characterState: '有所感触',
        imageStatus: 'not_needed',
      );
      await EchoStorageService(characterId: character.id).addItem(echo);
      try {
        await const EchoSocialInteractionService().generateForEcho(
          echo,
          now: now,
        );
      } catch (_) {
        // The milestone Echo remains durable if optional social feedback fails.
      }
      return;
    }
    if (milestone.level == 50) {
      await RelationshipGrowthService(
        characterId: character.id,
        milestoneHooks: const [],
      ).giveGift(RelationshipGiftType.collectible, at: now);
    }
  }
}
