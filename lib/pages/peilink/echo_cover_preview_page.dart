import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class EchoCoverPreviewPage extends StatelessWidget {
  const EchoCoverPreviewPage({super.key, required this.coverPath, required this.onChangeCover});

  final String coverPath;
  final Future<void> Function() onChangeCover;

  Widget _cover() {
    final file = coverPath.trim().isEmpty ? null : File(coverPath);
    if (file == null || !file.existsSync()) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7E98A5), Color(0xFFB8C6CB), Color(0xFF607985)],
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Transform.scale(scale: 1.12, child: Image.file(file, fit: BoxFit.cover)),
        ),
        ColoredBox(color: Colors.white.withValues(alpha: 0.15)),
        Center(child: Image.file(file, fit: BoxFit.contain, width: double.infinity)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _cover(),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            left: 6,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            right: 18,
            bottom: MediaQuery.paddingOf(context).bottom + 22,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                await onChangeCover();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.image_outlined),
              label: const Text('换封面'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.42),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
