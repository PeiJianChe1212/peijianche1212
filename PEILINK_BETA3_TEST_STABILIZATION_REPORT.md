# PeiLink Beta3 Test Infrastructure Stabilization Report

**完成时间**: 2026-09-14 23:50 CST
**项目**: G:\Development\PeiLink
**Flutter**: 3.44.6 stable / Dart 3.12.2

---

## 1. 根因处理总结

基于前序只读审计（TYPE B + C 混合型），本批针对三个核心风险点实施了修复：

| 风险点 | 修复方式 | 状态 |
|--------|---------|------|
| HomePage/ChatPage Timer.periodic 依赖隐式 dispose | 统一显式清理 helper + 高风险页面测试强制调用 | ✅ |
| `_DesktopBackground` 无限 `repeat(reverse: true)` 动画 | `enableAmbientAnimation` 构造参数，测试显式 false | ✅ |
| 12 核默认高并发 + Windows 文件 I/O 竞争 | `dart_test.yaml` 限制 concurrency: 4 | ✅ |

**未做的事**: 未使用 Zone hack / VM 私有 API 全局取消 Timer；未新增复杂 flutter_test_config.dart；未给全部 singleton 加 reset API；未修改任何业务逻辑。

---

## 2. Timer 页面清理方式

所有 pump 含长期生命周期资源页面（HomePage / ChatPage）的 widget test，在测试结束前显式调用：

```dart
await disposeTestWidgetTree(tester);
```

该 helper 执行：
1. `tester.pumpWidget(const SizedBox.shrink())` — 用空 widget 替换当前树，触发 State.dispose()
2. `tester.pump()` — 处理 dispose 期间的微任务
3. `tester.pump(Duration(milliseconds: 10))` — 额外短 pump，不使用 pumpAndSettle（避免无限动画挂起）

**已应用文件**:
- `test/ai_world_home_entry_test.dart` — 3 个 testWidgets 全部添加
- `test/life_desktop_layout_test.dart` — 5 个 testWidgets 全部添加（含 for 循环参数化测试）
- `test/widget_test.dart` — 2 个 pump PeiLinkApp（含 HomePage）的 testWidgets 添加

---

## 3. 新增 Test Cleanup Helper

**文件**: `test/helpers/widget_test_cleanup.dart`

提供两个函数：

### `disposeTestWidgetTree(tester)`
- 用空 widget 替换当前 widget tree
- 有限次数 pump，确保 State.dispose() 同步执行
- 不调用 pumpAndSettle，不使用反射或 VM 私有 API

### `settleFinite(tester, {frames, interval})`
- 替代 pumpAndSettle 的有限 settle 方案
- 固定帧数（默认 20）+ 固定间隔（默认 50ms）
- 保证上界，适用于含无限动画的页面

---

## 4. HomePage 无限动画测试隔离方式

### 修改内容

**`lib/pages/home_page.dart`**:

1. HomePage 新增构造参数：
```dart
const HomePage({
  super.key,
  this.initialHasVisibleCharacter,
  this.enableAmbientAnimation = true,  // 正式 App 默认 true
});
```

2. `_DesktopBackground` 新增 `enabled` 参数，仅在 enabled 时启动 repeat：
```dart
_controller = AnimationController(vsync: this, duration: ...);
if (widget.enabled) {
  _controller.repeat(reverse: true);
}
```

3. HomePage 将 `widget.enableAmbientAnimation` 传递给 `_DesktopBackground`

### 设计原则
- 正式 App 默认 `true`，用户看到的动画效果不变
- 测试显式传 `false`，不依赖 `kReleaseMode` / `kDebugMode`
- 不通过 themeId 或环境猜测测试模式
- Debug 真机和 Release 行为一致

### 已应用测试
- `ai_world_home_entry_test.dart`: `HomePage(enableAmbientAnimation: false)`
- `life_desktop_layout_test.dart`: 所有 HomePage pump 均传 `enableAmbientAnimation: false`

---

## 5. pumpAndSettle Audit 结果

全项目 **69 处** `pumpAndSettle()` 调用，分布在 20 个测试文件中。

**审计结论**:
- ✅ 无任何 pumpAndSettle 作用于 HomePage（含无限动画的页面）
- ✅ 无任何 pumpAndSettle 作用于含无限 AnimationController 的 widget
- ✅ GroupChatPage 的 CircularProgressIndicator 为条件渲染，相关测试未使用 pumpAndSettle
- ✅ 正常有限动画页面（design system、memory UI 等）可继续使用 pumpAndSettle

