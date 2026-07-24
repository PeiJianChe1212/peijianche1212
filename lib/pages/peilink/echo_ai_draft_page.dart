import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/echo_item.dart';
import '../../services/echo_generation_service.dart';
import '../../services/echo_storage_service.dart';

class EchoAiDraftPage extends StatefulWidget {
  const EchoAiDraftPage({
    super.key,
    required this.character,
  });

  final AiCharacter character;

  @override
  State<EchoAiDraftPage> createState() => _EchoAiDraftPageState();
}

class _EchoAiDraftPageState extends State<EchoAiDraftPage> {
  final TextEditingController _controller = TextEditingController();

  late final EchoGenerationService _generationService;
  bool _generating = true;
  bool _publishing = false;
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    _generationService = EchoGenerationService(character: widget.character);
    _generate();
  }

  @override
  void dispose() {
    _generationService.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _errorText = '';
    });

    try {
      final draft = await _generationService.generateDraft();
      if (!mounted) return;
      setState(() {
        _controller.text = draft;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
        _generating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _errorText = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _publish() async {
    if (_publishing || _generating) return;
    final content = _controller.text.trim();
    if (content.isEmpty) {
      _showMessage('草稿还是空的，先写点内容。');
      return;
    }

    setState(() => _publishing = true);
    final now = DateTime.now();

    try {
      await EchoStorageService(
        characterId: widget.character.id,
      ).addItem(
        EchoItem(
          id: 'echo_${now.microsecondsSinceEpoch}',
          characterId: widget.character.id,
          content: content,
          createdAt: now,
          sourceType: EchoSourceType.aiGenerated,
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _showMessage('发布失败：$error');
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final characterName = widget.character.characterName;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F4F1),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Echo 草稿',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _generating || _publishing ? null : _publish,
            child: _publishing
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            Text(
              '$characterName 想记录一条生活动态',
              style: const TextStyle(
                color: Color(0xFF777777),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 230),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: _generating
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 36),
                        CircularProgressIndicator(),
                        SizedBox(height: 18),
                        Text(
                          '正在整理他的生活片段…',
                          style: TextStyle(color: Color(0xFF777777)),
                        ),
                        SizedBox(height: 36),
                      ],
                    )
                  : _errorText.isNotEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.cloud_off_outlined,
                          size: 42,
                          color: Color(0xFF999999),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _errorText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF777777)),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: _generate,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重新生成'),
                        ),
                      ],
                    )
                  : TextField(
                      controller: _controller,
                      autofocus: false,
                      minLines: 8,
                      maxLines: 16,
                      maxLength: 1200,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '生成的草稿会出现在这里，你可以继续修改。',
                        counterText: '',
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            if (!_generating && _errorText.isEmpty)
              OutlinedButton.icon(
                onPressed: _publishing ? null : _generate,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('换一条'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            const Text(
              '这只是草稿。角色不会自动发布，你可以修改、重新生成，确认后再发布。',
              style: TextStyle(
                color: Color(0xFF999999),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
