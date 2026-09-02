import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../conversation/conversation_engine.dart';
import '../conversation/chat_reply_sanitizer.dart';
import '../conversation/conversation_provider_adapter.dart';
import '../conversation/reply_quality_guard.dart';
import '../conversation/peilink_v2_prompt.dart';
import '../models/ai_character.dart';
import '../models/api_settings.dart';
import '../models/ai_red_packet_opportunity.dart';
import '../models/chat_message.dart';
import '../models/character_settings.dart';
import '../models/character_user_profile.dart';
import '../models/memory_retrieval_result.dart';
import '../models/memory_summary.dart';
import '../models/pending_memory.dart';
import '../models/prompt_test_mode.dart';
import '../models/prompt_experiment_mode.dart';
import '../models/user_profile.dart';
import '../context_builder/character_context.dart';
import '../context_builder/context_build_result.dart';
import '../context_builder/conversation_context.dart';
import '../context_builder/existing_memory_context_provider.dart';
import '../context_builder/memory_context.dart';
import '../context_builder/relationship_context.dart';
import '../context_builder/response_strategy_context.dart';
import '../context_builder/temporal_context.dart';
import '../chat_flow/chat_flow_engine.dart';
import '../reply_strategy/reply_strategy_engine.dart';
import '../personality_style/personality_style_engine.dart';
import '../prompt_composer/prompt_composer.dart';
import '../prompt_composer/prompt_context.dart';
import 'activity_context_service.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'character_user_profile_storage_service.dart';
import 'character_archive_storage_service.dart';
import 'character_profile_storage_service.dart';
import 'echo_chat_context_service.dart';
import 'character_registry_service.dart';
import 'character_relationship_context_service.dart';
import 'ai_red_packet_opportunity_service.dart';
import 'context_builder.dart';
import 'prompt_test_context_builder.dart';
import 'prompt_test_mode_service.dart';
import 'prompt_test_snapshot_service.dart';
import 'prompt_experiment_mode_service.dart';
import 'prompt_experiment_context_builder.dart';
import 'relationship_cooldown_service.dart';
import 'shared_world_event_service.dart';
import 'memory2_chat_context_builder.dart';
import 'memory2_retriever.dart';
import 'memory_diagnostics_service.dart';
import 'transient_event_reply_guard.dart';
import 'user_profile_storage_service.dart';

class MemoryExtractionScope {
  const MemoryExtractionScope({
    required this.characterId,
    required this.character,
    required this.characterSettings,
    required this.userProfile,
    required this.userName,
    required this.transcript,
  });

  final String characterId;
  final AiCharacter character;
  final CharacterSettings characterSettings;
  final UserProfile userProfile;
  final String userName;
  final String transcript;
}

typedef Memory2RetrieverFactory =
    Memory2RetrieverGateway Function(String characterId);
typedef CharacterUserProfileLoader =
    Future<CharacterUserProfile> Function(String characterId);

class DeepSeekService {
  DeepSeekService({
    http.Client? client,
    Memory2RetrieverFactory? memory2RetrieverFactory,
    CharacterUserProfileLoader? characterUserProfileLoader,
  }) : _client = client ?? http.Client(),
       _memory2RetrieverFactory =
           memory2RetrieverFactory ??
           ((id) => Memory2Retriever(characterId: id)),
       _characterUserProfileLoader =
           characterUserProfileLoader ??
           ((id) =>
               CharacterUserProfileStorageService(characterId: id).load()) {
    _modelHub = ModelHub(client: _client);
  }

  final http.Client _client;
  late final ModelHub _modelHub;
  final UserProfileStorageService _profileStorage = UserProfileStorageService();
  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();
  final Memory2RetrieverFactory _memory2RetrieverFactory;
  final CharacterUserProfileLoader _characterUserProfileLoader;
  final CharacterSettingsStorageService _characterStorage =
      CharacterSettingsStorageService();

  Future<bool> get hasApiKey async =>
      (await _apiStorage.loadSettings()).isConfigured;

  void dispose() => _client.close();

