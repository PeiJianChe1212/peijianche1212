import 'api_settings.dart';

enum ConnectionTestState { idle, testing, success, failure }

extension ApiProviderUiPolicy on AIProvider {
  bool get isQuickProvider => this != AIProvider.custom;
  bool get supportsModelDiscovery => this != AIProvider.volcengine;
  bool get requiresEndpointId => this == AIProvider.volcengine;
}

const quickApiProviders = <AIProvider>[
  AIProvider.deepseek,
  AIProvider.openai,
  AIProvider.volcengine,
];

class ProviderSettingsDraft {
  const ProviderSettingsDraft({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  factory ProviderSettingsDraft.fromSettings(ApiSettings settings) =>
      ProviderSettingsDraft(
        apiKey: settings.apiKey,
        baseUrl: settings.baseUrl,
        model: settings.model,
      );

  final String apiKey;
  final String baseUrl;
  final String model;
}

class ProviderDraftStore {
  final Map<AIProvider, ProviderSettingsDraft> _drafts = {};

  void save(AIProvider provider, ProviderSettingsDraft draft) {
    _drafts[provider] = draft;
  }

  ProviderSettingsDraft? forProvider(AIProvider provider) => _drafts[provider];
}

/// 独立于页面 Widget 的基础状态，供第二批 UI 直接复用。
class ApiSettingsFormState {
  const ApiSettingsFormState({
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
    required this.availableModelIds,
    required this.selectedModel,
    required this.manualModelId,
    required this.loading,
    required this.discoveryError,
    required this.connectionTestState,
  });

  final AIProvider provider;
  final String apiKey;
  final String baseUrl;
  final List<String> availableModelIds;
  final String selectedModel;
  final String manualModelId;
  final bool loading;
  final String? discoveryError;
  final ConnectionTestState connectionTestState;
}
