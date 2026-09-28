# PeiLink Flutter Test Hang Audit

**审计时间**: 2026-09-14 23:30 CST
**审计范围**: G:\Development\PeiLink (只读)
**Flutter**: 3.44.6 stable / Dart 3.12.2
**操作系统**: Windows (12 逻辑核)

---

## A. 当前结论

PeiLink `flutter test` 的间歇性挂起**不是某一个 AI Agent 的执行问题**，而是项目测试基础设施中多个风险因素叠加的结果。核心问题集中在：

1. **页面级 Timer.periodic 在测试结束后可能残留**，导致 test isolate 无法退出（TYPE B 高概率）
2. **HomePage 中存在无条件渲染的无限重复动画**（`_DesktopBackground`），任何对 HomePage 使用 `pumpAndSettle()` 的测试都会永久挂起（TYPE A 中高概率，当前被规避但极其脆弱）
3. **12 核高并发 + 大量真实文件 I/O**，Windows 文件系统偶发延迟导致 `runAsync` 长时间无响应（TYPE C 中概率）
4. **无全局测试配置**（无 flutter_test_config.dart、无 dart_test.yaml、无 @Timeout），缺乏兜底超时和全局清理机制

**当前机器上没有 flutter test 进程在运行**。当前活跃的 dart/dartaotruntime 进程是 `flutter run --flavor user`（Codex 在 Android 模拟器上运行应用），不是测试。

---

## B. 当前正在运行的相关进程图

| PID | Parent PID | Name | Command | Role | 属于 Codex 当前任务 |
|-----|-----------|------|---------|------|---------------------|
| 35896 | 6568 | dart.exe | `flutter run --flavor user --target lib/main_user.dart` | Flutter tool 入口 | 是 |
| 42956 | 35896 | dartvm.exe | flutter_tools.snapshot run | Flutter tool 执行体 | 是 |
| 5816 | 42956 | dartaotruntime.exe | frontend_server_aot.dart.snapshot (增量编译器) | 编译器 | 是 |
| 17124 | 42956 | dart.exe | development-service (VM Service / DevTools) | 开发服务 | 是 |
| 16880 | — | java.exe | (Gradle daemon) | Gradle daemon (正常) | 否 (常驻) |
| 21264 | — | java.exe | (Gradle daemon, 1.2GB) | Gradle daemon (正常) | 否 (常驻) |

**结论**: 当前无测试进程。两个 Java 进程是正常 Gradle daemon，非故障。无历史残留 flutter test runner。

---

## C. 测试架构概况

| 指标 | 数值 |
|------|------|
| 测试文件总数 | 156 (test/ 根目录 133 + physical/ 22 + browser/ 1) |
| testWidgets 调用 | 121 |
| test() 调用 | ~864 (含部分字符串误匹配) |
| group() 调用 | 24 |
| setUp | 65 |
| setUpAll | 0 |
| tearDown | 67 |
| tearDownAll | 0 |
| lib Dart 文件 | 430 |

**测试类型分布**:
- **Widget tests**: 121 个 testWidgets，覆盖页面、组件、主题层
- **Unit tests**: 大量纯逻辑测试（memory、physical 协议解析、prompt 等）
- **Integration-style**: `physical_session_end_to_end_test.dart`、`core_bridge_server_test.dart`（含真实 HttpServer + HttpClient）
- **异步长任务**: 无测试代码中的 Timer/Future.delayed；但 lib 中页面有 Timer.periodic
- **真实文件系统读写**: 极重 — 70+ 测试文件使用 `Directory.systemTemp.createTemp`，73 处 `delete(recursive: true)`
- **SharedPreferences**: 无（项目使用 flutter_secure_storage + 文件存储）
- **FlutterSecureStorage**: 8 个测试文件使用 `setMockInitialValues({})`
- **Process 启动**: 无（test 和 lib 中均无 Process.start/run）
- **Isolate**: 无（test 和 lib 中均无 Isolate.spawn/ReceivePort）
- **Timer**: 测试代码 0 处；lib 中 4 处（1 one-shot + 3 periodic）
- **StreamController**: 测试代码 0 处；lib 中 2 处（均在 session_reset_service.dart，static broadcast）
- **.listen()**: 测试代码 1 处；lib 中 1 处（chat_page.dart 监听 SessionResetService）
- **MethodChannel**: 50+ 测试文件 mock path_provider channel
- **插件初始化**: 无显式插件初始化
- **全局 singleton**: 3 个（PeiLinkThemeController.instance、PeiLinkAppearanceController.instance、CharacterRegistryService.changes）
- **跨 test 共用静态状态**: 存在（见 E 节）

