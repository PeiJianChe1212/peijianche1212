import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/activity_status.dart';
import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../services/activity_service.dart';
import '../services/chat_storage_service.dart';
import '../services/deepseek_service.dart';
import '../services/memory_storage_service.dart';
import '../services/initiative_service.dart';
import '../services/life_trace_service.dart';
import '../services/memory_review_service.dart';
import '../services/settings_storage_service.dart';
import '../services/session_reset_service.dart';
import '../services/today_service.dart';
import '../services/user_profile_storage_service.dart';

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
  final SettingsStorageService _settingsStorage = SettingsStorageService();
  final UserProfileStorageService _profileStorage = UserProfileStorageService();
  final MemoryStorageService _memoryStorage = MemoryStorageService();
  final MemoryReviewService _memoryReview = MemoryReviewService();
  final DeepSeekService _deepSeekService = DeepSeekService();
  final TodayService _todayService = TodayService();
  final SessionResetService _sessionReset = SessionResetService();
  final InitiativeService _initiativeService = InitiativeService();
  final LifeTraceService _lifeTraceService = LifeTraceService();

  Timer? _activityTimer;
  Timer? _activityVisibilityTimer;
  DateTime _now = DateTime.now();

  bool _isLoading = false;
  bool _showActivitySubtitle = true;
  bool _isRegenerating = false;
  bool _isAnalyzingMemory = false;
  DateTime? _previousSeenAt;
  bool _conversationTraceRecorded = false;
  UserProfile _profile = const UserProfile();
  String _openingMessage = '回来了？今天过得怎么样。';
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
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await Future.wait([
      _loadChatSettings(),
      _loadProfile(),
      _initiativeService.markAllRead(),
      _loadPreviousSeen(),
    ]);
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
      final settings = await _settingsStorage.loadSettings();
      if (!mounted) return;
      setState(() {
        _openingMessage = settings.openingMessage;
        _conversationMode = settings.conversationMode;
        _temperature = settings.temperature;
        _replyLength = settings.replyLength;
        _initiative = settings.initiative;
        _intimacy = settings.intimacy;
        _tsundere = settings.tsundere;
      });
    } catch (error) {
      debugPrint('加载聊天设置失败：$error');
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
          ..addAll(loaded);
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
        ..add(ChatMessage(role: 'assistant', content: _openingMessage));
      _controller.clear();
      _isLoading = false;
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
      _addErrorMessage('还没有配置模型与 API，请先到设置中填写。');
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
    await _requestReply();
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
      _messages.add(ChatMessage(role: 'error', content: message));
      _isLoading = false;
      _isRegenerating = false;
    });
    await _saveMessages();
    _scrollToBottom();
  }

  void _addErrorMessage(String message) {
    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(role: 'error', content: message));
    });
    _saveMessages();
    _scrollToBottom();
  }

  Future<void> _recordCurrentActivity({DateTime? now}) async {
    try {
      final time = now ?? DateTime.now();
      await _todayService.recordActivity(
        _activityService.current(now: time),
        now: time,
      );
    } catch (error) {
      debugPrint('记录 Today 失败：$error');
    }
  }

  void _hideActivitySubtitle() {
    _activityVisibilityTimer?.cancel();
    if (!mounted || !_showActivitySubtitle) return;
    setState(() => _showActivitySubtitle = false);
  }

  Future<void> _showCleanupOptions() async {
    if (_isLoading) {
      _showSnack('等这条回复结束后再整理吧');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '清理与重置',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '选择你真正想清空的范围。',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.chat_bubble_outline_rounded),
                ),
                title: const Text('仅清空聊天'),
                subtitle: const Text('删除消息，但保留长期记忆、待审核记忆和今天。'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmClearChatOnly();
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.red.withValues(alpha: 0.10),
                  child: const Icon(
                    Icons.restart_alt_rounded,
                    color: Colors.red,
                  ),
                ),
                title: const Text('重新开始', style: TextStyle(color: Colors.red)),
                subtitle: const Text(
                  '清空聊天、长期记忆、待审核记忆和 Today。用户资料、人设与 API 会保留。',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmResetStory();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearChatOnly() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('仅清空聊天？'),
        content: const Text('全部消息会被删除，但裴简澈已经确认的记忆和今天的生活记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空聊天'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _sessionReset.clearChatOnly();
      await _loadChatSettings();
      await _createNewConversation();
      _showSnack('聊天已经重新开始，记忆仍然保留');
    } catch (error) {
      _showSnack('清空失败：$error');
    }
  }

  Future<void> _confirmResetStory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新开始这段故事？'),
        content: const Text(
          '这会永久清空聊天记录、长期记忆、待审核记忆和今天的生活时间线。\n\n用户资料、裴简澈人设、头像、壁纸与 API 配置不会受到影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('先不重置'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认重新开始'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _sessionReset.resetSharedStory();
      await _loadChatSettings();
      await _createNewConversation();
      await _recordCurrentActivity();
      _showSnack('已经重新开始');
    } catch (error) {
      _showSnack('重置失败：$error');
    }
  }

  void _handleChatMenu(String value) {
    if (value == 'clear') _showCleanupOptions();
    if (value == 'analyze_memory') _analyzeMemory();
  }

  Future<void> _analyzeMemory() async {
    if (_isLoading || _isAnalyzingMemory) {
      _showSnack('等当前回复结束后再整理记忆吧');
      return;
    }
    if (!await _deepSeekService.hasApiKey) {
      _showSnack('请先配置模型与 API');
      return;
    }
    if (!_messages.any((message) => message.role == 'user')) {
      _showSnack('还没有足够的聊天内容');
      return;
    }

    setState(() => _isAnalyzingMemory = true);
    try {
      final candidates = await _deepSeekService.extractMemories(
        messages: List<ChatMessage>.from(_messages),
      );
      final added = await _memoryReview.addCandidates(candidates);
      if (!mounted) return;
      if (candidates.isEmpty) {
        _showSnack('这段聊天里没有适合长期保存的内容');
      } else if (added == 0) {
        _showSnack('候选记忆已经存在，没有重复添加');
      } else {
        _showSnack('发现 $added 条候选记忆，已送去审核');
      }
    } on TimeoutException {
      _showSnack('记忆分析超时了，稍后再试');
    } on SocketException {
      _showSnack('当前无法连接网络');
    } catch (error) {
      _showSnack('记忆分析失败：$error');
    } finally {
      if (mounted) setState(() => _isAnalyzingMemory = false);
    }
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
      _addErrorMessage('还没有配置模型与 API，请先到设置中填写。');
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

  Color _getBubbleColor(String role) {
    if (role == 'user') return const Color(0xFF9DD1F4);
    if (role == 'error') return Colors.red.shade50;
    return Colors.grey.shade200;
  }

  Color _getTextColor(String role) {
    if (role == 'error') return Colors.red.shade700;
    return Colors.black87;
  }

  BorderRadius _getBubbleBorderRadius(bool isUser) {
    return BorderRadius.only(
      topLeft: const Radius.circular(17),
      topRight: const Radius.circular(17),
      bottomLeft: Radius.circular(isUser ? 17 : 5),
      bottomRight: Radius.circular(isUser ? 5 : 17),
    );
  }

  Widget _buildAvatar({required bool isUser, double size = 40}) {
    if (!isUser) {
      return _SquareAvatar(
        size: size,
        image: const AssetImage('assets/images/pei_avatar.jpg'),
        alignment: const Alignment(0, -0.15),
      );
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

  Widget _buildMessageBubble(
    BuildContext context,
    ChatMessage message,
    int index,
  ) {
    final isUser = message.role == 'user';
    final isAssistant = message.role == 'assistant';

    final bubble = GestureDetector(
      onLongPress: () => _showMessageActions(index),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.68,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _getBubbleColor(message.role),
            borderRadius: _getBubbleBorderRadius(isUser),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.source == 'initiative') ...[
                Text(
                  '他主动发来的',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: _getTextColor(message.role).withValues(alpha: 0.48),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.42,
                        color: _getTextColor(message.role),
                      ),
                    ),
                  ),
                  if (message.isFavorite) ...[
                    const SizedBox(width: 7),
                    const Icon(
                      Icons.favorite_rounded,
                      size: 13,
                      color: Color(0xFFCB718E),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!isAssistant && !isUser) {
      return Align(alignment: Alignment.centerLeft, child: bubble);
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _buildAvatar(isUser: false),
            const SizedBox(width: 7),
          ],
          Flexible(child: bubble),
          if (isUser) ...[const SizedBox(width: 7), _buildAvatar(isUser: true)],
        ],
      ),
    );
  }

  ActivityStatus get _activity => _activityService.current(now: _now);

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

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: '输入消息…',
                filled: true,
                fillColor: const Color(0xFFF1F1F1),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 22,
            backgroundColor: _isLoading
                ? Colors.grey.shade400
                : Colors.blueGrey.shade600,
            child: IconButton(
              tooltip: '发送',
              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              onPressed: _isLoading ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
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
                const Text(
                  '裴简澈',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                                      color: Colors.black.withValues(alpha: 0.48),
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
          PopupMenuButton<String>(
            tooltip: '聊天菜单',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: _handleChatMenu,
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'analyze_memory',
                enabled: !_isAnalyzingMemory,
                child: Row(
                  children: [
                    Icon(
                      _isAnalyzingMemory
                          ? Icons.hourglass_top_rounded
                          : Icons.psychology_alt_outlined,
                    ),
                    const SizedBox(width: 10),
                    Text(_isAnalyzingMemory ? '正在分析记忆…' : '分析记忆'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, color: Colors.red),
                    SizedBox(width: 10),
                    Text('清理与重置'),
                  ],
                ),
              ),
            ],
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
                      itemBuilder: (context, index) =>
                          _buildMessageBubble(context, _messages[index], index),
                    ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 3, 11, 8),
                child: _TypingIndicator(isRegenerating: _isRegenerating),
              ),
            _buildInputArea(),
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
    required this.alignment,
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.isRegenerating});

  final bool isRegenerating;

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
          const _SquareAvatar(
            size: 38,
            image: AssetImage('assets/images/pei_avatar.jpg'),
            alignment: Alignment(0, -0.15),
          ),
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
              widget.isRegenerating ? '重新组织语言…' : '裴简澈正在输入',
              style: const TextStyle(fontSize: 12, color: Colors.black38),
            ),
          ),
        ],
      ),
    );
  }
}
