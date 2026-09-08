# PeiLink Pre-Release Baseline

日期：2026-09-04。

**PRE-RELEASE BASELINE PASS WITH KNOWN LIMITATIONS**

本结论针对当前代码和测试基线，允许结束现有基础功能开发；不等同于已获得正式可发布签名 APK。第三阶段发现的按值清洗数据安全阻断已消除，首次安装已在独立空白 Android 模拟器完成验证。正式签名、最终 release 产物扫描和正式升级验收仍是发布前置准备，不冒充已经通过。

## 1. 已通过

- CharacterSettings 与 UserProfile 不再仅凭字段值匹配旧默认资料就清除并保存。
- 新用户和缺字段仍使用中性默认，不恢复开发者私人 defaults。
- 显式保存、重载及 .pei v1/v2 导入的同值资料保留。
- 独立空白 user 安装无预置角色、聊天、Memory、RC 测试数据；资料中性，创建流程可进入。
- user 设置无 Physical、Memory Diagnostics、Prompt Test、Developer Tools 入口。
- user cleartext 网络限制及 dev/user applicationId 保持隔离。
- Android 改包名后的原生 .pei/外部链接通道已恢复；dev 在读取 CoreBridge 配置前设置 dev 命名空间。
- Memory2、Physical 核心及 .pei Memory schema 未改动。
- 108 个安全离线测试文件，622 项通过；flutter analyze --no-pub 无问题；git diff --check 通过。

## 2. 用户数据保留规则

修改位置：

- lib/services/character_settings_storage_service.dart
- lib/services/user_profile_storage_service.dart

删除按内容判断来源的清洗函数及调用。不存在例外值白名单，也没有新增来源猜测、迁移状态机或复杂迁移系统。当前两种资料模型没有足以证明“该字段来自历史自动污染”的可靠字段级来源标记；内置角色 ID 也不能证明某个字段从未被用户编辑。

因此无来源证据的旧资料默认保留。以后若需清理，必须有可信来源或显式用户确认；不能再依据姓名、日期、关系内容推断。已经由旧代码删除的数据不会被本次修复自动恢复，需原备份或用户重填。

CharacterSettings 的既有登记册身份同步仍保留：登记册是姓名/备注/简介等公开身份的既有权威来源。这是数据源一致性规则，不是按私人字段内容清洗。本轮没有改变公开资料编辑的双存储接口。

### 新正向回归

test/persisted_profile_preservation_test.dart 新增 6 项：

1. 新安装及缺字段都中性。
2. 显式同值 CharacterSettings 在新 service 实例两次读取后保持，原文件未被改写。
3. .pei v1 显式资料导入及两次读取保持。
4. .pei v2 同样保持，不修改 Memory schema。
5. UserProfile 显式同值资料两次读取保持，文件未被改写。
6. 无来源标记的历史资料保留。

privacy_residual_isolation_test.dart 和 widget_test.dart 中两条旧“同值就清除”断言按用户确认的新契约改为保留；新装中性断言未删除。首次新增测试曾因夹具自带末尾换行与模型原有 trim 行为不一致失败，夹具改为明确输入后通过，未修改生产 trim 行为。全量回归还识别出第二条旧清洗断言，更新后最终全量通过；不隐瞒这些中间失败。

## 3. 当前核心系统与冻结区

当前覆盖的基础系统包括正式单聊、群聊、Echo 发布与社交反馈、角色设置/资料、全局及角色用户资料、Context Builder/Prompt Composer、红包、冷静期、主动消息既有链路、角色删除与运行时重置、.pei 和 Memory2。

Memory 2.0 仍保持 Final RC PASS WITH KNOWN LIMITATIONS，详细基线见 ../memory2/FINAL_TECHNICAL_BASELINE.md。Event/User/Summary、Lifecycle 30/60/90、Retriever 7.5 扩展规则、真正注入 Recall、Legacy 显式迁移及 Diagnostics 核心未改。此前历史两次聊天未回复的证据缺口仍保留，不被此次离线回归追溯解决。

.pei v1 默认纯角色，v2 仅显式包含 Memory；不携带聊天、Archive、Provider/API、Diagnostics、cursor/state。此次只修资料加载保留，不变更导出 schema 或 Memory 协议。

## 4. user / dev / Physical