---

## D. 高风险异步资源扫描

### D1. Timer

| 位置 | 类型 | 周期 | dispose 中 cancel? |
|------|------|------|---------------------|
| lib/pages/chat_page.dart:120 | Timer (one-shot) | 24s | 是 (line 134) |
| lib/pages/chat_page.dart:123 | Timer.periodic | 1min | 是 (line 133) |
| lib/pages/home_page.dart:104 | Timer.periodic | 30s | 是 (line 132) |
| lib/pages/home_page.dart:114 | Timer.periodic | 1min | 是 (line 133) |

**风险**: 所有 Timer 都在 State.dispose() 中正确 cancel。**但前提是 dispose() 被调用**。在 `testWidgets` 中，如果测试结束时 widget tree 未被正确清理（例如通过 runAsync 启动的异步操作尚未完成，或页面在路由中未被 pop），Timer.periodic 将持续运行并阻止 isolate 退出。

**关键证据**: `test/ai_world_home_entry_test.dart:104` 有明确注释：
```dart
// 关闭聊天页，避免其定时器影响测试收尾。
tester.state<NavigatorState>(find.byType(Navigator)).pop();
```
这证明开发者**已经实际遭遇过 ChatPage 定时器导致测试收尾卡住的问题**，并采取了手动 pop 的规避措施。

### D2. Stream / StreamController

| 位置 | 类型 | 是否 close? |
|------|------|-------------|
| lib/services/session_reset_service.dart:12 | `static final StreamController<String>.broadcast()` | **永不关闭** |

**风险**: 这是一个全局静态 broadcast StreamController。broadcast controller 本身不阻止 VM 退出（无订阅者时不持有事件）。但 `chat_page.dart:114` 通过 `_chatResetSubscription = SessionResetService.chatResets.listen(...)` 订阅它。如果 ChatPage 未被 dispose，subscription 不会被 cancel。

### D3. Observer / WidgetsBinding

| 位置 | addObserver | removeObserver |
|------|-------------|----------------|
| lib/pages/chat_page.dart:60,111 | 是 | 是 (dispose line 136) |
| lib/pages/home_page.dart:48,97 | 是 | 是 (dispose line 131) |

lib 中 addObserver/removeObserver 数量对称（各 2）。测试代码中无 addObserver/removeObserver。

**风险**: 同 Timer — 依赖 dispose() 被调用。

### D4. Isolate / Process / Socket

- **Isolate.spawn / ReceivePort / RawReceivePort**: test 和 lib 中均为 0
- **Process.start / Process.run**: test 和 lib 中均为 0
- **HttpServer**: lib/services/core_bridge_server.dart（有 stop()/dispose()）
- **ServerSocket**: test/core_bridge_server_test.dart（立即 close）
- **HttpClient**: test/core_bridge_server_test.dart（finally 中 close(force: true) + addTearDown）

**结论**: core_bridge 相关资源清理良好，非挂起来源。

### D5. pumpAndSettle

共 **69 处** pumpAndSettle 调用，分布在 20 个测试文件中。

**关键风险 — 无限动画**:

`lib/pages/home_page.dart:1959` 存在 **无条件渲染的无限重复动画**:
```dart
// _DesktopBackground (home_page.dart:1942-1966)
_controller = AnimationController(
  vsync: this,
  duration: HomeVisualTokens.motionAmbient,
)..repeat(reverse: true);  // 无限重复！
```

该 `_DesktopBackground` 在 home_page.dart:501 **无条件渲染**:
```dart
const Positioned.fill(child: _DesktopBackground()),
```

**这意味着：任何 pump HomePage 后调用 pumpAndSettle() 的测试将永久挂起。**

当前会 pump HomePage 的测试：
- `ai_world_home_entry_test.dart` — 使用自定义 `settle()`（手动 pump 40 轮），**规避了** pumpAndSettle
- `life_desktop_layout_test.dart` — 使用 `tester.pump()` / `tester.pump(duration)`，**规避了** pumpAndSettle
- `widget_test.dart` — 使用 `tester.pump()` + `runAsync`，**规避了** pumpAndSettle
- `echo_my_echo_entry_test.dart` — pump PeiLinkHomePage（新页面，无此动画）
- `group_chat_g1_test.dart` — pump PeiLinkHomePage
- `physical_release_isolation_test.dart` — pump PeiLinkHomePage

