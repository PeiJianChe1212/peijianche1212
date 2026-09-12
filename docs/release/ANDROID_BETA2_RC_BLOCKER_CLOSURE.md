# PeiLink Android Beta2 RC Blocker Closure

日期：2026-09-10。只处理本轮授权的原生存储竞争、四个旧测试契约、Physical 测试生命周期和 analyze 快照污染。未进入 Final Audit 2，未处理签名/版本号，也未构建 APK。

## A. Storage race 是否修复

固定 `<target>.tmp` 的竞争已修复。原 `replaceTextSafely` 共享临时文件，多次 registry 初始化可以互相移动/删除相同文件。原 `writeText/writeBytes` 是直接写目标；现在三者都走同一个完整暂存后 rename 的私有实现，没有直接覆盖目标的退化。

定向回归进一步复现 Windows errno 5/32 的短暂文件句柄冲突：唯一 tmp 并不能单独解决 rename 或 read 被另一个操作占用的问题。最终实现对原生读取和 rename 的 Windows 5/32/33 错误最多重试 5 次，延迟总和 310ms；不会先删除目标。其他错误立即抛出，持续权限错误最终仍抛出。

这是完整值替换，不是多个业务读改写操作的事务锁；不承诺并发修改会合并，最后完成的替换决定最终值。本轮没有重构 registry、Memory 或其他业务层。

## B. 唯一 tmp 策略

同目标目录中的 `<target>.<pid>.<counter>.<128-bit random>.tmp`。counter 区分当前 isolate 的重叠操作，安全随机后缀区分不同 isolate/进程。临时文件在目标同目录、同卷；写入 flush 完成再 rename。finally 只清理本次创建的临时路径，不清理其他 tmp、不删除目标。

rename 失败时保留原异常；清理因权限或目录已被删除而失败时不覆盖原异常。不能承诺操作系统拒绝删除时仍绝无残留，也没有增加启动时扫描/清理旧数据的逻辑。

recursive delete 的既有语义不变：显式删除目录会删除其中的 target/tmp，其他目录不受影响。它与进行中的写入没有增加事务排序；若目录被删除，操作允许失败。新实现不会为了 rename 重建已经被删的目录。并发测试的读写两支均等待完成后再删除测试目录，避免测试自身制造 teardown 竞争。

## C. 并发测试

`test/native_platform_storage_concurrency_test.dart`：**6 passed / 0 failed / 0 skipped**，最终单独运行和最终 Beta2 定向运行均通过。

覆盖：

1. 新文件、已有文件、文本/bytes/安全替换的完整读回。
2. 两个存储实例并发写同一目标，文件系统事件记录两份不同的同目录 tmp，最终为一次完整结果、无 tmp 残留。
3. 12 次并发替换与 20 次读取，读到的都是完整旧值或完整新值。
4. 以目录阻挡目标制造 rename 失败，保留目标内原内容及另一 writer 的临时文件，只清理自身 tmp。
5. 20 次并发初始化空 CharacterRegistry，不发生 tmp rename collision。
6. recursive delete 清除限定目录内的暂存文件，保留兄弟目录。

实际平台：Windows 本机。Android 共用 dart:io 原生实现，但 Windows sharing retry 分支不会在 Android 执行；本轮未做 Android 真机文件系统压力测试。Web 仍由 conditional import 选择 IndexedDB 的 `_put` 事务实现，没有改动 Web。

## D. 四个旧测试契约

生产 Group G3.1/G2 未修改。三项 transcript 测试改为检查实际稳定标签 `q(q)`、`a(a)`、`b(b)`、`乙(char_b)`，保留用户/系统正文断言，并增加角色正文不能以“用户：”标记的否定断言。

成员管理测试改为检查 4 个 GroupMemberChoice（固定用户 + 3 AI）：用户 selected/locked/onTap=null、点击不可取消；AI 可以取消/重新选中；仅 1 AI 时“完成”禁用、恢复 2 AI 后启用，保存后确实保留 2 AI。未删除或跳过原测试。

最终定向结果：group_chat_context 4/4，group_chat_g33_voice 10/10，group_chat_g2 7/7。此前失败的 group_chat_g1 也为 6/6。

## E. Physical 挂起根因

