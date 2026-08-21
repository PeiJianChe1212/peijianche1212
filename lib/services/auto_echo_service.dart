import '../models/ai_character.dart';
import '../models/auto_echo_state.dart';
import '../models/echo_item.dart';
import '../models/echo_daily_life.dart';
import '../models/life_moment.dart';
import 'auto_echo_state_service.dart';
import 'auto_echo_policy.dart';
import 'character_profile_storage_service.dart';
import 'character_registry_service.dart';
import 'character_settings_storage_service.dart';
import 'chat_storage_service.dart';
import 'echo_daily_life_service.dart';
import 'echo_generation_service.dart';
import 'echo_duplicate_guard.dart';
import 'echo_social_interaction_service.dart';
import 'echo_storage_service.dart';
import 'life_event_pool_service.dart';
import 'life_moment_storage_service.dart';
import 'relationship_growth_service.dart';
import 'shared_experience_storage_service.dart';
import 'shared_world_event_service.dart';

class AutoEchoReport {
  const AutoEchoReport({required this.checked, required this.published});
  final int checked;
  final int published;
}

enum AutoEchoTrigger { daily, specialEvent, activeShare, initial, debug }

class AutoEchoService {
  static bool _running = false;
  static const Duration _minimumCheckInterval = Duration(hours: 2);
  static const Duration _minimumPublishGap = Duration(hours: 6);
  static const int _maximumPerDay = 3;
  static const int _defaultDailyLimit = 1;

  final CharacterRegistryService _registry = CharacterRegistryService();
  final EchoDailyLifeService _dailyLife = const EchoDailyLifeService();
  final AutoEchoPolicy _policy = const AutoEchoPolicy();
  final EchoDuplicateGuard _duplicateGuard = const EchoDuplicateGuard();

  Future<AutoEchoReport> checkAll({DateTime? now}) async {
    if (_running) return const AutoEchoReport(checked: 0, published: 0);
    _running = true;
    try {
      final time = now ?? DateTime.now();
      final characters = await _registry.loadCharacters();
      var published = 0;
      for (final character in characters) {
        if (await _checkCharacter(character, time)) published++;
      }
      return AutoEchoReport(checked: characters.length, published: published);
    } finally {
      _running = false;
    }
  }