Android user applicationId=com.peilink.app，dev=com.peilink.dev；namespace 与 Kotlin MainActivity 为 com.peilink.app。与前一基线 applicationId 一致，两包可并存；namespace 改名本身不等于签名升级兼容。

文件和安全存储命名空间分别为 peilink_user / peilink_dev。user 入口不安装开发设置 builder，也不启动 CoreBridge runtime；dev 独立入口先配置命名空间再初始化。Physical 业务未扩展、未重构，没有连接 ESP32 或真实语音 Provider。

user APK 网络资源 base-config cleartextTrafficPermitted=false。开发局域网白名单只在 dev 资源中。user 未依赖开发者局域网地址。

iOS/macOS 仍保留 com.example.peijiancheApp 等历史命名，未为统一名称擅改；Windows/Linux 第二阶段 CMake 命名改动已记录，但未在本轮完成这些平台的安装升级验收。

## 5. Android 真正首次安装验收

设备：Android 34 x86_64 模拟器。使用现有设备规格但指定全新独立 userdata/cache 路径，初始盘来自 SDK userdata.img，不使用原 AVD 用户盘、不加载旧快照。安装前 pm list packages com.peilink 无输出。

安装产物：user debug，SHA256：

`442E8EE515FC929A6AA1688F47DF4330D4152313EB5D9F66D9D09BD6FBF988BD`

安装成功，启动 Status=ok、LaunchState=COLD，activity=com.peilink.app/.MainActivity。设备 UI 与实际文件核验：

| 场景 | 结果 |
| --- | --- |
| 首页 | 还没有角色、暂无角色/关系/动态 |
| 创建入口 | 打开创建 AI 菜单，继续进入创建角色表单；未提交角色 |
| 消息 | 暂无消息 |
| Echo | 生活尚未开始记录，等待第一次 Echo |
| Life | 无纪念日、无生活记录 |
| 设置 | 只有模型/API、反馈等用户入口；DEV_ENTRY_PRESENT=False |
| UserProfile | 中性字段核对 True，其余资料为空；PRIVATE_OR_RC_TERMS=False |
| Registry | REGISTRY_EMPTY=True |
| Echo 任务 | ECHO_TASKS_EMPTY=True |
| 数据目录 | 仅 character_registry.json、echo_comment_reply_tasks.json、user_profile.json；无角色目录、聊天、Memory 或 RC 测试文件 |

没有输入任何真实隐私，也没有调用模型。首个模拟器进程曾在安装后、页面核验前退出，原因未确定；降低资源配置重启后重新完成上述验收。失败的第一次没有算作通过。完成后独立模拟器已关闭；原 AVD 数据保持不变。

## 6. 构建和 AOT 静态扫描

user debug 构建通过。上一轮已验证 dev debug 构建通过；本轮未修改 dev/native 构建边界。标准 user release 命令仍因正式签名缺失而失败：Gradle 明确报告禁止回退 debug 签名。没有修改此规则、没有生成正式 keystore。

为补充 AOT 证据，本轮构建 user profile x86_64 APK，含 lib/x86_64/libapp.so，没有 kernel_blob。**它是 profile 验证产物，不是最终 release APK，不证明最终 release 已验收。**

profile AOT SHA256：

`AC5D594D53FC2B83F171CDAF0FE5E9CC66CD296895EBA787AF787EE5872130FC`

扫描 ZIP 内各文件 UTF-8、UTF-16 双对齐字节表示：

| 关键词 | profile AOT 扫描 |
| --- | --- |
| 林念念、一只小狐念、老裴 | 未命中 |
| 念念、裴简澈 | libapp.so 命中；对应保留的 Legacy 分类/回复前缀兼容字面量，不是私人默认人设注入 |
| PeiJianChe、JianChe | libapp.so 命中；核对为 file:///C:/Users/.../Pub/Cache/ 第三方源文件路径 |
| 192.168.2.215、ESP32、PhysicalHostPage | 未命中 |
| Memory Diagnostics、MemoryDiagnosticsPage | 未命中 |
| Prompt Test、PromptTestModePage、DeveloperEnvironmentPage | 未命中 |
| RC9 Companion、DEEPSEEK_API_KEY | 未命中 |
| G:\Development\PeiLink、C:\Users\ | 指定反斜线形式未命中；正斜线 Pub Cache 路径仍存在，不宣称无路径 |