**当前所有 pump HomePage 的测试都规避了 pumpAndSettle，但这是极其脆弱的约定。** 任何新增测试或重构中误加 pumpAndSettle 都会导致确定性挂起。

此外，`GroupChatPage` 有条件渲染的 `CircularProgressIndicator`（line 576, 1060）。如果测试触发 loading 状态后调用 pumpAndSettle，也会挂起。

### D6. Listener / ChangeNotifier

- lib 中 addListener: 18 处，removeListener: 18 处（对称）
- ChangeNotifier 子类: 4 个（PeiLinkThemeController、PeiLinkAppearanceController、PhysicalSessionController 等）
- ValueNotifier: 2 个（CharacterRegistryService.changes 为 static）
- AnimationController: 仅 home_page.dart（含无限重复的 _DesktopBackground）

**6 个使用 pumpAndSettle 但无 tearDown/addTearDown 的测试文件**:
- chat_input_area_test.dart
- chat_timeline_confirmation_test.dart
- memory201_source_ui_test.dart
- memory_center_page_test.dart
- memory_final_closure_ui_test.dart
- red_packet_send_entry_test.dart

这些测试不创建需要显式清理的资源（无 temp dir、无 server），widget 由测试框架自动管理。风险较低。

---

## E. Singleton / Global State 风险

| Singleton | 类型 | 位置 | 有 reset API? | 测试中使用? |
|-----------|------|------|---------------|-------------|
| `PeiLinkThemeController.instance` | static final | lib/services/peilink_theme_service.dart:14 | **无** | 多数测试创建本地实例，少数可能间接使用 |
| `PeiLinkAppearanceController.instance` | static final | lib/services/peilink_appearance_service.dart:20 | **无** | 多数测试用 `.testing()` 工厂创建本地实例 |
| `CharacterRegistryService.changes` | static final ValueNotifier<int> | lib/services/character_registry_service.dart:15 | **无** | beta3_existing_ux_fixes_test.dart 中使用，有 addTearDown removeListener |
| `SessionResetService._chatResetController` | static final StreamController.broadcast | lib/services/session_reset_service.dart:12 | **无（永不关闭）** | 间接通过 ChatPage 使用 |

**风险分析**:
1. Flutter test 中每个测试文件运行在独立 isolate 中，因此 static 状态**不会跨文件泄漏**。
2. 但在**同一文件内**，多个 test()/testWidgets() 共享同一 isolate 的 static 状态。
3. 当前大多数测试创建本地实例（通过构造函数注入 storage），不直接使用 static singleton，因此污染风险较低。
4. `CharacterRegistryService.changes` 是 static ValueNotifier，如果测试 A 添加 listener 后未移除（虽然当前有 addTearDown），会影响测试 B。
5. **无任何全局 reset API** — 如果未来需要在测试间重置 singleton 状态，没有现成机制。

---

## F. Windows 文件句柄 / 文件系统风险

1. **大量真实文件 I/O**: 70+ 测试文件使用 `Directory.systemTemp.createTemp()` 创建临时目录，通过 `NativePlatformStorage` 进行 JSON 文件读写。
2. **清理机制**: 73 处 `delete(recursive: true)`，多数通过 `addTearDown` 注册。
3. **文件锁风险**: Windows 上 `FileImage` 缓存（`imageCache`）可能持有文件句柄。`AvatarImageCache.evictPath()` 用于显式驱逐，但仅在 beta3 测试中调用。
4. **并发冲突**: 12 核并发运行时，多个 isolate 同时在 systemTemp 下创建/删除目录。虽然目录名唯一（createTemp 生成随机后缀），但 Windows 文件系统操作（尤其有杀毒软件时）可能偶发延迟。
5. **无 RandomAccessFile 未关闭**: 未发现 RandomAccessFile 使用。
6. **无 FileSystemWatcher**: 未发现。

**结论**: 文件系统本身不是确定性挂起来源，但在高并发 + Windows + 杀毒软件场景下，可能导致 `runAsync` 中的文件操作偶发耗时过长，表现为"测试无输出"。

---

## G. Test Runner / Flutter Tool 风险