  /// Called after character creation. It is API-free and therefore guarantees
  /// a visible first Echo even when model settings are not ready yet.
  Future<EchoItem?> generateInitialEcho(
    AiCharacter character, {
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final items = await EchoStorageService(
      characterId: character.id,
    ).loadItems();
    if (items.isNotEmpty) return null;
    return _publishDaily(
      character,
      time,
      trigger: AutoEchoTrigger.initial,
      recentUserMessages: 0,
      bypassLimit: true,
    );
  }

  /// Development entry point exposed from Settings.
  Future<EchoItem> generateTestEcho({
    AiCharacter? character,
    DateTime? now,
  }) async {
    final target = character ?? await _registry.loadActiveCharacter();
    final item = await _publishDaily(
      target,
      now ?? DateTime.now(),
      trigger: AutoEchoTrigger.debug,
      recentUserMessages: await _recentUserMessageCount(target.id, now),
      bypassLimit: true,
    );
    if (item == null) throw StateError('没有找到不重复的测试 Echo。');
    return item;
  }

  Future<bool> _checkCharacter(AiCharacter character, DateTime now) async {
    final stateService = AutoEchoStateService(characterId: character.id);
    var state = await stateService.load(now: now);
    final previousCheck = state.lastCheckedAt;
    if (previousCheck != null &&
        now.difference(previousCheck) < _minimumCheckInterval) {
      return false;
    }
    state = state.copyWith(lastCheckedAt: now);
    await stateService.save(state);
    if (state.publishedToday >= _maximumPerDay) return false;

    final items = await EchoStorageService(
      characterId: character.id,
    ).loadItems();
    if (items.isEmpty &&
        now.difference(character.createdAt) <= const Duration(hours: 24)) {
      final initial = await _publishDaily(
        character,
        now,
        trigger: AutoEchoTrigger.initial,
        recentUserMessages: 0,
      );
      return initial != null;
    }

    final recentUserMessages = await _recentUserMessageCount(character.id, now);
    final growthProfile = await RelationshipGrowthService(
      characterId: character.id,
    ).loadOrCreate(metAt: character.createdAt);
    final relationshipLevel = growthProfile.levelFor();
    final lastPublished = state.lastPublishedAt;
    final dailyDue = _policy.isDailyDue(
      characterId: character.id,
      now: now,
      lastPublishedAt: lastPublished,
    );
    final gapPassed =
        lastPublished == null ||
        now.difference(lastPublished) >= _minimumPublishGap;
    if (!gapPassed) return false;

    // Life/Moment remains the richer special-event and active-share layer.
    // Chat activity raises its attempt rate without becoming source content.
    final shouldTryMoment =
        state.publishedToday < _maximumPerDay &&
        _policy.shouldTryMoment(
          characterId: character.id,
          now: now,
          recentUserMessages: recentUserMessages,
          relationshipLevel: relationshipLevel,
        );
    if (shouldTryMoment && await _tryPublishMoment(character, now, state)) {
      return true;
    }

    // One ordinary life Echo per day is enough; special events may use the
    // remaining two slots above it.
    if (dailyDue && state.publishedToday < _defaultDailyLimit) {
      final daily = await _publishDaily(
        character,
        now,
        trigger: AutoEchoTrigger.daily,
        recentUserMessages: recentUserMessages,
        offlineReturn:
            previousCheck != null &&
            now.difference(previousCheck) >= const Duration(hours: 20),
      );
      return daily != null;
    }
    return false;
  }

  Future<bool> _tryPublishMoment(
    AiCharacter character,
    DateTime now,
    AutoEchoState state,
  ) async {
    final generation = EchoGenerationService(character: character);
    try {
      var draft = await generation.tryGenerateDraft(manualRequest: false);
      var decision = generation.lastDecision;
      if (draft == null || decision == null || !decision.shouldShare) {
        return false;
      }
      final firstContent = draft.content;
      draft = await _duplicateGuard.acceptOrRetryOnce(
        initial: draft,
        isDuplicate: (candidate) async => (await _duplicateGuard.check(
          content: candidate.content,
          characterId: character.id,
        )).isDuplicate,
        retry: () => generation.retryLastDraft(previousContent: firstContent),
      );
      if (draft == null) return false;
      final summary = draft.momentSummary.trim();
      if (summary.isNotEmpty &&
          state.recentSummaries.any((old) => _similar(old, summary))) {
        return false;
      }
      final selected = decision.candidate;
      final confirmed = selected.copyWith(occurredAt: now);
      final sharedExperience = await SharedExperienceStorageService()
          .findByLifeEventId(selected.id);
      final item = EchoItem(
        id: 'auto_echo_${now.microsecondsSinceEpoch}',
        characterId: character.id,
        content: draft.content,
        createdAt: _policy.distributedCreatedAt(
          characterId: character.id,
          now: now,
          trigger: 'moment',
        ),
        sourceType: EchoSourceType.futureAutoGenerated,
        lifeType: sharedExperience == null
            ? _lifeTypeForMoment(selected)
            : EchoLifeType.memory,
        sourceEvent: selected.event.trim(),
        characterState: selected.feeling.trim(),
        imagePrompt: draft.imagePrompt,
        imageStatus: draft.imagePrompt.isEmpty ? 'not_needed' : 'pending',
        sourceLifeEventId: selected.id,
        sourceSharedExperienceId: sharedExperience?.id ?? '',
      );
      await EchoStorageService(characterId: character.id).addItem(item);
      await LifeMomentStorageService(
        characterId: character.id,
      ).addItem(confirmed);
      await LifeEventPoolService(
        characterId: character.id,
      ).markUsed(selected.id, now: now);
      await SharedWorldEventService().recordConfirmedMoment(
        originCharacter: character,
        moment: confirmed,
        occurredAt: now,
      );
      await _attachSocialFeedback(item, now);
      await _savePublishedState(character.id, state, now, summary);
      return true;
    } catch (_) {
      return false;
    } finally {
      generation.dispose();
    }
  }

  Future<EchoItem?> _publishDaily(
    AiCharacter character,
    DateTime now, {
    required AutoEchoTrigger trigger,
    required int recentUserMessages,
    bool offlineReturn = false,
    bool bypassLimit = false,
  }) async {
    final stateService = AutoEchoStateService(characterId: character.id);
    final state = await stateService.load(now: now);
    if (!bypassLimit && state.publishedToday >= _maximumPerDay) {
      throw StateError('该角色今天的自动 Echo 已达到上限。');
    }
    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final profile = await CharacterProfileStorageService(
      characterId: character.id,
    ).load(character: character, legacySettings: settings);
    final growthProfile = await RelationshipGrowthService(
      characterId: character.id,
    ).loadOrCreate(metAt: character.createdAt);
    EchoDailyLife? life;
    const maximumAttempts = 16;
    for (var variation = 0; variation < maximumAttempts; variation++) {
      final candidate = _dailyLife.create(
        character: character,
        at: now,
        profile: profile,
        initial: trigger == AutoEchoTrigger.initial,
        offlineReturn: offlineReturn,
        recentUserMessages: recentUserMessages,
        relationshipLevel: growthProfile.levelFor(),
        excludedSummaries: state.recentSummaries,
        variation: variation,
      );
      final duplicate = await _duplicateGuard.check(
        content: candidate.content,
        characterId: character.id,
      );
      if (!duplicate.isDuplicate) {
        life = candidate;
        break;
      }
    }
    if (life == null && trigger == AutoEchoTrigger.initial) {
      final fallback = _dailyLife.create(
        character: character,
        at: now,
        profile: profile,
        initial: true,
        variation: maximumAttempts,
      );
      life = EchoDailyLife(
        kind: fallback.kind,
        content:
            '${fallback.content}就从${character.createdAt.month}月'
            '${character.createdAt.day}日 ${character.createdAt.hour}:'
            '${character.createdAt.minute.toString().padLeft(2, '0')}这一刻开始。',
        summary: fallback.summary,
        sourceEvent: fallback.sourceEvent,
        characterState: fallback.characterState,
      );
    }
    if (life == null) return null;
    final displayedAt = _policy.distributedCreatedAt(
      characterId: character.id,
      now: now,
      trigger: trigger.name,
      recentUserMessages: recentUserMessages,
      offlineReturn: offlineReturn,
    );
    final item = EchoItem(
      id: 'auto_daily_echo_${now.microsecondsSinceEpoch}_${character.id}',
      characterId: character.id,
      content: life.content,
      createdAt: displayedAt,
      sourceType: EchoSourceType.futureAutoGenerated,
      lifeType: life.lifeType,
      sourceEvent: life.sourceEvent,
      characterState: life.characterState,
      imageStatus: 'not_needed',
    );
    await EchoStorageService(characterId: character.id).addItem(item);
    await _attachSocialFeedback(item, now);
    await _savePublishedState(character.id, state, now, life.summary);
    return item;
  }

  Future<void> _attachSocialFeedback(EchoItem item, DateTime now) async {
    try {
      await const EchoSocialInteractionService().generateForEcho(
        item,
        now: now,
      );
    } catch (_) {
      // Echo publication is durable even if optional social simulation fails.
    }
  }

  Future<void> _savePublishedState(
    String characterId,
    AutoEchoState state,
    DateTime now,
    String summary,
  ) async {
    final summaries = <String>[
      summary,
      ...state.recentSummaries,
    ].where((value) => value.trim().isNotEmpty).take(8).toList();
    await AutoEchoStateService(characterId: characterId).save(
      state.copyWith(
        publishedToday: state.publishedToday + 1,
        lastPublishedAt: now,
        lastCheckedAt: now,
        recentSummaries: summaries,
      ),
    );
  }

  Future<int> _recentUserMessageCount(String characterId, DateTime? now) async {
    final time = now ?? DateTime.now();
    final start = time.subtract(const Duration(hours: 24));
    final messages = await ChatStorageService(
      characterId: characterId,
    ).loadMessages();
    return messages
        .where(
          (message) =>
              message.role == 'user' && !message.createdAt.isBefore(start),
        )
        .length;
  }

  EchoLifeType _lifeTypeForMoment(LifeMomentCandidate moment) {
    final facts = [
      moment.scene,
      moment.event,
      moment.detail,
      moment.feeling,
    ].join('|').toLowerCase();
    if (RegExp(r'学习|课程|考试|作业|工作|项目|会议|研究').hasMatch(facts)) {
      return EchoLifeType.workStudy;
    }
    if (RegExp(r'阅读|音乐|游戏|运动|绘画|料理|训练|探索').hasMatch(facts)) {
      return EchoLifeType.interest;
    }
    if (RegExp(r'天气|街道|窗外|地点|风|雨|雪|世界').hasMatch(facts)) {
      return EchoLifeType.environment;
    }
    if (moment.relatedCharacterNames.isNotEmpty ||
        moment.relationshipOpportunityId.trim().isNotEmpty) {
      return EchoLifeType.interaction;
    }
    if (moment.feeling.trim().isNotEmpty) return EchoLifeType.mood;
    return EchoLifeType.daily;
  }

  bool _similar(String a, String b) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？、,.!?;；:：\-—]'), '');
    final left = normalize(a);
    final right = normalize(b);
    return left.isNotEmpty &&
        right.isNotEmpty &&
        (left == right || left.contains(right) || right.contains(left));
  }
}
