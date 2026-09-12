# PeiLink Android Beta2 Final Release Audit

审计日期：2026-09-10。基线 HEAD：`fff41c0`，结论针对当前未提交工作区，不能将 HEAD 单独视为包含 Beta2 改动的版本。本轮没有修改产品代码、测试断言、存储或签名。

## A. Release Verdict

**BLOCKED**。

## B. Git / workspace 状态

开始审计时：28 个 modified、36 个 untracked 条目（目录按一个条目计），staged added 0、deleted 0。完整列表见文末。未跟踪内容包括必要的 Group G3.x 服务、群身份模型、气泡组件、背景组件、字体及测试，不能只打包已提交 HEAD。

`build/` 的截图、日志、截图测试及 `visual_polish_before` 源码快照属于审计产物，不是 pubspec 注册的生产资源。快照中的相对 import 不完整，实际被全项目 analyze 扫入。未删除它们，未增加忽略规则。截图字体加载开关在测试/构建资料中；未发现本轮视觉功能向生产入口加入测试 fixture 开关。Group Memory 保留已有诊断 logger，不输出模型密钥。未执行全二进制敏感信息取证。

## C. schema/storage compatibility

比较当前工作区与 HEAD：CharacterSettings、CharacterProfile、CharacterUserProfile、GroupChat/GroupMember、EchoItem 及原有存储实现无 diff。GroupMessage 只增加 copyWith(status)，toJson/fromJson 未变。

| 数据 | 当前路径/格式与结论 |
|---|---|
| 角色设置、档案、用户设定 | character_settings.json / character_profile.json / character_archive.json / user_persona.json；CharacterScopeService 保留默认角色根目录与其他 characters/<id> 隔离 |
| 聊天 | chat_history.json；原角色作用域未变 |
| 群 | group_chats.json、group_chats/<groupId>/messages.json；原格式未变 |
| 新群身份 | group_chats/<groupId>/user_profile.json；groupId/displayName/avatarPath/selfDescription/updatedAt；缺文件回退，不迁移旧群 |
| Memory2 | schemaVersion=2；event_memories.json / user_memories.json / memory_summary.json；原格式未变 |
| 新 Group Memory | group_chats/<sanitizedGroupId>/group_memories.json 和 group_memory_state.json，schemaVersion=2；缺文件返回空，拒收跨群事件 |
| Echo | echo_timeline.json，仍按 owner scope/角色隔离；EchoItem 序列化未变 |
| Appearance | peilink_appearance.json，仅 backgroundId/bubbleThemeId/fontThemeId |

本轮无 migration/schema 变更。原显式 Legacy Memory 迁移仍保留；新增群文件是独立扩展，不要求旧用户转换。上述是相对 HEAD 的兼容性证据，不能替代对实际 Beta1 数据包的核验。

## D. Beta1 -> Beta2 upgrade compatibility

user applicationId/namespace：com.peilink.app；dev applicationId：com.peilink.dev。构建/运行时文件未改；user documents 子目录 peilink_user，dev 为 peilink_dev，secure storage 命名空间保留。没有删除存量数据的本轮改动。

当前 pubspec 为 0.6.7+17。PRE_WEB_FINAL_BASELINE 与 STAGE3_REVIEW 也记录 code 17，但明确不是正式发布完成的证据，无法证明用户实际分发 Beta1 的 code/证书。**NEED USER CONFIRMATION：提供实际 Beta1 APK 或核实其包名、versionCode 和签名证书指纹。Beta2 必须使用相同签名，且 versionCode 高于该包。** 本轮未猜测或修改版本号。

## E. Memory

旧管理 BottomSheet/入口隐藏，新增经历在卡片内。底层 extraction、history、forgotten lifecycle、retry、Legacy 读取/显式迁移、内部导出控制器保留。Memory2 retriever/context builder 与原 Life/Echo 服务链没有因 UI 清理被删除；相关测试纳入定向及全套。没有新增自动清除旧记忆动作。

Group Memory 是新增独立机制，已有最多 200 条非固定事件的裁剪策略；不应将它描述为“所有数据永不自动裁剪”，它不清除旧单聊 Memory。两条 Memory storage info 不影响编译，不修复。

## F. Echo

Public Feed、用户头像到我的 Echo、+ 发布、角色头像到角色空间、Guide 入口保留；用户 owner 为 peilink_user_echo，角色为 character.id。Compose 与空间使用同一用户常量。原 storage/model 未改，旧 timeline 读取保留。入口与身份测试已执行；真机旧数据展示未验证。

## G. Single Chat

