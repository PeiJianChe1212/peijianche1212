import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/echo_draft.dart';
import '../../models/echo_item.dart';
import '../../services/character_scope_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../services/echo_generation_service.dart';
import '../../services/echo_storage_service.dart';
import '../../services/echo_social_interaction_service.dart';
import '../../services/image_generation_service.dart';
import '../../services/life_moment_storage_service.dart';
import '../../services/life_event_pool_service.dart';
import '../../services/shared_world_event_service.dart';
import '../../services/multimodal_service.dart';

class EchoAiDraftPage extends StatefulWidget {
  const EchoAiDraftPage({super.key, required this.character});
  final AiCharacter character;

  @override
  State<EchoAiDraftPage> createState() => _EchoAiDraftPageState();
}

class _EchoAiDraftPageState extends State<EchoAiDraftPage> {
  final TextEditingController _controller = TextEditingController();
  late final EchoGenerationService _generationService;
  late final MultimodalService _multimodalService;
  late final ImageGenerationService _imageGenerationService;

  bool _generating = true;
  bool _generatingImage = false;
  bool _publishing = false;
  String _errorText = '';
  String _momentSummary = '';
  String _imageScene = '';
  bool _imageRecommended = false;
  String _imagePath = '';

  @override
  void initState() {
    super.initState();
    _generationService = EchoGenerationService(character: widget.character);
    _multimodalService = MultimodalService();
    _imageGenerationService = ImageGenerationService();
    _generate();
  }

  @override
  void dispose() {
    _generationService.dispose();
    _multimodalService.dispose();
    _imageGenerationService.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_generatingImage || _publishing) return;
    setState(() {
      _generating = true;
      _errorText = '';
      _imagePath = '';
    });
    try {
      final draft = await _generationService.generateDraft();
      if (!mounted) return;
      _applyDraft(draft);
    } catch (error, stackTrace) {
      debugPrint('================ Echo Draft Generate Error ================');
      debugPrint('[EchoDraft] 生成失败：$error');
      debugPrintStack(stackTrace: stackTrace, label: '[EchoDraft] 异常堆栈');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'EchoAiDraftPage',
          context: ErrorDescription('generating an Echo draft'),
        ),
      );

      if (!mounted) return;
      setState(() {
        _generating = false;
        _errorText = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _applyDraft(EchoDraft draft) {
    setState(() {
      _controller.text = draft.content;
      _controller.selection = TextSelection.collapsed(
        offset: draft.content.length,
      );
      _momentSummary = draft.momentSummary;
      _imageRecommended =
          draft.shouldAttachImage && draft.imageScene.isNotEmpty;
      _imageScene = draft.imageScene;
      _generating = false;
    });
  }

  Future<void> _generateImage() async {
    if (_generating || _generatingImage || _publishing) return;
    final scene = _imageScene.trim();
    if (scene.isEmpty) {
      _showMessage('这条动态暂时没有适合配图的画面。');
      return;
    }

    setState(() => _generatingImage = true);
    try {
      final settings = await CharacterSettingsStorageService(
        characterId: widget.character.id,
      ).loadSettings();
      final visualStyle =
          '''
${settings.characterName}的生活摄影风格应来自人物设定：${settings.introduction}
整体像本人用手机随手拍，真实、自然、不过度精修。不要海报感，不要文字排版，不要默认出现完整人物正脸。
''';
      final prompt = await _multimodalService.buildImagePrompt(
        scene: scene,
        visualStyle: visualStyle,
        purpose: 'Echo 单张生活配图',
      );
      final characterDirectory = await CharacterScopeService(
        widget.character.id,
      ).characterDirectory();
      final target = Directory('${characterDirectory.path}/echo_images');
      final path = await _imageGenerationService.generateAndSave(
        prompt: prompt,
        targetDirectory: target,
      );
      if (!mounted) return;
      setState(() {
        _imagePath = path;
        _generatingImage = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _generatingImage = false);
      _showMessage('图片没有生成成功，但文字草稿还在：$error');
    }
  }

  void _removeImage() {
    setState(() => _imagePath = '');
  }

  Future<void> _publish() async {
    if (_publishing || _generating || _generatingImage) return;
    final content = _controller.text.trim();
    if (content.isEmpty) {
      _showMessage('草稿还是空的，先写点内容。');
      return;
    }
    setState(() => _publishing = true);
    final now = DateTime.now();
    try {
      final echo = EchoItem(
        id: 'echo_${now.microsecondsSinceEpoch}',
        characterId: widget.character.id,
        content: content,
        imagePaths: _imagePath.isEmpty ? const [] : [_imagePath],
        createdAt: now,
        sourceType: EchoSourceType.aiGenerated,
      );
      await EchoStorageService(characterId: widget.character.id).addItem(echo);
      try {
        await const EchoSocialInteractionService().generateForEcho(
          echo,
          now: now,
        );
      } catch (_) {
        // 评论系统失败不能影响 Echo 本身发布。
      }

      final selectedMoment = _generationService.lastDecision?.candidate;
      if (selectedMoment != null) {
        final confirmedMoment = selectedMoment.copyWith(occurredAt: now);
        await LifeMomentStorageService(
          characterId: widget.character.id,
        ).addItem(confirmedMoment);
        await LifeEventPoolService(
          characterId: widget.character.id,
        ).markUsed(selectedMoment.id, now: now);
        await SharedWorldEventService().recordConfirmedMoment(
          originCharacter: widget.character,
          moment: confirmedMoment,
          occurredAt: now,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _showMessage('发布失败：$error');
    }
  }

  void _showMessage(String text) {
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
          'Echo 草稿',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _generating || _generatingImage || _publishing
                ? null
                : _publish,
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
              '${widget.character.characterName}遇到了一个想分享的瞬间',
              style: const TextStyle(color: Color(0xFF777777), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 220),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: _buildDraftArea(),
            ),
            if (!_generating &&
                _errorText.isEmpty &&
                _momentSummary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFEDE8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '这一刻值得发：$_momentSummary',
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            if (!_generating && _errorText.isEmpty) ...[
              const SizedBox(height: 14),
              _buildImageCard(),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _publishing ? null : _generate,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('换一个瞬间'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              '当前仍是草稿模式。先确认“值得分享的瞬间”和单张配图是否自然，再进入自动发布。',
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

  Widget _buildDraftArea() {
    if (_generating) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 34),
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text('正在从生活里挑一个值得分享的瞬间…', style: TextStyle(color: Color(0xFF777777))),
          SizedBox(height: 34),
        ],
      );
    }
    if (_errorText.isNotEmpty) {
      return Column(
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
      );
    }
    return TextField(
      controller: _controller,
      minLines: 7,
      maxLines: 15,
      maxLength: 1200,
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: 'Echo 正文',
        counterText: '',
      ),
    );
  }

  Widget _buildImageCard() {
    if (_imagePath.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(File(_imagePath), fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _generatingImage ? null : _generateImage,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新生成'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _removeImage,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('取消图片'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _imageRecommended
                    ? Icons.photo_camera_outlined
                    : Icons.notes_rounded,
                color: const Color(0xFF777777),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _imageRecommended ? '这个瞬间适合配一张生活照' : '这个瞬间更适合纯文字',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_imageScene.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              _imageScene,
              style: const TextStyle(
                color: Color(0xFF777777),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          if (_imageRecommended) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _generatingImage ? null : _generateImage,
              icon: _generatingImage
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_outlined),
              label: Text(_generatingImage ? '正在生成生活照…' : '生成单张配图'),
            ),
          ],
        ],
      ),
    );
  }
}
