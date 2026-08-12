import 'dart:async';

import 'package:flutter/material.dart';

import '../config/peilink_runtime.dart';
import '../services/character_registry_service.dart';
import '../services/developer_environment_service.dart';
import '../services/environment_data_service.dart';
import 'home_page.dart';

class EnvironmentBootstrapPage extends StatefulWidget {
  const EnvironmentBootstrapPage({super.key, this.initialVisibility});

  final Future<bool>? initialVisibility;

  @override
  State<EnvironmentBootstrapPage> createState() =>
      _EnvironmentBootstrapPageState();
}

class _EnvironmentBootstrapPageState extends State<EnvironmentBootstrapPage>
    with SingleTickerProviderStateMixin {
  final _registry = CharacterRegistryService();
  final _developerEnvironment = DeveloperEnvironmentService();
  final _environmentData = EnvironmentDataService();
  late Future<bool> _initialization;
  late final AnimationController _butterflyController;
  Timer? _autoEnterTimer;
  int _developerTapCount = 0;
  bool _showAiWorld = false;
  bool? _initialHasVisibleCharacter;

  @override
  void initState() {
    super.initState();
    _butterflyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    _refresh();
  }

  void _refresh() {
    _initialization =
        widget.initialVisibility ??
        _registry.loadCharacters().then((items) => items.isNotEmpty);
    _initialization.then((hasCharacter) {
      if (!mounted) return;
      _initialHasVisibleCharacter = hasCharacter;
      if (!_showAiWorld) _scheduleAutoEnter();
    });
  }

  void _scheduleAutoEnter() {
    _autoEnterTimer?.cancel();
    _autoEnterTimer = Timer(const Duration(seconds: 3), _enterPeiLinkHome);
  }

  void _enterPeiLinkHome() {
    if (!mounted || _showAiWorld) return;
    setState(() => _showAiWorld = true);
  }

  void _handleLogoTap() {
    _autoEnterTimer?.cancel();
    _developerTapCount++;
    if (_developerTapCount < 7) return;
    _developerTapCount = 0;
    _verifyDeveloperAccess();
  }

  Future<void> _verifyDeveloperAccess() async {
    var enteredKey = '';
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开发者验证'),
        content: TextField(
          obscureText: false,
          autofocus: true,
          onChanged: (value) => enteredKey = value,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: const InputDecoration(labelText: '开发者密钥'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredKey),
            child: const Text('验证'),
          ),
        ],
      ),
    );
    if (key == null || !mounted) {
      if (mounted) _scheduleAutoEnter();
      return;
    }
    try {
      await _developerEnvironment.setEnabled(true, key: key);
      await _environmentData.initializeDeveloperSandbox();
      if (mounted) setState(_refresh);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('开发者密钥验证失败。')));
      _scheduleAutoEnter();
    }
  }

  @override
  void dispose() {
    _autoEnterTimer?.cancel();
    _butterflyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showAiWorld) {
      return HomePage(initialHasVisibleCharacter: _initialHasVisibleCharacter);
    }
    return FutureBuilder<bool>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF4F2FA),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 22),
              child: Column(
                children: [
                  const Spacer(),
                  if (PeiLinkRuntime.developerToolsEnabled)
                    GestureDetector(
                      key: const Key('developer-secret-logo'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleLogoTap,
                      child: _animatedButterfly(
                        key: const Key('developer-butterfly-image'),
                      ),
                    )
                  else
                    _animatedButterfly(key: const Key('user-welcome-logo')),
                  const SizedBox(height: 24),
                  const Text(
                    '欢迎来到 PeiLink',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF252A46),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '连接属于你的 AI 世界。\n稍后将自动进入 PeiLink。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: Color(0xFF737C98),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _animatedButterfly({Key? key}) {
    return AnimatedBuilder(
      key: key,
      animation: _butterflyController,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(_butterflyController.value);
        return Transform.translate(
          offset: Offset(0, -3 * value),
          child: Transform.scale(scale: 0.97 + value * 0.03, child: child),
        );
      },
      child: Image.asset(
        'assets/images/brand/peilink_butterfly.png',
        width: 88,
        height: 88,
      ),
    );
  }
}