| 配置项 | 值 | 风险 |
|--------|-----|------|
| flutter_test_config.dart | **不存在** | 无全局初始化/清理钩子 |
| dart_test.yaml | **不存在** | 无全局超时/并发配置 |
| @Timeout 注解 | **0 处** | 全部使用默认 30s 超时 |
| --concurrency | 未指定 | 默认 = CPU 核数 = 12 |
| fakeAsync | 0 处 | 全部使用真实异步 |
| runAsync | 100+ 处 | 真实文件 I/O 在 widget test 中执行 |

**关键风险**:
1. **无全局超时兜底**: 默认单测试超时 30s。但如果 hang 发生在 isolate 退出阶段（所有测试已完成但 Timer 残留），30s 超时不适用 — isolate 会永远等待。
2. **12 并发**: 高并发增加资源竞争和 race condition 概率。
3. **frontend_server**: dartaotruntime 进程负责增量编译。如果在测试编译阶段崩溃或挂起，测试 runner 无输出等待。当前 Flutter 3.44.6 较新（约 10 周），存在未发现 bug 的可能性。
4. **无 flutter_test_config.dart**: 无法添加全局 tearDown 来清理 static 状态、检查残留 Timer 等。

---

## H. 是否存在固定挂起 Test

**当前证据不支持固定挂起点**:
- 问题在 DeepSeek 和 Codex 上都出现，且描述为"偶尔"（间歇性）
- 无历史日志可对比最后运行位置
- 所有 pumpAndSettle 调用当前都规避了无限动画页面
- core_bridge 测试有完善的 addTearDown 清理

**但存在一个确定性挂起隐患**（当前被规避）:
- 任何对 `HomePage`（含 `_DesktopBackground` 无限动画）调用 `pumpAndSettle()` 的测试会**确定性永久挂起**
- 当前通过"不使用 pumpAndSettle"的约定规避，但无编译/运行时保护

---

## I. 是否存在 Test 顺序依赖

1. **setUp/tearDown 对称**: 65 setUp vs 67 tearDown，基本对称。无 setUpAll/tearDownAll。
2. **同文件内 static 状态**: 存在 static singleton，但多数测试创建本地实例，顺序依赖风险低。
3. **MethodChannel mock**: 50+ 测试文件在 setUp 中设置 path_provider mock，在 tearDown 中清除。对称良好。
4. **PeiLinkRuntime.configure**: 部分测试在 setUp/tearDown 中重置为 `unspecified`。但并非所有测试都这样做 — 如果测试 A 设置了 `PeiLinkBuild.user` 而测试 B 未重置，可能影响同文件后续测试。
5. **潜在模式**: Test A pump HomePage（启动 Timer.periodic）→ 测试结束时 widget 未完全 dispose → Timer 残留 → Test B 正常运行 → 所有测试完成后 isolate 因 Timer 无法退出。

**结论**: 存在轻度顺序依赖风险（PeiLinkRuntime 配置、static singleton），但不是主要挂起来源。最可能的顺序相关问题是**前一个测试的页面 Timer 残留导致整个文件的 isolate 无法退出**。

---

## J. DeepSeek 与 Codex 都会卡对根因判断的影响

**这是最重要的诊断线索之一**:
- 排除了"某 AI Agent 执行方式有问题"的假设
- 两个 Agent 可能以不同顺序、不同并发参数运行测试，但都遇到挂起
- 指向**项目本身的测试基础设施问题**，而非执行环境
- 进一步支持 TYPE B（资源未释放导致进程不退出）和 TYPE C（基础设施偶发挂起），而非 TYPE A（单个测试逻辑错误）
- 如果是 TYPE A（某个测试永不完成），应该能在两个 Agent 的日志中看到相同的最后运行测试，但用户描述为"偶尔"且未提到固定位置

---

## K. Root Cause Ranking

### P1 — 高概率: 页面 Timer.periodic 残留导致 test isolate 无法退出 (TYPE B)

**支持证据**:
- HomePage 有 2 个 Timer.periodic（30s + 1min），ChatPage 有 1 个 Timer.periodic（1min）+ 1 个 24s one-shot
- `ai_world_home_entry_test.dart:104` 明确注释"关闭聊天页，避免其定时器影响测试收尾"，证明开发者已实际遭遇此问题
- 多个测试文件 pump HomePage / ChatPage / GroupChatPage
- Flutter test 的 widget 自动清理与 `runAsync` 存在 race condition 可能
- 间歇性：取决于 widget dispose 时序和并发调度
- 两个 Agent 都遇到：与 Agent 无关，是项目代码问题

