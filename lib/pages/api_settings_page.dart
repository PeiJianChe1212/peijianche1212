import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/peilink_runtime.dart';
import '../ai/image_generation/image_generation_adapter.dart';
import '../models/api_settings.dart';
import '../models/api_settings_form_state.dart';
import '../models/ai_capability_health.dart';
import '../models/image_generation_settings.dart';
import '../models/vision_settings.dart';
import '../services/api_settings_storage_service.dart';
import '../services/ai_capability_status_service.dart';
import '../services/ai_capability_verification_storage_service.dart';
import '../services/capability_auto_save_service.dart';
import '../services/model_discovery_service.dart';
import '../services/image_generation_capability_test_service.dart';
import '../services/image_generation_settings_storage_service.dart';
import '../services/vision_capability_test_service.dart';
import '../services/vision_settings_storage_service.dart';

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ConnectionFeedback {
  const _ConnectionFeedback(this.success, this.message);

  final bool success;
  final String message;
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final _storage = ApiSettingsStorageService();
  final _capabilityStatusService = const AiCapabilityStatusService();
  final _verificationStorage = AiCapabilityVerificationStorageService();
  final _visionStorage = VisionSettingsStorageService();
  final _imageGenerationStorage = ImageGenerationSettingsStorageService();
  final _modelDiscovery = ModelDiscoveryService();
  final _visionCapabilityTest = VisionCapabilityTestService();
  final _imageGenerationCapabilityTest = ImageGenerationCapabilityTestService();
  late final CapabilityAutoSaveService _capabilityAutoSave;

  final _chatApiKeyController = TextEditingController();
  final _chatBaseUrlController = TextEditingController();
  final _chatModelController = TextEditingController();

  final _multimodalApiKeyController = TextEditingController();
  final _multimodalBaseUrlController = TextEditingController();
  final _multimodalModelController = TextEditingController();

  final _imageApiKeyController = TextEditingController();
  final _imageBaseUrlController = TextEditingController();
  final _imageModelController = TextEditingController();

  AIProvider _provider = AIProvider.deepseek;
  AIProvider _lastOfficialProvider = AIProvider.deepseek;
  bool _loading = true;
  bool _saving = false;
  String? _testingTarget;
  bool _obscureChatKey = true;
  bool _obscureMultimodalKey = true;
  bool _obscureImageKey = true;
  bool _discoveringModels = false;
  bool _manualModelEntry = false;
  bool _showCustomApi = false;
  String? _discoveryError;
  List<AvailableModel> _availableModels = const [];
  final Map<String, _ConnectionFeedback> _connectionFeedback = {};
  final ProviderDraftStore _providerDrafts = ProviderDraftStore();
  VisionUsageMode _visionUsageMode = VisionUsageMode.useChatModel;
  VisionProvider _visionProvider = VisionProvider.openai;
  bool _reuseChatKeyForVision = false;
  bool _discoveringVisionModels = false;
  bool _manualVisionModelEntry = false;
  String? _visionDiscoveryError;
  List<AvailableModel> _availableVisionModels = const [];
  VisionCapabilityStatus _visionCapabilityStatus =
      VisionCapabilityStatus.untested;
  String? _visionCapabilityMessage;
  final Map<VisionProvider, VisionSettings> _visionDrafts = {};
  ImageGenerationProvider _imageGenerationProvider =
      ImageGenerationProvider.volcengine;
  ImageApiKeySource _imageApiKeySource = ImageApiKeySource.independent;
  ImageGenerationProtocol _imageGenerationProtocol =
      ImageGenerationProtocol.openAiImagesCompatible;
  ImageGenerationCapabilityStatus _imageGenerationCapabilityStatus =
      ImageGenerationCapabilityStatus.untested;
  String? _imageGenerationCapabilityMessage;
  bool _discoveringImageModels = false;
  bool _manualImageModelEntry = false;
  String? _imageDiscoveryError;
  List<AvailableModel> _availableImageModels = const [];
  final Map<ImageGenerationProvider, ImageGenerationSettings> _imageDrafts = {};
  AiCapabilityVerificationSnapshot _verification =
      const AiCapabilityVerificationSnapshot();
  final _chatCardKey = GlobalKey();
  final _visionCardKey = GlobalKey();
  final _imageCardKey = GlobalKey();

  static const Map<AIProvider, ApiSettings> _presets = {
    AIProvider.deepseek: ApiSettings(
      provider: AIProvider.deepseek,
      baseUrl: 'https://api.deepseek.com/v1/chat/completions',
      model: 'deepseek-chat',
    ),
    AIProvider.volcengine: ApiSettings(
      provider: AIProvider.volcengine,
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      model: '',
    ),
    AIProvider.openai: ApiSettings(
      provider: AIProvider.openai,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5-mini',
    ),
    AIProvider.custom: ApiSettings(
      provider: AIProvider.custom,
      baseUrl: '',
      model: '',
    ),
  };

  @override
  void initState() {
    super.initState();
    _capabilityAutoSave = CapabilityAutoSaveService(
      saveChatSettings: _storage.saveChatSettings,
      saveVisionSettings: _visionStorage.saveSettings,
      saveImageSettings: _imageGenerationStorage.saveSettings,
      saveVerification: _verificationStorage.save,
    );
    _chatApiKeyController.addListener(_markModelsStale);
    _chatApiKeyController.addListener(_resetVisionForChatChange);
    _chatApiKeyController.addListener(_resetImageForReferencedKeyChange);
    _chatBaseUrlController.addListener(_markModelsStale);
    _chatBaseUrlController.addListener(_resetVisionForChatChange);
    _chatModelController.addListener(_resetVisionForChatChange);
    _multimodalApiKeyController.addListener(_resetVisionCapability);
    _multimodalApiKeyController.addListener(_markVisionModelsStale);
    _multimodalApiKeyController.addListener(_resetImageForReferencedKeyChange);
    _multimodalBaseUrlController.addListener(_resetVisionCapability);
    _multimodalBaseUrlController.addListener(_markVisionModelsStale);
    _multimodalModelController.addListener(_resetVisionCapability);
    _imageApiKeyController.addListener(_resetImageGenerationState);
    _imageBaseUrlController.addListener(_resetImageGenerationState);
    _imageModelController.addListener(_resetImageGenerationCapability);
    _load();
  }

  @override
  void dispose() {
    _chatApiKeyController.removeListener(_markModelsStale);
    _chatApiKeyController.removeListener(_resetVisionForChatChange);
    _chatApiKeyController.removeListener(_resetImageForReferencedKeyChange);
    _chatBaseUrlController.removeListener(_markModelsStale);
    _chatBaseUrlController.removeListener(_resetVisionForChatChange);
    _chatModelController.removeListener(_resetVisionForChatChange);
    _multimodalApiKeyController.removeListener(_resetVisionCapability);
    _multimodalApiKeyController.removeListener(_markVisionModelsStale);
    _multimodalApiKeyController.removeListener(
      _resetImageForReferencedKeyChange,
    );
    _multimodalBaseUrlController.removeListener(_resetVisionCapability);
    _multimodalBaseUrlController.removeListener(_markVisionModelsStale);
    _multimodalModelController.removeListener(_resetVisionCapability);
    _imageApiKeyController.removeListener(_resetImageGenerationState);
    _imageBaseUrlController.removeListener(_resetImageGenerationState);
    _imageModelController.removeListener(_resetImageGenerationCapability);
    _modelDiscovery.dispose();
    _chatApiKeyController.dispose();
    _chatBaseUrlController.dispose();
    _chatModelController.dispose();
    _multimodalApiKeyController.dispose();
    _multimodalBaseUrlController.dispose();
    _multimodalModelController.dispose();
    _imageApiKeyController.dispose();
    _imageBaseUrlController.dispose();
    _imageModelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _storage.loadSettings(),
      _visionStorage.loadSettings(),
      _imageGenerationStorage.loadSettings(),
      _verificationStorage.load(),
    ]);
    final settings = results[0] as ApiSettings;
    final visionSettings = results[1] as VisionSettings;
    final imageGenerationSettings = results[2] as ImageGenerationSettings;
    final verification = results[3] as AiCapabilityVerificationSnapshot;
    if (!mounted) return;
    setState(() {
      _provider = settings.provider;
      if (settings.provider != AIProvider.custom) {
        _lastOfficialProvider = settings.provider;
      }
      _chatApiKeyController.text = settings.apiKey;
      _chatBaseUrlController.text = settings.baseUrl;
      _chatModelController.text = settings.model;
      _providerDrafts.save(
        settings.provider,
        ProviderSettingsDraft.fromSettings(settings),
      );
      _showCustomApi = settings.provider == AIProvider.custom;
      _manualModelEntry =
          settings.provider == AIProvider.volcengine ||
          settings.provider == AIProvider.custom && settings.model.isNotEmpty;
      _visionUsageMode = visionSettings.usageMode;
      _visionProvider = visionSettings.provider;
      _reuseChatKeyForVision = visionSettings.reuseChatApiKey;
      _visionCapabilityStatus = visionSettings.capabilityStatus;
      _visionDrafts[visionSettings.provider] = visionSettings;
      _multimodalApiKeyController.text = visionSettings.apiKey;
      _multimodalBaseUrlController.text = visionSettings.baseUrl;
      _multimodalModelController.text = visionSettings.model;
      _manualVisionModelEntry = visionSettings.model.isNotEmpty;
      _imageGenerationProvider = imageGenerationSettings.provider;
      _imageApiKeySource = imageGenerationSettings.apiKeySource;
      _imageGenerationProtocol = imageGenerationSettings.protocol;
      _imageGenerationCapabilityStatus =
          imageGenerationSettings.capabilityStatus;
      _imageDrafts[imageGenerationSettings.provider] = imageGenerationSettings;
      _imageApiKeyController.text = imageGenerationSettings.apiKey;
      _imageBaseUrlController.text = imageGenerationSettings.baseUrl;
      _imageModelController.text = imageGenerationSettings.model;
      _manualImageModelEntry =
          imageGenerationSettings.provider ==
              ImageGenerationProvider.volcengine ||
          imageGenerationSettings.model.isNotEmpty;
      _verification = verification;
      _loading = false;
    });
  }

  void _applyPreset(AIProvider provider) {
    final preset = _presets[provider];
    if (preset == null) return;
    _providerDrafts.save(
      _provider,
      ProviderSettingsDraft(
        apiKey: _chatApiKeyController.text,
        baseUrl: _chatBaseUrlController.text,
        model: _chatModelController.text,
      ),
    );
    final draft = _providerDrafts.forProvider(provider);
    setState(() {
      _provider = provider;
      if (provider != AIProvider.custom) _lastOfficialProvider = provider;
      _chatApiKeyController.text = draft?.apiKey ?? '';
      _chatBaseUrlController.text = draft?.baseUrl ?? preset.baseUrl;
      _chatModelController.text = draft?.model ?? preset.model;
      _availableModels = const [];
      _discoveryError = null;
      _connectionFeedback.remove('chat');
      _manualModelEntry =
          provider == AIProvider.volcengine ||
          provider == AIProvider.custom &&
              _chatModelController.text.trim().isNotEmpty;
      if (_imageApiKeySource == ImageApiKeySource.chat) {
        _imageGenerationCapabilityStatus =
            ImageGenerationCapabilityStatus.untested;
      }
    });
  }

  void _markModelsStale() {
    if ((_availableModels.isEmpty && _discoveryError == null) || !mounted) {
      return;
    }
    setState(() {
      _availableModels = const [];
      _discoveryError = null;
      if (_provider != AIProvider.volcengine) _manualModelEntry = false;
    });
  }

  void _resetVisionCapability() {
    if (_loading ||
        !mounted ||
        _visionCapabilityStatus == VisionCapabilityStatus.untested) {
      return;
    }
    setState(() {
      _visionCapabilityStatus = VisionCapabilityStatus.untested;
      _visionCapabilityMessage = null;
    });
  }

  void _resetVisionForChatChange() {
    if (_visionUsageMode == VisionUsageMode.useChatModel ||
        _reuseChatKeyForVision) {
      _resetVisionCapability();
    }
  }

  void _markVisionModelsStale() {
    if (_loading ||
        !mounted ||
        (_availableVisionModels.isEmpty && _visionDiscoveryError == null)) {
      return;
    }
    setState(() {
      _availableVisionModels = const [];
      _visionDiscoveryError = null;
    });
  }

  void _resetImageGenerationCapability() {
    if (_loading ||
        !mounted ||
        _imageGenerationCapabilityStatus ==
            ImageGenerationCapabilityStatus.untested) {
      return;
    }
    setState(() {
      _imageGenerationCapabilityStatus =
          ImageGenerationCapabilityStatus.untested;
      _imageGenerationCapabilityMessage = null;
    });
  }

  void _resetImageGenerationState() {
    if (_loading || !mounted) return;
    setState(() {
      _availableImageModels = const [];
      _imageDiscoveryError = null;
      _imageGenerationCapabilityStatus =
          ImageGenerationCapabilityStatus.untested;
      _imageGenerationCapabilityMessage = null;
    });
  }

  void _resetImageForReferencedKeyChange() {
    final usesChangedKey =
        _imageApiKeySource == ImageApiKeySource.chat ||
        _imageApiKeySource == ImageApiKeySource.vision;
    if (usesChangedKey) _resetImageGenerationCapability();
  }

  ImageGenerationSettings _currentImageGenerationSettings() =>
      ImageGenerationSettings(
        provider: _imageGenerationProvider,
        apiKey: _imageApiKeyController.text.trim(),
        apiKeySource: _imageApiKeySource,
        baseUrl: _imageBaseUrlController.text.trim(),
        model: _imageModelController.text.trim(),
        protocol: _imageGenerationProtocol,
        capabilityStatus: _imageGenerationCapabilityStatus,
      );

  ManagedAiCapability? get _currentlyTesting => switch (_testingTarget) {
    'chat' => ManagedAiCapability.chat,
    'vision' => ManagedAiCapability.vision,
    'image' => ManagedAiCapability.imageGeneration,
    _ => null,
  };

  Map<ManagedAiCapability, AiCapabilityHealth> get _capabilityHealth =>
      _capabilityStatusService.evaluate(
        chatSettings: _currentSettings(),
        visionSettings: _currentVisionSettings(),
        imageSettings: _currentImageGenerationSettings(),
        verification: _verification,
        testing: _currentlyTesting,
      );

  Future<void> _recordVerification(
    ManagedAiCapability capability, {
    required bool success,
    Object? error,
  }) async {
    final verification = AiCapabilityVerification(
      fingerprint: _capabilityStatusService.fingerprintFor(
        capability,
        chatSettings: _currentSettings(),
        visionSettings: _currentVisionSettings(),
        imageSettings: _currentImageGenerationSettings(),
      ),
      success: success,
      errorCategory: success
          ? null
          : _capabilityStatusService.classifyError(error ?? Exception()),
    );
    _verification = _verification.withRecord(capability, verification);
    await _verificationStorage.save(_verification);
  }

  Future<bool> _saveSuccessfulCapability(ManagedAiCapability capability) async {
    try {
      _verification = await _capabilityAutoSave.saveSuccessfulTest(
        capability: capability,
        chatSettings: _currentSettings(),
        visionSettings: _currentVisionSettings(),
        imageSettings: _currentImageGenerationSettings(),
        verification: _verification,
      );
      return true;
    } catch (_) {
      if (mounted) _show('测试成功，但配置保存失败，请点击右上角保存');
      return false;
    }
  }

  ImageApiKeySource? _preferredImageKeySource(
    ImageGenerationProvider provider,
  ) {
    final chatMatches = switch (provider) {
      ImageGenerationProvider.openai => _provider == AIProvider.openai,
      ImageGenerationProvider.volcengine => _provider == AIProvider.volcengine,
      ImageGenerationProvider.custom => _provider == AIProvider.custom,
    };
    if (chatMatches) return ImageApiKeySource.chat;
    final visionMatches =
        _visionUsageMode == VisionUsageMode.separateVisionModel &&
        switch (provider) {
          ImageGenerationProvider.openai =>
            _visionProvider == VisionProvider.openai,
          ImageGenerationProvider.volcengine =>
            _visionProvider == VisionProvider.volcengine,
          ImageGenerationProvider.custom =>
            _visionProvider == VisionProvider.custom,
        };
    return visionMatches ? ImageApiKeySource.vision : null;
  }

  void _applyImageGenerationProvider(ImageGenerationProvider provider) {
    _imageDrafts[_imageGenerationProvider] = _currentImageGenerationSettings();
    final draft = _imageDrafts[provider];
    final reusableSource = _preferredImageKeySource(provider);
    _imageApiKeyController.text = draft?.apiKey ?? '';
    _imageBaseUrlController.text = draft?.baseUrl ?? provider.officialBaseUrl;
    _imageModelController.text = draft?.model ?? '';
    setState(() {
      _imageGenerationProvider = provider;
      _imageApiKeySource =
          draft?.apiKeySource ??
          reusableSource ??
          ImageApiKeySource.independent;
      _imageGenerationProtocol =
          draft?.protocol ?? ImageGenerationProtocol.openAiImagesCompatible;
      _availableImageModels = const [];
      _imageDiscoveryError = null;
      _manualImageModelEntry =
          provider == ImageGenerationProvider.volcengine ||
          (draft?.model.trim().isNotEmpty ?? false);
      _imageGenerationCapabilityStatus =
          draft?.capabilityStatus ?? ImageGenerationCapabilityStatus.untested;
      _imageGenerationCapabilityMessage = null;
    });
  }

  Future<void> _discoverImageModels() async {
    if (_discoveringImageModels ||
        !_imageGenerationProvider.supportsModelDiscovery) {
      return;
    }
    setState(() {
      _discoveringImageModels = true;
      _imageDiscoveryError = null;
    });
    try {
      final provider =
          _imageGenerationProvider == ImageGenerationProvider.openai
          ? AIProvider.openai
          : AIProvider.custom;
      final imageSettings = _currentImageGenerationSettings();
      final models = await _modelDiscovery.discover(
        provider: provider,
        apiKey: imageSettings.effectiveApiKey(
          chatSettings: _currentSettings(),
          visionSettings: _currentVisionSettings(),
        ),
        baseUrl: imageSettings.effectiveBaseUrl,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (_imageModelController.text.trim().isEmpty && models.isNotEmpty) {
        _imageModelController.text = models.first.id;
      }
      setState(() {
        _availableImageModels = models;
        _manualImageModelEntry = false;
      });
    } on ModelDiscoveryException catch (error) {
      if (!mounted) return;
      setState(() => _imageDiscoveryError = error.userMessage);
    } finally {
      if (mounted) setState(() => _discoveringImageModels = false);
    }
  }

  VisionSettings _currentVisionSettings() => VisionSettings(
    usageMode: _visionUsageMode,
    provider: _visionProvider,
    apiKey: _multimodalApiKeyController.text.trim(),
    reuseChatApiKey: _reuseChatKeyForVision,
    baseUrl: _multimodalBaseUrlController.text.trim(),
    model: _multimodalModelController.text.trim(),
    capabilityStatus: _visionCapabilityStatus,
  );

  void _applyVisionProvider(VisionProvider provider) {
    _visionDrafts[_visionProvider] = _currentVisionSettings();
    final draft = _visionDrafts[provider];
    final defaultReuse =
        provider == VisionProvider.openai && _provider == AIProvider.openai;
    _multimodalApiKeyController.text = draft?.apiKey ?? '';
    _multimodalBaseUrlController.text =
        draft?.baseUrl ?? provider.officialBaseUrl;
    _multimodalModelController.text = draft?.model ?? '';
    setState(() {
      _visionProvider = provider;
      _reuseChatKeyForVision = draft?.reuseChatApiKey ?? defaultReuse;
      _availableVisionModels = const [];
      _visionDiscoveryError = null;
      _manualVisionModelEntry =
          provider == VisionProvider.volcengine ||
          (draft?.model.trim().isNotEmpty ?? false);
      _visionCapabilityStatus =
          draft?.capabilityStatus ?? VisionCapabilityStatus.untested;
      _visionCapabilityMessage = null;
      if (_imageApiKeySource == ImageApiKeySource.vision) {
        _imageGenerationCapabilityStatus =
            ImageGenerationCapabilityStatus.untested;
      }
    });
  }

  Future<void> _discoverVisionModels() async {
    if (_discoveringVisionModels ||
        _visionProvider == VisionProvider.volcengine) {
      return;
    }
    setState(() {
      _discoveringVisionModels = true;
      _visionDiscoveryError = null;
    });
    try {
      final provider = _visionProvider == VisionProvider.openai
          ? AIProvider.openai
          : AIProvider.custom;
      final models = await _modelDiscovery.discover(
        provider: provider,
        apiKey: _reuseChatKeyForVision
            ? _chatApiKeyController.text
            : _multimodalApiKeyController.text,
        baseUrl: _visionProvider == VisionProvider.openai
            ? AIProvider.openai.officialBaseUrl
            : _multimodalBaseUrlController.text,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (_multimodalModelController.text.trim().isEmpty && models.isNotEmpty) {
        _multimodalModelController.text = models.first.id;
      }
      setState(() {
        _availableVisionModels = models;
        _manualVisionModelEntry = false;
      });
    } on ModelDiscoveryException catch (error) {
      if (!mounted) return;
      setState(() => _visionDiscoveryError = error.userMessage);
    } finally {
      if (mounted) setState(() => _discoveringVisionModels = false);
    }
  }

  Future<void> _testVisionCapability() async {
    if (_testingTarget != null) return;
    setState(() {
      _testingTarget = 'vision';
      _visionCapabilityMessage = null;
    });
    try {
      await _visionCapabilityTest.test(
        visionSettings: _currentVisionSettings(),
        chatSettings: _currentSettings(),
      );
      if (!mounted) return;
      setState(() {
        _visionCapabilityStatus = VisionCapabilityStatus.supported;
        _visionCapabilityMessage =
            _visionUsageMode == VisionUsageMode.useChatModel
            ? '当前聊天模型支持图片理解'
            : '图片理解可用';
      });
      final saved = await _saveSuccessfulCapability(ManagedAiCapability.vision);
      if (mounted && saved) _show('测试成功，配置已保存');
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _visionCapabilityStatus = VisionCapabilityStatus.unsupported;
        _visionCapabilityMessage =
            _visionUsageMode == VisionUsageMode.useChatModel
            ? '当前聊天模型暂不支持图片理解，建议单独配置图片理解模型'
            : message;
      });
      await _recordVerification(
        ManagedAiCapability.vision,
        success: false,
        error: error,
      );
    } finally {
      if (mounted) setState(() => _testingTarget = null);
    }
  }

  Future<void> _discoverModels() async {
    if (_discoveringModels) return;
    setState(() {
      _discoveringModels = true;
      _discoveryError = null;
    });
    try {
      final models = await _modelDiscovery.discover(
        provider: _provider,
        apiKey: _chatApiKeyController.text,
        baseUrl: _chatBaseUrlController.text,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (_chatModelController.text.trim().isEmpty && models.isNotEmpty) {
        _chatModelController.text = models.first.id;
      }
      setState(() {
        _availableModels = models;
        _manualModelEntry = _provider == AIProvider.volcengine;
      });
    } on ModelDiscoveryException catch (error) {
      if (!mounted) return;
      setState(() => _discoveryError = error.userMessage);
      _show(error.userMessage);
    } finally {
      if (mounted) setState(() => _discoveringModels = false);
    }
  }

  ApiSettings _currentSettings() {
    return ApiSettings(
      provider: _provider,
      apiKey: _chatApiKeyController.text.trim(),
      baseUrl: _chatBaseUrlController.text.trim(),
      model: _chatModelController.text.trim(),
      multimodalApiKey: _multimodalApiKeyController.text.trim(),
      multimodalBaseUrl: _multimodalBaseUrlController.text.trim(),
      multimodalModel: _multimodalModelController.text.trim(),
      imageApiKey: _imageApiKeyController.text.trim(),
      imageBaseUrl: _imageBaseUrlController.text.trim(),
      imageModel: _imageModelController.text.trim(),
    );
  }

  String? _validateUrl(String value, String label) {
    if (value.trim().isEmpty) return '请填写 $label';
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return '$label 格式不正确';
    }
    return null;
  }

  String? _validateChat(ApiSettings settings) {
    if (settings.apiKey.isEmpty) return '请填写聊天模型 API Key';
    final urlError = _validateUrl(settings.baseUrl, '聊天模型 Base URL');
    if (urlError != null) return urlError;
    if (settings.model.isEmpty) return '请填写聊天模型名称或接入点 ID';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final settings = _currentSettings();
    final error = _validateChat(settings);
    if (error != null) {
      _show(error);
      return;
    }

    setState(() => _saving = true);
    try {
      await Future.wait([
        _storage.saveSettings(settings),
        _visionStorage.saveSettings(_currentVisionSettings()),
        _imageGenerationStorage.saveSettings(_currentImageGenerationSettings()),
      ]);
      if (!mounted) return;
      _show('配置已安全保存在本机');
    } catch (error) {
      if (!mounted) return;
      _show('保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testChat() async {
    final settings = _currentSettings();
    final error = _validateChat(settings);
    if (error != null) return _show(error);
    await _runTest('chat', () async {
      final data = await _postJson(
        url: settings.chatCompletionsUrl,
        apiKey: settings.apiKey,
        body: {
          'model': settings.model,
          'messages': const [
            {'role': 'user', 'content': '请只回复：连接成功'},
          ],
          'stream': false,
          'max_tokens': 20,
          'temperature': 0,
        },
      );
      _readChatContent(data);
      return '聊天模型连接成功';
    });
  }

  Future<void> _testImage() async {
    if (_testingTarget != null) return;
    setState(() {
      _testingTarget = 'image';
      _imageGenerationCapabilityMessage = null;
    });
    try {
      final result = await _imageGenerationCapabilityTest.test(
        settings: _currentImageGenerationSettings(),
        chatSettings: _currentSettings(),
        visionSettings: _currentVisionSettings(),
      );
      if (!result.isValid) {
        throw const ImageGenerationException(
          ImageGenerationErrorKind.invalidResult,
          '图片结果格式不兼容',
        );
      }
      if (!mounted) return;
      setState(() {
        _imageGenerationCapabilityStatus =
            ImageGenerationCapabilityStatus.supported;
        _imageGenerationCapabilityMessage = result.isValid
            ? '图片生成可用'
            : '图片结果格式不兼容';
      });
      final saved = await _saveSuccessfulCapability(
        ManagedAiCapability.imageGeneration,
      );
      if (mounted && saved) _show('测试成功，配置已保存');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _imageGenerationCapabilityStatus =
            ImageGenerationCapabilityStatus.unsupported;
        _imageGenerationCapabilityMessage = error.toString().replaceFirst(
          'Exception: ',
          '',
        );
      });
      await _recordVerification(
        ManagedAiCapability.imageGeneration,
        success: false,
        error: error,
      );
    } finally {
      if (mounted) setState(() => _testingTarget = null);
    }
  }

  Future<void> _runTest(String target, Future<String> Function() action) async {
    if (_testingTarget != null) return;
    setState(() {
      _testingTarget = target;
      _connectionFeedback.remove(target);
    });
    try {
      final message = await action();
      if (!mounted) return;
      setState(() {
        _connectionFeedback[target] = _ConnectionFeedback(true, message);
      });
      if (target == 'chat') {
        final saved = await _saveSuccessfulCapability(ManagedAiCapability.chat);
        if (mounted && saved) _show('测试成功，配置已保存');
      } else {
        _show(message);
      }
    } on TimeoutException {
      if (!mounted) return;
      const message = '请求超时，请检查网络或服务地址';
      setState(() {
        _connectionFeedback[target] = const _ConnectionFeedback(false, message);
      });
      if (target == 'chat') {
        await _recordVerification(
          ManagedAiCapability.chat,
          success: false,
          error: TimeoutException(message),
        );
      }
      _show('连接失败：$message');
    } on SocketException {
      if (!mounted) return;
      const message = '网络不可用或无法访问服务地址';
      setState(() {
        _connectionFeedback[target] = const _ConnectionFeedback(false, message);
      });
      if (target == 'chat') {
        await _recordVerification(
          ManagedAiCapability.chat,
          success: false,
          error: const SocketException('network unavailable'),
        );
      }
      _show('连接失败：$message');
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _connectionFeedback[target] = _ConnectionFeedback(false, message);
      });
      if (target == 'chat') {
        await _recordVerification(
          ManagedAiCapability.chat,
          success: false,
          error: error,
        );
      }
      _show('连接失败：$message');
    } finally {
      if (mounted) setState(() => _testingTarget = null);
    }
  }

  Future<Map<String, dynamic>> _postJson({
    required String url,
    required String apiKey,
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(responseText, response.statusCode, apiKey));
    }
    final data = jsonDecode(responseText);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('接口返回格式不是 JSON 对象');
    }
    return data;
  }

  String _readChatContent(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const FormatException('接口没有返回 choices');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map || message['content'] == null) {
      throw const FormatException('接口没有返回回复内容');
    }
    return message['content'].toString();
  }

  String _extractError(String body, int statusCode, String apiKey) {
    if (statusCode == 401 || statusCode == 403) {
      return 'API Key 无效或没有访问权限';
    }
    try {
      final data = jsonDecode(body);
      if (data is Map && data['error'] is Map) {
        final error = data['error'] as Map;
        final rawMessage = error['message']?.toString() ?? '';
        final message = apiKey.isEmpty
            ? rawMessage
            : rawMessage.replaceAll(apiKey, '••••');
        final code = error['code']?.toString() ?? '';
        if (code.contains('model') ||
            message.toLowerCase().contains('model') && statusCode == 404) {
          return '模型不存在或当前 API Key 无权使用该模型：$message';
        }
        if (message.isNotEmpty) return '接口错误（$statusCode）：$message';
      }
    } catch (_) {}
    if (statusCode == 404) return '接口地址或模型不存在（404）';
    return '接口错误（$statusCode），服务返回了无法识别的错误信息';
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _softDecoration({
    required String label,
    IconData? icon,
    String? hint,
    String? helper,
    Widget? suffix,
  }) {
    final radius = BorderRadius.circular(18);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8F6FC),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: const Color(0xFF8D72C9).withValues(alpha: .10),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Color(0xFF9478D3), width: 1.3),
      ),
    );
  }

  Widget _apiKeyField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? helperText,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: _softDecoration(
        label: label,
        helper: helperText,
        icon: Icons.key_rounded,
        suffix: IconButton(
          tooltip: obscure ? '显示' : '隐藏',
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .92)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8063B5).withValues(alpha: .08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEDE6FA),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: const Color(0xFF7556B3)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(color: Color(0xFF777080), height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusLine({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }

  (IconData, Color, String) _healthVisual(
    AiCapabilityHealth health, {
    required String readyText,
  }) => switch (health.state) {
    AiCapabilityHealthState.notConfigured => (
      Icons.info_outline_rounded,
      const Color(0xFF777080),
      health.message,
    ),
    AiCapabilityHealthState.needsAttention => (
      Icons.warning_amber_rounded,
      const Color(0xFFA57725),
      '需要重新测试',
    ),
    AiCapabilityHealthState.ready => (
      Icons.check_circle_rounded,
      const Color(0xFF3E9568),
      readyText,
    ),
    AiCapabilityHealthState.testing => (
      Icons.more_horiz_rounded,
      const Color(0xFF8062BE),
      '测试中…',
    ),
    AiCapabilityHealthState.error => (
      Icons.error_outline_rounded,
      const Color(0xFFB85C68),
      health.message,
    ),
  };

  Widget _unifiedCapabilityLine(
    ManagedAiCapability capability, {
    required String readyText,
  }) {
    final visual = _healthVisual(
      _capabilityHealth[capability]!,
      readyText: readyText,
    );
    return _statusLine(icon: visual.$1, color: visual.$2, text: visual.$3);
  }

  String _testLabel(ManagedAiCapability capability, String initialLabel) =>
      _verification[capability] == null ? initialLabel : '重新测试';

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: .06,
      );
    }
  }

  Widget _capabilityOverview() {
    final entries = [
      (ManagedAiCapability.chat, '聊天', '聊天模型可用', _chatCardKey),
      (ManagedAiCapability.vision, '图片理解', '图片理解可用', _visionCardKey),
      (ManagedAiCapability.imageGeneration, '图片生成', '图片生成可用', _imageCardKey),
    ];
    return _glassCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI 能力',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final entry in entries)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _scrollTo(entry.$4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 82,
                      child: Text(
                        entry.$2,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (_) {
                          final visual = _healthVisual(
                            _capabilityHealth[entry.$1]!,
                            readyText: entry.$3,
                          );
                          return Row(
                            children: [
                              Icon(visual.$1, size: 17, color: visual.$2),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  visual.$3,
                                  style: TextStyle(
                                    color: visual.$2,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFA098AA),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _connectionLine(String target) {
    final feedback = _connectionFeedback[target];
    if (feedback == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _statusLine(
        icon: feedback.success
            ? Icons.check_circle_rounded
            : Icons.error_outline_rounded,
        text: feedback.success ? '连接成功' : feedback.message,
        color: feedback.success
            ? const Color(0xFF3E9568)
            : const Color(0xFFB85C68),
      ),
    );
  }

  Widget _testButton(String target, String label, VoidCallback action) {
    final testing = _testingTarget == target;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _testingTarget == null ? action : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF8062BE),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: testing
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.wifi_tethering_rounded, size: 19),
        label: Text(testing ? '正在测试连接…' : label),
      ),
    );
  }

  bool get _usesCustomOpenAiAddress {
    if (_provider != AIProvider.openai) return false;
    final value = _chatBaseUrlController.text.trim().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return value.isNotEmpty &&
        value != AIProvider.openai.officialBaseUrl &&
        value != '${AIProvider.openai.officialBaseUrl}/chat/completions';
  }

  Future<void> _editOpenAiAddress() async {
    final controller = TextEditingController(text: _chatBaseUrlController.text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OpenAI 高级配置'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: _softDecoration(
            label: '自定义接口地址',
            icon: Icons.link_rounded,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) _chatBaseUrlController.text = value;
  }

  void _showEndpointHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Endpoint ID 在哪里？'),
        content: const Text('打开火山方舟控制台，创建模型推理接入点，然后复制该接入点的 Endpoint ID 填写到这里。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _modelDiscoveryArea({required bool custom}) {
    if (_manualModelEntry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _chatModelController,
            autocorrect: false,
            decoration: _softDecoration(
              label: '模型 ID',
              icon: Icons.memory_rounded,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _manualModelEntry = false),
            child: const Text('返回模型列表选择'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _discoveringModels
                    ? '正在获取可用模型…'
                    : _availableModels.isEmpty
                    ? '填写 API Key 后获取可用模型'
                    : '已获取 ${_availableModels.length} 个可用模型',
                style: const TextStyle(color: Color(0xFF777080), fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: _discoveringModels ? null : _discoverModels,
              icon: _discoveringModels
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _availableModels.isEmpty
                          ? Icons.cloud_download_outlined
                          : Icons.refresh_rounded,
                      size: 18,
                    ),
              label: Text(_availableModels.isEmpty ? '获取模型' : '刷新'),
            ),
          ],
        ),
        if (_availableModels.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              '${_provider.name}-${_availableModels.length}-${_chatModelController.text}',
            ),
            initialValue:
                _availableModels.any(
                  (model) => model.id == _chatModelController.text.trim(),
                )
                ? _chatModelController.text.trim()
                : null,
            decoration: _softDecoration(
              label: custom ? '可用模型' : '聊天模型',
              icon: Icons.memory_rounded,
            ),
            items: _availableModels
                .map(
                  (model) => DropdownMenuItem(
                    value: model.id,
                    child: Text(
                      model.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _chatModelController.text = value;
            },
          ),
          const SizedBox(height: 10),
          _statusLine(
            icon: Icons.check_circle_rounded,
            text: '已获取 ${_availableModels.length} 个可用模型',
            color: const Color(0xFF3E9568),
          ),
          if (_chatModelController.text.trim().isNotEmpty &&
              !_availableModels.any(
                (model) => model.id == _chatModelController.text.trim(),
              )) ...[
            const SizedBox(height: 8),
            _statusLine(
              icon: Icons.warning_amber_rounded,
              text: '当前模型未出现在最新模型列表中，可继续保留或重新选择。',
              color: const Color(0xFFA57725),
            ),
          ],
        ],
        if (_discoveryError != null) ...[
          const SizedBox(height: 10),
          _statusLine(
            icon: Icons.error_outline_rounded,
            text: custom ? '未能自动获取模型列表，你仍然可以手动填写模型 ID。' : '暂时无法获取模型列表',
            color: const Color(0xFFB85C68),
          ),
        ],
        if (custom || _discoveryError != null)
          TextButton(
            onPressed: () => setState(() => _manualModelEntry = true),
            child: Text(custom ? '手动填写模型 ID' : '无法自动获取模型？手动填写模型 ID'),
          ),
      ],
    );
  }

  Widget _officialChatCard() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.chat_bubble_rounded,
            '日常聊天模型',
            '负责角色平时的文字聊天、人格和说话方式。',
          ),
          const SizedBox(height: 22),
          DropdownButtonFormField<AIProvider>(
            key: ValueKey(_provider),
            initialValue: _provider == AIProvider.custom
                ? _lastOfficialProvider
                : _provider,
            decoration: _softDecoration(
              label: 'API 来源',
              icon: Icons.hub_rounded,
            ),
            items: quickApiProviders
                .map(
                  (provider) => DropdownMenuItem(
                    value: provider,
                    child: Text(provider.label),
                  ),
                )
                .toList(),
            onChanged: (provider) {
              if (provider != null) _applyPreset(provider);
            },
          ),
          if (_usesCustomOpenAiAddress) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _editOpenAiAddress,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Color(0xFF8062BE),
                    ),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '当前使用自定义 OpenAI 接口地址',
                        style: TextStyle(
                          color: Color(0xFF8062BE),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Color(0xFF8062BE)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _apiKeyField(
            controller: _chatApiKeyController,
            label: '聊天模型 API Key',
            obscure: _obscureChatKey,
            onToggle: () => setState(() => _obscureChatKey = !_obscureChatKey),
          ),
          const SizedBox(height: 16),
          if (_provider.requiresEndpointId) ...[
            TextField(
              controller: _chatModelController,
              autocorrect: false,
              decoration: _softDecoration(
                label: 'Endpoint ID',
                hint: 'doubao-xxxxxxxxxxxxxxxx',
                icon: Icons.memory_rounded,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '在火山方舟控制台创建推理接入点后，将 Endpoint ID 填写到这里。',
              style: TextStyle(
                color: Color(0xFF777080),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            TextButton.icon(
              onPressed: _showEndpointHelp,
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: const Text('Endpoint ID 在哪里？'),
            ),
          ] else
            _modelDiscoveryArea(custom: false),
          const SizedBox(height: 8),
          _testButton(
            'chat',
            _testLabel(ManagedAiCapability.chat, '测试连接'),
            _testChat,
          ),
          const SizedBox(height: 12),
          _unifiedCapabilityLine(ManagedAiCapability.chat, readyText: '聊天模型可用'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, color: Color(0xFFEDE8F3)),
          ),
          const Text(
            '高级配置',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF777080),
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              _applyPreset(AIProvider.custom);
              setState(() => _showCustomApi = true);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '使用自定义 API / 公益站',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '适用于公益站、代理接口、本地模型及其他兼容服务。',
                          style: TextStyle(
                            color: Color(0xFF827B89),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Color(0xFF8062BE)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _visionCapabilityLine() {
    return _unifiedCapabilityLine(
      ManagedAiCapability.vision,
      readyText: '图片理解可用',
    );
  }

  Widget _visionModelSelector() {
    if (_manualVisionModelEntry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _multimodalModelController,
            autocorrect: false,
            decoration: _softDecoration(
              label: _visionProvider == VisionProvider.volcengine
                  ? 'Endpoint ID'
                  : '图片理解模型 ID',
              icon: Icons.remove_red_eye_rounded,
            ),
          ),
          if (_visionProvider != VisionProvider.volcengine)
            TextButton(
              onPressed: () => setState(() => _manualVisionModelEntry = false),
              child: const Text('返回模型列表选择'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _discoveringVisionModels
                    ? '正在获取候选模型…'
                    : _availableVisionModels.isEmpty
                    ? '获取候选模型后再测试图片能力'
                    : '已获取 ${_availableVisionModels.length} 个候选模型',
                style: const TextStyle(color: Color(0xFF777080), fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: _discoveringVisionModels
                  ? null
                  : _discoverVisionModels,
              icon: _discoveringVisionModels
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _availableVisionModels.isEmpty
                          ? Icons.cloud_download_outlined
                          : Icons.refresh_rounded,
                      size: 18,
                    ),
              label: Text(_availableVisionModels.isEmpty ? '获取模型' : '刷新'),
            ),
          ],
        ),
        if (_availableVisionModels.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'vision-${_visionProvider.name}-${_availableVisionModels.length}-${_multimodalModelController.text}',
            ),
            initialValue:
                _availableVisionModels.any(
                  (model) => model.id == _multimodalModelController.text.trim(),
                )
                ? _multimodalModelController.text.trim()
                : null,
            decoration: _softDecoration(
              label: '图片理解模型',
              icon: Icons.remove_red_eye_rounded,
            ),
            items: _availableVisionModels
                .map(
                  (model) => DropdownMenuItem(
                    value: model.id,
                    child: Text(
                      model.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _multimodalModelController.text = value;
            },
          ),
          if (_multimodalModelController.text.trim().isNotEmpty &&
              !_availableVisionModels.any(
                (model) => model.id == _multimodalModelController.text.trim(),
              )) ...[
            const SizedBox(height: 8),
            _statusLine(
              icon: Icons.warning_amber_rounded,
              text: '当前模型未出现在最新模型列表中，可继续保留或重新选择。',
              color: const Color(0xFFA57725),
            ),
          ],
        ],
        if (_visionDiscoveryError != null) ...[
          const SizedBox(height: 8),
          _statusLine(
            icon: Icons.error_outline_rounded,
            text: '未能自动获取模型列表，你仍然可以手动填写模型 ID。',
            color: const Color(0xFFB85C68),
          ),
        ],
        TextButton(
          onPressed: () => setState(() => _manualVisionModelEntry = true),
          child: const Text('手动填写模型 ID'),
        ),
      ],
    );
  }

  Widget _visionCard() {
    final useChat = _visionUsageMode == VisionUsageMode.useChatModel;
    final canReuseChatKey =
        _provider == AIProvider.openai &&
        _visionProvider == VisionProvider.openai;
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.visibility_rounded,
            '图片理解模型',
            '负责理解你发送给角色的图片，也负责将生活场景整理为可用的画面描述。',
          ),
          const SizedBox(height: 20),
          const Text('使用方式', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SegmentedButton<VisionUsageMode>(
            segments: const [
              ButtonSegment(
                value: VisionUsageMode.useChatModel,
                icon: Icon(Icons.chat_bubble_outline_rounded),
                label: Text('使用聊天模型'),
              ),
              ButtonSegment(
                value: VisionUsageMode.separateVisionModel,
                icon: Icon(Icons.tune_rounded),
                label: Text('单独配置'),
              ),
            ],
            selected: {_visionUsageMode},
            showSelectedIcon: false,
            onSelectionChanged: (values) {
              setState(() {
                _visionUsageMode = values.first;
                if (_visionUsageMode == VisionUsageMode.separateVisionModel &&
                    _visionProvider == VisionProvider.openai &&
                    _provider == AIProvider.openai &&
                    _multimodalApiKeyController.text.trim().isEmpty) {
                  _reuseChatKeyForVision = true;
                }
                _visionCapabilityStatus = VisionCapabilityStatus.untested;
                _visionCapabilityMessage = null;
                if (_imageApiKeySource == ImageApiKeySource.vision) {
                  _imageGenerationCapabilityStatus =
                      ImageGenerationCapabilityStatus.untested;
                }
              });
            },
          ),
          const SizedBox(height: 18),
          if (useChat) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F6FC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当前聊天模型',
                    style: TextStyle(color: Color(0xFF777080), fontSize: 13),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_provider.label} · ${_chatModelController.text.trim().isEmpty ? '尚未选择模型' : _chatModelController.text.trim()}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ] else ...[
            DropdownButtonFormField<VisionProvider>(
              key: ValueKey(_visionProvider),
              initialValue: _visionProvider,
              decoration: _softDecoration(
                label: '图片理解 API 来源',
                icon: Icons.hub_rounded,
              ),
              items: VisionProvider.values
                  .map(
                    (provider) => DropdownMenuItem(
                      value: provider,
                      child: Text(provider.label),
                    ),
                  )
                  .toList(),
              onChanged: (provider) {
                if (provider == null) return;
                _applyVisionProvider(provider);
              },
            ),
            if (canReuseChatKey) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('使用聊天模型 API Key'),
                value: _reuseChatKeyForVision,
                onChanged: (value) => setState(() {
                  _reuseChatKeyForVision = value;
                  _availableVisionModels = const [];
                  _visionDiscoveryError = null;
                  _visionCapabilityStatus = VisionCapabilityStatus.untested;
                  if (_imageApiKeySource == ImageApiKeySource.vision) {
                    _imageGenerationCapabilityStatus =
                        ImageGenerationCapabilityStatus.untested;
                  }
                }),
              ),
            ],
            if (!canReuseChatKey || !_reuseChatKeyForVision) ...[
              const SizedBox(height: 12),
              _apiKeyField(
                controller: _multimodalApiKeyController,
                label: '图片理解 API Key',
                obscure: _obscureMultimodalKey,
                onToggle: () => setState(
                  () => _obscureMultimodalKey = !_obscureMultimodalKey,
                ),
              ),
            ],
            if (_visionProvider == VisionProvider.custom) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _multimodalBaseUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: _softDecoration(
                  label: 'Base URL',
                  hint: 'https://example.com/v1',
                  icon: Icons.link_rounded,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _visionModelSelector(),
          ],
          const SizedBox(height: 12),
          _visionCapabilityLine(),
          const SizedBox(height: 14),
          _testButton(
            'vision',
            _testLabel(
              ManagedAiCapability.vision,
              useChat ? '测试当前模型的图片理解能力' : '测试图片理解能力',
            ),
            _testVisionCapability,
          ),
          if (_visionCapabilityStatus == VisionCapabilityStatus.unsupported &&
              useChat)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _visionUsageMode = VisionUsageMode.separateVisionModel;
                  _visionCapabilityStatus = VisionCapabilityStatus.untested;
                }),
                child: const Text('单独配置图片理解模型'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _imageGenerationCapabilityLine() {
    return _unifiedCapabilityLine(
      ManagedAiCapability.imageGeneration,
      readyText: '图片生成可用',
    );
  }

  Widget _imageModelSelector() {
    if (_manualImageModelEntry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _imageModelController,
            autocorrect: false,
            decoration: _softDecoration(
              label: _imageGenerationProvider.requiresEndpointId
                  ? 'Endpoint / Model ID'
                  : '图片模型 ID',
              icon: Icons.image_rounded,
            ),
          ),
          if (_imageGenerationProvider.supportsModelDiscovery)
            TextButton(
              onPressed: () => setState(() => _manualImageModelEntry = false),
              child: const Text('返回模型列表选择'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _discoveringImageModels
                    ? '正在获取候选模型…'
                    : _availableImageModels.isEmpty
                    ? '获取候选模型后再测试生图能力'
                    : '已获取 ${_availableImageModels.length} 个候选模型',
                style: const TextStyle(color: Color(0xFF777080), fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: _discoveringImageModels ? null : _discoverImageModels,
              icon: _discoveringImageModels
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _availableImageModels.isEmpty
                          ? Icons.cloud_download_outlined
                          : Icons.refresh_rounded,
                      size: 18,
                    ),
              label: Text(_availableImageModels.isEmpty ? '获取模型' : '刷新'),
            ),
          ],
        ),
        if (_availableImageModels.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'image-${_imageGenerationProvider.name}-${_availableImageModels.length}-${_imageModelController.text}',
            ),
            initialValue:
                _availableImageModels.any(
                  (model) => model.id == _imageModelController.text.trim(),
                )
                ? _imageModelController.text.trim()
                : null,
            decoration: _softDecoration(
              label: '图片模型',
              icon: Icons.image_rounded,
            ),
            items: _availableImageModels
                .map(
                  (model) => DropdownMenuItem(
                    value: model.id,
                    child: Text(
                      model.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) _imageModelController.text = value;
            },
          ),
          if (_imageModelController.text.trim().isNotEmpty &&
              !_availableImageModels.any(
                (model) => model.id == _imageModelController.text.trim(),
              )) ...[
            const SizedBox(height: 8),
            _statusLine(
              icon: Icons.warning_amber_rounded,
              text: '当前模型未出现在最新模型列表中，可继续保留或重新选择。',
              color: const Color(0xFFA57725),
            ),
          ],
        ],
        if (_imageDiscoveryError != null) ...[
          const SizedBox(height: 8),
          _statusLine(
            icon: Icons.error_outline_rounded,
            text: '未能自动获取模型列表，你仍然可以手动填写模型 ID。',
            color: const Color(0xFFB85C68),
          ),
        ],
        TextButton(
          onPressed: () => setState(() => _manualImageModelEntry = true),
          child: const Text('手动填写模型 ID'),
        ),
      ],
    );
  }

  Widget _imageGenerationCard() {
    final reusableSource = _preferredImageKeySource(_imageGenerationProvider);
    final reusing = _imageApiKeySource != ImageApiKeySource.independent;
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.auto_awesome_rounded,
            '图片生成模型',
            '负责生成角色图片、生活场景和其他视觉内容。',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<ImageGenerationProvider>(
            key: ValueKey(_imageGenerationProvider),
            initialValue: _imageGenerationProvider,
            decoration: _softDecoration(
              label: 'API 来源',
              icon: Icons.hub_rounded,
            ),
            items: ImageGenerationProvider.values
                .map(
                  (provider) => DropdownMenuItem(
                    value: provider,
                    child: Text(provider.label),
                  ),
                )
                .toList(),
            onChanged: (provider) {
              if (provider != null) _applyImageGenerationProvider(provider);
            },
          ),
          if (reusableSource != null) ...[
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('复用已有 API Key'),
              subtitle: Text(
                reusableSource == ImageApiKeySource.chat
                    ? '使用同 Provider 的聊天模型 Key'
                    : '使用同 Provider 的图片理解模型 Key',
              ),
              value: reusing,
              onChanged: (value) => setState(() {
                _imageApiKeySource = value
                    ? reusableSource
                    : ImageApiKeySource.independent;
                _availableImageModels = const [];
                _imageDiscoveryError = null;
                _imageGenerationCapabilityStatus =
                    ImageGenerationCapabilityStatus.untested;
              }),
            ),
          ],
          if (!reusing) ...[
            const SizedBox(height: 12),
            _apiKeyField(
              controller: _imageApiKeyController,
              label: '图片生成 API Key',
              obscure: _obscureImageKey,
              onToggle: () =>
                  setState(() => _obscureImageKey = !_obscureImageKey),
            ),
          ],
          if (_imageGenerationProvider.showsCustomBaseUrl) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _imageBaseUrlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: _softDecoration(
                label: 'Base URL',
                hint: 'https://example.com/v1',
                icon: Icons.link_rounded,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<ImageGenerationProtocol>(
              initialValue: _imageGenerationProtocol,
              decoration: _softDecoration(
                label: '接口协议',
                icon: Icons.account_tree_outlined,
              ),
              items: const [
                DropdownMenuItem(
                  value: ImageGenerationProtocol.openAiImagesCompatible,
                  child: Text('OpenAI Images Compatible'),
                ),
              ],
              onChanged: (protocol) {
                if (protocol != null) {
                  setState(() => _imageGenerationProtocol = protocol);
                }
              },
            ),
          ],
          const SizedBox(height: 14),
          _imageModelSelector(),
          const SizedBox(height: 12),
          _imageGenerationCapabilityLine(),
          const SizedBox(height: 14),
          _testButton(
            'image',
            _testLabel(ManagedAiCapability.imageGeneration, '测试图片生成能力'),
            _testImage,
          ),
          const SizedBox(height: 8),
          const Text(
            '能力测试会生成一张最小测试图，不会写入聊天记录或正式图片目录。',
            style: TextStyle(color: Color(0xFF777080), fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _customApiBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
      children: [
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                Icons.tune_rounded,
                '自定义 API',
                '连接公益站、代理接口、本地模型或其他自定义模型服务。',
              ),
              const SizedBox(height: 22),
              _apiKeyField(
                controller: _chatApiKeyController,
                label: 'API Key',
                obscure: _obscureChatKey,
                onToggle: () =>
                    setState(() => _obscureChatKey = !_obscureChatKey),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _chatBaseUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: _softDecoration(
                  label: 'Base URL',
                  hint: 'https://example.com/v1',
                  icon: Icons.link_rounded,
                ),
              ),
              const SizedBox(height: 14),
              _modelDiscoveryArea(custom: true),
              const SizedBox(height: 10),
              _testButton('chat', '测试连接', _testChat),
              _connectionLine('chat'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mainBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
      children: [
        _capabilityOverview(),
        const SizedBox(height: 16),
        KeyedSubtree(key: _chatCardKey, child: _officialChatCard()),
        const SizedBox(height: 16),
        KeyedSubtree(key: _visionCardKey, child: _visionCard()),
        const SizedBox(height: 16),
        KeyedSubtree(key: _imageCardKey, child: _imageGenerationCard()),
        if (PeiLinkRuntime.developerToolsEnabled) ...[
          const SizedBox(height: 16),
          _developerDiagnosticsCard(),
        ],
      ],
    );
  }

  Widget _developerDiagnosticsCard() {
    final diagnostics = _capabilityStatusService.diagnostics(
      chatSettings: _currentSettings(),
      visionSettings: _currentVisionSettings(),
      imageSettings: _currentImageGenerationSettings(),
    );
    const capabilityNames = {
      ManagedAiCapability.chat: '聊天',
      ManagedAiCapability.vision: '图片理解',
      ManagedAiCapability.imageGeneration: '图片生成',
    };

    return _glassCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.developer_mode_rounded),
        title: const Text('开发诊断'),
        subtitle: const Text('仅显示 Provider、模型与请求地址，不包含 API Key'),
        children: diagnostics.map((item) {
          final lines = <String>[
            'Provider：${item.provider}',
            'Model：${item.model.isEmpty ? '未设置' : item.model}',
            'Request URL：${item.requestUrl.isEmpty ? '不可用' : item.requestUrl}',
            if (item.discoveryUrl != null) 'Discovery URL：${item.discoveryUrl}',
          ];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              capabilityNames[item.capability] ?? item.capability.name,
            ),
            subtitle: SelectableText(lines.join('\n')),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3FA),
        surfaceTintColor: Colors.transparent,
        title: Text(_showCustomApi ? '自定义 API' : '模型与 API'),
        leading: _showCustomApi
            ? IconButton(
                tooltip: '返回快速配置',
                onPressed: () {
                  _applyPreset(_lastOfficialProvider);
                  setState(() => _showCustomApi = false);
                },
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        actions: [
          TextButton.icon(
            onPressed: _loading || _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_saving ? '保存中…' : '保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF6F3FA), Color(0xFFFBFAFD)],
                ),
              ),
              child: _showCustomApi ? _customApiBody() : _mainBody(),
            ),
    );
  }
}