ChatBubbleSurface 共用真实 decoration，文本消费装扮字体，代码段仍走 monospace；系统内容不强制套普通消息样式。背景与 + 面板保留原入口。Archive/Profile/UserProfile 底层无变化，单聊及主题测试已纳入。

全套出现 group_chat_g1_test 首页创建角色路径的临时 character_registry.json.tmp rename 失败。NativePlatformStorage 使用固定 .tmp 名，角色 registry 不存在时读取会写空表；堆栈涉及 RelationshipHubPage 异步加载。可能存在初始化并发或测试生命周期竞争，尚不能证明只发生于测试。本轮不猜测修复存储，作为未排除的首次启动风险阻止放行。

## H. Group Chat G2.5 / G3.1～G3.5

- G2.5：每群独立文件；未设置时只读取全局 UserProfile 展示回退，不用 CharacterUserProfile 冒充群公开身份。角色私人用户认知仍作为独立私有上下文读取，这不等于公开群身份来源。
- G3.1：transcript 使用“名字(ID)”稳定标签。当前角色历史 transport role=assistant，其他角色在三角色 API 适配中仍为 user，但 content 明确携带真实身份标签。因此不能笼统声称“所有角色历史的 transport role 都是 assistant”。
- G3.2：纯本地评分，@/直接点名优先；allowInitiative=false 限制非点名参与，最多 4 候选。
- G3.3：当前 selectedCharacter.id 读取其 settings/profile/archive 与样本；未写入其他角色。
- G3.4：本地提取/相关性检索，按 groupId 文件隔离，缺文件兼容；不写 CharacterUserProfile。
- G3.5：本地 user/character/group 目标，planner hint 只接受当前轮真实存在目标；角色消息不触发新轮；不增加 Relationship 写入。
- 每轮一次 createPlan，最多 4 个 step；每 step 一次 generateStep，replyCount 1～3，总计划最多 6 条。新增 participation/voice/memory/target 无额外模型调用。没有无限角色接龙循环。

三项旧 transcript 字符串断言失败，实际实现附加稳定 ID；G2 成员管理测试仍寻找 CheckboxListTile，而真实组件为 GroupMemberChoice。未倒退实现或删减断言。

## I. Theme / Bubble / Font / Background

全 App 用户级 Appearance 作用域不变；notifyListeners 后保存，load 按 ID 恢复，不用 index。

气泡原 ID：minimal、qq_rounded、soft_cloud、glass。新增：paper_note、milk_candy、minimal_outline、soft_glimmer、journal_card。预览与实际使用 ChatBubbleSurface / decoration。

旧背景：default_light、starry_ai_space、morning_mist_sky、silver_moon_night、city_neon_night、mirror_lake_fantasy、cat_paw_blush、star_butterfly_blue、cream_bear、mist_star、lavender_flower、soft_cloud_blue。新增 12 项：moon_butterfly、white_peach、osmanthus_shade、ginkgo_leaf、quiet_snow、rain_glass、sea_salt、aurora_dust、pure_white、soft_fog_gray、warm_white、midnight_slate。只保存 backgroundId，不保存 pattern。

字体现状与此前缺失资源报告不同：现在四个文件真实存在、注册、内部 name 表声明 OFL，licenses 随包；未发现打包 Windows 商业字体，本轮未下载资源。

| 选项 | family | 基本汉字区覆盖（20992 码位） |
|---|---|---:|
| 清爽黑体 | sans-serif | Android 系统提供 |
| 手写体（hard_pen） | PeiLinkHandwriting / Ma Shan Zheng | 6763 |
| 楷体 | PeiLinkKai / LXGW WenKai | 20992 |
| 温柔圆体 | PeiLinkGentleRounded / Zen Maru Gothic | 6682 |
| 科技字体 | PeiLinkTechMono / Noto Sans Mono CJK SC | 20976 |

以上为本地字体 cmap/name 表检查，不声称覆盖全部 Unicode 中文。圆体预览缺 U+FF5E“～”，会用 PeiLinkKai 补字；手写/圆体其余缺字也走该 fallback。科技字体尾级 monospace 由平台处理。四字体合计约 49.3 MiB，资源许可证及测试存在；未进行远端原始发行文件哈希核验。字体文件详情见 build/rc_fonts.json。

## J. API / provider isolation

工作区无 provider、model hub、API 配置、endpoint、secure storage、runtime/native 配置变更。context_builder 增加默认空的群身份段；prompt_builder 样本去重/截断是已有 Beta2 diff，会影响默认调用的样本数量，不应称全部提示内容不变；它不改变 API 协议或增加请求。没有读取/输出真实 API 密钥。

## K. Automated Tests

