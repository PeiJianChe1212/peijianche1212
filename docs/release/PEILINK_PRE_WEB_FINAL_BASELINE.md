# PeiLink Pre-Web Final Baseline

**PEILINK PRE-WEB BASELINE PASS WITH KNOWN LIMITATIONS**

冻结日期：2026-09-04（Asia/Shanghai）。版本：`0.6.7+17`，Android versionName `0.6.7`、versionCode `17`。这是 Android / Flutter 既有功能的源码与功能基线冻结，不是正式发布完成。

## 范围与既有依据

本轮验收现有角色、Profile、聊天、Memory、Echo、群聊、红包、Life、`.pei`、user/dev 隔离及 Physical 离线能力。没有开发功能、调整 UI、修改生产代码或重新设计 Memory。

- [Memory 2.0.1 Final RC](../memory2/MEMORY_2_0_1_FINAL_RC.md)：沿用 PASS WITH KNOWN LIMITATIONS，47 个文件 / 363 项通过及真实 E/F、来源回溯与缺失降级证据。本轮未再次调用 Provider。
- [Pre-Release Baseline](PRE_RELEASE_BASELINE.md)：沿用既有发布隔离与中性默认值基线；本轮重新构建和验收。
- 独立 DeepSeek 审计：沿用用户提供的 `AUDIT PASS WITH FINDINGS`、Android user 必须修复项为 0 的结论。仓库未找到独立审计原报告，不能将其表述为本轮重新执行的全仓独立审计。本轮最新 AOT 复核与该结论一致，未发现需停止的差异。

## 最终安全回归与静态检查

| 项目 | 本轮结果 |
| --- | --- |
| Flutter 安全可执行完整测试集 | 113 个测试文件，727 项通过，0 失败；JSON reporter 最终 success=true |
| 明确排除 | `test/physical_release_isolation_test.dart`，沿用历史 FakeAsync / 文件 I/O 挂起记录；本轮未重新复现，未修改、删除或弱化 |
| 其他 Physical fake/mock | `test/physical/` 相关测试及 CoreBridge 回归通过，未调用真实设备、ASR 或 TTS |
| `flutter analyze --no-pub` | No issues found（2.6 秒） |
| `git diff --check` | 通过；LF/CRLF 转换提示仅为 Git 换行提示，不是 whitespace error |

测试选择为 `rg --files test -g '*_test.dart'` 后仅排除上述单一文件，使用 `flutter test --no-pub` 和 JSON reporter。没有写成“全部测试无排除通过”。覆盖 Memory 2.0/2.0.1、Explicit Remember、Extraction、Event/User/Summary、Lifecycle 30/60/90、Retriever、current/historical recall、Source、Reprocessing、Content Boundary、Legacy、`.pei v1/v2`、Context/Prompt、CharacterSettings、UserProfile、CharacterUserProfile、Memory Center、Chat、Echo、群聊、红包、Life、CoreBridge、Physical mock、发布隔离、隐私默认值和持久化保护。

## Android 构建与身份

以下构建均使用当前工作树、`--no-pub --target-platform android-x64`；产物目录为 `build/app/outputs/flutter-apk/`。

| 产物 | 身份 / 名称 | 结果与用途 |
| --- | --- | --- |
| `app-user-profile.apk` | `com.peilink.app` / PeiLink | 成功；本轮最新 user profile AOT，扫描对象 |
| `app-user-debug.apk` | `com.peilink.app` / PeiLink | 成功；全新独立模拟器的实际 UI 验收安装包 |
| `app-dev-debug.apk` | `com.peilink.dev` / PeiLink Dev | 成功；开发 flavor 保留 |
| 标准 user release | `com.peilink.app` | 预期失败：缺少正式签名配置，明确禁止 debug fallback |

三份成功 APK 均通过 aapt 核验 versionName `0.6.7`、versionCode `17`。profile ZIP 中存在 `lib/x86_64/libapp.so`，不存在 `kernel_blob`，确认为 Dart AOT。原生插件可能包含其他 ABI；本轮不声称完成其他 ABI 的 Dart 构建与设备验收。profile/debug 均不冒充正式发布包。

| APK | SHA-256 |
| --- | --- |
| user profile | `44BA211DA3FC28B0C8E2CD7F2F93C8FA487C2FE2907BE256B2E9E24677867FE9` |
| user debug | `FDFFE2CC72538B6C2C9F92A7BCD16E62C35ACBE6D2D7DB4FB885E5426C0327AB` |
| dev debug | `69581B0ADC73C071905D610FA7E73BAE868C6640F91C0A311B1E5551A9870CF0` |