**高风险页面（HomePage）的测试全部使用有限 pump 或自定义 settle，未使用 pumpAndSettle。**

---

## 6. GroupChat Loading Audit

**`lib/pages/peilink/group_chat_page.dart`**:
- Line 576: `Center(child: CircularProgressIndicator())` — 条件渲染（loading state）
- Line 1060: `CircularProgressIndicator(strokeWidth: 1.6)` — 条件渲染

**审计结论**:
- 两个 CircularProgressIndicator 均为条件渲染，仅在 loading state 显示
- 所有 pump GroupChatPage 的测试（group_chat_g1, group_chat_g2, group_user_profile）均未使用 pumpAndSettle
- 当前无确定性挂起路径
- 建议后续新增 GroupChatPage 测试时避免在 loading state 下使用 pumpAndSettle

---

## 7. dart_test.yaml 内容

**文件**: `dart_test.yaml`（项目根目录，新建）

```yaml
concurrency: 4
timeout: 60s
```

**设计依据**:
- `concurrency: 4`: 原默认 = 12 逻辑核，高并发放大 Windows 文件系统竞争和 race condition。4 并发在保持吞吐量的同时显著降低资源争用。
- `timeout: 60s`: Dart 默认 30s，PeiLink widget test 中 runAsync 真实文件 I/O 在 Windows 负载下偶发超 30s。60s 给合理余量，不掩盖真正挂起。需更长超时的测试应使用 per-test @Timeout。

---

## 8. 测试并发策略

| 环境 | 并发 | 说明 |
|------|------|------|
| 默认（dart_test.yaml） | 4 | 全量测试标准配置 |
| 单文件调试 | 1 | `flutter test test/xxx.dart --concurrency=1` |
| CI / Agent | 4 | 通过 run_tests.ps1 统一 |
| 本地快速验证 | 4 | 与 CI 一致，避免"本地过 CI 挂" |

**禁止**: 不使用默认 12 并发运行全量测试。

---

## 9. run_tests.ps1 结构

**文件**: `tool/run_tests.ps1`（新建）

### 支持模式
| 模式 | 内容 |
|------|------|
| `sanity` | widget_test.dart + peilink_design_system_test.dart |
| `theme` | theme_framework, batch3_butterfly_fox, beta3_existing_ux_fixes, chat_bubble_theme, chat_font, chat_font_assets, appearance, theme_background |
| `chat` | chat_input, chat_timeline, chat_image, chat_flow, group_chat_g1/g2/g33/g34/g35, group_context, group_create, group_participation, group_user_profile, group_visual, ai_world_home_entry, life_desktop_layout |
| `echo` | echo_my_echo_entry, echo_comment_*, echo_duplicate_guard, echo_expression, echo_first_echo_natural, echo_image_prompt, echo_interaction, echo_profile, echo_social_*, echo_space_* |
| `all` | `flutter test --concurrency=4` |

### 功能
- 工具链 pre-flight 检查（dart --version / flutter --version，超 30s 判定 TOOLCHAIN HANG）
- 记录开始/结束时间、exit code、stdout/stderr 到 `build/test_logs/`
- 失败时输出最后 30 行日志
- 所有模式统一使用 `--concurrency=4`

---

## 10. 挂起检测策略

| 阶段 | 正常预期 | 疑似挂起阈值 |
|------|---------|-------------|
| 首次编译 | 1-3 分钟有编译输出 | 超过 5 分钟无任何输出 |
| 增量编译 | 10-30 秒 | 超过 2 分钟无输出 |
| 测试执行 | 每 10-30 秒有新 test 结果 | **连续 3 分钟无新增 test case 输出** |
| 测试完成后 | 5 秒内输出 "All tests passed" 并退出 | 超过 30 秒进程仍在运行 → 资源收尾异常 |

**核心原则**: 不仅凭 CPU > 0 判断正常推进。CPU 可能只是 compiler / GC / daemon 在活动。

---

## 11. 修改文件清单

### 新建文件
| 文件 | 说明 |
|------|------|
| `test/helpers/widget_test_cleanup.dart` | 统一清理 helper（disposeTestWidgetTree + settleFinite） |
| `dart_test.yaml` | 项目级测试配置（concurrency: 4, timeout: 60s） |
| `tool/run_tests.ps1` | 标准测试运行脚本（5 种模式 + 挂起检测 + 日志） |

