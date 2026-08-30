class PhysicalHostSettings {
  const PhysicalHostSettings({
    this.esp32Host = '',
    this.requestKey = '',
    this.volcengineApiKey = '',
    this.boostingTableId = '',
    this.characterId = '',
    this.playbackGain = 0.18,
  });

  final String esp32Host;
  final String requestKey;
  final String volcengineApiKey;
  final String boostingTableId;
  final String characterId;
  final double playbackGain;

  bool get isDeviceConfigured =>
      esp32Host.trim().isNotEmpty && requestKey.trim().isNotEmpty;
  bool get isCloudConfigured => volcengineApiKey.trim().isNotEmpty;
  bool get isConfigured =>
      isDeviceConfigured && isCloudConfigured && characterId.trim().isNotEmpty;
}
