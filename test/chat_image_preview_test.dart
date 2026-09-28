import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/widgets/chat/chat_image_preview.dart';
import 'package:peijianche_app/widgets/chat/renderers/image_message_renderer.dart';

void main() {
  late Directory tempDirectory;
  late File imageFile;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'peilink_chat_preview_',
    );
    imageFile = File('${tempDirectory.path}/image.png');
    await imageFile.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> pumpMessage(WidgetTester tester, {required String role}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ImageMessageRenderer(
              message: ChatMessage(
                role: role,
                type: MessageType.image,
                content: '',
                metadata: {'imagePath': imageFile.path},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void openPreview(WidgetTester tester) {
    final trigger = tester.widget<GestureDetector>(
      find.byKey(const Key('chat-image-preview-trigger')),
    );
    expect(trigger.onTap, isNotNull);
    trigger.onTap!();
  }

  testWidgets('AI image message opens the shared full-screen preview', (
    tester,
  ) async {
    await pumpMessage(tester, role: 'assistant');
    openPreview(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatImagePreview), findsOneWidget);
  });

  testWidgets('user image message opens the same preview', (tester) async {
    await pumpMessage(tester, role: 'user');
    openPreview(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatImagePreview), findsOneWidget);
  });

  testWidgets('image renderer never shows legacy inline caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageMessageRenderer(
            message: ChatMessage(
              role: 'assistant',
              type: MessageType.image,
              content: '喏，刚拍的。',
              metadata: {'imagePath': imageFile.path},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('喏，刚拍的。'), findsNothing);
    expect(find.byKey(const Key('chat-image-preview-trigger')), findsOneWidget);
  });

  testWidgets(
    'preview contains the original image and supports zoom gestures',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatImagePreview(imagePath: imageFile.path)),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(image.fit, BoxFit.contain);
      expect(viewer.maxScale, 5);

      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChatImagePreview), findsOneWidget);
    },
  );

  testWidgets('back button closes preview without changing the chat route', (
    tester,
  ) async {
    await pumpMessage(tester, role: 'assistant');
    openPreview(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatImagePreview), findsNothing);
    expect(find.byType(ImageMessageRenderer), findsOneWidget);
  });

  testWidgets('save button invokes the gallery save flow and shows overlay', (
    tester,
  ) async {
    String? savedPath;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatImagePreview(
          imagePath: imageFile.path,
          saveImage: (path) async => savedPath = path,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('保存图片'));
    await tester.pump();
    expect(savedPath, imageFile.path);
    expect(find.text('已保存到系统相册'), findsOneWidget);
  });

  testWidgets('missing image does not crash and save failure is visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatImagePreview(
          imagePath: '${tempDirectory.path}/missing.png',
          saveImage: (_) async => throw StateError('missing'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('图片暂时无法查看'), findsOneWidget);
    await tester.tap(find.byTooltip('保存图片'));
    await tester.pump();
    expect(find.text('保存失败，请稍后重试'), findsOneWidget);
  });
}
