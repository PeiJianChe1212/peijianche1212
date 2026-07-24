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
  final TransformationController _transformController =
      TransformationController();

  double _blurSigma = 5;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('封面预览还没有准备好。');
      }
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('封面图片生成失败。');
      if (!mounted) return;
      Navigator.pop(context, data.buffer.asUint8List());
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存封面失败：$error')));
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111315),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111315),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('调整 Echo 封面'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? '保存中' : '完成',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: AspectRatio(
                aspectRatio: 1.16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: RepaintBoundary(
                    key: _captureKey,
                    child: ColoredBox(
                      color: const Color(0xFF77858C),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: _blurSigma,
                          sigmaY: _blurSigma,
                        ),
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 1,
                          maxScale: 5,
                          boundaryMargin: const EdgeInsets.all(500),
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox.expand(
                            child: Image.file(
                              File(widget.imagePath),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white70,
                                  size: 52,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              '拖动调整位置，双指缩放图片',
              style: TextStyle(color: Color(0xFFB8BDC1), fontSize: 13),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              decoration: const BoxDecoration(
                color: Color(0xFF1B1E21),
                border: Border(top: BorderSide(color: Color(0xFF2A2E32))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.blur_on_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '虚化程度',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const Spacer(),
                      Text(
                        _blurSigma == 0 ? '关闭' : _blurSigma.toStringAsFixed(0),
                        style: const TextStyle(
                          color: Color(0xFFB8BDC1),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _blurSigma,
                    min: 0,
                    max: 14,
                    divisions: 14,
                    onChanged: (value) => setState(() => _blurSigma = value),
                  ),
                  const Text(
                    '上方就是最终封面效果，调整时会实时预览。',
                    style: TextStyle(color: Color(0xFF8F969B), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
