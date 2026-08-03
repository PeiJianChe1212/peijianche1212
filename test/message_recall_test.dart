import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'message_recall_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documentsDirectory.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await documentsDirectory.delete(recursive: true);
  });

  test('normal messages are saved with normal status', () async {
    final storage = ChatStorageService();
    final message = ChatMessage(id: 'normal-1', role: 'user', content: '你好');

    await storage.saveMessages([message]);

    final loaded = await storage.loadMessages();
    expect(loaded, hasLength(1));
    expect(loaded.single.messageStatus, MessageStatus.normal);

    final raw = jsonDecode(
      await File('${documentsDirectory.path}/chat_history.json').readAsString(),
    ) as List<dynamic>;
    expect((raw.single as Map<String, dynamic>)['messageStatus'], 'normal');
  });

  test('recall keeps the message record and changes only its status', () async {
    final storage = ChatStorageService();
    await storage.saveMessages([
      ChatMessage(id: 'recall-1', role: 'user', content: '测试撤回'),
    ]);

    expect(await storage.recallMessage('recall-1'), isTrue);

    final loaded = await storage.loadMessages();
    expect(loaded, hasLength(1));
    expect(loaded.single.content, '测试撤回');
    expect(loaded.single.messageStatus, MessageStatus.recalled);
  });

  test('legacy messages without status load as normal', () async {
    final file = File('${documentsDirectory.path}/chat_history.json');
    await file.writeAsString(
      jsonEncode([
        {'id': 'legacy-1', 'role': 'user', 'content': '旧消息'},
      ]),
    );

    final loaded = await ChatStorageService().loadMessages();

    expect(loaded, hasLength(1));
    expect(loaded.single.messageStatus, MessageStatus.normal);
  });

  test('recalled messages are excluded from model conversation context', () {
    final context = ConversationContext([
      ChatMessage(role: 'user', content: '你好'),
      ChatMessage(
        role: 'user',
        content: '今晚有件事想告诉你',
        messageStatus: MessageStatus.recalled,
      ),
      ChatMessage(role: 'assistant', content: '我在听'),
    ]);

    expect(context.messages.map((message) => message.content), [
      '你好',
      '我在听',
    ]);
  });
}