关键词扫描不是完整 secret 审计，也不保证无所有可能的编码形式。未把第三方构建路径误判成用户资料泄漏，也未删除冻结区兼容逻辑来制造零命中。

## 7. 最终验证数字

- 全安全离线回归：108 个测试文件，622 项通过，退出码 0。
- 唯一整文件排除：test/physical_release_isolation_test.dart，已知 FakeAsync/文件 I/O 历史挂起；本轮未重跑、未删、未弱化。其他 Physical fake/mock 纳入通过。
- 覆盖 Memory2、Context/Prompt、Character/Profile、.pei/Legacy、删除/清理/重置以及现有旧功能回归；不将现有离线覆盖描述为所有功能均有设备端端到端验收。
- flutter analyze --no-pub：No issues found，退出码 0。
- git diff --check：通过。
- 真正 Provider / 语音请求：0；ESP32：0。

## 8. Known limitations

1. 无来源证据的历史污染默认保留；用户可见旧值不再被静默清除。已被旧版本删除的数据不能自动恢复。
2. Physical 历史挂起测试明确排除；不宣称全仓无排除通过。
3. AOT profile 仍含 Legacy/前缀兼容字面量和 Pub Cache 路径，不是零字符串产物；没有最终 release 二进制结果。
4. 当前设备功能验收使用 user debug；profile 包用于 AOT 静态扫描，没有以 profile 或正式 release 重复完整 UI 验收。
5. Memory2 原基线中的历史未回复证据缺口、跨文件非断电事务等限制不变。
6. Apple/桌面平台未完成本轮构建和升级测试。

## 9. 尚需用户完成的发布准备项

这些项目不再构成本轮数据保留代码修复的阻断，但**实际 APK 公测发布前必须完成**：

1. 准备正式签名密钥和管理策略，不使用 debug keystore。确认此前是否分发过同包名旧签名版本。
2. 仓库外加密保存 keystore，限制读取权限，离线加密备份并验证恢复；密码由密码管理器/CI secret 管理，不写入脚本或日志。
3. 使用现有正式 user release 入口构建，核验签名证书指纹及 versionCode。
4. 对真正最终 release/AOT APK 重新扫描私人、开发入口、地址、Secret/测试数据，并记录 SHA256。profile 扫描不能代替这一项。
5. 用正式证书产物完成安装/升级验收。applicationId 相同不代表新正式证书可覆盖旧 debug 证书；保持既定正式 app signing 身份，必要时按平台签名升级机制处理。

本轮没有创建密钥、签名发布或上传 APK。[Android 官方签名说明](https://developer.android.com/studio/publish/app-signing)

## 10. 工作树与本轮改动归属

当前分支 main...origin/main，工作树本来就包含第二阶段及此前封板的未提交修改。完整历史分类见 STAGE3_REVIEW.md，本轮未回滚它们。

本轮实际修改：

- lib/services/character_settings_storage_service.dart：移除按值清洗。
- lib/services/user_profile_storage_service.dart：移除按值清洗。
- test/privacy_residual_isolation_test.dart：旧清洗契约改为持久化保留。
- test/widget_test.dart：全局同值资料保留契约。
- test/persisted_profile_preservation_test.dart：新增 6 项正向回归。
- docs/release/STAGE3_REVIEW.md：标注历史阻断已由本次修复取代，保留历史证据。
- docs/release/PRE_RELEASE_BASELINE.md：本基线。

此前 Memory2 两份封板文档/测试、第二阶段 release/native/dev-only 改动及上一轮两项原生隔离修复均不是本轮新增。Memory2/Physical 核心无新差异。

最终 tracked diff（相对 HEAD，含全部历史改动）：21 文件，140 插入/506 删除；不包括 untracked 新测试/文档。构建临时报告和本轮独立模拟器盘清理不涉及用户文件；APK 留在忽略的 build 目录。无意外源码差异，无 commit/push。

## 11. 后续维护原则

**现有基础功能自此冻结。**

后续默认只允许：真实 Bug 修复、安全/隐私修复、小范围 UI/体验微调、独立新功能增量开发。不再无明确需求重构已经稳定的核心链路。Memory2 与 Physical 冻结边界继续有效。

本轮结束后停止，不开始 UI 美化、新功能、Git 历史清理、正式 keystore 生成或 APK 发布。
