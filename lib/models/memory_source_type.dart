enum MemorySourceType {
  manual,
  legacy,
  imported,
  automatic;

  static MemorySourceType fromJson(dynamic value) {
    final name = value?.toString();
    return MemorySourceType.values.firstWhere(
      (item) => item.name == name,
      orElse: () => MemorySourceType.manual,
    );
  }
}
