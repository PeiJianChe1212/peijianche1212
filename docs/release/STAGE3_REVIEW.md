# PeiLink Pre-Release 第三阶段：Sol 独立复核

> 历史报告：下述 BLOCKED 记录保留作为发现依据。用户确认保留优先策略后，
> 阻断已修复并补齐独立空白模拟器验收；最新结论与发布准备项见
> [PRE_RELEASE_BASELINE.md](PRE_RELEASE_BASELINE.md)。不将历史失败改写为未发生。

日期：2026-09-04。结论：**PRE-RELEASE BASELINE BLOCKED**。

第二阶段的中性默认值、user 网络配置和正式 release 禁止 debug fallback 基本落地，但独立复核发现两个可局部修复的回归，以及一个尚未闭环的数据保留阻断。前两个已最小修复；后者不能用“全测试通过”掩盖。因此不生成 PRE_RELEASE_BASELINE.md，也不宣告现有版本最终封板。

## 1. 阻断：按值清洗会删除明确导入的用户资料

位置：`lib/services/character_settings_storage_service.dart` 的 loadSettings / _removeLegacyDeveloperDefaults。

该逻辑对非内置角色按值清空 userCallName、remark、relation、birthday、anniversary、introduction，并在读取时保存。它没有来源或迁移版本依据，无法区分用户主动设置与旧版误继承。

本轮使用临时目录、纯虚构 v1 .pei 做真实服务调用诊断：

1. configuration 明确设置 anniversary 为“1月17日”。
2. PeiFileService.parse 后该值存在。
3. PeiFileService.importCharacter 完成。
4. CharacterSettingsStorageService.loadSettings 后该值为空。
5. 再次 loadSettings 仍为空，证明发生持久化清洗。

诊断测试验证的是上述不正确行为确实存在，不是业务验收通过。临时测试及其临时数据已移除；没有真实用户资料参与。首次运行诊断脚本曾因测试调用名写错无法编译，修正后复现成功，最终 analyze 无问题。

这种按值清洗在基线中已有前身，并非全部由第二阶段新引入；第二阶段将完整默认对象比较改成字面量比较后仍保留了问题。现有 privacy_residual_isolation_test 甚至要求同名字段被清空，因此现有回归绿不能证明合法同值资料被保留。

全局 UserProfileStorageService 也存在同类按值清洗（user flavor），是已有逻辑，本轮只读指出，没有扩大修改。其他普通自定义资料仍按持久化资料加载；不能把这一点泛化成“所有旧角色/.pei 都不受影响”。

### 建议的最小后续处理

- 中性 defaults 和缺字段 fallback 保持不变。
- 停止在普通读取中仅凭内容等于旧默认值就覆盖用户明确保存的字段。
- 历史污染没有可靠来源标记时，应采用用户确认或可信来源限定的清理，不能猜测；具体保留/清理策略需用户与 GPT 确认。
- 补“同值但用户明确填写”“.pei 显式资料”“缺字段仍中性”的正向回归，并重新验收首次安装。

本轮不擅自改变既有历史清洗策略，不新增迁移系统，不修改 Memory2 schema。

## 2. 本轮已做的两项最小修复

### Android 原生通道恢复

第二阶段将旧 MainActivity 移到 com.peilink.app 时，只保留空 FlutterActivity，丢失 peilink/pei_file 和 peilink/external_url 通道，导致 Android 文件选择/保存与外部链接无法按原实现工作。

已在新包路径恢复 HEAD 的完整原生实现，仅修改 package 声明。逐行归一化比较确认 NATIVE_BODY_EQUALS_BASELINE=True；没有扩展原生功能或改动 .pei 协议。

### dev 初始化顺序

第二阶段把 CoreBridge 初始化移至 main_dev，但放在 runPeiLink 配置 dev 命名空间之前。这会先按 unspecified 根目录读取配置。已在初始化前增加 PeiLinkRuntime.configure(PeiLinkBuild.dev)，不修改 Physical/CoreBridge 业务算法。

新增 test/pre_release_native_boundary_test.dart：2 项静态契约回归，确认原生通道和 dev 配置顺序。静态契约测试不冒充真机文件选择器交互测试。

## 3. 第二阶段逐项核验