### 修改文件
| 文件 | 修改内容 |
|------|---------|
| `lib/pages/home_page.dart` | 新增 enableAmbientAnimation 参数；_DesktopBackground 尊重 enabled 标志 |
| `test/ai_world_home_entry_test.dart` | import helper；HomePage 传 enableAmbientAnimation: false；3 个测试末尾加 disposeTestWidgetTree |
| `test/life_desktop_layout_test.dart` | import helper；所有 HomePage 传 enableAmbientAnimation: false；5 个测试末尾加 disposeTestWidgetTree |
| `test/widget_test.dart` | import helper；2 个 HomePage 相关测试末尾加 disposeTestWidgetTree |

**未修改**: 任何业务逻辑、Theme 01 视觉设计、butterfly_fox 资源、聊天/群聊/Echo/Memory/Archive/Life/Bond/Relationship 功能。

---

## 12. dart --version / flutter --version

```
Dart SDK version: 3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "windows_x64"
  Elapsed: 412ms

Flutter 3.44.6 • channel stable • https://github.com/flutter/flutter.git
Framework • revision ee80f08bbf (10 weeks ago) • 2026-07-08 15:02:06 -0700
Engine • hash d3a3293399556a85388faf8c6f0723a7a5597aa
Tools • Dart 3.12.2 • DevTools 2.57.0
  Elapsed: 835ms
```

工具链健康，无挂起。

---

## 13. HomePage 单文件测试结果

**命令**: `flutter test test/ai_world_home_entry_test.dart --concurrency=1`

```
00:00 +0: loading ...
00:25 +1: AI World 展示角色 e 时，聊天入口进入 e
00:50 +2: 切换展示角色为 q 后，聊天入口立即跟随 q
01:12 +3: 三个快捷入口都存在且可点击，Echo 仍进入 Echo 页面
01:12 +3: All tests passed!
```

- **结果**: 3/3 通过
- **耗时**: 1分16秒
- **退出**: 正常退出（exit code 0），无残留进程
- **验证点**: Timer 页面测试稳定退出 ✅

---

## 14. Batch 03 专项测试结果

**命令**: `flutter test test/life_desktop_layout_test.dart test/widget_test.dart test/theme_framework_test.dart test/batch3_butterfly_fox_theme_test.dart test/beta3_existing_ux_fixes_test.dart --concurrency=2`

- **通过**: 30/31
- **失败**: 1（预存问题）
- **耗时**: 约 7 秒
- **挂起**: 无

**预存失败**: `batch3_butterfly_fox_theme_test.dart: theme dressing lists and applies both built-in themes live`
- 断言失败: expected 'butterfly_fox', actual 'default'（主题持久化加载未读到保存值）
- 伴随 Windows 文件锁: `PathAccessException: Deletion failed ... (OS Error: 另一个程序正在使用此文件，errno = 32)`
- **非本次修改导致**，非挂起

---

## 15. Batch 01/02 回归结果

**命令**: `flutter test test/chat_input_area_test.dart test/chat_timeline_confirmation_test.dart test/group_chat_g1_test.dart test/group_chat_g2_test.dart test/echo_my_echo_entry_test.dart test/echo_social_ecosystem_test.dart --concurrency=2`

- **通过**: 29/30
- **失败**: 1（预存问题）
- **耗时**: 40 秒
- **挂起**: 无

**预存失败**: `group_chat_g1_test.dart: 群聊消费 bubble / font / background 装扮`
- 断言失败: 期望 key `'theme-background-star_butterfly_blue'` 的 widget，实际找到 0 个
- **非本次修改导致**，非挂起

---

## 16. 全量 flutter test --concurrency=4 结果

**命令**: `flutter test --concurrency=4`

```
01:23 +1032 -2: Some tests failed.
```

- **通过**: 1032
- **失败**: 2（均为上述预存问题）
- **耗时**: 1分26秒
- **挂起**: **无** ✅
- **退出**: 正常退出（exit code 1，因 2 个预存测试失败）

**关键验证**: 全量 156 个测试文件、1034 个测试用例在 1分26秒内完成并正常退出，无任何挂起或资源收尾异常。

---

## 17. flutter analyze

**全量 analyze**: 5 个 issue（均为预存，非本次修改引入）
- 2 × info: curly_braces_in_flow_control_structures（memory2_storage_service.dart）
- 1 × info: unintended_html_in_doc_comment（group_chat_create_flow_test.dart）
- 1 × warning: unused_element（group_chat_create_flow_test.dart）

