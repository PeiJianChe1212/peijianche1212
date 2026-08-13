import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/ai_character.dart';
import '../../models/character_archive.dart';
import '../../models/character_profile.dart';
import '../../models/character_settings.dart';
import '../../services/auto_echo_service.dart';
import '../../services/character_archive_storage_service.dart';
import '../../services/character_avatar_storage_service.dart';
import '../../services/character_profile_storage_service.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';

class CharacterCreationPage extends StatefulWidget {
  const CharacterCreationPage({super.key});
  @override
  State<CharacterCreationPage> createState() => _CharacterCreationPageState();
}

class _CharacterCreationPageState extends State<CharacterCreationPage> {
  final _picker = ImagePicker();
  final _storage = const CharacterAvatarStorageService();
  final _controllers = <String, TextEditingController>{
    for (final key in const [
      'name',
      'age',
      'gender',
      'height',
      'identity',
      'core',
      'backgroundStory',
      'worldview',
      'appearance',
      'personality',
      'clothing',
      'speakingStyle',
      'relationships',
      'interests',
      'dislikes',
      'possessions',
      'abilities',
    ])
      key: TextEditingController(),
  };
  String _avatarSource = '';
  String _backgroundSource = '';
  Uint8List? _avatarBytes;
  Uint8List? _backgroundBytes;
  bool _saving = false;

  String value(String key) => _controllers[key]!.text.trim();

  @override
  void dispose() {
    for (final item in _controllers.values) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 96,
    );
    if (image == null || !mounted) return;
    _avatarSource = image.path;
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AvatarCropDialog(imagePath: image.path),
    );
    if (bytes != null && mounted) setState(() => _avatarBytes = bytes);
  }

  Future<void> _pickBackground() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 94,
      maxWidth: 2400,
    );
    if (image == null || !mounted) return;
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BackgroundCropDialog(imagePath: image.path),
    );
    if (bytes != null && mounted) {
      setState(() {
        _backgroundSource = image.path;
        _backgroundBytes = bytes;
      });
    }
  }

  Future<void> _create() async {
    if (_saving) return;
    const required = <String, String>{
      'name': '名称',
      'age': '年龄',
      'gender': '性别',
      'height': '身高',
      'identity': '身份',
      'core': '核心人设/简介',
      'backgroundStory': '背景经历',
      'worldview': '世界观',
      'appearance': '外貌',
      'personality': '性格',
    };
    for (final entry in required.entries) {
      if (value(entry.key).isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('请填写${entry.value}')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final id = 'character_${now.microsecondsSinceEpoch}';
      final avatar = _avatarBytes == null
          ? ''
          : await _storage.saveAvatarBytes(
              characterId: id,
              bytes: _avatarBytes!,
            );
      final background = _backgroundBytes == null
          ? ''
          : await _storage.savePortraitBytes(
              characterId: id,
              bytes: _backgroundBytes!,
            );
      final character = AiCharacter(
        id: id,
        characterName: value('name'),
        remark: '',
        createdAt: now,
        avatarPath: avatar,
        backgroundImage: background,
        introduction: value('appearance'),
        persona: value('core'),
      );
      final defaults = CharacterSettings.fromAiCharacter(character);
      await CharacterSettingsStorageService(characterId: id).saveSettings(
        defaults.copyWith(
          coreProfile: value('core'),
          introduction: value('appearance'),
        ),
      );
      await CharacterProfileStorageService(characterId: id).save(
        CharacterProfile(
          characterId: id,
          name: value('name'),
          age: value('age'),
          gender: value('gender'),
          height: value('height'),
          identity: value('identity'),
          overallAppearance: value('appearance'),
          personalityDescription: value('personality'),
          clothingStyle: value('clothing'),
          worldview: value('worldview'),
          backgroundStory: value('backgroundStory'),
          characterRelationships: value('relationships'),
          interests: value('interests'),
          dislikes: value('dislikes'),
          possessions: value('possessions'),
          specialAbilities: value('abilities'),
          speakingStyle: value('speakingStyle'),
        ),
      );
      await CharacterArchiveStorageService(characterId: id).save(
        CharacterArchive(
          characterId: id,
          values: {
            'likes': value('interests'),
            'dislikes': value('dislikes'),
            'possessions': value('possessions'),
            'specialAbilities': value('abilities'),
            'speakingStyle': value('speakingStyle'),
          },
        ),
      );
      final registry = CharacterRegistryService();
      await registry.addCharacter(character);
      await registry.setActiveCharacter(id);
      try {
        await AutoEchoService().generateInitialEcho(character, now: now);
      } catch (_) {}
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F7FF),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      title: const Column(
        children: [
          Text('创建角色', style: TextStyle(fontWeight: FontWeight.w800)),
          Text(
            '创造属于你的 AI 伙伴',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      centerTitle: true,
    ),
    body: Stack(
      children: [
        const Positioned(
          right: 24,
          top: 6,
          child: Icon(Icons.flutter_dash, size: 54, color: Color(0x227A66DF)),
        ),
        ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
          children: [
            _section('角色形象', Icons.auto_awesome, [_imageFields()]),
            _section('基础资料', Icons.person_outline, [
              _row([
                _field('name', '名称', required: true),
                _field('age', '年龄', required: true),
              ]),
              _row([
                _field('gender', '性别', required: true),
                _field('height', '身高', required: true, suffix: 'cm'),
              ]),
              _field('identity', '身份', required: true),
              _field('core', '核心人设 / 简介', required: true, lines: 4),
            ]),
            _section('世界设定', Icons.public, [
              _field(
                'backgroundStory',
                '背景经历',
                required: true,
                lines: 5,
                hint: '成长经历、重要事件、过去的生活等…',
              ),
              _field(
                'worldview',
                '世界观',
                required: true,
                lines: 5,
                hint: '所处世界背景、时代设定、世界规则等…',
              ),
            ]),
            _section('角色特点', Icons.star_border_rounded, [
              _row([
                _field('appearance', '外貌', required: true, lines: 6),
                _field('personality', '性格', required: true, lines: 6),
              ]),
              _row([
                _field('clothing', '穿着', lines: 4),
                _field('speakingStyle', '说话风格', lines: 4),
              ]),
            ]),
            _section('关系与生活', Icons.groups_outlined, [
              _row([
                _field(
                  'relationships',
                  '角色关系',
                  lines: 5,
                  hint: '好友、家人、宿敌、重要人物等…',
                ),
                _field('interests', '兴趣爱好', lines: 5),
              ]),
              _row([
                _field('dislikes', '讨厌的事（东西）', lines: 5),
                _field('possessions', '持有物品', lines: 5),
              ]),
            ]),
            _section('高级设定', Icons.auto_fix_high, [
              _field('abilities', '特殊能力', lines: 4, hint: '魔法、异能、修为、技能等特殊能力…'),
            ]),
          ],
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 18,
          child: SafeArea(
            child: SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _create,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7658DE),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        '✦  创建角色',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _section(String title, IconData icon, List<Widget> children) =>
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEAE6FA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12715AD3),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF8065E5)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _imageFields() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 122, child: _imageTile('头像', '聊天头像', true)),
      const SizedBox(width: 12),
      Expanded(child: _imageTile('背景图', 'AI World 主页背景', false)),
    ],
  );

  Widget _imageTile(String title, String subtitle, bool avatar) {
    final path = avatar ? _avatarSource : _backgroundSource;
    final ImageProvider<Object>? provider = avatar && _avatarBytes != null
        ? MemoryImage(_avatarBytes!)
        : (!avatar && _backgroundBytes != null
              ? MemoryImage(_backgroundBytes!)
              : (path.isNotEmpty ? FileImage(File(path)) : null));
    return InkWell(
      onTap: avatar ? _pickAvatar : _pickBackground,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: avatar ? 190 : 190,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x66F7F5FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 9),
            Expanded(
              child: AspectRatio(
                aspectRatio: avatar ? 1 : 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    shape: avatar ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: avatar ? null : BorderRadius.circular(14),
                    color: const Color(0xFFEDE9FF),
                    image: provider == null
                        ? null
                        : DecorationImage(image: provider, fit: BoxFit.cover),
                  ),
                  child: provider == null
                      ? const Center(
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Color(0xFF8065E5),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Center(
              child: Text(
                avatar ? '更换头像' : '更换背景',
                style: const TextStyle(color: Color(0xFF8065E5), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (int i = 0; i < children.length; i++) ...[
        Expanded(child: children[i]),
        if (i < children.length - 1) const SizedBox(width: 12),
      ],
    ],
  );
  Widget _field(
    String key,
    String label, {
    bool required = false,
    int lines = 1,
    String hint = '',
    String? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _controllers[key],
      minLines: lines,
      maxLines: lines,
      maxLength: lines > 1 ? 800 : null,
      keyboardType: key == 'age' || key == 'height'
          ? TextInputType.number
          : null,
      decoration: InputDecoration(
        label: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: label),
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
        ),
        hintText: hint,
        suffixText: suffix,
        filled: true,
        fillColor: const Color(0x88FAF9FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE9E5F5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE9E5F5)),
        ),
      ),
    ),
  );
}