测试在 widget test 的 fake async 区域直接 await `DeveloperEnvironmentService.setEnabled`，该方法经 path_provider 后进行真实目录/文件 I/O；测试可在首次 pumpWidget 前停住。原 pumpAndSettle 也不能替代对真实 I/O 完成的等待，页面导航后还有 settings/registry 异步读取及加载指示器。

测试侧把配置 I/O 放入 tester.runAsync，使用有限次数的真实事件循环等待与 pump；配置 FlutterSecureStorage 的空内存 mock，避免依赖真实插件；加载完成后检查实际 Physical 配置正文和无加载指示器，末尾卸载 widget，使 controller/listener 正常 dispose。没有改 PhysicalHostPage、runtime、开发开关、权限分支或产品 Timer/stream。

## F. Physical 测试是否完成

**三项均能结束；2 passed / 1 failed / 0 skipped，不是全绿。**

- dev + developer enabled：进入 Physical，实际配置内容加载完成，通过。
- dev + developer disabled：隐藏 Physical，通过。
- user：失败原因是 `ListTile background color or ink splashes may be invisible`，设置页 ListTile 被有背景色的 DecoratedBox 隔开。最终日志中在切换页面后的 flushIo 捕获，user 路径未完整通过。

这条既有 UI 诊断在上一轮审计日志中也出现过。它不是“user 打开了 Physical”的证据；本轮没有打开 user 开发权限。但不能因为诊断与权限无关就吞掉它、删除断言或报告通过。它不是挂起，属于尚未解决的测试/UI 诊断；本轮不修改禁止范围内的页面来清零。

## G. Analyze 污染

analysis_options.yaml 仅增加 `build/visual_polish_before/**` 精确排除。快照、日志、预览图均保留，lib/test 不排除，lint 规则不改变。

最终全项目 `flutter analyze --no-pub`：**0 error / 1 warning / 3 info**，不再有快照带来的 137 error。非零退出来自保留的诊断：

- memory2_storage_service.dart:290、298：历史 if 花括号 info。
- group_chat_create_flow_test.dart:13：注释尖括号 info。
- 同测试 :75：未使用 helper warning。

`git diff --check` 通过。

## H. 本轮修改文件

- lib/platform/storage/native_platform_storage.dart
- analysis_options.yaml
- test/native_platform_storage_concurrency_test.dart（新增）
- test/group_chat_context_test.dart
- test/group_chat_g33_voice_test.dart
- test/group_chat_g2_test.dart
- test/physical_release_isolation_test.dart
- docs/release/ANDROID_BETA2_RC_BLOCKER_CLOSURE.md（本报告）

其他既有 Beta2 未提交文件保留。本轮证据在 build/closure_*：storage_final、targeted_final、analyze_final、diff_check；早期失败日志保留，不冒充最终结果。

## I. Schema/storage 是否变化

JSON/schema/最终 target path/logical key/namespace/storage root 均未变，无 migration。仅原生物理读写策略与临时文件名变化；旧数据无需转换。Web 无变更。

## J. 剩余代码级 Release Blocker

固定 tmp 和已复现的 Windows 读写锁竞争已通过新增回归；四个旧契约已同步，Physical 无限等待已解除。本轮没有发现新的确定性数据格式/权限隔离阻断。

但 **不能宣布全部代码验证门禁关闭**：Physical user 的既有 ListTile 诊断仍失败。该项需要后续明确处理范围或由发布负责人判断其非阻断性质，不能在本轮默认为通过。

最终 Beta2 定向套件：**487 passed / 1 failed / 0 skipped**，有正常 done 事件，约 38 秒完成，无挂起。失败仅上面的 Physical user 项。没有执行 full suite、Final Audit 2、debug/release 构建或设备验收。

## K. 用户动作/外部证据 blocker

仍需实际 Beta1 APK/证书及 versionCode 证据、恢复 Beta1 同一正式签名环境，后续确认 Beta2 code 严格递增，再做独立 Final Audit 2 与真机覆盖升级。均未在本轮猜测、改写或绕过。

自动审批曾拒绝一个“替换重复断言并运行 analyze”的组合操作，理由是可能削弱集成覆盖。该操作未执行；保留原断言后单独运行 analyze，未绕过审批。

本轮停止，不开展签名、版本变更或后续功能。