| 检查 | 结果 |
| --- | --- |
| CharacterSettings.defaults | 委托 genericDefaults；角色身份、关系、日期、人设、示例均为中性/空 |
| 私人 Prompt 默认文件 | character_prompt.dart / example_messages.dart 已从工作树删除，引用移除 |
| 缺字段 fallback | 使用中性默认，不重新注入私人完整人设 |
| 持久化角色资料 | 一般字段保留，但存在第 1 节同值清洗阻断 |
| user 网络配置 | APK 内 base-config cleartextTrafficPermitted=false；无 192.168.2.215 |
| dev 网络配置 | 局域网白名单仍在 dev 资源，未搬入 user |
| 正式 release signing | 明确使用 release 配置，无 debug fallback；缺配置的标准 user release 命令实际失败 |
| user 页面 | main.dart / settings_page.dart 不引用 PhysicalHostPage；dev 扩展由 main_dev 安装 |
| dev 页面 | Physical/CoreBridge/开发工具区块仍在 dev-only builder；dev debug 构建成功 |
| Physical 业务 | lib/physical 无本轮或第二阶段工作树差异；未连接硬件 |
| Android ID | user=com.peilink.app、dev=com.peilink.dev，与 HEAD 相同；namespace 改 com.peilink.app |
| MainActivity | .MainActivity 与新 Kotlin package 一致；原生功能已恢复 |
| Apple 命名 | iOS/macOS 仍有 com.example.peijiancheApp，未擅改；未在 Windows 构建验证 |
| 桌面命名 | 第二阶段已改 Windows/Linux CMake 名称，未验证安装升级行为，不等同于 Android 升级验证 |

## 4. Memory 2.0 冻结保护

EventMemory、UserMemory、MemorySummary、Lifecycle、Retriever、Extraction、Recall、Summary、Legacy migration、.pei 服务及 Memory Diagnostics 实现没有工作树业务差异。Settings 的 dev-only 注入属于入口隔离，不改变记忆算法。

30/60/90、7.5 query expansion、最终注入 Recall、v1/v2 Memory 规则保持原基线。此次 Android 通道恢复保障 .pei 到平台的接线，不改其载荷或校验。Memory2 既有 Final RC 状态不被本次应用级 BLOCKED 否定。

## 5. user APK 静态反查

实测构建：user debug、dev debug 均成功。user 产物为 `build/app/outputs/flutter-apk/app-user-debug.apk`，不是正式 release 签名包。

扫描产物 SHA256：`EEF86184BAA42745FD53B515069CCD1C1B902DD6A60E06B758C81E10B0129B3D`。

包信息：com.peilink.app，versionName=0.6.7，versionCode=17，minSdk=24，targetSdk=36。APK XML 反查证实 user cleartext=false。

扫描 ZIP 内各文件的 UTF-8 / UTF-16 文本命中，不输出周边原始正文：

| 关键词 | 命中分类 |
| --- | --- |
| 林念念 | 未命中 |
| 念念 / 一只小狐念 / 裴简澈 / 老裴 | kernel_blob.bin；源码仍有旧数据清洗、Legacy 分类归一化及回复前缀兼容字面量，非中性默认主动填入；清洗行为风险见阻断项 |
| PeiJianChe / JianChe | kernel_blob.bin；本地用户名/调试源路径类信息，lib 源码没有对应业务文本命中 |
| 192.168.2.215 / ESP32 / PhysicalHostPage | 未命中 |
| Memory Diagnostics | 未命中 |
| Prompt Test | kernel_blob.bin；DeepSeekService 中 Legacy Prompt Test 标记，不是开发设置页入口证明 |
| RC9 Companion / DEEPSEEK_API_KEY | 未命中 |
| G:\Development\PeiLink | 指定反斜线形式未命中；不能据此宣称没有其他形式路径 |
| C:\Users\ | Flutter engine、isolate snapshot、kernel 调试/构建路径；不是用户资料正文 |

该扫描不是全二进制取证，也不能替代最终 AOT release 产物扫描。当前 debug 产物未包含 PhysicalHostPage 的字符串，结合 import 隔离可支持入口移除；不宣称所有带 Physical 名称的抽象类型或所有开发信息绝对不在最终包中。正式签名/AOT 包仍须发布前独立复查。

## 6. 首次安装 / 空白状态

源码追踪：user 入口先配置 peilink_user；新 registry 写空列表；UserProfile 初始中性；开发环境受 runtime 门控；user 不安装开发设置区块。现有空目录 widget/隔离回归确认无角色、可见创建入口、空 Echo/Life 状态，不自动注入私人或 RC9 数据。

