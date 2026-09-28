import 'dart:async';

/// Serializes Game Room actions and guards their async results with an epoch.
///
/// Turtle Soup 的 Question Engine 在 deterministic 规则无法判断时会异步调用
/// Semantic Judge。User / Character Action 必须保持提交顺序，并且旧 epoch 的
/// 结果（例如上一局的 Judge 回答、已离开页面的房间）绝不能再写回新 Session。
class GameActionPipeline {
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;
  bool _disposed = false;

  int get epoch => _epoch;
  bool get isDisposed => _disposed;

  /// 排队执行 [task]：任务严格按提交顺序运行，前一个任务结束后才开始下一个。
  ///
  /// 目前返回的 Future 永远以正常完成收尾：单个 Action 的失败不应让房间中断，
  /// 也不允许异常穿透到 Widget 回调。
  Future<void> enqueue(Future<void> Function() task) {
    final run = _tail.then((_) async {
      if (_disposed) return;
      try {
        await task();
      } catch (_) {
        // 用户 Action 已经尽力执行；失败不阻塞后续 Action。
      }
    });
    _tail = run;
    return run;
  }

  /// 开始一次新 Action，同时让此前所有 epoch 立即失效。
  int begin() => ++_epoch;

  /// 只接受当前 epoch 的结果。
  bool accepts(int epoch) => !_disposed && epoch == _epoch;

  /// 让在途结果全部失效（例如换题重开一局）。
  void invalidate() {
    _epoch++;
  }

  void dispose() {
    _disposed = true;
    _epoch++;
  }

  /// 等待当前排队任务全部结束，仅供测试与流程收尾使用。
  Future<void> get idle => _tail;
}
