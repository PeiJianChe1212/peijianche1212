import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/character_settings.dart';
import 'chat_image_generation_service.dart';
import 'chat_storage_service.dart';
import 'deepseek_service.dart';

/// 图片生成任务不再属于某一个聊天页面。
///
/// 用户退出聊天页以后，单例仍然存活，生成完成后会直接把图片消息写进聊天记录。
class ChatImageTaskManager extends ChangeNotifier {
  ChatImageTaskManager._();

  static final ChatImageTaskManager instance = ChatImageTaskManager._();

  final ChatImageGenerationService _generationService =
      ChatImageGenerationService();
  final DeepSeekService _deepSeekService = DeepSeekService();

  ChatImageTaskState _state = const ChatImageTaskState.idle();
  ChatImageTaskState get state => _state;

  bool get isRunning => _state.status == ChatImageTaskStatus.running;

  Future<void> start({
    required String userRequest,
    required CharacterSettings characterSettings,
    required List<ChatMessage> recentMessages,
  }) async {
    if (isRunning) return;

    final taskId = DateTime.now().microsecondsSinceEpoch.toString();
    _setState(
      ChatImageTaskState(
        taskId: taskId,
        status: ChatImageTaskStatus.running,
        userRequest: userRequest,
        startedAt: DateTime.now(),
      ),
    );

    try {
      final generated = await _generationService.generate(
        userRequest: userRequest,
        characterSettings: characterSettings,
        recentMessages: recentMessages,
      );
      final caption = await _deepSeekService.composeImageMessage(
        userRequest: userRequest,
      );

      final imageMessage = ChatMessage(
        role: 'assistant',
        type: MessageType.image,
        content: caption,
        source: 'generated_image',
        metadata: {
          'imagePath': generated.imagePath,
          'generationPrompt': generated.prompt,
          'generatedBy': 'doubao_image',
          'taskId': taskId,
        },
      );

      final storage = ChatStorageService();
      final messages = await storage.loadMessages();
      if (!messages.any((message) => message.metadata['taskId'] == taskId)) {
        messages.add(imageMessage);
        await storage.saveMessages(messages);
      }

      _setState(
        ChatImageTaskState(
          taskId: taskId,
          status: ChatImageTaskStatus.completed,
          userRequest: userRequest,
          startedAt: _state.startedAt,
          completedAt: DateTime.now(),
          resultMessageId: imageMessage.id,
        ),
      );
    } on TimeoutException {
      _fail(taskId, userRequest, '图片生成超时了，这次先不发图。');
    } on SocketException {
      _fail(taskId, userRequest, '当前网络连不上图片模型，这次先不发图。');
    } catch (error) {
      _fail(taskId, userRequest, '图片没有生成成功：$error');
    }
  }

  void clearFinishedState() {
    if (isRunning) return;
    _setState(const ChatImageTaskState.idle());
  }

  void _fail(String taskId, String userRequest, String message) {
    _setState(
      ChatImageTaskState(
        taskId: taskId,
        status: ChatImageTaskStatus.failed,
        userRequest: userRequest,
        startedAt: _state.startedAt,
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

class ChatImageTaskState {
  const ChatImageTaskState({
    required this.taskId,
    required this.status,
    required this.userRequest,
    this.startedAt,
    this.completedAt,
    this.resultMessageId,
    this.errorMessage,
  });

  const ChatImageTaskState.idle()
      : taskId = '',
        status = ChatImageTaskStatus.idle,
        userRequest = '',
        startedAt = null,
        completedAt = null,
        resultMessageId = null,
        errorMessage = null;

  final String taskId;
  final ChatImageTaskStatus status;
  final String userRequest;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? resultMessageId;
  final String? errorMessage;
}