只读核验 Gradle：请求 release 且无正式签名时直接失败；没有退回 debug 签名。本轮未创建 `.jks`、`.keystore`、`key.properties`、密码或签名身份。

## 最新 user AOT 残留与隐私复核

方法：对 APK 的全部 ZIP 条目搜索指定字面量的 UTF-8 / UTF-16LE / UTF-16BE 编码，并结合所在文件、符号和源码解释命中；补充长 token、Bearer 凭据、私钥头与常见 key 形态检查。下表 F 包含非秘密的 UI / 协议文字和第三方符号，不能把字面量出现等同于凭据泄漏。没有输出 Secret 正文。

| 检查项 | 结果 / 命中分类 | 依据 |
| --- | --- | --- |
| 林念念、一只小狐念、老裴 | 未命中 | 全部 APK 条目扫描 |
| 念念 | B：Legacy 兼容 | libapp.so 内唯一 UTF-16LE 命中为旧分类“关于念念”，用于归一化为“关于我” |
| 裴简澈 | B：兼容字面量 | 两个 UTF-16LE 命中为带全角/半角冒号的回复前缀清理文字，不是角色资料注入 |
| PeiJianChe、JianChe | E：本机构建路径 | 各 138 个 UTF-8 命中，全部属于 Pub/Cache 的 file URI，不是用户 Profile |
| pei_jian_che | B：开发角色 ID 兼容过滤 | 单个 UTF-8 命中；注册表非 dev 过滤机制使用，空白 user 未生成该角色 |
| 192.168.2.215、ESP32、PhysicalHostPage | 未命中 | 未进入本轮 user AOT APK |
| Memory Diagnostics、Prompt Test、Developer Environment、RC9 | 未命中 | 未进入本轮 user AOT APK |
| Companion | F：第三方符号 | Dex / Kotlin builtins 的 `$Companion` 等符号，不是 RC9 Companion 功能 |
| API Key | F：非秘密 UI / 协议标签 | 配置和提示文字；没有随附真实凭据候选 |
| Bearer | F：鉴权协议常量 | libapp.so 中两个 scheme 命中，未发现完整长 token 候选 |
| Secret | F：第三方安全类型 | Dex 加密 / 安全类符号 |
| Password | F：通用类型 / 字段 | Dex、Flutter、VM 与应用字段文字，不是实际密码 |
| Token | F：类型 / 元数据 | Dex、Flutter、VM、应用符号；13 个 PNG 内为 C2PA `tstTokens` 时间戳签名元数据，不是 API token |

没有发现 A 类私人资料泄漏或待确认的 G 类命中；没有发现真实 API Key / Secret 候选。兼容文字未清洗，Legacy 未修改。扫描结论限于本次产物、指定编码和候选识别范围，不宣称能够证明任意编码形式的秘密都不存在。正式 release 仍须单独扫描。

## 首次安装与核心 smoke

使用本轮新建 Android 34 x86_64 AVD，配置和完整用户磁盘放在独立临时目录，设备为 `emulator-5556`。安装前无 PeiLink 包，安装本轮 user debug APK；没有读取、覆盖或清理原有用户安装数据。以下为模拟器级验收，不冒称实体 Android 手机验收。

| 检查 | 结果与证据边界 |
| --- | --- |
| 首次启动 | 成功；首页无角色、关系与动态，无私人聊天 / Memory / Echo |
| 中性 UserProfile | 未设置 / 未填写；没有私人姓名、生日或喜好注入 |
| 创建角色 | 实际填写并保存纯虚构 `PreWeb_Fiction`，重启后保留，注册表仅 1 个虚构角色 |
| 普通聊天 | 页面可进入，只有虚构角色的本地初始问候；没有发送 Provider 请求 |
| 角色详情 | 可进入，展示虚构角色，无私人资料 |
| Settings | 可进入；user 全局设置仅模型/API 与反馈，没有 Physical / Diagnostics / Prompt Test / Developer Environment |
| Memory Center | 可进入，虚构新角色无 User/Event/Summary 记忆；没有重新 Extraction |
| Echo | 可进入；创建角色后出现本地初始 Echo，与首次安装无私人 Echo 的结论一致 |
| 群聊 | 创建入口与成员选择页可进入，显示虚构角色；只有 1 个角色，未完成要求至少 2 人的群创建。完整业务以离线群聊回归为证据 |
| `.pei` 导入 | 导入入口可用，调用原生 Android 文件选择器；空白目录后取消，未导入用户资料 |
| `.pei` 导出 | 导出确认入口可用，“包含记忆”默认未选；取消。文件流与 round-trip 由离线测试覆盖 |
| 局域网 / 开发环境依赖 | user 在空白环境无需私人配置启动，开发入口不可达；user 未初始化 Physical CoreBridge，user cleartext 禁止，AOT 无指定私人 IP / Physical 符号。未进行网络抓包或硬件试连 |

