import 'dart:async';

import 'package:flutter/material.dart';

/// App 级连续使用时长追踪与提醒服务。
///
/// 依据《人工智能拟人化互动服务管理暂行办法》第十八条：
/// 连续使用拟人化互动服务每超过 2 小时，应以弹窗方式提醒用户注意使用时长。
///
/// 计时基于 [RouteObserver] + [RouteAware]：只有当前路由栈顶可见的
/// 拟人化互动页面才会计时。被新页面覆盖时自动暂停，返回时恢复。
class UsageTimerService with WidgetsBindingObserver {
  UsageTimerService._();
  static final UsageTimerService instance = UsageTimerService._();

  /// 正式环境：连续使用 2 小时触发提醒。
  static const Duration _productionThreshold = Duration(hours: 2);

  /// 测试环境短阈值（秒）。通过 dart-define `PEILINK_USAGE_TEST_THRESHOLD_SEC` 覆盖。
  static final Duration threshold = () {
    const testSec = int.fromEnvironment(
      'PEILINK_USAGE_TEST_THRESHOLD_SEC',
      defaultValue: 0,
    );
    if (testSec > 0) return Duration(seconds: testSec);
    return _productionThreshold;
  }();

  /// App 切到后台后超过此时长，视为连续使用中断。技术默认值，非法条规定。
  static const Duration backgroundResetGrace = Duration(minutes: 15);

  /// 全局路由观察者，由各互动页面通过 RouteAware 订阅。
  final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  Timer? _ticker;
  Duration _accumulated = Duration.zero;
  bool _inForeground = true;
  bool _topRouteVisible = false;
  DateTime? _pausedAt;
  bool _dialogShowing = false;
  bool _initialized = false;

  Duration get accumulated => _accumulated;
  bool get dialogShowing => _dialogShowing;

  bool get _isTiming =>
      _inForeground && _topRouteVisible && !_dialogShowing;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// 互动路由变为栈顶可见（didPush / didPopNext）。
  void onInteractiveRouteVisible() {
    _topRouteVisible = true;
    _maybeStartTicker();
  }

  /// 互动路由被新页面覆盖或出栈（didPushNext / didPop）。
  void onInteractiveRouteHidden() {
    _topRouteVisible = false;
    _stopTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _inForeground = true;
        if (_pausedAt != null) {
          final away = DateTime.now().difference(_pausedAt!);
          if (away >= backgroundResetGrace) {
            _accumulated = Duration.zero;
          }
          _pausedAt = null;
        }
        _maybeStartTicker();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _inForeground = false;
        _pausedAt = DateTime.now();
        _stopTicker();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _maybeStartTicker() {
    if (_ticker != null) return;
    if (!_isTiming) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _accumulated += const Duration(seconds: 1);
      if (_accumulated >= threshold && !_dialogShowing) {
        _stopTicker();
        _showReminder();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _showReminder() {
    _dialogShowing = true;
    final context = navigatorKey.currentContext;
    if (context == null) {
      _dialogShowing = false;
      _accumulated = Duration.zero;
      _maybeStartTicker();
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          '休息一下吧',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          '你已经连续使用 PeiLink 较长时间了。当前互动内容由人工智能生成，建议适当休息一下。',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _onDialogDismissed();
            },
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _onDialogDismissed() {
    _dialogShowing = false;
    _accumulated = Duration.zero;
    _maybeStartTicker();
  }

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