  Future<String> sendMessage({
    required List<ChatMessage> messages,
    required String conversationMode,
    required double temperature,
    required String replyLength,
    required double initiative,
    required double intimacy,
    required double tsundere,
    String? characterId,
    String transientEventContext = '',
    bool applyStoredChatControls = false,
  }) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }
    final promptTestMode = await PromptTestModeService().load();
    final promptExperiment = await PromptExperimentModeService().load();
    if (promptExperiment != null &&
        promptExperiment.requiredProvider != apiSettings.provider) {
      throw StateError(
        '${promptExperiment.code} 仅支持 ${promptExperiment.requiredProvider.label}，'
        '当前 Provider 是 ${apiSettings.provider.label}。请先切换实验或 Provider。',
      );
    }
    final useFullPeiLinkPrompt =
        promptExperiment == null &&
        promptTestMode == PromptTestMode.peilinkFull;

    final conversationContext = ConversationContext(messages);
    final validConversation = conversationContext.messages;

    final userProfile = await _profileStorage.loadProfile();
    final characterSettings = await CharacterSettingsStorageService(
      characterId: characterId,
    ).loadSettings();
    final registeredCharacters = await CharacterRegistryService()
        .loadCharacters();
    AiCharacter? currentCharacter;
    for (final item in registeredCharacters) {
      if (item.id == characterId) {
        currentCharacter = item;
        break;
      }
    }
    currentCharacter ??= await CharacterRegistryService().loadActiveCharacter();
    final resolvedCharacterId = currentCharacter.id;
    final legacyMemoryContext = promptExperiment == null
        ? const MemoryContext()
        : await ExistingMemoryContextProvider(
            characterId: resolvedCharacterId,
          ).load();
    Memory2RetrieverGateway? memory2Retriever;
    var memory2Retrieval = MemoryRetrievalResult(
      memorySummary: MemorySummary(characterId: resolvedCharacterId),
      diagnostics: const MemoryRetrievalDiagnostics(
        eventCandidates: 0,
        userCandidates: 0,
        legacyCandidates: 0,
        recallIntent: false,
        lifecycleRefreshSucceeded: false,
      ),
    );
    var characterUserProfile = CharacterUserProfile(
      characterId: resolvedCharacterId,
    );
    if (promptExperiment == null) {
      try {
        memory2Retriever = _memory2RetrieverFactory(resolvedCharacterId);
        final latestUser = validConversation
            .where((message) => message.role == 'user')
            .lastOrNull;
        memory2Retrieval = await memory2Retriever.retrieve(
          currentMessage: latestUser?.content ?? '',
          recentMessages: validConversation.length > 1
              ? validConversation.sublist(0, validConversation.length - 1)
              : const [],
          now: DateTime.now(),
        );
        characterUserProfile = await _characterUserProfileLoader(
          resolvedCharacterId,
        );
      } catch (error) {
        // Memory is optional context and must never block the chat request.
        // ignore: avoid_print
        print(
          '[Memory2Chat] characterId=$resolvedCharacterId '
          'degraded errorType=${error.runtimeType}',
        );
      }
    }
    final memory2Prompt = Memory2ChatContextBuilder.build(
      retrieval: memory2Retrieval,
      characterUserProfile: characterUserProfile,
    );
    final memoryContext = MemoryContext(confirmedMemory: memory2Prompt);
    final characterProfile = await CharacterProfileStorageService(
      characterId: currentCharacter.id,
    ).load(character: currentCharacter, legacySettings: characterSettings);
    final characterArchive = await CharacterArchiveStorageService(
      characterId: currentCharacter.id,
    ).load();
    late final String dynamicSystemPrompt;
    if (promptExperiment != null || useFullPeiLinkPrompt) {
      final activity = await ActivityContextService(
        characterId: characterId ?? 'default',
      ).resolve();
      final recentLifeFacts =
          useFullPeiLinkPrompt &&
              characterId != null &&
              characterId.trim().isNotEmpty
          ? await EchoChatContextService(
              characterId: characterId,
            ).buildFactsSection()
          : '';
      final sharedWorldFacts =
          useFullPeiLinkPrompt &&
              characterId != null &&
              characterId.trim().isNotEmpty
          ? await SharedWorldEventService().buildFactsSection(characterId)
          : '';
      final relationshipFacts = useFullPeiLinkPrompt
          ? await CharacterRelationshipContextService().buildFactsSection(
              currentCharacter: currentCharacter,
              allCharacters: registeredCharacters,
            )
          : '';
      dynamicSystemPrompt = PromptExperimentContextBuilder.buildFacts(
        settings: characterSettings,
        profile: characterProfile,
        archive: characterArchive,
        user: userProfile,
        memory: legacyMemoryContext.confirmedMemory,
        currentTime: _buildTimeFact(),
        recentLifeFacts: recentLifeFacts,
        sharedWorldFacts: sharedWorldFacts,
        relationshipFacts: relationshipFacts,
        activity:
            validConversation
                    .where((message) => message.role == 'user')
                    .length <=
                1
            ? activity
            : null,
      );
    } else {
      dynamicSystemPrompt = PromptTestContextBuilder.build(
        mode: promptTestMode,
        memoryPrompt: '',
        transientEventContext: transientEventContext,
        profile: characterProfile,
        settings: characterSettings,
      );
    }
    final baseContext = promptExperiment != null || useFullPeiLinkPrompt
        ? _buildExperimentBaseContext(
            facts: dynamicSystemPrompt,
            conversation: conversationContext,
          )
        : ContextBuilder.buildChatRequest(
            character: CharacterContext(
              settings: characterSettings,
              userProfile: userProfile,
              profile: characterProfile,
              archive: characterArchive,
            ),
            relationship: const RelationshipContext(),
            memory: memoryContext,
            conversation: conversationContext,
            responseStrategy: ResponseStrategyContext(
              dynamicPrompt: dynamicSystemPrompt,
              mediaRules: '',
            ),
            messageContent: (message) => _messageContentForModel(message),
            includeBehaviorRules: false,
            includeBaseRelationshipRules: false,
          );
    final experimentStyleValues = <String, String>{};
    final experimentInternalDependencies = <String>[];
    final composer = PromptComposer(baseContext: baseContext);
    if (promptExperiment != null) {
      composer.addContext(
        PromptContext.extension(
          id: 'peilink_experiment_core',
          content: PromptExperimentContextBuilder.core,
          priority: PromptContextPriority.character,
        ),
      );
      switch (promptExperiment) {
        case PromptExperimentMode.dsA:
        case PromptExperimentMode.dbA:
          break;
        case PromptExperimentMode.dsB:
          composer.addContext(
            PromptContext.extension(
              id: 'conversation_engine',
              content: ConversationEngine.build(
                messages: validConversation,
                conversationMode: conversationMode,
              ).prompt,
              priority: PromptContextPriority.chatFlow,
            ),
          );
        case PromptExperimentMode.dsC:
          final style = const PersonalityStyleEngine().resolveForExperiment(
            settings: applyStoredChatControls
                ? characterSettings
                : characterSettings.copyWith(
                    replyLength: 'standard',
                    initiative: 0.5,
                  ),
          );
          experimentStyleValues.addAll(style.snapshotValues);
          composer.addContext(
            PromptContext.personalityStyle(style.toPromptSection()),
          );
        case PromptExperimentMode.dsD:
          final isInCooldown = await RelationshipCooldownService(
            characterId: characterId,
          ).isInCooldown();
          final flow = const ChatFlowEngine().plan(
            conversationContext,
            isInCooldown: isInCooldown,
          );
          final strategy = const ReplyStrategyEngine().plan(
            conversation: conversationContext,
            flow: flow,
            isInCooldown: isInCooldown,
          );
          experimentInternalDependencies.add(
            'Chat Flow plan (calculation only; Prompt excluded)',
          );
          composer.addContext(
            PromptContext.replyStrategy(strategy.toPromptSection()),
          );
        case PromptExperimentMode.dbB:
          composer.addContext(
            PromptContext.providerAdapter(
              ConversationProviderAdapter.promptFor(AIProvider.volcengine),
            ),
          );
        case PromptExperimentMode.dbC:
          composer
              .addContext(
                PromptContext.providerAdapter(
                  ConversationProviderAdapter.promptFor(AIProvider.volcengine),
                ),
              )
              .addContext(
                PromptContext.replyStrategy(
                  PromptExperimentContextBuilder.simplifiedDoubaoStrategy,
                ),
              );
      }
    } else if (useFullPeiLinkPrompt) {
      composer
          .addContext(
            PromptContext.extension(
              id: 'memory2_context',
              content: memory2Prompt,
              priority: PromptContextPriority.memory,
            ),
          )
          .addContext(
            PromptContext.extension(
              id: 'peilink_v2_core',
              content: PeiLinkV2Prompt.core,
              priority: PromptContextPriority.character,
            ),
          )
          .addContext(
            PromptContext.providerAdapter(
              PeiLinkV2Prompt.adapterFor(apiSettings.provider),
            ),
          );
    }
    final modelContext = composer.compose();

    final provider = await _modelHub.chatProvider(settings: apiSettings);
    MemoryDiagnosticsService.recordPromptInjection(
      characterId: resolvedCharacterId,
      eventIds: memory2Prompt.isEmpty
          ? const []
          : memory2Retrieval.injectedEventIds,
      characterUserProfileInjected:
          memory2Prompt.isNotEmpty &&
          (characterUserProfile.userName.trim().isNotEmpty ||
              characterUserProfile.gender.trim().isNotEmpty ||
              characterUserProfile.effectiveDescription.trim().isNotEmpty),
    );
    if (memory2Retriever != null &&
        memory2Retrieval.injectedEventIds.isNotEmpty &&
        memory2Prompt.isNotEmpty) {
      unawaited(
        _recordMemory2RecallSafely(
          memory2Retriever,
          memory2Retrieval.injectedEventIds,
          now: DateTime.now(),
        ),
      );
    }
    Future<String> complete(List<Map<String, dynamic>> messages) {
      PromptTestSnapshotService.capture(
        mode: promptTestMode,
        messages: messages,
        experiment: promptExperiment,
        provider: apiSettings.provider,
        architecture: useFullPeiLinkPrompt
            ? PeiLinkV2Prompt.architectureName
            : promptExperiment != null
            ? 'Module Experiment ${promptExperiment.code}'
            : 'Legacy Prompt Test',
        providerAdapter: useFullPeiLinkPrompt
            ? PeiLinkV2Prompt.adapterNameFor(apiSettings.provider)
            : '',
        enabledModules:
            promptExperiment?.enabledModules ??
            (useFullPeiLinkPrompt
                ? const [
                    'Character Facts',
                    'PeiLink Core V2',
                    'Provider Adapter V2',
                    'Output Guard',
                  ]
                : const []),
        disabledModules:
            promptExperiment?.disabledModules ??
            (useFullPeiLinkPrompt
                ? const [
                    'Personality Style',
                    'Full Reply Strategy',
                    'Round-modulo Chat Flow',
                    'Legacy Conversation Engine prompt',
                    'Legacy PeiLink Conversation Spec',
                    'Style Examples',
                    'Fixed Response Shape',
                    'Sentence / bubble percentages',
                    'Stored initiative controls',
                    'Every-4 / every-7 round behaviors',
                    'Legacy natural-chat duplicate rules',
                    'Legacy Reply Length duplicate rules',
                    'Duplicate length / initiative rules',
                  ]
                : const []),
        styleValues: experimentStyleValues,
        internalDependencies: experimentInternalDependencies,
      );
      return provider.complete(
        messages: messages,
        temperature: temperature,
        maxTokens: _getMaxTokens(
          applyStoredChatControls ? replyLength : 'long',
          conversationMode,
        ),
        topP: _getTopP(temperature),
      );
    }

    Future<String> generate(List<Map<String, dynamic>> messages) =>
        transientEventContext.trim().isEmpty
        ? complete(messages)
        : TransientEventReplyGuard.completeWithEmptyReplyFallback(
            messages: messages,
            complete: complete,
            localFallback: () => _buildRedPacketFallback(characterSettings),
          );

    final recentAssistantReplies = validConversation
        .where((message) => message.role == 'assistant')
        .map((message) => message.content)
        .toList()
        .reversed
        .take(3)
        .toList();
    final guarded = useFullPeiLinkPrompt
        ? _applyV2OutputGuard(
            await generate(modelContext.messages),
            recentAssistantReplies: recentAssistantReplies,
          )
        : await const ReplyQualityRetryRunner().run(
            recentAssistantReplies: recentAssistantReplies,
            generate: (attempt) {
              final messages = attempt == 0
                  ? modelContext.messages
                  : [
                      ...modelContext.messages.map(
                        (item) => Map<String, dynamic>.from(item),
                      ),
                      const {
                        'role': 'system',
                        'content':
                            '上一版回复未通过质量检查。只重新生成一次：保持角色人格，避免助手模板和近期重复；'
                            '不要输出解释、JSON、消息编号或内部标记。',
                      },
                    ];
              return generate(messages);
            },
          );
    return _cleanReply(guarded);
  }

  Future<void> _recordMemory2RecallSafely(
    Memory2RetrieverGateway retriever,
    Iterable<String> eventIds, {
    required DateTime now,
  }) async {
    try {
      await retriever.recordInjectedEvents(eventIds, now: now);
    } catch (error) {
      // Recall persistence is an optional side effect and never blocks chat.
      // ignore: avoid_print
      print(
        '[Memory2Chat] recallPersistenceFailed '
        'errorType=${error.runtimeType}',
      );
    }
  }

  Future<AiRedPacketOpportunity> evaluateRedPacketOpportunity({
    required List<ChatMessage> messages,
  }) async {
    final provider = await _modelHub.chatProvider();
    return const AiRedPacketOpportunityService().evaluate(
      messages: messages,
      complete: (requestMessages) => provider.complete(
        messages: requestMessages,
        temperature: 0.15,
        maxTokens: 160,
        topP: 0.8,
      ),
    );
  }

  String _messageContentForModel(ChatMessage message) {
    if (message.type != MessageType.image) return message.content;

    final caption = message.content.trim();
    if (message.role == 'assistant') {
      final prompt =
          message.metadata['generationPrompt']?.toString().trim() ?? '';
      final parts = <String>['[角色刚刚发送了一张图片]'];
      if (prompt.isNotEmpty) parts.add('图片场景：$prompt');
      if (caption.isNotEmpty) parts.add('角色随图说：$caption');
      return parts.join('\n');
    }

    final description =
        message.metadata['visionDescription']?.toString().trim() ?? '';
    final parts = <String>['[用户发送了一张图片]'];
    if (description.isNotEmpty) {
      parts.add('图片内容：$description');
    } else {
      parts.add('图片内容暂时无法识别。不要假装看清了具体画面。');
    }
    if (caption.isNotEmpty) parts.add('用户随图片说：$caption');
    parts.add('请按照当前角色的说话方式自然回应图片和用户的话，不要复述识图报告。');
    return parts.join('\n');
  }

  String _buildRedPacketFallback(CharacterSettings settings) {
    if (settings.tsundere >= 0.68) {
      return '……我收下了。下次别这么乱花。';
    }
    if (settings.intimacy >= 0.66) {
      return '收到了。谢谢你，这份心意我会好好收着。';
    }
    return '我收到了，谢谢你。你的心意我记下了。';
  }

  Future<String> composeImageMessage({required String userRequest}) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      return '给你。';
    }

    final characterSettings = await _characterStorage.loadSettings();
    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.imageMessage,
            settings: characterSettings,
            taskRules: '''
你刚刚按照用户的要求生成并发送了一张图片。
现在只写一句自然的随图消息，像聊天里把照片发过去时顺口说的话。
不要解释生成过程，不要说“AI绘图”“模型”“提示词”，不要复述完整画面描述。
通常 4 到 24 个字，最多两句。只输出消息正文。
''',
          ),
        },
        {'role': 'user', 'content': '用户原话：$userRequest'},
      ],
      temperature: 0.72,
      maxTokens: 80,
      topP: 0.86,
    );
    final cleaned = _cleanReply(raw).replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return cleaned.isEmpty ? '给你。' : cleaned;
  }

  Future<List<PendingMemory>> extractMemories({
    required List<ChatMessage> messages,
    required String characterId,
  }) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final conversation = messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .toList();
    final recent = conversation.length > 24
        ? conversation.sublist(conversation.length - 24)
        : conversation;
    if (!recent.any((message) => message.role == 'user')) return [];

    final scope = await buildMemoryExtractionScope(
      characterId: characterId,
      messages: recent,
    );
    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.memoryExtraction,
            settings: scope.characterSettings,
            userProfile: scope.userProfile,
            taskRules: '''
你是 PeiLink 的记忆整理器。只提取关于用户的、长期有效且未来互动确实有帮助的信息。
可以保存：长期兴趣、稳定偏好、害怕或禁忌、重要关系、长期习惯、重要经历、明确约定。
不要保存：当天饮食、天气、临时情绪、随口玩笑、未确认猜测、角色自己的台词和重复信息。
只返回 JSON 数组，不要 Markdown，不要解释，最多 5 条。
格式：
[{"content":"用户……","reason":"说明未来聊天为什么有用","category":"关于我/兴趣偏好/生活习惯/害怕与禁忌/重要关系/经历过的事/我们的约定/共同纪念"}]
没有值得保存的内容时返回 []。
''',
            recentConversation: scope.transcript,
          ),
        },
        {'role': 'user', 'content': scope.transcript},
      ],
      temperature: 0.15,
      maxTokens: 700,
    );
    return _parsePendingMemories(raw);
  }

  Future<MemoryExtractionScope> buildMemoryExtractionScope({
    required String characterId,
    required List<ChatMessage> messages,
  }) async {
    final normalizedId = characterId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(characterId, 'characterId', '不能为空');
    }
    final characters = await CharacterRegistryService().loadCharacters();
    final characterIndex = characters.indexWhere(
      (item) => item.id == normalizedId,
    );
    if (characterIndex < 0) {
      throw StateError('Memory 提取目标角色不存在');
    }
    final character = characters[characterIndex];
    final characterSettings = await CharacterSettingsStorageService(
      characterId: normalizedId,
    ).loadSettings();
    final userProfile = await _profileStorage.loadProfile();
    final rawNickname = userProfile.nickname.trim();
    final userName = rawNickname.isEmpty || rawNickname == '未设置'
        ? '用户'
        : rawNickname;
    final characterName = character.characterName.trim().isEmpty
        ? '角色'
        : character.characterName.trim();
    final transcript = messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .map(
          (message) =>
              '${message.role == 'user' ? userName : characterName}：${message.content}',
        )
        .join('\n');
    return MemoryExtractionScope(
      characterId: normalizedId,
      character: character,
      characterSettings: characterSettings,
      userProfile: userProfile,
      userName: userName,
      transcript: transcript,
    );
  }

  List<PendingMemory> _parsePendingMemories(String raw) {
    var cleaned = raw.trim();
    cleaned = cleaned.replaceFirst(
      RegExp(r'^```(?:json)?\s*', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceFirst(RegExp(r'\s*```$'), '');
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start < 0 || end < start) return [];
    final decoded = jsonDecode(cleaned.substring(start, end + 1));
    if (decoded is! List) return [];
    const allowed = {
      '关于我',
      '兴趣偏好',
      '生活习惯',
      '害怕与禁忌',
      '重要关系',
      '经历过的事',
      '我们的约定',
      '共同纪念',
    };
    return decoded
        .whereType<Map>()
        .map((json) {
          final content = json['content']?.toString().trim() ?? '';
          final reason = json['reason']?.toString().trim() ?? '可能长期有效';
          final rawCategory = json['category']?.toString().trim() ?? '关于我';
          final normalizedCategory = rawCategory == '关于念念'
              ? '关于我'
              : rawCategory;
          return PendingMemory(
            content: content,
            reason: reason,
            category: allowed.contains(normalizedCategory)
                ? normalizedCategory
                : '关于我',
          );
        })
        .where((item) => item.content.isNotEmpty)
        .take(5)
        .toList();
  }

  String _buildTimeFact() {
    return TemporalContext.now().toPromptSection();
  }

  ContextBuildResult _buildExperimentBaseContext({
    required String facts,
    required ConversationContext conversation,
  }) {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': facts},
      ...conversation.recentMessages.map(
        (message) => <String, dynamic>{
          'role': message.role,
          'content': _messageContentForModel(message),
        },
      ),
    ];
    return ContextBuildResult(messages: messages, systemPrompt: facts);
  }

  double _getTopP(double temperature) {
    return (0.78 + (temperature - 0.55) * 0.28).clamp(0.78, 0.88).toDouble();
  }

  int _getMaxTokens(String replyLength, String conversationMode) {
    var maxTokens = switch (replyLength) {
      'short' => 180,
      'long' => 520,
      _ => 300,
    };
    if (conversationMode == 'long' && maxTokens < 480) maxTokens = 480;
    if (conversationMode == 'deep' && maxTokens < 520) maxTokens = 520;
    return maxTokens;
  }

  String _cleanReply(String reply) {
    var cleaned = reply.trim();
    for (final prefix in ['裴简澈：', '裴简澈:', '助手：', '助手:']) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
      }
    }
    if (cleaned.length >= 2 &&
        cleaned.startsWith('“') &&
        cleaned.endsWith('”')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    return ChatReplySanitizer.clean(cleaned);
  }

  String _applyV2OutputGuard(
    String reply, {
    required List<String> recentAssistantReplies,
  }) {
    final result = const ReplyQualityGuard().inspect(
      reply: reply,
      recentAssistantReplies: recentAssistantReplies,
      allowRetry: false,
    );
    return result.output.trim().isEmpty ? '……' : result.output;
  }
}
