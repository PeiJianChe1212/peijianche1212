/// Memory Context 的快照。
///
/// 第一阶段保留现有记忆文本，不在这里改变筛选、排序或审核规则。
class MemoryContext {
  const MemoryContext({this.confirmedMemory = ''});

  final String confirmedMemory;
}

abstract interface class MemoryContextProvider {
  Future<MemoryContext> load();
}