计数排除 machine reporter 的 hidden loading 项，失败包括 failure/error；两个运行互相重叠，不能相加当独立总覆盖。

| 执行 | passed | failed | skipped | 状态 |
|---|---:|---:|---:|---|
| Beta2 定向 | 475 | 4 | 0 | Physical dev 测试不结束，停止；非完整成功 |
| 完整套件（--timeout 30s） | 904 | 5 | 0 | Physical dev、AI world 快捷入口测试未结束，停止；非完整成功 |

未完成/未执行不是 skipped。完整套件并未产生正常 done 成功事件。机器日志：build/rc_targeted.jsonl、build/rc_full.jsonl。测试覆盖 Memory、Echo、群 G2.5/G3.x、主题、气泡、背景、装扮及发布静态隔离；不能把部分成功声称全套通过。

失败分类：3 项 transcript 和 1 项旧控件断言属测试契约未同步（C）；临时文件竞争尚未排除产品风险（发布验证阻断）。另见 O 的 Physical 未验证情况。没有删除、跳过或放宽测试。

## L. flutter analyze

`flutter analyze --no-pub` 非零退出：**137 error / 1 warning / 3 info**。

137 error 全部来自 build/visual_polish_before 的非生产源码快照；实际 lib 为 0 error / 0 warning / 2 info（memory2_storage_service.dart:290、298）；test 为 0 error / 1 warning / 1 info（group_chat_create_flow_test 未用 helper 与注释尖括号）。保存原始失败结果，未改 analyzer 配置、未删除快照。日志 build/rc_analyze.log。

## M. Android user/dev build

两项 exit 0：

- flutter build apk --debug --flavor user --target lib/main.dart --no-pub
- flutter build apk --debug --flavor dev --target lib/main_dev.dart --no-pub

日志 build/rc_user_debug.log、build/rc_dev_debug.log。这些只是 debug 构建通过，不作为正式 Beta2 发布包。

## N. Release signing

android/key.properties 不存在、未跟踪；四个 PEILINK_KEYSTORE_* / PEILINK_KEY_* 环境配置均未设置。Gradle 对缺签名的 release 明确失败，没有 debug fallback。本轮未尝试绕过、未生成 key、未构建正式 release。

需要恢复 **Beta1 同一正式密钥** 的 key.properties（storeFile/storePassword/keyAlias/keyPassword），或 PEILINK_KEYSTORE_FILE / PEILINK_KEYSTORE_PASSWORD / PEILINK_KEY_ALIAS / PEILINK_KEY_PASSWORD。不要把密码发到报告或提交 Git；恢复本地安全配置后核对旧包证书。

## O. Physical release isolation

静态入口：main.dart 配置 user，不安装 dev sections；main_dev.dart 才导入并安装开发区块，runtime.developerToolsEnabled 仅 dev=true。相应源文件未改，user/dev 构建通过。

指定的“dev with developer environment shows and enters Physical”本轮再次未结束。不是已证实的功能泄露，也不能算测试通过。原因尚未完全定位，包含真实文件 I/O 与 widget 测试异步环境，按环境未验证处理；没有破坏隔离来迁就测试。user 隐藏路径的单独补测结果在最终附记记录。

## P. Release Blockers

1. 缺 Beta1 同一签名配置，无法生成并核验正式包。
2. 实际 Beta1 versionCode/证书无证据；当前 17 未证明满足严格递增。
3. 全套未完成且有初始化文件竞争失败，首次启动风险尚未排除；不可宣称完整发布门禁通过。

## Q. Known non-blocking issues

字体部分中文/符号使用 fallback；137 个 build 快照分析错误不影响已成功的 App 编译；两个 Memory lint、测试 helper/comment lint 为历史/测试技术债。4 个过时测试期望保留为失败，不掩盖。真实设备的玻璃/深色背景对比度、滚动与输入法表现待检查。

## R. 本轮实际修复文件

无产品/测试修复。本轮仅新增本审计报告与 build 下证据日志、字体检查结果；没有 schema、存储格式、签名或版本修改。

## S. 未验证项目

正式签名 release/AOT 产物、正式证书比对、实际 Beta1 数据覆盖升级、真机首次启动、真实在线 provider 请求/费用、多角色真实回复质量、真机字体/性能、未完成的测试。没有操作用户设备、删除数据或声称完成安装。

## T. 真机最终验收 checklist

