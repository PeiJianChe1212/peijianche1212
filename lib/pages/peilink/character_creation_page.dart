import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ai_character.dart';
import '../../models/character_archive.dart';
import '../../models/character_profile.dart';
import '../../services/character_archive_storage_service.dart';
import '../../models/character_settings.dart';
import '../../services/character_avatar_storage_service.dart';
import '../../services/character_registry_service.dart';
import '../../services/auto_echo_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../../services/character_profile_storage_service.dart';

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
  final Map<String, TextEditingController> _fields = {
    for (final key in const [
      'name',
      'age',
      'gender',
      'height',
      'birthday',
      'identity',
      'occupation',
      'location',
      'overallAppearance',
      'hairColor',
      'eyes',
      'bodyType',
      'clothingStyle',
      'specialMarks',
      'aura',
      'personalityTags',
      'personalityDescription',
      'surfacePersonality',
      'deepPersonality',
      'familyBackground',
      'upbringing',
      'importantExperiences',
      'worldview',
      'relationship',
      'howMet',
      'currentStage',
      'likes',
      'smallHabits',
      'inLove',
      'importantPrinciples',
      'dailyState',
      'currentState',
      'languageHabits',
    ])
      key: TextEditingController(),
  };

  bool _saving = false;
  String _portraitSourcePath = '';
  Uint8List? _avatarBytes;

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
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

  Future<void> _createCharacter() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final persona = _personaController.text.trim();
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
        introduction: _value('overallAppearance').isEmpty
            ? persona
            : _value('overallAppearance'),
        persona: persona,
        createdAt: now,
      );

      final defaults = CharacterSettings.fromAiCharacter(character);
      final settings = defaults.copyWith(
        introduction: _value('overallAppearance').isEmpty
            ? persona
            : _value('overallAppearance'),
        coreProfile: persona,
        relation: _value('relationship').isEmpty
            ? defaults.relation
            : _value('relationship'),
      );
      await CharacterSettingsStorageService(
        characterId: characterId,
      ).saveSettings(settings);
      await CharacterProfileStorageService(characterId: characterId).save(
        CharacterProfile(
          characterId: characterId,
          name: _value('name'),
          age: _value('age'),
          gender: _value('gender'),
          height: _value('height'),
          birthday: _value('birthday'),
          identity: _value('identity'),
          occupation: _value('occupation'),
          location: _value('location'),
          overallAppearance: _value('overallAppearance'),
          hairColor: _value('hairColor'),
          eyes: _value('eyes'),
          bodyType: _value('bodyType'),
          clothingStyle: _value('clothingStyle'),
          specialMarks: _value('specialMarks'),
          aura: _value('aura'),
          personalityTags: _value('personalityTags'),
          personalityDescription: _value('personalityDescription').isEmpty
              ? persona
              : _value('personalityDescription'),
          surfacePersonality: _value('surfacePersonality'),
          deepPersonality: _value('deepPersonality'),
          familyBackground: _value('familyBackground'),
          upbringing: _value('upbringing'),
          importantExperiences: _value('importantExperiences'),
          worldview: _value('worldview'),
          relationship: _value('relationship'),
          howMet: _value('howMet'),
          currentStage: _value('currentStage'),
        ),
      );
      await CharacterArchiveStorageService(characterId: characterId).save(
        CharacterArchive(
          characterId: characterId,
          values: {
            'likes': _value('likes'),
            'smallHabits': _value('smallHabits'),
            'inLove': _value('inLove'),
            'importantPrinciples': _value('importantPrinciples'),
            'dailyState': _value('dailyState'),
            'currentState': _value('currentState'),
            'languageHabits': _value('languageHabits'),
          },
        ),
      );
      await _registry.addCharacter(character);
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

  String _value(String key) => _fields[key]!.text.trim();

  @override
  Widget build(BuildContext context) {
    final portraitFile = _portraitSourcePath.isEmpty
        ? null
        : File(_portraitSourcePath);
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_rounded,
                                          size: 46,
                                          color: Color(0xFF8D959D),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '创建形象',
                                          style: TextStyle(
                                            color: Color(0xFF8D959D),
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
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
                                      ? const Icon(
                                          Icons.crop_rounded,
                                          color: Color(0xFF7C858D),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '聊天头像预览',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
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
                    _sectionTitle('基础信息'),
                    _InputCard(
                      label: '角色名称（必填）',
                      hint: '请填写角色名称',
                      controller: _nameController,
                      maxLength: 20,
                    ),
                    const SizedBox(height: 12),
                    _InputCard(
                      label: '角色简介 / 核心人设（必填）',
                      hint: '例如：银白短发，蓝色眼睛。性格冷淡，但对亲近的人温柔。',
                      controller: _personaController,
                      minLines: 5,
                      maxLines: 10,
                      maxLength: 2400,
                    ),
                    const SizedBox(height: 12),
                    _ExpansionCard(
                      title: '更多基础资料',
                      subtitle: '姓名、年龄、身份等均为选填',
                      fields: _inputFields(const [
                        ('name', '姓名'),
                        ('age', '年龄'),
                        ('gender', '性别'),
                        ('height', '身高'),
                        ('birthday', '生日'),
                        ('identity', '身份'),
                        ('occupation', '职业'),
                        ('location', '所在地'),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('详细资料（选填）'),
                    _ExpansionCard(
                      title: '外貌设定',
                      subtitle: '整体外貌、发色、穿衣风格与气质',
                      fields: _inputFields(const [
                        ('overallAppearance', '整体外貌'),
                        ('hairColor', '发色'),
                        ('eyes', '眼睛'),
                        ('bodyType', '身材'),
                        ('clothingStyle', '穿衣风格'),
                        ('specialMarks', '特殊标记'),
                        ('aura', '气质'),
                      ]),
                    ),
                    _ExpansionCard(
                      title: '性格设定',
                      subtitle: '标签、描述、表层表现与深层性格',
                      fields: _inputFields(const [
                        ('personalityTags', '性格标签'),
                        ('personalityDescription', '性格描述'),
                        ('surfacePersonality', '表层表现'),
                        ('deepPersonality', '深层性格'),
                      ], long: true),
                    ),
                    _ExpansionCard(
                      title: '背景故事',
                      subtitle: '家庭、成长、经历与世界观',
                      fields: _inputFields(const [
                        ('familyBackground', '家庭背景'),
                        ('upbringing', '成长经历'),
                        ('importantExperiences', '重要经历'),
                        ('worldview', '世界观'),
                      ], long: true),
                    ),
                    _ExpansionCard(
                      title: '关系资料',
                      subtitle: '与用户的关系、相识方式与当前阶段',
                      fields: _inputFields(const [
                        ('relationship', '与用户关系'),
                        ('howMet', '相识方式'),
                        ('currentStage', '当前阶段'),
                      ], long: true),
                    ),
                    _ExpansionCard(
                      title: '角色档案',
                      subtitle: '喜好、习惯、情感、价值观与生活表达',
                      fields: _inputFields(const [
                        ('likes', '喜好'),
                        ('smallHabits', '习惯'),
                        ('inLove', '情感模式'),
                        ('importantPrinciples', '价值观'),
                        ('dailyState', '日常生活'),
                        ('currentState', '世界设定'),
                        ('languageHabits', '语言表达'),
                      ], long: true),
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
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '创建角色',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
  );

  List<_CreationField> _inputFields(
    List<(String, String)> definitions, {
    bool long = false,
  }) => definitions
      .map(
        (field) => _CreationField(
          label: field.$2,
          controller: _fields[field.$1]!,
          minLines: long ? 2 : 1,
          maxLines: long ? 5 : 1,
        ),
      )
      .toList();
}

class _CreationField {
  const _CreationField({
    required this.label,
    required this.controller,
    required this.minLines,
    required this.maxLines,
  });

  final String label;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;
}

class _ExpansionCard extends StatelessWidget {
  const _ExpansionCard({
    required this.title,
    required this.subtitle,
    required this.fields,
  });

  final String title;
  final String subtitle;
  final List<_CreationField> fields;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white.withValues(alpha: 0.82),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        children: fields
            .map(
              (field) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: field.controller,
                  minLines: field.minLines,
                  maxLines: field.maxLines,
                  decoration: InputDecoration(
                    labelText: field.label,
                    filled: true,
                    fillColor: const Color(0xFFF6F7F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取图片失败：$error')));
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
      final boundary =
          _captureKey.currentContext?.findRenderObject()
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
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