只读取本轮新 AVD 的 `peilink_user` 数据目录进行复核：注册表仅上述虚构角色、Profile 中性、指定私人词命中文件为 0。创建后的自动本地问候、Echo、Life 数据属于虚构角色正常初始化，不误报成首次安装私人数据。

验收期间模拟器进程曾意外退出一次，未观察到对应应用崩溃证据，原因未定；在同一独立磁盘上重启并降低模拟器内存/CPU 后完成剩余验收，不据此推断为应用问题或隐瞒环境中断。完成后已关闭该模拟器，核验绝对路径并删除本轮独立 AVD 目录；原有设备与用户数据未触碰。

## `.pei` 与原生边界

只读确认 `android/app/src/main/kotlin/com/peilink/app/MainActivity.kt` 的 package 为 `com.peilink.app`，`peilink/pei_file` 与 `peilink/external_url` 通道存在。原生文件选择器已在本轮 UI 实际打开。

默认 `includeMemories=false`，v1 为纯角色；只有用户显式选择才输出携带 Memory 的 v2。Memory payload 使用 Legacy / Events / Users / Summary 白名单，不携带聊天、Archive、提取 cursor/state、迁移 journal、Diagnostics、Provider/API 配置、Physical 状态或全局 UserProfile。本轮未改 schema；v1/v2 导入导出、关系和保护字段 round-trip 回归通过。

## Memory / Physical 冻结保护

Memory 生产代码本轮零修改：Event/User/Summary schema、Lifecycle 30/60/90、Retriever threshold、key aliases、Explicit Remember、historical recall、Source Resolver、Reprocessing、Content Boundary、Summary priority、Legacy migration、`.pei` Memory schema 均保持开工前状态。工作树中的既有差异不是本轮改动。

Physical 保持冻结：user 无可达入口；dev 入口仍注册开发设置并保留 CoreBridge 初始化，dev 构建通过。证据为源码隔离、user UI/AOT 和 fake/mock 回归，本轮未启动 dev 硬件链路、连接 ESP32、烧录、调用 ASR/TTS 或修改协议、UI、算法。真实模型调用次数为 0。

## Known limitations 与下一阶段

1. 单一历史挂起测试明确排除；没有修改它来获得全绿。其余安全测试通过。
2. 正式 release signing 未配置，预期拒绝构建；profile 不是正式发行包。
3. 本轮设备验收为 Android 34 x86_64 模拟器 / user debug；user profile AOT 单独构建扫描，未冒充 profile 全 UI 或所有 ABI / 实体机验收。
4. 模拟器发生一次原因未定的环境退出，重启后完成验收；不扩展修复范围。
5. 群聊仅入口与成员选择 UI smoke，导入/导出未在设备实际完成文件 round-trip；完整业务以本轮离线回归为证据。
6. AOT 仍含已解释的兼容字面量、本机依赖路径及第三方符号，与用户提供的独立审计结论一致；未为消除字面量改 Legacy。
7. Memory 沿用既有 RC 限制：Prompt 优先级不等于任意模型的确定性语义保证；历史 Provider 截断、有限 alias、来源原件缺失降级等详见其报告。没有重复真实 Provider 验收。
8. iOS/macOS 历史 bundle ID `com.example.peijiancheApp` 留待多端阶段；本轮未验证或修改这些平台。Web 不在本轮范围，不自动启动 Web / iOS 用户接入或多端改造。
9. 已有未跟踪 `android/build/reports/problems/problems-report.html` 是 Gradle 问题报告，构建可能刷新；不属于生产代码。没有开工前内容哈希，不声称该未跟踪产物字节不变，也未删除它或扩大修改 `.gitignore`。

## 正式发布前 Release Ceremony

源码 / 功能冻结不等于正式发布完成。公测前仍须：

1. 创建并安全保存正式 Android signing key。
2. 配置 release signing。
3. 构建正式签名 AOT release APK。
4. 核验签名证书指纹。
5. 对最终 release APK 重做隐私 / Secret / 开发残留扫描。
6. 完成正式签名首次安装。
7. 完成正式签名升级测试。
8. 固定并备份正式签名身份。