class AvatarCropDialog extends StatefulWidget {
  const AvatarCropDialog({super.key, required this.imagePath});
  final String imagePath;
  @override
  State<AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<AvatarCropDialog> {
  final _key = GlobalKey();
  final _controller = TransformationController();
  bool _saving = false;
  Future<void> _save() async {
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (mounted) Navigator.pop(context, data!.buffer.asUint8List());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('调整头像'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('双指缩放，拖动调整位置', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        ClipOval(
          child: RepaintBoundary(
            key: _key,
            child: SizedBox(
              width: 260,
              height: 260,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 6,
                boundaryMargin: EdgeInsets.zero,
                clipBehavior: Clip.hardEdge,
                child: Image.file(
                  File(widget.imagePath),
                  width: 260,
                  height: 260,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存头像'),
      ),
    ],
  );
}

class BackgroundCropDialog extends StatefulWidget {
  const BackgroundCropDialog({super.key, required this.imagePath});
  final String imagePath;

  @override
  State<BackgroundCropDialog> createState() => _BackgroundCropDialogState();
}

class _BackgroundCropDialogState extends State<BackgroundCropDialog> {
  final _key = GlobalKey();
  final _controller = TransformationController();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (mounted) Navigator.pop(context, data!.buffer.asUint8List());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('调整背景图'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '双指缩放，拖动调整 16:9 展示范围',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: RepaintBoundary(
            key: _key,
            child: SizedBox(
              width: 320,
              height: 180,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 6,
                boundaryMargin: EdgeInsets.zero,
                clipBehavior: Clip.hardEdge,
                child: Image.file(
                  File(widget.imagePath),
                  width: 320,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存背景'),
      ),
    ],
  );
}
