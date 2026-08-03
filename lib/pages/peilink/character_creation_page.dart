import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ai_character.dart';
import '../../models/character_settings.dart';
import '../../services/character_avatar_storage_service.dart';
import '../../services/character_registry_service.dart';
import '../../services/auto_echo_service.dart';
import '../../services/character_settings_storage_service.dart';

class CharacterCreationPage extends StatefulWidget {
  const CharacterCreationPage({super.key});

  @override
  State<CharacterCreationPage> createState() => _CharacterCreationPageState();
}

class _CharacterCreationPageState extends State<CharacterCreationPage> {
  final CharacterRegistryService _registry = CharacterRegistryService();
  final CharacterAvatarStorageService _avatarStorage =
      const CharacterAvatarStorageService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _personaController = TextEditingController();
  final TextEditingController _introductionController = TextEditingController();
  final TextEditingController _behaviorController = TextEditingController();
  final TextEditingController _forbiddenController = TextEditingController();
  final TextEditingController _examplesController = TextEditingController();

  bool _saving = false;
  String _portraitSourcePath = '';
  Uint8List? _avatarBytes;

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    _introductionController.dispose();
    _behaviorController.dispose();
    _forbiddenController.dispose();
    _examplesController.dispose();
    super.dispose();
  }

  Future<void> _pickPortrait() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 94,
        maxWidth: 2200,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _portraitSourcePath = picked.path;
        _avatarBytes = null;
      });
      await _editAvatar();
    } catch (error) {
      if (mounted) _showMessage('选择角色图片失败：$error');
    }
  }

  Future<void> _editAvatar() async {
    if (_portraitSourcePath.isEmpty) {
      _showMessage('请先选择完整角色图片。');
      return;
    }
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AvatarCropDialog(imagePath: _portraitSourcePath),
    );
    if (bytes != null && mounted) setState(() => _avatarBytes = bytes);
  }

  Future<void> _openAdvancedSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF6F6F7),
      builder: (sheetContext) {
        final bottom = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '高级设置',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '这些内容用于约束长期相处方式，不会展示在角色资料页。',
                  style: TextStyle(color: Colors.black54, height: 1.45),
                ),
                const SizedBox(height: 18),
                _InputCard(
                  label: '行为规则',
                  hint: '例如：先回应用户真正说的事情；保持自然口语；允许简短回复。',
                  controller: _behaviorController,
                  minLines: 5,
                  maxLines: 9,
                  maxLength: 1600,
                ),
                const SizedBox(height: 14),
                _InputCard(
                  label: '禁止事项',
                  hint: '例如：不要使用括号动作；不要强行把普通话题变成情话。',
                  controller: _forbiddenController,
                  minLines: 5,
                  maxLines: 9,
                  maxLength: 1600,
                ),
                const SizedBox(height: 14),
                _InputCard(
                  label: '示例对话',
                  hint: '用户：今天有点累。\n角色：先歇会儿，别硬撑。',
                  controller: _examplesController,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 2400,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createCharacter() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final persona = _personaController.text.trim();
    final introduction = _introductionController.text.trim();
    if (name.isEmpty) {
      _showMessage('请填写角色名称。');
      return;
    }
    if (persona.isEmpty) {
      _showMessage('角色设定不能是空白的。');
      return;
    }
    if (_portraitSourcePath.isNotEmpty && _avatarBytes == null) {
      _showMessage('请先调整并保存聊天头像。');
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final characterId = 'character_${now.microsecondsSinceEpoch}';
      final portraitPath = _portraitSourcePath.isEmpty
          ? ''
          : await _avatarStorage.savePortrait(
              characterId: characterId,
              sourcePath: _portraitSourcePath,
            );
      final avatarPath = _avatarBytes == null
          ? ''
          : await _avatarStorage.saveAvatarBytes(
              characterId: characterId,
              bytes: _avatarBytes!,
            );

      final character = AiCharacter(
        id: characterId,
        characterName: name,
        remark: '',
        avatarPath: avatarPath,
        portraitPath: portraitPath,
        introduction: introduction,
        persona: persona,
        createdAt: now,
      );
      await _registry.addCharacter(character);

      final defaults = CharacterSettings.fromAiCharacter(character);
      final settings = defaults.copyWith(
        introduction: introduction,
        coreProfile: persona,
        behaviorStyle: _behaviorController.text.trim().isEmpty
            ? defaults.behaviorStyle
            : _behaviorController.text.trim(),
        forbiddenRules: _forbiddenController.text.trim().isEmpty
            ? defaults.forbiddenRules
            : _forbiddenController.text.trim(),
        exampleDialogues: _examplesController.text.trim(),
      );
      await CharacterSettingsStorageService(characterId: characterId)
          .saveSettings(settings);
      try {
        await AutoEchoService().generateInitialEcho(character, now: now);
      } catch (_) {
        // Initial Echo is a protection layer and must not block character creation.
      }
      await _registry.setActiveCharacter(character.id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('创建失败：$error');
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final portraitFile =
        _portraitSourcePath.isEmpty ? null : File(_portraitSourcePath);
    final hasPortrait = portraitFile != null && portraitFile.existsSync();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F6F8),
          surfaceTintColor: Colors.transparent,
          title: const Text('创建角色'),
          centerTitle: true,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
                  children: [
                    _sectionTitle('角色形象'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _saving ? null : _pickPortrait,
                            child: Container(
                              height: 250,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                image: hasPortrait
                                    ? DecorationImage(
                                        image: FileImage(portraitFile),
                                        fit: BoxFit.contain,
                                      )
                                    : null,
                              ),
                              child: hasPortrait
                                  ? null
                                  : const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_rounded,
                                            size: 46, color: Color(0xFF8D959D)),
                                        SizedBox(height: 10),
                                        Text('创建形象',
                                            style: TextStyle(
                                                color: Color(0xFF8D959D),
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 96,
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _saving ? null : _editAvatar,
                                child: CircleAvatar(
                                  radius: 42,
                                  backgroundColor: Colors.white,
                                  backgroundImage: _avatarBytes == null
                                      ? null
                                      : MemoryImage(_avatarBytes!),
                                  child: _avatarBytes == null
                                      ? const Icon(Icons.crop_rounded,
                                          color: Color(0xFF7C858D))
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('聊天头像预览',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black54)),
                              TextButton(
                                onPressed: _saving ? null : _editAvatar,
                                child: const Text('调整'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('角色名称'),
                    _InputCard(
                      label: '名称',
                      hint: '请填写角色名称',
                      controller: _nameController,
                      maxLength: 20,
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('角色设定'),
                    _InputCard(
                      label: '人物设定',
                      hint: '角色的性格、身份、说话风格，以及与用户的关系等。请使用“用户”称呼与角色对话的人。',
                      controller: _personaController,
                      minLines: 10,
                      maxLines: 18,
                      maxLength: 6000,
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('角色简介（选填）'),
                    _InputCard(
                      label: '一句介绍',
                      hint: '例如：每天都会等你回家。',
                      controller: _introductionController,
                      maxLength: 20,
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('高级设置'),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      child: ListTile(
                        onTap: _saving ? null : _openAdvancedSettings,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 9),
                        title: const Text('行为规则、禁止事项与示例对话'),
                        subtitle: const Text('可选，未填写时使用 PeiLink 默认规则'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _saving ? null : _createCharacter,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Text('创建角色',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.label,
    required this.hint,
    required this.controller,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }
}

class _AvatarCropDialog extends StatefulWidget {
  const _AvatarCropDialog({required this.imagePath});

  final String imagePath;

  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  static const double _viewportSize = 250;

  final GlobalKey _captureKey = GlobalKey();
  final TransformationController _transformationController =
      TransformationController();

  bool _saving = false;
  bool _loadingImage = true;
  double _imageWidth = _viewportSize;
  double _imageHeight = _viewportSize;

  @override
  void initState() {
    super.initState();
    _prepareImage();
  }

  Future<void> _prepareImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final sourceWidth = frame.image.width.toDouble();
      final sourceHeight = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();

      final aspectRatio = sourceWidth / sourceHeight;
      final displayWidth = aspectRatio >= 1
          ? _viewportSize * aspectRatio
          : _viewportSize;
      final displayHeight = aspectRatio >= 1
          ? _viewportSize
          : _viewportSize / aspectRatio;

      if (!mounted) return;
      setState(() {
        _imageWidth = displayWidth;
        _imageHeight = displayHeight;
        _loadingImage = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _transformationController.value = Matrix4.identity()
          ..translate(
            -(_imageWidth - _viewportSize) / 2,
            -(_imageHeight - _viewportSize) / 2,
          );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取图片失败：$error')),
      );
    }
  }

  void _clampTransform() {
    final matrix = _transformationController.value.clone();
    final scale = matrix.getMaxScaleOnAxis().clamp(1.0, 5.0);
    final scaledWidth = _imageWidth * scale;
    final scaledHeight = _imageHeight * scale;

    final minX = _viewportSize - scaledWidth;
    final minY = _viewportSize - scaledHeight;
    final translation = matrix.getTranslation();
    final x = translation.x.clamp(minX, 0.0).toDouble();
    final y = translation.y.clamp(minY, 0.0).toDouble();

    _transformationController.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(scale);
  }

  Future<void> _save() async {
    if (_saving || _loadingImage) return;
    _clampTransform();
    setState(() => _saving = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('头像预览尚未准备好。');
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('头像保存失败。');
      if (!mounted) return;
      Navigator.pop(context, data.buffer.asUint8List());
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('调整聊天头像'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '拖动图片调整位置，双指缩放。图片会始终铺满头像范围。',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          ClipOval(
            child: RepaintBoundary(
              key: _captureKey,
              child: SizedBox(
                width: _viewportSize,
                height: _viewportSize,
                child: _loadingImage
                    ? const ColoredBox(
                        color: Color(0xFFF1F2F3),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : InteractiveViewer(
                        transformationController: _transformationController,
                        minScale: 1,
                        maxScale: 5,
                        boundaryMargin: EdgeInsets.zero,
                        constrained: false,
                        clipBehavior: Clip.hardEdge,
                        onInteractionEnd: (_) => _clampTransform(),
                        child: Image.file(
                          File(widget.imagePath),
                          width: _imageWidth,
                          height: _imageHeight,
                          fit: BoxFit.fill,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || _loadingImage ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('保存头像'),
        ),
      ],
    );
  }
}
