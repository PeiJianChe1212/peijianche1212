import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ai_character.dart';
import '../../models/echo_item.dart';
import '../../services/echo_image_storage_service.dart';
import '../../services/echo_storage_service.dart';

class EchoComposePage extends StatefulWidget {
  const EchoComposePage({
    super.key,
    required this.character,
    this.ownerLabel,
    this.isUserEcho = false,
  });

  final AiCharacter character;
  final String? ownerLabel;
  final bool isUserEcho;

  @override
  State<EchoComposePage> createState() => _EchoComposePageState();
}

class _EchoComposePageState extends State<EchoComposePage> {
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String _selectedImagePath = '';
  bool _saving = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1800,
      );
      if (result == null || !mounted) return;
      setState(() => _selectedImagePath = result.path);
    } catch (error) {
      _showMessage('选择图片失败：$error');
    }
  }

  Future<void> _publish() async {
    if (_saving) return;
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImagePath.isEmpty) {
      _showMessage('写点内容，或者选一张图片。');
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final echoId = 'echo_${now.microsecondsSinceEpoch}';

    try {
      final imagePaths = <String>[];
      if (_selectedImagePath.isNotEmpty) {
        final storedPath = await EchoImageStorageService(
          characterId: widget.character.id,
        ).saveImage(sourcePath: _selectedImagePath, echoId: echoId);
        imagePaths.add(storedPath);
      }

      await EchoStorageService(characterId: widget.character.id).addItem(
        EchoItem(
          id: echoId,
          characterId: widget.character.id,
          content: content,
          imagePaths: imagePaths,
          createdAt: now,
          sourceType: EchoSourceType.manual,
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('发布失败：$error');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F4F1),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '记录一条动态',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _publish,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '发布',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Text(
            widget.isUserEcho
                ? '正在记录自己的生活'
                : '正在替 ${widget.ownerLabel ?? widget.character.characterName} 记录',
            style: const TextStyle(color: Color(0xFF777777), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: TextField(
              controller: _contentController,
              autofocus: true,
              minLines: 7,
              maxLines: 14,
              maxLength: 1200,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '这里发生了什么？',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_selectedImagePath.isNotEmpty)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(_selectedImagePath),
                    width: double.infinity,
                    height: 240,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 160,
                      child: Center(child: Text('图片无法预览')),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => setState(() => _selectedImagePath = ''),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('添加一张图片'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            widget.isUserEcho ? '这里会显示在你自己的 Echo 主页。' : '这是角色的生活记录，不是你自己的社交账号。',
            style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