本轮未做 Android 模拟器真实首次安装。ADB 查询没有在线设备；发现数据保留阻断后没有启动模拟器或触碰既有安装数据。因此本轮证据等级是源码、空目录/widget 验证和 APK 构建，不是完整设备首次安装验收。该验收仍待阻断修复后补齐，不能写成已完成。

## 7. 回归及限制

最终全安全离线回归：**107 个测试文件、616 项通过，0 失败**，退出码 0。新增 2 项已包含在总数中；临时缺陷诊断不计入 616。

覆盖现有 Memory2 全专项、Context Builder/Prompt Composer、Character/Profile/UserProfile、.pei、Legacy、清理/重置、群聊、Echo 发布/评论/点赞、红包、冷静期和其他现有离线回归。只证明现有测试覆盖范围，不声称每个旧功能都完成设备端全流程；消息撤回/主动消息等没有为本轮额外造验收测试。

唯一整文件排除：test/physical_release_isolation_test.dart（历史 FakeAsync/文件 I/O 挂起边界，本轮未重跑、未删、未弱化；第二阶段仅添加了 dev registry 安装接线）。其他 Physical fake/mock 随全量通过。

flutter analyze --no-pub：No issues found，退出码 0。git diff --check 通过。构建有 Android SDK XML 工具版本警告，不影响本次 debug 构建，但正式构建环境需锁定工具版本。

真实 Provider 请求 0，语音 Provider 0，ESP32 连接 0；没有使用真实用户隐私。

## 8. release signing 结论与准备

标准发布脚本固定 user + lib/main.dart + release。实际执行该命令在缺少配置时于 Gradle 明确失败，未静默生成 debug-signed release。当前只是发布结构验证，不是正式可分发产物。

正式公测前：由负责人准备正式密钥及签名策略、配置安全构建环境、验证实际签名证书指纹、提升 versionCode、复查最终 AOT 包并完成安装/升级验收。本轮未创建 keystore。

密钥保存在仓库外、权限受控的加密存储，留离线加密备份并验证恢复；密码由密码管理器或 CI secret 注入，不放源码、脚本正文、命令行日志。当前 .gitignore 排除 key.properties/*.jks/*.keystore，已跟踪文件列表没有这些密钥文件；忽略规则不等于完整历史 secret 审计，本轮不做历史扫描。

Android 升级不仅看 applicationId，还校验签名：包名保持不变并不保证旧 debug 签名安装可被新正式签名覆盖。必须确认已分发版本签名，不能用新 key 承诺无缝升级；若尚无正式分发，应从首次公测固定正式签名，持续使用同一受管身份。Google Play 场景应区分 app signing key 与 upload key，并按平台签名流程维护。[Android 官方签名说明](https://developer.android.com/studio/publish/app-signing)

## 9. 工作树分类

开始时 main...origin/main，有 20 个 tracked 差异；134 插入/462 删除，不是本轮创造。结束 tracked diff 为 135 插入/462 删除（多出 dev 配置一行）；未跟踪文件不计入 git diff --stat。

- A 第二阶段：.gitignore、Android Gradle/manifest/network/包路径、main/main_dev/settings registry/dev_only、中性 CharacterSettings/旧 Prompt 删除/storage 清洗、Windows/Linux CMake，以及相应旧测试调整、release 新测试和 scripts。
- B 已有 Memory2 封板：docs/memory2 两份文档及 memory_final_closure 两份测试，本轮未改；核心实现已在 HEAD。
- C Physical：核心业务无工作树改动；physical_release_isolation_test 的 8 行接线修改是开始时已有第二阶段差异，未回滚。
- D 本轮：恢复新路径 MainActivity、main_dev 增加 configure、新增 pre_release_native_boundary_test.dart，以及本报告。
- E 构建生成 android/build/reports/problems/problems-report.html：确认本轮新增后仅移除此单文件，可重新构建生成。临时诊断测试也已移除；未删除旧逻辑或用户文件。无其他意外差异。

没有 reset/clean/checkout、历史重写、commit/push。没有修改 Memory2 或 Physical 核心算法。

## 10. 停止与待确认

暂不生成通过状态的 PRE_RELEASE_BASELINE.md。需要先决定并修复第 1 节“按内容猜测来源并持久化清洗”的策略，再补设备首次安装和最终签名产物验收。此处停止，不开始 UI 美化、新功能、正式 keystore 生成或 APK 发布。
