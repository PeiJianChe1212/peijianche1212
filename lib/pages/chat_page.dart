import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/activity_status.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/character_settings.dart';
import '../models/user_profile.dart';
import '../services/activity_context_service.dart';
import '../services/activity_service.dart';
import '../services/character_registry_service.dart';
import '../services/chat_image_generation_service.dart';
import '../services/chat_image_request_router_service.dart';
import '../services/chat_image_storage_service.dart';
import '../services/chat_storage_service.dart';
import '../services/deepseek_service.dart';
import '../services/initiative_service.dart';
import '../services/life_trace_service.dart';
import '../services/memory_storage_service.dart';
import '../services/multimodal_service.dart';
import '../services/character_settings_storage_service.dart';
import '../services/today_service.dart';
import '../services/user_profile_storage_service.dart';
import 'peilink/character_management_page.dart';
import '../widgets/chat/chat_input_bar.dart';
import '../widgets/chat/message_renderer.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<ChatMessage> _messages = [];
  final ActivityService _activityService = const ActivityService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatStorageService _chatStorage = ChatStorageService();
  final ChatImageStorageService _chatImageStorage =
      const ChatImageStorageService();
  final ChatImageGenerationService _chatImageGenerationService =
      ChatImageGenerationService();
  final ChatImageRequestRouterService _chatImageRequestRouter =
      ChatImageRequestRouterService();
  final ImagePicker _imagePicker = ImagePicker();
  final MultimodalService _multimodalService = MultimodalService();
  final CharacterSettingsStorageService _characterStorage =
      CharacterSettingsStorageService();
  final UserProfileStorageService _profileStorage = UserProfileStorageService();
  final MemoryStorageService _memoryStorage = MemoryStorageService();
  final DeepSeekService _deepSeekService = DeepSeekService();
  final TodayService _todayService = TodayService();
  final InitiativeService _initiativeService = InitiativeService();
  final LifeTraceService _lifeTraceService = LifeTraceService();
  final CharacterRegistryService _characterRegistry = CharacterRegistryService();

  Timer? _activityTimer;
  Timer? _activityVisibilityTimer;
  DateTime _now = DateTime.now();
  ActivityStatus? _resolvedActivity;

  bool _isLoading = false;
  bool _isGeneratingImage = false;
  bool _showActivitySubtitle = true;
  bool _isRegenerating = false;
  DateTime? _previousSeenAt;
  bool _conversationTraceRecorded = false;
  UserProfile _profile = const UserProfile();
  AiCharacter _activeCharacter = AiCharacter.peiJianChe();
  CharacterSettings _characterSettings = CharacterSettings.defaults();
  String _conversationMode = 'basic';
  double _temperature = 0.72;
  String _replyLength = 'standard';
  double _initiative = 0.58;
  double _intimacy = 0.52;
  double _tsundere = 0.62;

  @override
  void initState() {
    super.initState();
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
    _controller.dispose();
    _scrollController.dispose();
    _deepSeekService.dispose();
    _multimodalService.dispose();
    _chatImageGenerationService.dispose();
    _chatImageRequestRouter.dispose();
    super.dispose();
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
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded.where((message) => message.role != 'error'));
      });
      _scrollToBottom();
    } catch (error) {
      debugPrint('加载聊天记录失败：$error');
      await _createNewConversation();
    }
  }

  Future<void> _saveMessages() async {
    try {
      await _chatStorage.saveMessages(_messages);
    } catch (error) {
      debugPrint('保存聊天记录失败：$error');
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
            content: '我是${_characterSettings.characterName}。',
          ),
        )
        ..add(
          ChatMessage(
            role: 'system',
            type: MessageType.system,
            content:
                '你已与${_characterSettings.characterName}建立羁绊，开始聊天吧。',
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
    if (userMessage.isEmpty || _isLoading) return;
    if (!await _deepSeekService.hasApiKey) {
      _showSnack('还没有配置模型与 API，请先到设置中填写。');
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
    setState(() => _isGeneratingImage = true);

    try {
      final generated = await _chatImageGenerationService.generate(
        userRequest: userRequest,
        characterSettings: _characterSettings,
        recentMessages: List<ChatMessage>.from(_messages),
      );
      final caption = await _deepSeekService.composeImageMessage(
        userRequest: userRequest,
      );
      if (!mounted) return;

      setState(() {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            type: MessageType.image,
            content: caption,
            source: 'generated_image',
            metadata: {
              'imagePath': generated.imagePath,
              'generationPrompt': generated.prompt,
              'generatedBy': 'doubao_image',
            },
          ),
        );
        _isLoading = false;
        _isGeneratingImage = false;
        _isRegenerating = false;
      });
      await _saveMessages();
      if (!_conversationTraceRecorded) {
        _conversationTraceRecorded = true;
        await _lifeTraceService.recordConversation();
      }
      _scrollToBottom();
    } on TimeoutException {
      await _handleImageGenerationError('图片生成超时了，这次先不发图。');
    } on SocketException {
      await _handleImageGenerationError('当前网络连不上图片模型，这次先不发图。');
    } catch (error) {
      await _handleImageGenerationError('图片没有生成成功：$error');
    }
  }

  Future<void> _handleImageGenerationError(String message) async {
    if (!mounted) return;
    setState(() => _isGeneratingImage = false);
    _showSnack(message);
    await _requestReply();
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

      final caption = _controller.text.trim();
      final message = ChatMessage(
        role: 'user',
        type: MessageType.image,
        content: caption,
      );
      final savedPath = await _chatImageStorage.saveImage(
        sourcePath: picked.path,
        messageId: message.id,
      );

      _hideActivitySubtitle();
      setState(() {
        _messages.add(
          message.copyWith(
            metadata: {
              'imagePath': savedPath,
              'visionStatus': 'recognizing',
            },
          ),
        );
        _controller.clear();
        _isLoading = true;
        _isRegenerating = false;
      });
      await _saveMessages();
      _scrollToBottom();

      String description;
      try {
        final result = await _multimodalService.understandForChat(
          imagePath: savedPath,
          userText: caption,
        );
        description = result.description;
      } catch (error) {
        description = '';
        debugPrint('识图失败：$error');
        if (mounted) {
          _showSnack('图片已经发出，但识图失败了。这次会按看不清图片来回复。');
        }
      }

      if (!mounted) return;
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index >= 0) {
        final current = _messages[index];
        setState(() {
          _messages[index] = current.copyWith(
            metadata: {
              ...current.metadata,
              'visionDescription': description,
              'visionStatus': description.isEmpty ? 'failed' : 'completed',
            },
          );
        });
        await _saveMessages();
      }

      await _requestReply();
    } catch (error) {
      await _handleRequestError('发送图片失败：$error');
    }
  }

  Future<void> _requestReply() async {
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
      );
      final readingDelay = Duration(
        milliseconds: (350 + reply.length * 7).clamp(650, 1800).toInt(),
      );
      await Future<void>.delayed(readingDelay);
      if (!mounted) return;
      _hideActivitySubtitle();
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: reply));
        _isLoading = false;
        _isRegenerating = false;
      });
      await _saveMessages();
      if (!_conversationTraceRecorded) {
        _conversationTraceRecorded = true;
        await _lifeTraceService.recordConversation();
      }
      _scrollToBottom();
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

  Future<ActivityStatus> _refreshActivity({DateTime? now}) async {
    final time = now ?? DateTime.now();
    try {
      final activity = await ActivityContextService(
        characterId: _activeCharacter.id,
      ).resolve(now: time);
      if (mounted) setState(() => _resolvedActivity = activity);
      return activity;
    } catch (error) {
      debugPrint('刷新生活状态失败：$error');
      return _activityService.current(
        now: time,
        characterId: _activeCharacter.id,
      );
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

  Future<void> _openCharacterSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CharacterManagementPage()),
    );
    await _loadChatSettings();
    await _loadActiveCharacter();
    await _refreshActivity();
  }

  Future<void> _showMessageActions(int index) async {
    if (_isLoading || index < 0 || index >= _messages.length) return;
    final message = _messages[index];
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

  Future<void> _regenerateFrom(int index) async {
    if (_isLoading || index < 0 || index >= _messages.length) return;
    if (_messages[index].role != 'assistant') return;
    if (!await _deepSeekService.hasApiKey) {
      _showSnack('还没有配置模型与 API，请先到设置中填写。');
      return;
    }

    final confirmed = await _confirmTimelineChange(
      title: '重新生成这条回复？',
      content: index == _messages.length - 1
          ? '当前回复会被替换。'
          : '这条回复和它之后的聊天都会被移除，再从这里重新生成。',
      confirmText: '重新生成',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _messages.removeRange(index, _messages.length);
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

    setState(() => _messages.removeRange(index + 1, _messages.length));
    await _saveMessages();
    _scrollToBottom();
    _showSnack('已经回到这里');
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
    await Future.wait([
      _saveMessages(),
      _memoryStorage.addOrUpdateFavorite(
        messageId: message.id,
        content: message.content,
        isFavorite: nextValue,
      ),
    ]);
    _showSnack(nextValue ? '已收藏到记忆页' : '已取消收藏');
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildAvatar({required bool isUser, double size = 40}) {
    if (!isUser) {
      final path = _activeCharacter.avatarPath.trim();
      final file = path.isEmpty ? null : File(path);
      if (file != null && file.existsSync()) {
        return _SquareAvatar(size: size, image: FileImage(file));
      }
      if (_activeCharacter.isBuiltIn) {
        return _SquareAvatar(
          size: size,
          image: const AssetImage('assets/images/pei_avatar.jpg'),
          alignment: const Alignment(0, -0.15),
        );
      }
      return _AvatarPlaceholder(size: size);
    }

    final avatarPath = _profile.avatarPath.trim();
    final avatarFile = avatarPath.isEmpty ? null : File(avatarPath);
    final hasFile = avatarFile != null && avatarFile.existsSync();
    return _SquareAvatar(
      size: size,
      image: hasFile
          ? FileImage(avatarFile)
          : const AssetImage('assets/images/user_avatar_default.jpg'),
      alignment: const Alignment(0, -0.05),
    );
  }

  ActivityStatus get _activity =>
      _resolvedActivity ??
      _activityService.current(
        now: _now,
        characterId: _activeCharacter.id,
      );

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

  String? get _lastSeenText {
    final previous = _previousSeenAt;
    if (previous == null) return null;
    final now = DateTime.now();
    final difference = now.difference(previous);
    if (difference.inMinutes < 2) return '刚刚还见过你';
    if (difference.inHours < 1) return '上次见你：${difference.inMinutes}分钟前';
    if (difference.inHours < 24) return '上次见你：${difference.inHours}小时前';
    if (difference.inDays == 1) return '上次见你：昨天';
    return '上次见你：${previous.month}月${previous.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 68,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _showActivityDetails,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Column(
              children: [
                Text(
                  _characterSettings.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: _showActivitySubtitle
                      ? Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: AnimatedOpacity(
                            opacity: _showActivitySubtitle ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Column(
                              children: [
                                Text(
                                  _activity.displayText,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                if (_lastSeenText != null)
                                  Text(
                                    _lastSeenText!,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: Colors.black.withValues(
                                        alpha: 0.48,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
        backgroundColor: Colors.blue.shade100,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
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
                      padding: const EdgeInsets.fromLTRB(11, 15, 11, 10),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) => MessageRenderer(
                        message: _messages[index],
                        onLongPress: () => _showMessageActions(index),
                        assistantAvatar: _buildAvatar(isUser: false),
                        userAvatar: _buildAvatar(isUser: true),
                      ),
                    ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 3, 11, 8),
                child: _TypingIndicator(
                  isRegenerating: _isRegenerating,
                  isGeneratingImage: _isGeneratingImage,
                  avatar: _buildAvatar(isUser: false, size: 38),
                ),
              ),
            ChatInputBar(
              controller: _controller,
              isLoading: _isLoading,
              onSend: _sendMessage,
              onPickImage: _pickAndSendImage,
            ),
          ],
        ),
      ),
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
        borderRadius: BorderRadius.circular(10),
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
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(Icons.auto_awesome_rounded, size: size * 0.5, color: const Color(0xFF647C8B)),
  );
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({
    required this.isRegenerating,
    required this.isGeneratingImage,
    required this.avatar,
  });

  final bool isRegenerating;
  final bool isGeneratingImage;
  final Widget avatar;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          widget.avatar,
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                topRight: Radius.circular(17),
                bottomLeft: Radius.circular(5),
                bottomRight: Radius.circular(17),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final phase = (_controller.value - index * 0.18) % 1.0;
                    final lift = phase < 0.5 ? phase / 0.5 : (1 - phase) / 0.5;
                    return Transform.translate(
                      offset: Offset(0, -2.5 * lift),
                      child: Opacity(opacity: 0.42 + 0.58 * lift, child: child),
                    );
                  },
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
                    decoration: const BoxDecoration(
                      color: Color(0xFF6E7781),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              widget.isGeneratingImage
                  ? '正在准备图片…'
                  : widget.isRegenerating
                  ? '重新组织语言…'
                  : '裴简澈正在输入',
              style: const TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ),
        ],
      ),
    );
  }
}
