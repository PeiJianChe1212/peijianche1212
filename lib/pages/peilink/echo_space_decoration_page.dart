import 'package:flutter/material.dart';

import '../../services/echo_space_decoration_storage_service.dart';

class EchoSpaceDecorationPage extends StatefulWidget {
  const EchoSpaceDecorationPage({
    super.key,
    required this.characterId,
    required this.initialConfig,
  });

  final String characterId;
  final EchoSpaceDecorationConfig initialConfig;

  @override
  State<EchoSpaceDecorationPage> createState() =>
      _EchoSpaceDecorationPageState();
}

class _EchoSpaceDecorationPageState extends State<EchoSpaceDecorationPage> {
  static const _backgrounds = [
    _SpaceBackgroundPreset(name: '默认空间', assetPath: ''),
    _SpaceBackgroundPreset(
      name: '雾色清晨',
      assetPath: 'assets/images/echo_space_misty_dawn.png',
    ),
    _SpaceBackgroundPreset(
      name: '暖野黄昏',
      assetPath: 'assets/images/echo_space_warm_meadow.png',
    ),
  ];

  late EchoSpaceDecorationConfig _config;
  bool _saving = false;
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errorText = '';
    });
    try {
      await EchoSpaceDecorationStorageService(
        characterId: widget.characterId,
      ).save(_config);
      if (!mounted) return;
      Navigator.pop(context, _config);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = '装扮暂时没有保存成功，请稍后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F4),
      appBar: AppBar(
        title: const Text('空间装扮'),
        backgroundColor: const Color(0xFFF4F5F4),
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Text(
            '空间背景',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          const Text(
            '选择一种陪伴空间的氛围。',
            style: TextStyle(color: Color(0xFF8B9296), fontSize: 12),
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _backgrounds.length,
              separatorBuilder: (context, index) => const SizedBox(width: 11),
              itemBuilder: (context, index) {
                final preset = _backgrounds[index];
                return _BackgroundChoice(
                  preset: preset,
                  selected: preset.assetPath == _config.background,
                  onTap: () => setState(
                    () => _config = _config.copyWith(
                      background: preset.assetPath,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '空间氛围',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          const Text(
            '调整背景与内容之间的层次，文字会始终保持清晰。',
            style: TextStyle(color: Color(0xFF8B9296), fontSize: 12),
          ),
          const SizedBox(height: 13),
          SegmentedButton<EchoSpaceThemeMode>(
            segments: const [
              ButtonSegment(
                value: EchoSpaceThemeMode.airy,
                label: Text('轻盈'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: EchoSpaceThemeMode.balanced,
                label: Text('平衡'),
                icon: Icon(Icons.blur_on_outlined),
              ),
              ButtonSegment(
                value: EchoSpaceThemeMode.immersive,
                label: Text('沉浸'),
                icon: Icon(Icons.nights_stay_outlined),
              ),
            ],
            selected: {_config.themeMode},
            onSelectionChanged: (selection) {
              final mode = selection.firstOrNull;
              if (mode == null) return;
              setState(() => _config = _config.copyWith(themeMode: mode));
            },
          ),
          const SizedBox(height: 22),
          _DecorationPreview(config: _config),
          if (_errorText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _errorText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFC45E65)),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存装扮'),
          ),
        ],
      ),
    );
  }
}

class _SpaceBackgroundPreset {
  const _SpaceBackgroundPreset({required this.name, required this.assetPath});

  final String name;
  final String assetPath;
}

class _BackgroundChoice extends StatelessWidget {
  const _BackgroundChoice({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final _SpaceBackgroundPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? const Color(0xFF6F9DB4)
                    : const Color(0xFFE2E7E9),
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (preset.assetPath.isEmpty)
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFEAF0F2), Color(0xFFB8C8CE)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        )
                      else
                        Image.asset(preset.assetPath, fit: BoxFit.cover),
                      if (selected)
                        const Positioned(
                          top: 7,
                          right: 7,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Color(0xFF608BA0),
                            child: Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    preset.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DecorationPreview extends StatelessWidget {
  const _DecorationPreview({required this.config});

  final EchoSpaceDecorationConfig config;

  @override
  Widget build(BuildContext context) {
    final opacity = switch (config.themeMode) {
      EchoSpaceThemeMode.airy => 0.94,
      EchoSpaceThemeMode.balanced => 0.84,
      EchoSpaceThemeMode.immersive => 0.72,
    };
    return SizedBox(
      height: 150,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (config.background.isEmpty)
              const ColoredBox(color: Color(0xFFE9EFF1))
            else
              Image.asset(config.background, fit: BoxFit.cover),
            Center(
              child: Container(
                width: 230,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: opacity),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white70),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '空间效果预览',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '让故事住进属于这个角色的空间。',
                      style: TextStyle(color: Color(0xFF59666D), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
