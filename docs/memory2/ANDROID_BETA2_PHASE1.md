# Android 第二轮内测 Phase 1：记忆页面收口

日期：2026-09-10。实现完成，正式 user release 与真机覆盖安装验收待签名配置。

## 范围与 UI

仅修改记忆首页及相关测试；没有修改字体系统、聊天气泡、背景、Echo、群聊或 Memory 核心。

- 删除右上角管理按钮、管理 BottomSheet 及其首页导航分发。
- 删除首页历史回顾/失败请求弹层、复制全部回调、手动迁移确认弹层、旧记忆只读弹层；这些是页面私有展示代码。
- 随管理入口下线的兼容工具还包括迁移旧版记忆、旧版记忆、旧版待审核。
- 删除悬浮新增经历按钮。现在“经历过的事”卡片内，标题/副标题下方右对齐显示轻量“＋ 添加经历”，位于列表/空状态之前；空与非空状态均可用，随卡片滚动，不覆盖内容。
- 继续调用原 addEvent → _EventDialog → MemoryCenterController.addEvent 流程，不改保存、固定或取消语义。沿用卡片颜色、圆角、边框、字体与按钮主题。

## 只读审计结论

审计先于修改，检查了入口声明、全 lib 调用位置、Controller、存储服务与新版提取/检索链路。项目在这些路径上没有单独命名的 Repository，存储服务承担持久化职责。

A = 仅旧 UI 使用；B = 新版后台仍依赖；C = 历史兼容；D = 完全废弃。分类分别描述界面与底层，不能把旧入口等同于废弃数据。

| 入口 | 原 Widget / 导航 | Service 与存储层 | 持久化数据 | 分类与新版依赖 |
| --- | --- | --- | --- | --- |
| 重新整理聊天记录 | MemoryPage 管理 sheet 的 reprocess → MaterialPageRoute → MemoryReprocessingPage | MemoryCenterController.loadReprocessingMessages/reprocessMessages → ChatStorageService、AutoMemoryExtractionService.reprocess → Memory2Engine / Memory2StorageService、MemoryExtractionStateService | chat_history.json、memory_extraction_state.json、event_memories.json、user_memories.json | 入口 A；共用提取/写入底层 B。手动 reprocess 仅重整理页面调用；新版聊天 afterReplySaved 使用自动提取服务。保留整个重整理页面及服务，取消首页导航。 |
| 用户记忆历史 | history → MemoryPage.showHistory 的 BottomSheet，来源通过 showMemorySources | Controller.load / updateUserMemory、Memory2StorageService、MemorySourceResolver；新版 Memory2Engine、Memory2Retriever | user_memories.json 的 superseded、supersededById、mergedFromIds；chat_history.json 来源 | 入口 A，历史数据 B。新版修改事实会保留历史链；检索仍读取 superseded 信息。仅移除弹层。 |
| 未完成的保存请求 | explicit → showExplicitFailures 的 BottomSheet | Controller.loadExplicitFailures/retryExplicit → MemoryExtractionStateService、ChatStorageService、AutoMemoryExtractionService.maybeExtract(retryExplicit: true) | memory_extraction_state.json 的 explicitAttempts；chat_history.json；成功时写新版记忆文件 | 入口 A，尝试状态与共用提取逻辑 B。新版明确保存会读取/写入成功或失败状态；保留控制器重试能力和全部状态文件。 |
| 已遗忘的记忆 | forgotten → MaterialPageRoute → ForgottenMemoriesPage | Controller.load/restoreEvent → EventMemoryLifecycleService、Memory2StorageService；Memory2Retriever | event_memories.json 的 forgotten 状态及生命周期字段 | 入口 A，生命周期 B。新版首页 load 刷新状态、检索排除 forgotten；保留原页面及恢复/存储代码，仅移除首页导航。 |
| 复制全部记忆 | copy → MemoryPage.copyAll → Clipboard.setData，无独立页面 | Controller.buildCopyText，使用已加载 snapshot；不增加存储写入 | 读取 user_persona.json、user_memories.json、event_memories.json、memory_summary.json、memories.json 与迁移 ID；仅写系统剪贴板 | 格式化导出 A，未发现新版自动流程调用 buildCopyText；保留该方法，删除首页复制回调。共享数据仍属 B/C。 |

未将任一共用底层判为 D 并删除。

## 兼容能力保留

LegacyMemoryAdapter、LegacyMemoryMigrationService（含显式迁移执行、去重和 legacy_memory_migration.json 台账）、MemoryReviewService、MemoryReviewPage 全部保留。memories.json、pending_memories.json 均不删除、不重写。

新版仍明确依赖：

1. MemoryCenterController.load 读取旧记忆只读视图、迁移来源 ID、旧待审核数量。
2. Memory2Retriever 仍读取旧记忆，排除归档/已迁移项后作为兼容候选；仍处理用户历史链和遗忘过滤。
3. MemorySummaryGenerationService 仍把未归档的旧记忆作为汇总参考。
4. 聊天自动提取仍使用 AutoMemoryExtractionService，保存请求状态不能删除。

无存储格式、storage key、数据库 schema 或迁移策略变化；没有新增自动迁移。CharacterScopeService 角色路径规则保持原样：默认角色兼容根目录文件，其余为 characters/<角色ID>/<文件名>。自动记忆开关仍用 character_settings.json；设定仍用 user_persona.json。

## 修改文件

- lib/pages/memory_page.dart
- test/memory_center_page_test.dart
- test/memory201_source_ui_test.dart
- test/memory_final_closure_ui_test.dart
- test/legacy_memory_integration_test.dart
- docs/memory2/ANDROID_BETA2_PHASE1.md（本报告）

原管理入口测试更新为隐藏断言；重整理和遗忘页直接实例化测试，保留旧页面功能覆盖。兼容集成测试验证旧数据读取、显式迁移与原始字节保留；新增卡片入口测试验证空状态新增、非空状态入口、保存、取消、角色隔离和重新打开读取。

## 验证

- flutter analyze：执行完成，退出码 1；仅 2 条已有 info：memory2_storage_service.dart:290、298 的 curly_braces_in_flow_control_structures。已对照 HEAD 确认原有；该文件未修改。无新增 lint、warning 或 error。
- 24 个 memory 相关测试文件：259 项全部通过。
- Android user release：执行项目相同命令 flutter build apk --release --flavor user --target lib/main.dart --no-pub，因缺少正式签名配置而失败（android/app/build.gradle.kts:34）。未绕过签名保护、未使用临时密钥。
- Android user debug：通过，build/app/outputs/flutter-apk/app-user-debug.apk。
- Android dev debug：按 scripts/build_dev.ps1 等效命令执行，通过，build/app/outputs/flutter-apk/app-dev-debug.apk。
- git diff --check：通过。

日志位于 build/memory_phase1_analyze.log、build/memory_phase1_tests.log、build/memory_phase1_user_build.log、build/memory_phase1_user_debug.log、build/memory_phase1_dev_build.log。

尚未完成：使用与旧内测版相同的正式签名构建 user release，以及真机覆盖安装验收。当前兼容结论来自代码审计与文件持久化/旧数据测试，不声称已在设备上验证覆盖安装。需在本机提供 android/key.properties 或既有 PEILINK_KEYSTORE_FILE / PEILINK_KEYSTORE_PASSWORD / PEILINK_KEY_ALIAS / PEILINK_KEY_PASSWORD 后重跑正式构建。