- [ ] A：确认包名/证书相同且 code 递增后，Beta1 直接覆盖安装 Beta2。
- [ ] B：打开旧角色。
- [ ] C：检查旧聊天记录。
- [ ] D：检查 Memory 和已有经历。
- [ ] E：检查 Echo 公共流、我的 Echo 与角色空间。
- [ ] F：检查旧气泡、字体与背景恢复。
- [ ] G：发送新单聊消息并收到回复。
- [ ] H：创建/打开群聊。
- [ ] I：测试 @、点名及非主动角色。
- [ ] J：测试 + 面板及键盘切换。
- [ ] K：测试两个群身份独立，重启仍在。
- [ ] L：测试成员增删，用户自身不可删。
- [ ] M：检查多角色身份、回复目标及回复数量。
- [ ] N：深色背景、长消息、Emoji 与代码块可读。
- [ ] O：重启 App，再检查角色/记录/Memory/Echo/装扮/API 配置。
- [ ] P：在另一个设备或独立测试配置中全新安装测试首次启动；不要清除旧用户设备数据。

## U. Beta2 APK 输出路径

不填写：没有成功生成正式签名 release APK。

## V. SHA-256

不填写：没有本轮正式 APK。

**不允许将当前 commit/worktree 作为 PeiLink Android Beta2 Release Candidate 放行。** 代码冻结保留，完成签名、真实 Beta1 证据和未决回归验证后再判断；本轮不开展新功能。

### 最终附记

user Physical 隐藏路径单独补测也未结束（0 passed / 0 failed / 0 skipped，1 started 未完成），已停止，不再重试。没有把挂起归为产品失败。

### 开始审计时工作区完整列表

```text
 M lib/models/group_message.dart
 M lib/pages/home_page.dart
 M lib/pages/memory_page.dart
 M lib/pages/peilink/add_ai_page.dart
 M lib/pages/peilink/create_group_chat_page.dart
 M lib/pages/peilink/echo_compose_page.dart
 M lib/pages/peilink/group_chat_page.dart
 M lib/pages/peilink/group_chat_settings_page.dart
 M lib/pages/peilink/peilink_echo_page.dart
 M lib/pages/peilink/peilink_home_page.dart
 M lib/pages/peilink/peilink_profile_drawer.dart
 M lib/pages/peilink/theme_decoration_page.dart
 M lib/services/auto_echo_service.dart
 M lib/services/context_builder.dart
 M lib/services/echo_daily_life_service.dart
 M lib/services/group_conversation_coordinator.dart
 M lib/services/prompt_builder.dart
 M lib/theme/app_theme_background.dart
 M lib/theme/chat_visual_theme.dart
 M lib/theme/theme_background.dart
 M lib/widgets/chat/chat_more_panel.dart
 M lib/widgets/chat/message_bubble.dart
 M lib/widgets/chat/renderers/text_message_renderer.dart
 M pubspec.yaml
 M test/legacy_memory_integration_test.dart
 M test/memory201_source_ui_test.dart
 M test/memory_center_page_test.dart
 M test/memory_final_closure_ui_test.dart
?? assets/fonts/
?? docs/memory2/ANDROID_BETA2_PHASE1.md
?? docs/release/ANDROID_BETA2_FINAL_VISUAL_POLISH.md
?? docs/release/ANDROID_BETA2_PHASE2_FONTS.md
?? docs/release/ANDROID_BETA2_PHASE31_BUBBLES.md
?? docs/release/ANDROID_BETA2_PHASE3_BUBBLES.md
?? lib/models/group_memory_event.dart
?? lib/models/group_user_profile.dart
?? lib/pages/peilink/group_user_profile_page.dart
?? lib/services/echo_identity.dart
?? lib/services/group_character_voice.dart
?? lib/services/group_memory_extractor.dart
?? lib/services/group_memory_service.dart
?? lib/services/group_memory_storage_service.dart
?? lib/services/group_participation_service.dart
?? lib/services/group_reply_target.dart
?? lib/services/group_user_profile_storage_service.dart
?? lib/theme/theme_background_surface.dart
?? lib/widgets/chat/chat_bubble_surface.dart
?? lib/widgets/group/
?? test/ai_world_home_entry_test.dart
?? test/chat_bubble_theme_test.dart
?? test/chat_font_assets_test.dart
?? test/chat_font_test.dart
?? test/echo_first_echo_natural_test.dart
?? test/echo_my_echo_entry_test.dart
?? test/group_chat_context_test.dart
?? test/group_chat_create_flow_test.dart
?? test/group_chat_g1_test.dart
?? test/group_chat_g2_test.dart
?? test/group_chat_g33_voice_test.dart
?? test/group_chat_g34_memory_test.dart
?? test/group_chat_g35_reply_target_test.dart
?? test/group_participation_test.dart
?? test/group_user_profile_test.dart
?? test/group_visual_polish_test.dart
```
