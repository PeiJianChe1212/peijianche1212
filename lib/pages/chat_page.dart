import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/activity_status.dart';
import '../conversation/reply_segment_parser.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/message_list_status.dart';
import '../models/red_packet_data.dart';
import '../models/character_settings.dart';
import '../models/user_profile.dart';
import '../services/activity_context_service.dart';
import '../services/activity_service.dart';
import '../services/ai_red_packet_event_service.dart';
import '../services/ai_red_packet_opportunity_service.dart';
import '../services/auto_memory_extraction_service.dart';
import '../services/character_registry_service.dart';
import '../services/character_avatar_storage_service.dart';
import '../services/avatar_change_request_service.dart';
import '../services/chat_image_task_manager.dart';
import '../services/chat_image_request_router_service.dart';
import '../services/chat_image_storage_service.dart';
import '../services/chat_storage_service.dart';
import '../services/deepseek_service.dart';
import '../services/initiative_service.dart';
import '../services/life_trace_service.dart';
import '../services/session_reset_service.dart';
import '../services/character_settings_storage_service.dart';
import '../services/today_service.dart';
import '../services/user_profile_storage_service.dart';
import 'peilink/character_detail_page.dart';
import 'peilink/character_creation_page.dart';
import 'peilink/chat_settings_page.dart';
import 'peilink/character_user_profile_page.dart';
import '../widgets/chat/chat_input_area.dart';
import '../theme/app_theme_background.dart';
import '../widgets/chat/message_renderer.dart';
import '../widgets/chat/red_packet_send_dialog.dart';
import '../widgets/chat/renderers/red_packet_message_renderer.dart';
import '../widgets/peilink/relationship_badge.dart';
import '../widgets/peilink/role_status_mark.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.backDestinationBuilder});

  /// Optional destination used when this chat needs a custom back route.
  final WidgetBuilder? backDestinationBuilder;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  final ActivityService _activityService = const ActivityService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ChatStorageService _chatStorage = ChatStorageService();
  final ChatImageStorageService _chatImageStorage =
      const ChatImageStorageService();
  final ChatImageTaskManager _imageTaskManager = ChatImageTaskManager.instance;
  final ChatImageRequestRouterService _chatImageRequestRouter =
      ChatImageRequestRouterService();
  final ImagePicker _imagePicker = ImagePicker();
  final CharacterSettingsStorageService _characterStorage =
      CharacterSettingsStorageService();
  final UserProfileStorageService _profileStorage = UserProfileStorageService();
  final DeepSeekService _deepSeekService = DeepSeekService();
  final TodayService _todayService = TodayService();
  final InitiativeService _initiativeService = InitiativeService();
  final LifeTraceService _lifeTraceService = LifeTraceService();
  final CharacterRegistryService _characterRegistry =
      CharacterRegistryService();

  Timer? _activityTimer;
  Timer? _activityVisibilityTimer;
  StreamSubscription<String>? _chatResetSubscription;
  DateTime _now = DateTime.now();
  ActivityStatus? _resolvedActivity;

  bool _isLoading = false;
  bool _isGeneratingImage = false;
  bool _showActivitySubtitle = true;
  bool _isRegenerating = false;
  bool _showMoreFunctions = false;
  DateTime? _previousSeenAt;
  bool _conversationTraceRecorded = false;
  UserProfile _profile = const UserProfile();
  AiCharacter _activeCharacter = AiCharacter.placeholder();
  CharacterSettings _characterSettings = CharacterSettings.genericDefaults();
  bool _isRedirectingBack = false;
  String? _pendingImagePath;
  String _conversationMode = 'basic';
  double _temperature = 0.72;
  String _replyLength = 'standard';
  double _initiative = 0.58;
  double _intimacy = 0.52;
  double _tsundere = 0.62;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _imageTaskManager.addListener(_onImageTaskChanged);
    UserProfileStorageService.changes.addListener(_onUserProfileChanged);
    _chatResetSubscription = SessionResetService.chatResets.listen(
      _onChatReset,
    );
    _syncImageTaskState();
    _initializeApp();
    _recordCurrentActivity();
    _activityVisibilityTimer = Timer(const Duration(seconds: 24), () {
      if (mounted) setState(() => _showActivitySubtitle = false);
    });
    _activityTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() => _now = now);
      await _recordCurrentActivity(now: now);
    });
  }

  @override
  void dispose() {
    _activityTimer?.cancel();
    _activityVisibilityTimer?.cancel();
    _chatResetSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _deepSeekService.dispose();
    _imageTaskManager.removeListener(_onImageTaskChanged);
    UserProfileStorageService.changes.removeListener(_onUserProfileChanged);
    _chatImageRequestRouter.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 键盘弹出、收起或高度变化时，让最后一条消息始终停在输入框上方。
    _scrollToBottom(delay: const Duration(milliseconds: 80));
  }

  Future<void> _initializeApp() async {
    await Future.wait([
      _loadChatSettings(),
      _loadProfile(),
      _loadActiveCharacter(),
      _initiativeService.markAllRead(),
      _loadPreviousSeen(),
    ]);
    await _refreshActivity();
    await _loadMessages();
  }

  Future<void> _loadPreviousSeen() async {
    try {
      final previous = await _lifeTraceService.beginVisit();
      if (!mounted) return;
      setState(() => _previousSeenAt = previous);
    } catch (error) {
      debugPrint('记录上次见面失败：$error');
    }
  }

  Future<void> _loadActiveCharacter() async {
    try {
      final character = await _characterRegistry.loadActiveCharacter();
      if (!mounted) return;
      setState(() {
        _activeCharacter = character;
        _resolvedActivity = null;
      });
      _syncImageTaskState();
    } catch (error) {
      debugPrint('加载当前角色失败：$error');
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileStorage.loadProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (error) {
      debugPrint('加载用户资料失败：$error');
    }
  }

  void _onUserProfileChanged() {
    unawaited(_loadProfile());
  }

  Future<void> _loadChatSettings() async {
    try {
      final settings = await _characterStorage.loadSettings();
      if (!mounted) return;
      setState(() {
        _characterSettings = settings;
        _conversationMode = settings.conversationMode;
        _temperature = settings.temperature;
        _replyLength = settings.replyLength;
        _initiative = settings.initiative;
        _intimacy = settings.intimacy;
        _tsundere = settings.tsundere;
      });
    } catch (error) {
      debugPrint('加载角色聊天设置失败：$error');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final loaded = await _chatStorage.loadMessages();
      if (loaded.isEmpty) {
        await _createNewConversation();
        return;
      }
      if (!mounted) return;
      final normalized = loaded
          .where((message) => message.role != 'error')
          .map(_normalizeCharacterDisplayName)
          .toList();
      setState(() {
        _messages
          ..clear()
          ..addAll(normalized);
      });
      _scrollToBottom();
    } catch (error) {
      debugPrint('加载聊天记录失败：$error');
      await _createNewConversation();
    }
  }

  ChatMessage _normalizeCharacterDisplayName(ChatMessage message) {
    if (message.type != MessageType.system ||
        !message.content.contains('建立羁绊')) {
      return message;
    }
    return message.copyWith(content: '你已与$_activeDisplayName建立羁绊，开始聊天吧。');
  }

  Future<bool> _saveMessages() async {
    try {
      await _chatStorage.saveMessages(_messages);
      return true;
    } catch (error) {
      debugPrint('保存聊天记录失败：$error');
      return false;
    }
  }

  Future<void> _createNewConversation() async {
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..add(
          ChatMessage(
            role: 'assistant',
            content: '我是${_activeCharacter.characterName}。',
          ),
        )
        ..add(
          ChatMessage(
            role: 'system',
            type: MessageType.system,
            content: '你已与${_activeCharacter.displayName}建立羁绊，开始聊天吧。',
          ),
        );
      _controller.clear();
      _isLoading = false;
      _isGeneratingImage = false;
      _isRegenerating = false;
      _conversationTraceRecorded = false;
    });
    await _saveMessages();
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final userMessage = _controller.text.trim();
    if ((userMessage.isEmpty && _pendingImagePath == null) || _isLoading) {
      return;
    }
    if (!await _deepSeekService.hasApiKey) {
      _showSnack('还没有配置模型与 API，请先到设置中填写。');
      return;
    }

    if (_pendingImagePath != null) {
      await _sendPendingImage(userMessage);
      return;
    }
    _hideActivitySubtitle();
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: userMessage));
      _controller.clear();
      _isLoading = true;
      _isRegenerating = false;
    });
    await _saveMessages();
    _scrollToBottom();

    final decision = await _chatImageRequestRouter.decide(
      userText: userMessage,
      recentMessages: List<ChatMessage>.from(_messages),
    );
    if (decision.shouldGenerateImage) {
      await _requestGeneratedImage(userMessage);
    } else {
      await _requestReply();
    }
  }

  Future<void> _requestGeneratedImage(String userRequest) async {
    if (!mounted) return;
    setState(() {
      _isGeneratingImage = true;
      _isLoading = true;
    });

    await _imageTaskManager.start(
      userRequest: userRequest,
      character: _activeCharacter,
      recentMessages: List<ChatMessage>.from(_messages),
    );
  }

  void _syncImageTaskState() {
    final state = _imageTaskManager.state;
    if (state.characterId.isNotEmpty &&
        state.characterId != _activeCharacter.id) {
      return;
    }
    final running = state.status == ChatImageTaskStatus.running;
    _isGeneratingImage = running;
    if (running) _isLoading = true;
    if (state.status == ChatImageTaskStatus.completed ||
        state.status == ChatImageTaskStatus.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_handleImageTaskChanged());
      });
    }
  }

  void _onImageTaskChanged() {
    unawaited(_handleImageTaskChanged());
  }

  Future<void> _handleImageTaskChanged() async {
    if (!mounted) return;
    final state = _imageTaskManager.state;
    if (state.characterId.isNotEmpty &&
        state.characterId != _activeCharacter.id) {
      return;
    }

    if (state.status == ChatImageTaskStatus.running) {
      setState(() {
        _isGeneratingImage = true;
        _isLoading = true;
      });
      return;
    }

    if (state.status == ChatImageTaskStatus.completed) {
      await _loadMessages();
      if (!mounted) return;
      setState(() {
        _isGeneratingImage = false;
        _isLoading = false;
        _isRegenerating = false;
      });
      if (!_conversationTraceRecorded) {
        _conversationTraceRecorded = true;
        await _lifeTraceService.recordConversation();
      }
      _imageTaskManager.clearFinishedState();
      _scrollToBottom();
      return;
    }

    if (state.status == ChatImageTaskStatus.failed) {
      setState(() {
        _isGeneratingImage = false;
        _isLoading = false;
        _isRegenerating = false;
      });
      final error = state.errorMessage;
      _imageTaskManager.clearFinishedState();
      if (error != null && error.isNotEmpty) _showSnack(error);
      if (state.kind == ChatImageTaskKind.generatedImage) {
        await _requestReply();
      } else {
        await _loadMessages();
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_isLoading) return;
    if (!await _deepSeekService.hasApiKey) {
      _showSnack('还没有配置日常聊天模型与 API，请先到设置中填写。');
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2048,
      );
      if (picked == null || !mounted) return;
      setState(() => _pendingImagePath = picked.path);
      _inputFocusNode.requestFocus();
    } catch (error) {
      _showSnack('选择图片失败：$error');
    }
  }

  Future<void> _sendPendingImage(String caption) async {
    final pickedPath = _pendingImagePath;
    if (pickedPath == null) return;
    if (_imageTaskManager.isRunning) {
      _showSnack('另一个图片任务还在处理，请稍后再发送。');
      return;
    }
    try {
      final message = ChatMessage(
        role: 'user',
        type: MessageType.image,
        content: caption,
      );
      final savedPath = await _chatImageStorage.saveImage(
        sourcePath: pickedPath,
        messageId: message.id,
      );

      _hideActivitySubtitle();
      setState(() {
        _messages.add(
          message.copyWith(
            metadata: {'imagePath': savedPath, 'visionStatus': 'recognizing'},
          ),
        );
        _controller.clear();
        _pendingImagePath = null;
        _isLoading = true;
        _isRegenerating = false;
      });
      await _saveMessages();
      _scrollToBottom();

      _imageTaskManager.startUserImage(
        characterId: _activeCharacter.id,
        messageId: message.id,
        imagePath: savedPath,
        caption: caption,
        conversationMode: _conversationMode,
        temperature: _temperature,
        replyLength: _replyLength,
        initiative: _initiative,
        intimacy: _intimacy,
        tsundere: _tsundere,
      );
    } catch (error) {
      await _handleRequestError('发送图片失败：$error');
    }
  }

  Future<void> _requestAvatarChange() async {
    if (_isLoading) return;
    _closeMorePanel();
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 96,
        maxWidth: 2200,
      );
      if (picked == null || !mounted) return;
      final bytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AvatarCropDialog(imagePath: picked.path),
      );
      if (bytes == null || !mounted) return;

      final avatarStorage = const CharacterAvatarStorageService();
      await avatarStorage.savePendingAvatarBytes(
        characterId: _activeCharacter.id,
        bytes: bytes,
      );
      final decision = await AvatarChangeRequestService(
        characterId: _activeCharacter.id,
      ).decide();
      if (decision.accepted) {
        final path = await avatarStorage.acceptPendingSocialAvatar(
          characterId: _activeCharacter.id,
        );
        final updated = _activeCharacter.copyWith(socialAvatarPath: path);
        await _characterRegistry.updateCharacter(updated);
        if (!mounted) return;
        setState(() => _activeCharacter = updated);
      } else {
        await avatarStorage.clearPendingAvatar(_activeCharacter.id);
      }

      if (mounted) _showSnack(decision.accepted ? '社交头像已更新' : 'Ta 暂时不想使用这张头像');
    } catch (error) {
      debugPrint('更换角色头像失败：$error');
      if (mounted) _showSnack('更换头像失败，请稍后再试');
    }
  }

  Future<void> _requestReply({String transientEventContext = ''}) async {
    final memoryCharacterId = _activeCharacter.id;
    final memoryUserMessageId = _messages
        .where((m) => m.role == 'user')
        .lastOrNull
        ?.id;
    try {
      final reply = await _deepSeekService.sendMessage(
        messages: List<ChatMessage>.from(_messages),
        conversationMode: _conversationMode,
        temperature: _temperature,
        replyLength: _replyLength,
        initiative: _initiative,
        intimacy: _intimacy,
        tsundere: _tsundere,
        characterId: _activeCharacter.id,
        transientEventContext: transientEventContext,
      );
      if (reply.trim().isEmpty) {
        if (!mounted) return;
        _hideActivitySubtitle();
        setState(() {
          _isLoading = false;
          _isRegenerating = false;
        });
        return;
      }
      final segments = ReplySegmentParser.parse(reply);
      if (segments.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final streamId = DateTime.now().microsecondsSinceEpoch.toString();
      var replyPersisted = true;
      for (var index = 0; index < segments.length; index++) {
        final segment = segments[index];
        final delay = index == 0
            ? (320 + segment.length * 8).clamp(520, 1500)
            : (260 + segment.length * 10).clamp(380, 1100);
        await Future<void>.delayed(Duration(milliseconds: delay.toInt()));
        if (!mounted) return;
        _hideActivitySubtitle();
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: segment,
              source: 'reply_segment',
              metadata: {
                'replyStreamId': streamId,
                'segmentIndex': index,
                'segmentCount': segments.length,
              },
            ),
          );
          if (index == segments.length - 1) {
            _isLoading = false;
            _isRegenerating = false;
          }
        });
        final saved = await _saveMessages();
        replyPersisted = replyPersisted && saved;
        _scrollToBottom();
      }
      AutoMemoryExtractionService.afterReplySaved(
        characterId: memoryCharacterId,
        replyPersisted: replyPersisted,
        userMessageId: memoryUserMessageId,
      );
      if (!_conversationTraceRecorded) {
        _conversationTraceRecorded = true;
        await _lifeTraceService.recordConversation();
      }
      if (transientEventContext.trim().isEmpty) {
        await _maybeSendAiRedPacket();
      }
    } on TimeoutException {
      await _handleRequestError('连接超时了，稍后再试一次。');
    } on SocketException {
      await _handleRequestError('当前无法连接网络，请检查网络后重试。');
    } catch (error) {
      await _handleRequestError('请求失败：$error');
    }
  }

  Future<void> _handleRequestError(String message) async {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isGeneratingImage = false;
      _isRegenerating = false;
    });
    _showSnack(message);
  }

  Future<void> _maybeSendAiRedPacket() async {
    try {
      final snapshot = List<ChatMessage>.from(_messages);
      final opportunity = await _deepSeekService.evaluateRedPacketOpportunity(
        messages: snapshot,
      );
      if (!opportunity.shouldSendRedPacket || !mounted) return;

      final amount = const AiRedPacketOpportunityService().amountInCents(
        opportunity,
      );
      if (amount <= 0) return;
      final message = ChatMessage(
        role: 'assistant',
        content: '',
        source: 'ai_red_packet_opportunity',
        type: MessageType.redPacket,
        redPacket: RedPacketData(
          amount: amount,
          message: opportunity.kind.name == 'specialEvent'
              ? '给你的小庆祝'
              : '今天要对自己好一点',
          senderId: _activeCharacter.id,
          receiverId: 'user',
        ),
        metadata: {
          'opportunityReason': opportunity.reason,
          'opportunityKind': opportunity.kind.name,
          'futureGiftIntent': opportunity.futureGiftIntent,
        },
      );
      setState(() => _messages.add(message));
      await _saveMessages();
      _scrollToBottom();
    } catch (error) {
      debugPrint('AI red packet opportunity skipped: $error');
    }
  }

  Future<ActivityStatus> _refreshActivity({DateTime? now}) async {
    final time = now ?? DateTime.now();
    try {
      final activity = await ActivityContextService(
        characterId: _activeCharacter.id, // ← 加这一行
      ).resolve(now: time);
      if (mounted) setState(() => _resolvedActivity = activity);
      return activity;
    } catch (error) {
      debugPrint('刷新生活状态失败：$error');
      return _activityService.current(now: time);
    }
  }

  Future<void> _recordCurrentActivity({DateTime? now}) async {
    try {
      final time = now ?? DateTime.now();
      final activity = await _refreshActivity(now: time);
      await _todayService.recordActivity(activity, now: time);
    } catch (error) {
      debugPrint('记录 Today 失败：$error');
    }
  }

  void _hideActivitySubtitle() {
    _activityVisibilityTimer?.cancel();
    if (!mounted || !_showActivitySubtitle) return;
    setState(() => _showActivitySubtitle = false);
  }

  Future<void> _openActiveCharacterDetail() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CharacterDetailPage(character: _activeCharacter),
      ),
    );
    await _loadChatSettings();
    await _loadActiveCharacter();
  }

  Future<void> _openCharacterSettings() async {
    final chatReset = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatSettingsPage(character: _activeCharacter),
      ),
    );
    await _loadChatSettings();
    await _loadActiveCharacter();
    await _refreshActivity();
    if (chatReset == true) await _loadMessages();
  }

  void _onChatReset(String _) {
    if (!mounted) return;
    _loadMessages();
  }

  void _toggleMorePanel() {
    if (_isLoading) return;
    _inputFocusNode.unfocus();
    setState(() => _showMoreFunctions = !_showMoreFunctions);
    if (_showMoreFunctions) _scrollToBottom();
  }

  void _closeMorePanel() {
    if (!_showMoreFunctions || !mounted) return;
    setState(() => _showMoreFunctions = false);
  }

  Future<void> _showRedPacketSendDialog() async {
    if (_isLoading || !mounted) return;
    _closeMorePanel();
    final draft = await showDialog<RedPacketDraft>(
      context: context,
      builder: (_) => const RedPacketSendDialog(),
    );
    if (draft == null || !mounted) return;

    _hideActivitySubtitle();
    final message = buildRedPacketMessage(
      draft,
      receiverId: _activeCharacter.id,
    );
    setState(() => _messages.add(message));
    await _saveMessages();
    _scrollToBottom();

    final event = await AiRedPacketEventService(
      characterId: _activeCharacter.id,
      storage: _chatStorage,
    ).receive(message);
    if (event == null || !mounted) return;

    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      setState(() => _messages[index] = event.message);
    }
    if (!event.shouldGenerateReply || !await _deepSeekService.hasApiKey) return;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isRegenerating = false;
    });
    await _requestReply(transientEventContext: event.buildContext());
  }

  Future<void> _showMessageActions(int index) async {
    if (_isLoading || index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    if (message.isRecalled) return;
    HapticFeedback.selectionClick();

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('复制'),
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
              if (message.role == 'user')
                ListTile(
                  leading: const Icon(Icons.undo_rounded),
                  title: const Text('撤回'),
                  onTap: () => Navigator.pop(sheetContext, 'recall'),
                ),
              if (message.role == 'assistant')
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('重新生成'),
                  subtitle: const Text('从这条回复之前重新生成，后续内容会被移除'),
                  onTap: () => Navigator.pop(sheetContext, 'regenerate'),
                ),
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('回溯到这里'),
                subtitle: const Text('保留这一条，删除它之后的聊天'),
                onTap: () => Navigator.pop(sheetContext, 'rollback'),
              ),
              if (message.role == 'assistant')
                ListTile(
                  leading: Icon(
                    message.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: message.isFavorite ? Colors.pink : null,
                  ),
                  title: Text(message.isFavorite ? '取消收藏' : '收藏回复'),
                  onTap: () => Navigator.pop(sheetContext, 'favorite'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.content));
        _showSnack('已复制');
        break;
      case 'recall':
        await _recallMessage(message.id);
        break;
      case 'regenerate':
        await _regenerateFrom(index);
        break;
      case 'rollback':
        await _rollbackTo(index);
        break;
      case 'favorite':
        await _toggleFavorite(index);
        break;
    }
  }

  Future<void> _recallMessage(String messageId) async {
    try {
      final recalled = await _chatStorage.recallMessage(messageId);
      if (!recalled || !mounted) {
        if (mounted) _showSnack('消息撤回失败');
        return;
      }

      final index = _messages.indexWhere((message) => message.id == messageId);
      if (index < 0) return;
      setState(() {
        _messages[index] = _messages[index].copyWith(
          messageStatus: MessageStatus.recalled,
        );
      });
    } catch (error) {
      debugPrint('撤回消息失败：$error');
      _showSnack('消息撤回失败');
    }
  }

  Future<void> _openRedPacket(String messageId) async {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    final existing = _messages[index].redPacket;
    if (existing == null) return;

    const currentUserId = 'user';
    if (currentUserId == existing.senderId) {
      await _showOwnRedPacketNotice();
      return;
    }
    if (currentUserId != existing.receiverId) {
      _showSnack('你不能领取这个红包');
      return;
    }

    try {
      final updatedMessage = existing.isOpened
          ? _messages[index]
          : await _chatStorage.openRedPacket(
              messageId,
              currentUserId: currentUserId,
            );
      if (updatedMessage == null || !mounted) {
        if (mounted) _showSnack('红包打开失败');
        return;
      }

      final updatedPacket = updatedMessage.redPacket;
      if (updatedPacket == null) return;
      final currentIndex = _messages.indexWhere(
        (message) => message.id == messageId,
      );
      if (currentIndex >= 0 && !existing.isOpened) {
        setState(() => _messages[currentIndex] = updatedMessage);
      }
      await showDialog<void>(
        context: context,
        builder: (_) => RedPacketOpenedDialog(
          data: updatedPacket,
          senderName: _redPacketSenderName(updatedPacket.senderId),
        ),
      );
    } catch (error) {
      debugPrint('打开红包失败：$error');
      _showSnack('红包打开失败');
    }
  }

  Future<void> _showOwnRedPacketNotice() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('这是你发出的红包'),
        content: const Text('等待对方领取'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  String _redPacketSenderName(String senderId) {
    if (senderId == _activeCharacter.id) return _activeDisplayName;
    if (senderId == 'user') return '你';
    final normalized = senderId.trim();
    return normalized.isEmpty ? '对方' : normalized;
  }

  Future<void> _regenerateFrom(int index) async {
    if (_isLoading || index < 0 || index >= _messages.length) return;
    if (_messages[index].role != 'assistant') return;
    final streamId = _messages[index].metadata['replyStreamId']?.toString();
    var regenerateFrom = index;
    if (streamId != null && streamId.isNotEmpty) {
      final firstSegment = _messages.indexWhere(
        (message) => message.metadata['replyStreamId']?.toString() == streamId,
      );
      if (firstSegment >= 0) regenerateFrom = firstSegment;
    }
    if (!await _deepSeekService.hasApiKey) {
      _showSnack('还没有配置模型与 API，请先到设置中填写。');
      return;
    }

    final confirmed = await _confirmTimelineChange(
      title: '重新生成这条回复？',
      content: regenerateFrom == _messages.length - 1
          ? '当前回复会被替换。'
          : '这一组回复和它之后的聊天都会被移除，再从这里重新生成。',
      confirmText: '重新生成',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _messages.removeRange(regenerateFrom, _messages.length);
      _isLoading = true;
      _isRegenerating = true;
    });
    await _saveMessages();
    _scrollToBottom();
    await _requestReply();
  }

  Future<void> _rollbackTo(int index) async {
    if (_isLoading || index < 0 || index >= _messages.length - 1) {
      if (index == _messages.length - 1) _showSnack('已经在这里了');
      return;
    }

    final confirmed = await _confirmTimelineChange(
      title: '回溯到这里？',
      content: '这一条之后的 ${_messages.length - index - 1} 条消息会被删除，且无法恢复。',
      confirmText: '回溯',
    );
    if (!confirmed || !mounted) return;

    final removedMessages = _messages.sublist(index + 1);
    ChatMessage? editableMessage;
    for (final item in removedMessages.reversed) {
      if (item.role == 'user' && item.type == MessageType.text) {
        editableMessage = item;
        break;
      }
    }
    if (editableMessage == null &&
        _messages[index].role == 'user' &&
        _messages[index].type == MessageType.text) {
      editableMessage = _messages[index];
    }

    setState(() {
      _messages.removeRange(index + 1, _messages.length);
      if (editableMessage != null) {
        _controller.text = editableMessage.content;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    });
    await _saveMessages();
    _scrollToBottom();
    _showSnack(editableMessage == null ? '已经回到这里' : '已恢复上一条消息，可以直接修改');
  }

  Future<bool> _confirmTimelineChange({
    required String title,
    required String content,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _toggleFavorite(int index) async {
    if (index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    final nextValue = !message.isFavorite;
    setState(() => _messages[index] = message.copyWith(isFavorite: nextValue));
    await _saveMessages();
    _showSnack(nextValue ? '已收藏这条聊天消息' : '已取消收藏');
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollToBottom({Duration delay = Duration.zero}) {
    Future<void>.delayed(delay, () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    });
  }

  Widget _buildAvatar({required bool isUser, double size = 40}) {
    if (!isUser) {
      final path = _activeCharacter.effectiveSocialAvatarPath.trim();
      final file = path.isEmpty ? null : File(path);
      if (file != null && file.existsSync()) {
        return _SquareAvatar(size: size, image: FileImage(file));
      }
      return _AvatarPlaceholder(size: size);
    }

    final avatarPath = _profile.avatarPath.trim();
    final avatarFile = avatarPath.isEmpty ? null : File(avatarPath);
    final hasFile = avatarFile != null && avatarFile.existsSync();
    if (hasFile) {
      return _SquareAvatar(
        size: size,
        image: FileImage(avatarFile),
        alignment: const Alignment(0, -0.05),
      );
    }
    return _AvatarPlaceholder(size: size);
  }

  String get _activeDisplayName => _activeCharacter.displayName;

  ActivityStatus get _activity =>
      _resolvedActivity ?? _activityService.current(now: _now);

  Future<void> _showActivityDetails() async {
    final activity = _activity;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activity.displayText,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                activity.detail,
                style: const TextStyle(fontSize: 15, height: 1.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePop(bool didPop) {
    final destinationBuilder = widget.backDestinationBuilder;
    if (didPop || destinationBuilder == null || _isRedirectingBack) return;
    _isRedirectingBack = true;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: destinationBuilder));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.backDestinationBuilder == null,
      onPopInvokedWithResult: (didPop, result) => _handlePop(didPop),
      child: _buildChatContent(),
    );
  }

  Widget _buildChatContent() {
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 0,
          toolbarHeight: 62,
          title: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _showActivityDetails,
            child: Row(
              children: [
                _buildAvatar(isUser: false, size: 34),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _isLoading
                          ? const Text(
                              '正在输入…',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            )
                          : _ChatIdentityStatus(
                              relationship: _activeCharacter.relationship,
                              status: _resolvedActivity == null
                                  ? MessageListStatus.online
                                  : MessageListStatus.fromActivity(
                                      _resolvedActivity!,
                                    ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          actions: [
            IconButton(
              tooltip: '角色设置',
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: _openCharacterSettings,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有聊天记录',
                          style: TextStyle(color: Colors.black38, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final previous = index > 0
                              ? _messages[index - 1]
                              : null;
                          final showAvatar =
                              previous == null ||
                              previous.role != message.role ||
                              previous.type == MessageType.system ||
                              message.type == MessageType.system;
                          return MessageRenderer(
                            message: message,
                            showAvatar: showAvatar,
                            onLongPress: () => _showMessageActions(index),
                            assistantAvatar: _buildAvatar(isUser: false),
                            userAvatar: _buildAvatar(isUser: true),
                            onAssistantAvatarTap: _openActiveCharacterDetail,
                            onRedPacketTap: () => _openRedPacket(message.id),
                            currentViewerId: 'user',
                          );
                        },
                      ),
              ),
              ChatInputArea(
                controller: _controller,
                focusNode: _inputFocusNode,
                isLoading: _isLoading,
                isMorePanelOpen: _showMoreFunctions,
                onSend: _sendMessage,
                onMore: _toggleMorePanel,
                onInputTap: _closeMorePanel,
                onUserPersona: () {
                  _closeMorePanel();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CharacterUserProfilePage(
                        characterId: _activeCharacter.id,
                        characterName: _activeDisplayName,
                      ),
                    ),
                  );
                },
                onPickImage: () {
                  _closeMorePanel();
                  _pickAndSendImage();
                },
                onRedPacket: _showRedPacketSendDialog,
                onChangeAvatar: _requestAvatarChange,
                onUnavailable: (feature) => _showSnack('$feature功能敬请期待'),
                pendingImagePath: _pendingImagePath,
                onRemovePendingImage: () =>
                    setState(() => _pendingImagePath = null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatIdentityStatus extends StatelessWidget {
  const _ChatIdentityStatus({required this.relationship, required this.status});

  final String relationship;
  final MessageListStatus status;

  @override
  Widget build(BuildContext context) {
    final hasRelationship =
        RelationshipBadge.displayTextFor(relationship) != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasRelationship) ...[
          Flexible(child: RelationshipBadge(relationship: relationship)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              '·',
              style: TextStyle(color: Color(0xFF9EA7AC), fontSize: 11),
            ),
          ),
        ],
        RoleStatusMark(key: const ValueKey('chat-role-status'), status: status),
      ],
    );
  }
}

class _SquareAvatar extends StatelessWidget {
  const _SquareAvatar({
    required this.size,
    required this.image,
    this.alignment = Alignment.center,
  });

  final double size;
  final ImageProvider image;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        image: DecorationImage(
          image: image,
          fit: BoxFit.cover,
          alignment: alignment,
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFE5EBEE),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      Icons.auto_awesome_rounded,
      size: size * 0.5,
      color: const Color(0xFF647C8B),
    ),
  );
}
