import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class EchoCoverEditorPage extends StatefulWidget {
  const EchoCoverEditorPage({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<EchoCoverEditorPage> createState() => _EchoCoverEditorPageState();
}

class _EchoCoverEditorPageState extends State<EchoCoverEditorPage> {
  final GlobalKey _captureKey = GlobalKey();
  ui.Image? _decodedImage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final image = await decodeImageFromList(bytes);
    if (!mounted) return;
    setState(() => _decodedImage = image);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('封面预览还没有准备好。');
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('封面图片生成失败。');
      if (!mounted) return;
      Navigator.pop(context, data.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存封面失败，请稍后再试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('调整封面'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中' : '完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.62,
                child: RepaintBoundary(
                  key: _captureKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final image = _decodedImage;
                      if (image == null) {
                        return const ColoredBox(
                          color: Color(0xFF222222),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final imageAspect = image.width / image.height;
                      final targetAspect =
                          constraints.maxWidth / constraints.maxHeight;
                      final tallEnough = imageAspect <= targetAspect;
                      final file = File(widget.imagePath);

                      if (tallEnough) {
                        return Image.file(file, fit: BoxFit.cover);
                      }

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: 18,
                              sigmaY: 18,
                            ),
                            child: Transform.scale(
                              scale: 1.12,
                              child: Image.file(file, fit: BoxFit.cover),
                            ),
                          ),
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                          Image.file(file, fit: BoxFit.contain),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 30),
            child: Text(
              '图片足够填满封面时会直接裁切显示；图片较短时，中间保留清晰原图，上下用虚化背景补齐。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFB8BDC1),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