**反对证据**:
- 所有 Timer 都在 State.dispose() 中正确 cancel
- Flutter test 框架理论上会在测试结束后清理 widget tree
- 无直接日志证明 isolate 因 Timer 无法退出

**还缺什么证据**:
- 挂起时的进程栈信息（Dart VM service 连接，查看活跃 Timer）
- 挂起时是否所有测试已输出完成（区分"测试中挂起" vs "测试完成后不退出"）

### P2 — 中高概率: _DesktopBackground 无限动画 + pumpAndSettle 隐患 (TYPE A)

**支持证据**:
- home_page.dart:1959 `..repeat(reverse: true)` 无条件渲染的无限动画
- 69 处 pumpAndSettle 调用分布在 20 个测试文件中
- 当前通过"约定不使用 pumpAndSettle"规避，无强制保护
- 任何新增/重构测试误加 pumpAndSettle 都会确定性挂起
- GroupChatPage 有条件 CircularProgressIndicator，也可能导致 pumpAndSettle 挂起

**反对证据**:
- 当前所有 pump HomePage 的测试都规避了 pumpAndSettle
- 如果是这个原因，应该是确定性挂起而非间歇性
- 无证据表明当前有测试实际触发了此路径

**还缺什么证据**:
- 确认挂起时最后运行的测试文件是否包含 pumpAndSettle + HomePage 组合

### P3 — 中概率: Windows 高并发文件 I/O 偶发延迟 (TYPE C)

**支持证据**:
- 12 核 CPU → 默认 12 并发 test isolate
- 70+ 测试文件使用真实文件 I/O（systemTemp + NativePlatformStorage）
- 100+ 处 `runAsync` 执行真实文件操作
- Windows 文件系统 + 杀毒软件可能导致偶发长延迟
- 间歇性：取决于系统负载和杀毒扫描时机
- 两个 Agent 都遇到：系统级问题

**反对证据**:
- 文件操作都是小文件（JSON），通常毫秒级
- 临时目录名唯一，无跨 isolate 资源冲突
- 30s 默认超时应能捕获过长文件操作

**还缺什么证据**:
- 挂起时的磁盘 I/O 监控
- 测试输出中是否有"compiling"阶段长时间无输出

### P4 — 中低概率: Flutter Tool / frontend_server 偶发挂起 (TYPE C)

**支持证据**:
- Flutter 3.44.6 较新（约 10 周），Dart 3.12.2
- frontend_server (dartaotruntime) 负责增量编译，历史上有过挂起 bug
- 编译阶段无测试输出，表现为"长时间无新输出"
- 间歇性：编译器状态依赖缓存

**反对证据**:
- Flutter stable 渠道通常经过充分测试
- 无证据表明编译阶段挂起
- 首次编译慢是正常现象，不应被误判为挂起

**还缺什么证据**:
- 挂起时是否处于编译阶段（输出中是否有 "Compiling" 且无后续）
- flutter test --verbose 输出

### P5 — 低概率: Global State 污染 (TYPE A/B)

**支持证据**:
- 3 个 static singleton 无 reset API
- CharacterRegistryService.changes 为 static ValueNotifier
- SessionResetService._chatResetController 为 static 且永不关闭

**反对证据**:
- 每个测试文件独立 isolate，不跨文件污染
- 大多数测试创建本地实例，不使用 static singleton
- 同文件内测试间影响有限

**还缺什么证据**: 无

---

## L. 当前故障类型

**判断: TYPE B + C 混合型（B 为主，C 为辅）**

- **TYPE B（所有 test case 实际完成，但资源未释放导致进程不退出）**: 最可能。页面 Timer.periodic 在 test isolate 中残留，导致所有测试输出完成后进程无法退出，外层 Agent 超时。开发者注释直接证实了这一现象。
- **TYPE C（Flutter / Dart test runner / Windows 进程基础设施偶发挂起）**: 次要。高并发文件 I/O 和 Flutter tool 可能在特定系统状态下偶发延迟。
- **TYPE A（某个 PeiLink 测试自身永不完成）**: 存在确定性隐患（_DesktopBackground + pumpAndSettle）但当前被规避，不是当前间歇性挂起的主因。

---

## M. 推荐的最小复现与下一步验证方案

