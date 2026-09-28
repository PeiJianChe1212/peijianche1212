import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/chat_image_gallery_service.dart';

typedef ChatImageSaveCallback = Future<void> Function(String imagePath);

class ChatImagePreview extends StatefulWidget {
  const ChatImagePreview({super.key, required this.imagePath, this.saveImage});

  final String imagePath;
  final ChatImageSaveCallback? saveImage;

  static Future<void> open(BuildContext context, String imagePath) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatImagePreview(imagePath: imagePath),
        ),
      );

  @override
  State<ChatImagePreview> createState() => _ChatImagePreviewState();
}

class _ChatImagePreviewState extends State<ChatImagePreview> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;
  Timer? _feedbackTimer;
  String? _feedback;
  bool _feedbackIsError = false;
  bool _saving = false;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await (widget.saveImage ?? const ChatImageGalleryService().save)(
        widget.imagePath,
      );
      if (mounted) _showFeedback('已保存到系统相册', isError: false);
    } catch (_) {
      if (mounted) _showFeedback('保存失败，请稍后重试', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showFeedback(String message, {required bool isError}) {
    _feedbackTimer?.cancel();
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _transformationController.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final point = _doubleTapDetails?.localPosition ?? Offset.zero;
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(
        -point.dx * (scale - 1),
        -point.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.imagePath);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (details) => _doubleTapDetails = details,
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: file.existsSync()
                        ? Image.file(
                            file,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const _PreviewLoadError(),
                          )
                        : const _PreviewLoadError(),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              top: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ToolbarButton(
                    tooltip: '返回',
                    icon: Icons.arrow_back_ios_new_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  _ToolbarButton(
                    tooltip: '保存图片',
                    icon: Icons.download_rounded,
                    onPressed: _saving ? null : _save,
                    loading: _saving,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 28,
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _feedback == null
                      ? const SizedBox.shrink()
                      : Center(
                          key: ValueKey(_feedback),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _feedbackIsError
                                  ? const Color(0xFFD45B62)
                                  : const Color(0xFF6178A8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 9,
                              ),
                              child: Text(
                                _feedback!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        color: Colors.white,
      ),
    );
  }
}

class _PreviewLoadError extends StatelessWidget {
  const _PreviewLoadError();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: Colors.white54, size: 34),
        SizedBox(height: 10),
        Text('图片暂时无法查看', style: TextStyle(color: Colors.white70)),
      ],
    );
  }
}
