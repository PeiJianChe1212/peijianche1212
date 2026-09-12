import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../conversation/reply_segment_parser.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import 'chat_image_generation_service.dart';
import 'chat_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'deepseek_service.dart';
import 'multimodal_service.dart';

/// Owns image work after it has been committed to a conversation.
class ChatImageTaskManager extends ChangeNotifier {
  ChatImageTaskManager._();
  static final ChatImageTaskManager instance = ChatImageTaskManager._();

  final _generationService = ChatImageGenerationService();
  final _deepSeekService = DeepSeekService();
  ChatImageTaskState _state = const ChatImageTaskState.idle();
  ChatImageTaskState get state => _state;
  bool get isRunning => _state.status == ChatImageTaskStatus.running;

  Future<void> start({
    required String userRequest,
    required AiCharacter character,
    required List<ChatMessage> recentMessages,
  }) async {
    if (isRunning) return;
    final taskId = DateTime.now().microsecondsSinceEpoch.toString();
    _setState(
      ChatImageTaskState(
        taskId: taskId,
        characterId: character.id,
        kind: ChatImageTaskKind.generatedImage,
        status: ChatImageTaskStatus.running,
        userRequest: userRequest,
        startedAt: DateTime.now(),
      ),
    );
    try {
      final generated = await _generationService.generate(
        userRequest: userRequest,
        character: character,
        recentMessages: recentMessages,
      );
      final caption = await _deepSeekService.composeImageMessage(
        userRequest: userRequest,
        characterId: character.id,
      );
      final imageMessage = ChatMessage(
        role: 'assistant',
        type: MessageType.image,
        content: caption,
        source: 'generated_image',
        metadata: {
          'imagePath': generated.imagePath,
          'generationPrompt': generated.prompt,
          'generatedBy': 'image_generation_router',
          'taskId': taskId,
        },
      );
      final storage = ChatStorageService(characterId: character.id);
      final messages = await storage.loadMessages();
      if (!messages.any((item) => item.metadata['taskId'] == taskId)) {
        messages.add(imageMessage);
        await storage.saveMessages(messages);
      }
      _complete(taskId, imageMessage.id);
    } on TimeoutException {
      _fail(taskId, '图片生成超时了，这次先不发图。');
    } on SocketException {
      _fail(taskId, '当前网络连不上图片模型，这次先不发图。');
    } catch (_) {
      _fail(taskId, '图片没有生成成功，这次先不发图。');
    }
  }

  /// Dispatches vision and reply work without retaining a ChatPage.
  void startUserImage({
    required String characterId,
    required String messageId,
    required String imagePath,
    required String caption,
    required String conversationMode,
    required double temperature,
    required String replyLength,
    required double initiative,
    required double intimacy,
    required double tsundere,
  }) {
    if (isRunning) return;
    final taskId = DateTime.now().microsecondsSinceEpoch.toString();
    _setState(
      ChatImageTaskState(
        taskId: taskId,
        characterId: characterId,
        kind: ChatImageTaskKind.userImage,
        status: ChatImageTaskStatus.running,
        userRequest: caption,
        startedAt: DateTime.now(),
      ),
    );
    unawaited(
      _runUserImage(
        taskId: taskId,
        characterId: characterId,
        messageId: messageId,
        imagePath: imagePath,
        caption: caption,
        conversationMode: conversationMode,
        temperature: temperature,
        replyLength: replyLength,
        initiative: initiative,
        intimacy: intimacy,
        tsundere: tsundere,
      ),
    );
  }