### 阶段 1: 信息采集（不运行全量测试，不抢 Codex 资源）

1. **等待 Codex 当前 flutter run 结束后**，运行单次 `flutter test --verbose > test_log.txt 2>&1`
2. 记录: 启动时间、PID、每次输出的时间戳
3. 定义"疑似挂起"阈值: **连续 3 分钟无新增 test case 输出**（正常编译阶段除外）
4. 挂起时立即:
   - `Get-Process dart,dartaotruntime | Select-Object Id,CPU,StartTime`
   - 通过 VM service 连接查看活跃 Timer（如可连接）
   - 检查 test_log.txt 最后 20 行，确认是"测试中"还是"测试完成后不退出"

### 阶段 2: 隔离验证

5. **单文件运行**: `flutter test test/ai_world_home_entry_test.dart` — 这是已知有 Timer 规避注释的文件，验证单独运行是否正常退出
6. **HomePage + pumpAndSettle 确定性验证**: 创建临时测试文件，pump HomePage 后调用 pumpAndSettle，验证是否永久挂起（确认 P2 隐患）
7. **--concurrency=1 对比**: `flutter test --concurrency=1` 全量运行，对比并发模式下是否更容易挂起
8. **二分法**: 如果全量挂起，将 test 文件分成两组分别运行，定位挂起所在组

### 阶段 3: 根因确认

9. **添加 flutter_test_config.dart**: 在全局 tearDown 中打印活跃 Timer 数量（通过 `dart:developer` 或自定义追踪），确认是否有 Timer 残留
10. **进程退出检测**: 测试脚本中添加 `flutter test ...; echo "EXIT CODE: $LASTEXITCODE"`，确认是进程不退出还是进程退出但 Agent 未检测到
11. **Windows 性能监视器**: 挂起时观察磁盘 I/O、CPU、内存，区分"有 CPU 但无进展" vs "完全无 CPU"

### 正常编译慢 vs 疑似挂起的阈值建议

| 阶段 | 正常预期 | 疑似挂起阈值 |
|------|---------|-------------|
| 首次编译（无缓存） | 1-3 分钟有 "Compiling" 输出 | 超过 5 分钟无任何输出 |
| 增量编译 | 10-30 秒 | 超过 2 分钟无输出 |
| 测试执行中 | 每 10-30 秒有新 test 结果 | **连续 3 分钟无新增 test case 输出** |
| 测试完成后 | 5 秒内输出 "All tests passed" 并退出 | 超过 30 秒无退出且无输出 → 资源未释放 |

---

## N. 是否建议修改代码

**YES** — 但本轮不实施，仅列出建议修改点：

### 建议修改点（按优先级）

1. **[P1] 创建 `test/flutter_test_config.dart`**
   - 添加全局 tearDownAll，检查并取消残留 Timer
   - 可添加 `debugPrint` 输出测试完成时间，帮助区分"测试中挂起" vs "不退出"

2. **[P1] 为所有 pump 含 Timer 页面的测试添加显式清理**
   - 在测试结束前 `tester.pumpWidget(const SizedBox())` 强制触发页面 dispose
   - 或在 `ai_world_home_entry_test.dart` 的模式基础上，统一封装一个 `pumpPageAndCleanup` 辅助函数

3. **[P2] 消除 `_DesktopBackground` 无限动画在测试中的风险**
   - 方案 A: 在 `_DesktopBackground` 中添加 `kIsWeb || !kReleaseMode` 条件判断，测试环境不启动 repeat
   - 方案 B: 将动画时长设为有限值，或使用 `repeat(reverse: true, max: 1)` 限制循环次数
   - 方案 C: 添加 `flutter_test_config.dart` 全局禁用非必要动画

4. **[P3] 为 static singleton 添加测试 reset API**
   - `PeiLinkThemeController.resetForTesting()`
   - `PeiLinkAppearanceController.resetForTesting()`
   - `CharacterRegistryService.resetChangesForTesting()`

5. **[P3] 添加 `dart_test.yaml` 设置合理的全局超时**
   - ```yaml
     timeout: 60s
     ```
   - 确保单个测试不会无限挂起（虽然 isolate 退出阶段的 hang 不受此保护）

6. **[P4] 考虑降低默认并发**
   - CI/Agent 环境中使用 `--concurrency=4` 减少资源竞争
   - 或在 dart_test.yaml 中设置 `concurrency: 4`

---

**AUDIT COMPLETE**