本轮没有执行这些正式发布动作，它们不阻止本次 Android / Flutter 基线冻结。

## 工作树复核

开工和结束均记录 `git status --short --branch`、`git diff --stat`、`git diff --check`。分支为 `main...origin/main`，开工已存在 38 个 tracked 差异文件（1107 insertions / 608 deletions）；逐文件展开包含 70 个既有 modified/deleted/untracked 路径。结束时 tracked binary diff 与开工快照一致；没有生产代码变更。

| 分类 | 结论 |
| --- | --- |
| A Pre-Release 已有 | 身份、签名边界、入口隔离、中性默认值等保留 |
| B Memory 已有 | 第一/二批及 RC Hotfix 既有差异保留，无本轮修改 |
| C Physical 既有 | 与 A 的 dev 入口/隔离、D 的 Physical 测试存在交叉；Physical 核心实现无本轮差异 |
| D 测试 / 文档已有 | 开工前测试与验收文档保留，不重写既有报告 |
| E 本轮交付 | 仅新增本文件；构建输出、临时验收日志另记，不计生产改动 |
| F 意外差异 | 无新增源码/测试路径或 tracked diff 变化；已有 Gradle 报告可能刷新见限制，未声称其字节一致 |

APK 位于已被 gitignore 的 `build/`；已有 `android/build/` 报告是上述明确例外。辅助扫描脚本与日志放在系统 TEMP，未加入仓库。本轮未 reset、clean、checkout、stash、回滚用户工作、commit 或 push。未触碰原有私人用户数据；本轮虚构设备已清理。

以下附录按开工状态完整列出既有路径；类别可以交叉，`M`/`D`/`??` 为 Git 状态，不代表本轮修改。最终唯一新增交付路径为 `docs/release/PEILINK_PRE_WEB_FINAL_BASELINE.md`。

## 冻结声明

PeiLink 当前 Android / Flutter 既有功能基线正式冻结。除真实使用发现可复现 Bug、安全/隐私问题、发布阻断或多端适配所必需的兼容改动外，不再无理由修改现有核心系统。

后续可单独规划 UI 小范围美化、新功能独立开发、Web 版本方案、iOS 用户接入、多端数据与架构；这些均未在本轮启动。Memory 2.0.1 与 Physical 保持冻结。本轮无源码冻结 blocker，验收至此结束。

## 附录：开工完整文件分类