  Future<void> _runUserImage({
    required String taskId,
    required String characterId,
    required String messageId,
    required String imagePath,
    required String caption,
    required String conversationMode,
    required double temperature,
    required String replyLength,
    required double initiative,
    required double intimacy,
    required double tsundere,
  }) async {
    final storage = ChatStorageService(characterId: characterId);
    final vision = MultimodalService();
    final chat = DeepSeekService();
    var description = '';
    try {
      try {
        final characterSettings = await CharacterSettingsStorageService(
          characterId: characterId,
        ).loadSettings();
        description = (await vision.understandForChat(
          imagePath: imagePath,
          userText: caption,
          characterSettings: characterSettings,
        )).description;
      } catch (error) {
        debugPrint('识图失败：$error');
      }
      var messages = await storage.loadMessages();
      final index = messages.indexWhere((item) => item.id == messageId);
      if (index >= 0) {
        final current = messages[index];
        messages[index] = current.copyWith(
          metadata: {
            ...current.metadata,
            'visionDescription': description,
            'visionStatus': description.isEmpty ? 'failed' : 'completed',
          },
        );
        await storage.saveMessages(messages);
      }
      messages = await storage.loadMessages();
      final reply = await chat.sendMessage(
        messages: messages,
        conversationMode: conversationMode,
        temperature: temperature,
        replyLength: replyLength,
        initiative: initiative,
        intimacy: intimacy,
        tsundere: tsundere,
        characterId: characterId,
      );
      final segments = ReplySegmentParser.parse(reply);
      if (segments.isNotEmpty) {
        messages = await storage.loadMessages();
        messages.addAll(
          segments.map((text) => ChatMessage(role: 'assistant', content: text)),
        );
        await storage.saveMessages(messages);
      }
      _complete(taskId, segments.isEmpty ? null : messages.last.id);
    } catch (error) {
      debugPrint('图片聊天任务失败：$error');
      final messages = await storage.loadMessages();
      final index = messages.indexWhere((item) => item.id == messageId);
      if (index >= 0 &&
          messages[index].metadata['visionStatus'] == 'recognizing') {
        final current = messages[index];
        messages[index] = current.copyWith(
          metadata: {
            ...current.metadata,
            'visionStatus': 'failed',
            'visionDescription': '',
          },
        );
        await storage.saveMessages(messages);
      }
      _fail(taskId, '图片已经发出，但这次没有成功生成回复。');
    } finally {
      vision.dispose();
      chat.dispose();
    }
  }

  void clearFinishedState() {
    if (!isRunning) _setState(const ChatImageTaskState.idle());
  }

  void _complete(String taskId, String? messageId) {
    if (_state.taskId != taskId) return;
    _setState(
      _state.copyWith(
        status: ChatImageTaskStatus.completed,
        completedAt: DateTime.now(),
        resultMessageId: messageId,
      ),
    );
  }

  void _fail(String taskId, String message) {
    if (_state.taskId != taskId) return;
    _setState(
      _state.copyWith(
        status: ChatImageTaskStatus.failed,
        completedAt: DateTime.now(),
        errorMessage: message,
      ),
    );
  }

  void _setState(ChatImageTaskState value) {
    _state = value;
    notifyListeners();
  }
}

enum ChatImageTaskStatus { idle, running, completed, failed }

enum ChatImageTaskKind { generatedImage, userImage }

class ChatImageTaskState {
  const ChatImageTaskState({
    required this.taskId,
    required this.characterId,
    required this.kind,
    required this.status,
    required this.userRequest,
    this.startedAt,
    this.completedAt,
    this.resultMessageId,
    this.errorMessage,
  });
  const ChatImageTaskState.idle()
    : taskId = '',
      characterId = '',
      kind = ChatImageTaskKind.generatedImage,
      status = ChatImageTaskStatus.idle,
      userRequest = '',
      startedAt = null,
      completedAt = null,
      resultMessageId = null,
      errorMessage = null;

  final String taskId;
  final String characterId;
  final ChatImageTaskKind kind;
  final ChatImageTaskStatus status;
  final String userRequest;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? resultMessageId;
  final String? errorMessage;

  ChatImageTaskState copyWith({
    ChatImageTaskStatus? status,
    DateTime? completedAt,
    String? resultMessageId,
    String? errorMessage,
  }) => ChatImageTaskState(
    taskId: taskId,
    characterId: characterId,
    kind: kind,
    status: status ?? this.status,
    userRequest: userRequest,
    startedAt: startedAt,
    completedAt: completedAt ?? this.completedAt,
    resultMessageId: resultMessageId ?? this.resultMessageId,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}