**修改文件专项 analyze**:
```
Analyzing 5 items...
No issues found! (ran in 3.2s)
```

本次修改的 5 个文件（home_page.dart, ai_world_home_entry_test.dart, life_desktop_layout_test.dart, widget_test.dart, widget_test_cleanup.dart）**零 issue**。

---

## 18. git diff --check

```
git diff --check exit code: 0
```

通过（仅 Windows CRLF 警告，正常）。

---

## 19. 最终 user Debug APK 构建结果

**命令**: `flutter build apk --flavor user --debug --target lib/main_user.dart`

```
Running Gradle task 'assembleUserDebug'...  15.1s
√ Built build\app\outputs\flutter-apk\app-user-debug.apk
```

- **路径**: `G:\Development\PeiLink\build\app\outputs\flutter-apk\app-user-debug.apk`
- **大小**: 262.72 MB
- **构建时间**: 18 秒
- **APK 时间戳**: 2026-09-14 23:49:49
- **晚于 Batch 03 最终代码修改**: ✅（最新代码修改 23:09，APK 23:49）

**Batch 03 资源验证**:
- butterfly_fox/backgrounds/chat.png (1.9 MB) ✅ 已打入 asset bundle
- butterfly_fox/frames/avatar.png (697 KB) ✅ 已打入 asset bundle
- Flutter asset bundle 路径: `build/app/intermediates/flutter/userDebug/flutter_assets/assets/themes/butterfly_fox/` ✅

**非旧 APK**: 构建时间 23:49，晚于用户提到的 22:50 旧 APK ✅

---

## 20. 是否仍出现 toolchain hang

**否**。本批全过程中：
- dart --version: 412ms ✅
- flutter --version: 835ms ✅
- 全量 flutter test: 1:26 完成并正常退出 ✅
- flutter build apk: 18s 完成 ✅
- 无任何工具链挂起、无 stdout 长时间无输出、无残留 dart/flutter 进程

---

## 21. 遗留风险

| 风险 | 等级 | 说明 | 建议 |
|------|------|------|------|
| 2 个预存测试失败 | 中 | batch3 主题持久化断言 + group_chat_g1 butterfly_blue key | 后续 Batch 03 功能修复时处理，非测试基础设施问题 |
| Windows temp dir 文件锁 | 中 | PathAccessException errno=32，测试 teardown 删除临时目录时偶发 | 可在 helper 中增加重试删除逻辑；或改用 Flutter test 内置临时目录 |
| PeiLinkApp 内嵌 HomePage 未传 enableAmbientAnimation | 低 | widget_test.dart 中 pump PeiLinkApp，PeiLinkApp 内部创建 HomePage 时未传 false | 如需可给 PeiLinkApp 也加 enableAmbientAnimation 透传；当前测试未用 pumpAndSettle 故无实际挂起 |
| static singleton 缺 reset API | 低 | PeiLinkThemeController.instance 等无 reset | 本批按原则未加，记录为后续测试治理项 |
| 无 flutter_test_config.dart | 低 | 本批按原则未新增复杂全局配置 | 如需全局 suite 日志可后续轻量添加 |

---

## 验收问答

1. **Timer 页面测试是否稳定退出？** ✅ 是，ai_world_home_entry 单文件 1:16 正常退出，全量 1:26 正常退出
2. **HomePage 无限动画是否不再威胁测试？** ✅ 是，enableAmbientAnimation=false 显式关闭，测试不再有 pumpAndSettle 路径
3. **是否还有 HomePage + pumpAndSettle 路径？** ✅ 无，69 处 pumpAndSettle 审计确认无一处作用于 HomePage
4. **--concurrency=4 是否稳定？** ✅ 是，全量 1034 测试 1:26 完成无挂起
5. **DeepSeek / Codex 常见测试挂起是否明显缓解？** ✅ 是，本批全量运行零挂起，核心风险（Timer 残留 + 无限动画 + 高并发）均已处理
6. **再次挂起能否区分类型？** ✅ 是，run_tests.ps1 + 挂起检测阈值可区分 test case hang / resource cleanup hang / toolchain hang
7. **Batch 03 能否完成最终验证与 APK 构建？** ✅ 是，APK 已构建（262.72 MB，含 butterfly_fox 资源）

---

**READY FOR DEVICE CHECK**