| Git 状态 | 路径 | 分类 |
| --- | --- | --- |
| M | `.gitignore` | A Pre-Release已有 |
| M | `android/app/build.gradle.kts` | A Pre-Release已有 |
| M | `android/app/src/main/AndroidManifest.xml` | A Pre-Release已有 |
| D | `android/app/src/main/kotlin/com/example/peijianche_app/MainActivity.kt` | A Pre-Release已有 |
| D | `android/app/src/main/res/xml/network_security_config.xml` | A Pre-Release已有 |
| M | `lib/main.dart` | A Pre-Release已有 |
| M | `lib/main_dev.dart` | A / C 开发入口及 Physical 隔离已有 |
| M | `lib/models/character_settings.dart` | A Pre-Release已有 |
| M | `lib/models/memory_extraction_result.dart` | B Memory已有 |
| M | `lib/models/memory_extraction_state.dart` | B Memory已有 |
| M | `lib/models/memory_retrieval_result.dart` | B Memory已有 |
| M | `lib/pages/chat_page.dart` | B Memory已有 |
| M | `lib/pages/memory_page.dart` | B Memory已有 |
| M | `lib/pages/settings_page.dart` | A Pre-Release已有 |
| D | `lib/prompts/character_prompt.dart` | A Pre-Release已有 |
| D | `lib/prompts/example_messages.dart` | A Pre-Release已有 |
| M | `lib/services/auto_memory_extraction_service.dart` | B Memory已有 |
| M | `lib/services/character_settings_storage_service.dart` | A Pre-Release已有 |
| M | `lib/services/memory2_chat_context_builder.dart` | B Memory已有 |
| M | `lib/services/memory2_engine.dart` | B Memory已有 |
| M | `lib/services/memory2_extractor.dart` | B Memory已有 |
| M | `lib/services/memory2_retriever.dart` | B Memory已有 |
| M | `lib/services/memory_center_controller.dart` | B Memory已有 |
| M | `lib/services/memory_extraction_state_service.dart` | B Memory已有 |
| M | `lib/services/user_profile_storage_service.dart` | A Pre-Release已有 |
| M | `linux/CMakeLists.txt` | A Pre-Release已有 |
| M | `test/context_builder_test.dart` | B / D Memory 测试或文档已有 |
| M | `test/memory2_auto_extraction_test.dart` | B / D Memory 测试或文档已有 |
| M | `test/memory9_data_safety_test.dart` | B / D Memory 测试或文档已有 |
| M | `test/memory_center_controller_test.dart` | B / D Memory 测试或文档已有 |
| M | `test/memory_center_page_test.dart` | B / D Memory 测试或文档已有 |
| M | `test/pei_memory_compatibility_test.dart` | B / D Memory 测试或文档已有 |
| M | `test/peilink_design_system_test.dart` | D 测试/文档已有 |
| M | `test/personality_style_engine_test.dart` | D 测试/文档已有 |
| M | `test/physical_release_isolation_test.dart` | C / D Physical 既有测试 |
| M | `test/privacy_residual_isolation_test.dart` | D 测试/文档已有 |
| M | `test/widget_test.dart` | D 测试/文档已有 |
| M | `windows/CMakeLists.txt` | A Pre-Release已有 |
| ?? | `android/app/src/dev/AndroidManifest.xml` | A / C 开发入口及 Physical 隔离已有 |
| ?? | `android/app/src/dev/res/xml/network_security_config.xml` | A / C 开发入口及 Physical 隔离已有 |
| ?? | `android/app/src/main/kotlin/com/peilink/app/MainActivity.kt` | A Pre-Release已有 |
| ?? | `android/app/src/user/AndroidManifest.xml` | A Pre-Release已有 |
| ?? | `android/app/src/user/res/xml/network_security_config.xml` | A Pre-Release已有 |
| ?? | `android/build/reports/problems/problems-report.html` | A 既有构建报告（可能被本轮构建刷新） |
| ?? | `docs/memory2/FINAL_RC_REPORT.md` | B / D Memory 测试或文档已有 |
| ?? | `docs/memory2/FINAL_TECHNICAL_BASELINE.md` | B / D Memory 测试或文档已有 |
| ?? | `docs/memory2/MEMORY_2_0_1_FINAL_RC.md` | B / D Memory 测试或文档已有 |
| ?? | `docs/release/PRE_RELEASE_BASELINE.md` | D 测试/文档已有 |
| ?? | `docs/release/STAGE3_REVIEW.md` | D 测试/文档已有 |
| ?? | `lib/config/peilink_settings_sections_registry.dart` | A Pre-Release已有 |
| ?? | `lib/dev_only/developer_settings_sections.dart` | A / C 开发入口及 Physical 隔离已有 |
| ?? | `lib/pages/memory_reprocessing_page.dart` | B Memory已有 |
| ?? | `lib/services/explicit_remember_intent.dart` | B Memory已有 |
| ?? | `lib/services/memory_content_boundary.dart` | B Memory已有 |
| ?? | `lib/services/memory_source_resolver.dart` | B Memory已有 |
| ?? | `lib/services/user_memory_key_aliases.dart` | B Memory已有 |
| ?? | `lib/widgets/memory_source_sheet.dart` | B Memory已有 |
| ?? | `scripts/build_dev.ps1` | A Pre-Release已有 |
| ?? | `scripts/build_user_release.ps1` | A Pre-Release已有 |
| ?? | `test/memory201_explicit_history_test.dart` | B / D Memory 测试或文档已有 |
| ?? | `test/memory201_key_alias_test.dart` | B / D Memory 测试或文档已有 |
| ?? | `test/memory201_source_ui_test.dart` | B / D Memory 测试或文档已有 |
| ?? | `test/memory201_sources_reprocessing_test.dart` | B / D Memory 测试或文档已有 |
| ?? | `test/memory201_summary_priority_test.dart` | B / D Memory 测试或文档已有 |
| ?? | `test/memory_final_closure_chat_test.dart` | B / D Memory 测试或文档已有 |
| ?? | `test/memory_final_closure_ui_test.dart` | B / D Memory 测试或文档已有 |
| ?? | `test/persisted_profile_preservation_test.dart` | D 测试/文档已有 |
| ?? | `test/pre_release_native_boundary_test.dart` | D 测试/文档已有 |
| ?? | `test/release_defaults_neutral_test.dart` | D 测试/文档已有 |
| ?? | `test/release_packaging_static_test.dart` | D 测试/文档已有 |
