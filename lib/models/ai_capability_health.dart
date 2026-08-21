enum ManagedAiCapability { chat, vision, imageGeneration }

enum AiCapabilityHealthState {
  notConfigured,
  needsAttention,
  ready,
  testing,
  error,
}

enum AiUserErrorCategory {
  invalidApiKey,
  modelUnavailable,
  permissionDenied,
  unsupportedCapability,
  invalidBaseUrl,
  incompatibleProtocol,
  networkUnavailable,
  timeout,
  invalidResponse,
  unknown,
}

extension AiUserErrorCategoryDetails on AiUserErrorCategory {
  String get message => switch (this) {
    AiUserErrorCategory.invalidApiKey => 'API Key 无效',
    AiUserErrorCategory.modelUnavailable => '当前模型不可用',
    AiUserErrorCategory.permissionDenied => '没有该模型权限',
    AiUserErrorCategory.unsupportedCapability => '当前模型不支持此能力',
    AiUserErrorCategory.invalidBaseUrl => '接口地址无效',
    AiUserErrorCategory.incompatibleProtocol => '接口协议不兼容',
    AiUserErrorCategory.networkUnavailable => '网络连接失败',
    AiUserErrorCategory.timeout => '请求超时',
    AiUserErrorCategory.invalidResponse => '接口返回格式异常',
    AiUserErrorCategory.unknown => '连接失败',
  };
}

class AiCapabilityHealth {
  const AiCapabilityHealth({
    required this.capability,
    required this.state,
    required this.message,
    this.errorCategory,
  });

  final ManagedAiCapability capability;
  final AiCapabilityHealthState state;
  final String message;
  final AiUserErrorCategory? errorCategory;
}

class AiCapabilityVerification {
  const AiCapabilityVerification({
    required this.fingerprint,
    required this.success,
    this.errorCategory,
  });

  final String fingerprint;
  final bool success;
  final AiUserErrorCategory? errorCategory;

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'success': success,
    if (errorCategory != null) 'errorCategory': errorCategory!.name,
  };

  static AiCapabilityVerification? fromJson(Object? value) {
    if (value is! Map) return null;
    final fingerprint = value['fingerprint']?.toString() ?? '';
    if (fingerprint.isEmpty || value['success'] is! bool) return null;
    final categoryName = value['errorCategory']?.toString();
    return AiCapabilityVerification(
      fingerprint: fingerprint,
      success: value['success'] as bool,
      errorCategory: AiUserErrorCategory.values
          .where((category) => category.name == categoryName)
          .firstOrNull,
    );
  }
}

class AiCapabilityVerificationSnapshot {
  const AiCapabilityVerificationSnapshot({this.records = const {}});

  final Map<ManagedAiCapability, AiCapabilityVerification> records;

  AiCapabilityVerification? operator [](ManagedAiCapability capability) =>
      records[capability];

  AiCapabilityVerificationSnapshot withRecord(
    ManagedAiCapability capability,
    AiCapabilityVerification verification,
  ) => AiCapabilityVerificationSnapshot(
    records: {...records, capability: verification},
  );

  Map<String, dynamic> toJson() => {
    for (final entry in records.entries) entry.key.name: entry.value.toJson(),
  };

  static AiCapabilityVerificationSnapshot fromJson(Object? value) {
    if (value is! Map) return const AiCapabilityVerificationSnapshot();
    final records = <ManagedAiCapability, AiCapabilityVerification>{};
    for (final capability in ManagedAiCapability.values) {
      final verification = AiCapabilityVerification.fromJson(
        value[capability.name],
      );
      if (verification != null) records[capability] = verification;
    }
    return AiCapabilityVerificationSnapshot(records: records);
  }
}

class AiRequestDiagnostics {
  const AiRequestDiagnostics({
    required this.capability,
    required this.provider,
    required this.model,
    required this.requestUrl,
    this.discoveryUrl,
    this.httpStatus,
    this.errorCategory,
  });

  final ManagedAiCapability capability;
  final String provider;
  final String model;
  final String requestUrl;
  final String? discoveryUrl;
  final int? httpStatus;
  final AiUserErrorCategory? errorCategory;

  Map<String, Object?> toSafeMap() => {
    'capability': capability.name,
    'provider': provider,
    'model': model,
    'requestUrl': requestUrl,
    'discoveryUrl': discoveryUrl,
    'httpStatus': httpStatus,
    'errorCategory': errorCategory?.name,
  };
}
