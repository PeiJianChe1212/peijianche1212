# PeiLink Feature Registry

> 扫描日期：2026-08-11  
> 扫描范围：`lib/`、`assets/`、`test/`、`pubspec.yaml`、`CHANGELOG.md`、`ROADMAP.md` 与 Git 提交历史  
> 扫描方式：静态只读扫描；未修改任何 Dart 或业务文件  
> 当前包版本：`0.6.7+17`；最新提交所用产品版本名：`PeiLink v2.5 UI baseline`

## 判定口径

- **已完成 / 已展示**：页面、数据与入口均已接线。
- **已完成 / 隐藏入口**：实现与入口存在，但入口不对普通用户显式提示。
- **已完成 / 未展示**：实现存在，但扫描不到从当前可达页面进入的路径。
- **部分完成**：主体可用，但仍包含占位项、预留 Provider 或未持久化交互。
- **占位**：有 UI 或接口声明，明确提示“未来能力 / 暂未开放”。
- “用户是否可见”按当前导航可达性判断，不代表已进行真机验收。

---

# 1. 当前版本功能列表

## 1.1 启动、首页与用户资料

### 首次启动与角色引导

- **状态：** 已完成 / 已展示
- **入口：** App 启动；没有可见角色时自动出现
- **主要文件：** `lib/main.dart`、`lib/pages/environment_bootstrap_page.dart`、`lib/pages/peilink/character_creation_page.dart`
- **作用：** 检查角色 Registry；无角色时引导创建第一位 AI，有角色时进入桌面首页。
- **用户是否可见：** 是（仅无角色状态）

### 三屏桌面首页

- **状态：** 已完成 / 已展示
- **入口：** App 启动后的主界面，左右滑动
- **主要文件：** `lib/pages/home_page.dart`、`lib/widgets/home/home_glass.dart`、`lib/widgets/home/home_visual_tokens.dart`
- **作用：** 角色桌面、Life 桌面、Apps 桌面；展示当前角色、生活状态、最近痕迹、未读消息，并提供聊天、Echo、Today、PeiLink、设置等入口。
- **用户是否可见：** 是

### 首页角色切换

- **状态：** 已完成 / 已展示
- **入口：** 角色桌面顶部角色选择
- **主要文件：** `lib/pages/home_page.dart`、`lib/services/home_character_storage_service.dart`、`lib/services/character_registry_service.dart`
- **作用：** 选择首页展示角色，并同步活动、主动消息和生活痕迹。
- **用户是否可见：** 是

### Today 时间线与生活痕迹

- **状态：** 已完成 / 已展示
- **入口：** 首页活动状态、Life 桌面
- **主要文件：** `lib/pages/today_page.dart`、`lib/services/today_service.dart`、`lib/services/life_trace_service.dart`、`lib/models/today_event.dart`、`lib/models/life_trace.dart`
- **作用：** 记录当天活动变化和真实交互痕迹，并可从时间线返回聊天。
- **用户是否可见：** 是

### 用户资料

- **状态：** 已完成 / 已展示
- **入口：** PeiLink 左侧资料抽屉头像
- **主要文件：** `lib/pages/profile_page.dart`、`lib/pages/edit_profile_page.dart`、`lib/pages/profile_field_edit_page.dart`、`lib/pages/profile_region_page.dart`、`lib/services/user_profile_storage_service.dart`
- **作用：** 编辑头像、昵称、性别、地区、身份、签名等用户资料。
- **用户是否可见：** 是

## 1.2 PeiLink 主体导航

### 消息列表

- **状态：** 已完成 / 已展示
- **入口：** PeiLink 底部导航“消息”（标题显示 PeiLink）
- **主要文件：** `lib/pages/peilink/peilink_chats_page.dart`、`lib/services/chat_storage_service.dart`、`lib/services/group_chat_storage_service.dart`、`lib/services/initiative_service.dart`
- **作用：** 汇总单聊、群聊、最后消息和主动消息未读数。
- **用户是否可见：** 是

### 羁绊中心

- **状态：** 已完成 / 已展示
- **入口：** PeiLink 底部导航“羁绊”
- **主要文件：** `lib/pages/peilink/relationship_hub_page.dart`、`lib/services/relationship_group_storage_service.dart`、`lib/services/relationship_growth_service.dart`
- **作用：** 角色关系总览、最近互动、分组的新建/改名/成员管理、角色空间入口。
- **用户是否可见：** 是

### Echo 公共时间线

- **状态：** 已完成 / 已展示
- **入口：** PeiLink 底部导航“Echo”
- **主要文件：** `lib/pages/peilink/peilink_echo_page.dart`、`lib/pages/peilink/peilink_discover_page.dart`、`lib/services/echo_storage_service.dart`
- **作用：** 聚合角色 Echo，展示角色自动生活动态与用户发布内容。
- **用户是否可见：** 是

### 阿澈 Guide

- **状态：** 已完成 / 已展示
- **入口：** PeiLink 底部导航“Guide”
- **主要文件：** `lib/pages/peilink/peilink_guide_page.dart`、`lib/models/guide_knowledge.dart`、`assets/images/guide/`
- **作用：** 本地知识问答、功能搜索、新手指南，并直达创建角色、API 设置、帮助与反馈。
- **用户是否可见：** 是

### 资料抽屉

- **状态：** 部分完成 / 已展示
- **入口：** PeiLink 顶部头像/菜单
- **主要文件：** `lib/pages/peilink/peilink_profile_drawer.dart`
- **作用：** 进入用户资料、角色管理、收藏（当前实际进入 Memory）、相册（当前实际进入 Echo）、主题装扮和设置。
- **用户是否可见：** 是；“消息设置”“账号管理”仍为 Coming Soon。

## 1.3 角色系统

### 多角色 Registry

- **状态：** 已完成 / 已展示
- **入口：** 羁绊中心、AI 创造中心、首页角色切换
- **主要文件：** `lib/models/ai_character.dart`、`lib/services/character_registry_service.dart`、`lib/services/character_scope_service.dart`
- **作用：** 注册、选择、归档和按角色隔离数据；保留内置角色兼容。
- **用户是否可见：** 是

### AI 创造中心

- **状态：** 部分完成 / 已展示
- **入口：** PeiLink 顶部新增按钮、羁绊中心空状态、Guide 快捷卡
- **主要文件：** `lib/pages/peilink/ai_creation_center_page.dart`
- **作用：** 汇总创建角色、导入角色、创建群聊等创建入口；部分卡片仍为 Coming Soon。
- **用户是否可见：** 是

### 角色创建与导入 `.pei`

- **状态：** 已完成 / 已展示
- **入口：** AI 创造中心
- **主要文件：** `lib/pages/peilink/character_creation_page.dart`、`lib/pages/peilink/character_import_page.dart`、`lib/services/pei_file_service.dart`、`lib/services/pei_file_platform_service.dart`
- **作用：** 新建角色；解析、预览、校验并导入 Pei 角色包。
- **用户是否可见：** 是

### 角色资料、档案与用户侧人设

- **状态：** 已完成 / 已展示
- **入口：** 角色详情 → 编辑/管理；角色资料首页
- **主要文件：** `lib/pages/peilink/character_detail_page.dart`、`character_profile_*`、`character_archive_page.dart`、`character_user_profile_page.dart`、对应 storage services
- **作用：** 管理角色结构化资料、长期档案、角色眼中的用户身份和互动设定；旧设置可迁移到结构化 Profile。
- **用户是否可见：** 是

### 角色设置与管理

- **状态：** 已完成 / 已展示
- **入口：** 角色详情/聊天设置 → 角色管理
- **主要文件：** `lib/pages/peilink/character_management_page.dart`、`lib/pages/peilink/chat_settings_page.dart`
- **作用：** 调整相处模式、主动联系、记忆等角色级配置；清理聊天或重新开始；非内置角色支持删除。
- **用户是否可见：** 是；聊天设置中的搜索记录等条目仍为占位。

## 1.4 聊天、群聊与多模态

### AI 单聊

- **状态：** 已完成 / 已展示
- **入口：** 首页“聊天”、消息列表、角色详情
- **主要文件：** `lib/pages/chat_page.dart`、`lib/services/deepseek_service.dart`、`lib/conversation/`、`lib/chat_flow/`、`lib/reply_strategy/`、`lib/prompt_composer/`
- **作用：** 基于角色、用户、关系、记忆、当前生活和会话策略生成回复；支持消息持久化、重新生成、撤回状态和上下文保护。
- **用户是否可见：** 是

### 主动联系

- **状态：** 已完成 / 已展示
- **入口：** 自动运行；消息列表和首页未读角标
- **主要文件：** `lib/services/initiative_service.dart`、`lib/services/initiative_life_context_service.dart`、`lib/models/initiative_state.dart`
- **作用：** 按时间段、每日次数和冷却规则向真实聊天记录写入角色主动消息。
- **用户是否可见：** 是（结果可见，无独立页面）

### 消息撤回

- **状态：** 已完成 / 已展示
- **入口：** 聊天消息交互
- **主要文件：** `lib/models/chat_message.dart`、`lib/widgets/chat/message_bubble.dart`、相关测试
- **作用：** 标记消息为 recalled，并兼容旧消息无 status 字段的读取。
- **用户是否可见：** 是

### 红包与 AI 红包事件

- **状态：** 已完成 / 已展示
- **入口：** 聊天更多面板、聊天消息
- **主要文件：** `lib/widgets/chat/red_packet_send_dialog.dart`、`red_packet_message_renderer.dart`、`lib/services/ai_red_packet_*`、`lib/models/red_packet_data.dart`
- **作用：** 用户发送红包、接收方权限校验，以及 AI 根据安慰/特殊事件机会发出红包。
- **用户是否可见：** 是

### 图片消息与图片生成链路

- **状态：** 部分完成 / 已展示
- **入口：** 聊天更多面板、图片消息渲染
- **主要文件：** `lib/services/chat_image_*`、`lib/services/image_generation_service.dart`、`lib/services/multimodal_service.dart`、`lib/widgets/chat/renderers/image_message_renderer.dart`
- **作用：** 路由图片请求、管理生成任务并将图片保存为聊天消息；Model Hub 中部分图像/语音 Provider 仍是预留能力。
- **用户是否可见：** 图片链路可见；完整多 Provider 能力未完全开放。

### 群聊

- **状态：** 已完成 / 已展示
- **入口：** AI 创造中心或聊天设置“发起群聊”；消息列表进入群聊
- **主要文件：** `lib/pages/peilink/create_group_chat_page.dart`、`group_chat_page.dart`、`group_chat_settings_page.dart`、`lib/services/group_conversation_coordinator.dart`、`group_*_storage_service.dart`
- **作用：** 创建多角色群聊、协调角色回复、存储群消息、修改成员与群设置、清空或删除群。
- **用户是否可见：** 是

### 语音能力抽象

- **状态：** 占位 / 未展示
- **入口：** 无完整 UI
- **主要文件：** `lib/ai/text_to_speech_provider.dart`、`speech_to_text_provider.dart`、`lib/ai/model_hub.dart`
- **作用：** 为未来语音合成和识别提供统一 Provider 接口。
- **用户是否可见：** 否

## 1.5 Echo 与生活系统

### 手动 Echo

- **状态：** 已完成 / 已展示
- **入口：** Echo 发布按钮 → 手动发布
- **主要文件：** `lib/pages/peilink/echo_compose_page.dart`、`lib/services/echo_storage_service.dart`、`echo_image_storage_service.dart`
- **作用：** 发布文字/图片 Echo，并触发社交互动生成。
- **用户是否可见：** 是

### AI Echo 草稿与发布

- **状态：** 已完成 / 已展示
- **入口：** Echo 发布按钮 → AI 生成
- **主要文件：** `lib/pages/peilink/echo_ai_draft_page.dart`、`lib/services/echo_generation_service.dart`、`lib/models/echo_draft.dart`
- **作用：** 从已发生的生活 Moment 生成 Echo 草稿，可附带图片场景并在确认后发布。
- **用户是否可见：** 是

### 自动 Echo 生活动态

- **状态：** 已完成 / 自动运行
- **入口：** 首页启动、恢复前台与定时检查
- **主要文件：** `lib/services/auto_echo_service.dart`、`auto_echo_policy.dart`、`auto_echo_state_service.dart`、`echo_daily_life_service.dart`
- **作用：** 按 daily、specialEvent、activeShare、initial 等触发器，把角色生活 Moment 自动发布为 Echo；包含冷却和重复内容保护。
- **用户是否可见：** 结果可见，触发器本身不可见

### Echo 社交生态

- **状态：** 已完成 / 已展示
- **入口：** Echo 动态、评论页、访客列表
- **主要文件：** `lib/services/echo_social_interaction_service.dart`、`auto_echo_comment_service.dart`、`echo_comment_*`、`echo_visitor_*`、`relationship_echo_comment_service.dart`
- **作用：** AI 角色/世界居民评论、回复、互动、访客记录、热度统计及基于关系的社交反馈。
- **用户是否可见：** 是

### 角色 Echo 空间

- **状态：** 已完成 / 已展示
- **入口：** 角色详情、羁绊中心角色卡、Echo 角色头像
- **主要文件：** `lib/pages/peilink/peilink_echo_page.dart`、`echo_cover_*`、`echo_space_decoration_page.dart`、`echo_gift_collection_page.dart`、`lib/widgets/echo/`
- **作用：** 角色主页、封面、空间资料、相册、动态、访客、互动概览、羁绊快捷入口和礼物收藏。
- **用户是否可见：** 是；音乐等菜单项尚未形成独立完整能力。

## 1.6 羁绊、关系与记忆

### 羁绊成长

- **状态：** 已完成 / 已展示
- **入口：** 角色 Echo 空间 → 羁绊成长
- **主要文件：** `lib/pages/peilink/relationship_growth_page.dart`、`relationship_gift_page.dart`、`lib/models/relationship_growth.dart`、`lib/services/relationship_growth_service.dart`
- **作用：** 汇总聊天、Echo 互动和共同经历，计算关系阶段、成长事件、纪念信息与礼物记录。
- **用户是否可见：** 是

### 关系网络与共同经历

- **状态：** 已完成 / 系统使用，直接展示有限
- **入口：** 由群聊、Echo、生活事件和羁绊系统间接触发
- **主要文件：** `lib/services/relationship_network_service.dart`、`relationship_memory_service.dart`、`shared_experience_service.dart`、`lib/models/relationship_network.dart`、`shared_experience.dart`
- **作用：** 建立角色间连接图、共同经历、关系摘要和最近连接，为上下文与社交行为提供证据。
- **用户是否可见：** 部分（羁绊与空间中可见摘要，无完整关系图 UI）

### 长期记忆与待审核记忆

- **状态：** 已完成 / 已展示
- **入口：** 资料抽屉“收藏”（实际 Memory）、角色管理 → Memory
- **主要文件：** `lib/pages/memory_page.dart`、`memory_review_page.dart`、`lib/services/memory_storage_service.dart`、`memory_review_service.dart`、`lib/models/memory_item.dart`、`pending_memory.dart`
- **作用：** 从聊天提取候选记忆，经用户审核后成为长期记忆；支持搜索、分类、排序、编辑与删除，并进入 Prompt。
- **用户是否可见：** 是；抽屉命名“收藏”与实际页面含义不完全一致。

## 1.7 设置、外观与反馈

### 模型与 API 设置 / Model Hub

- **状态：** 部分完成 / 已展示
- **入口：** 设置、Guide 快捷卡
- **主要文件：** `lib/pages/api_settings_page.dart`、`lib/ai/model_hub.dart`、`lib/ai/providers/`、`lib/services/api_settings_storage_service.dart`
- **作用：** 配置聊天模型、API 地址与密钥；统一声明聊天、图像、TTS、STT 能力。
- **用户是否可见：** 是；聊天 Provider 可用，部分图像与语音能力仅预留。

### 主题装扮

- **状态：** 部分完成 / 已展示
- **入口：** PeiLink 资料抽屉“主题装扮”
- **主要文件：** `lib/pages/peilink/theme_decoration_page.dart`、`lib/services/peilink_appearance_service.dart`、`lib/theme/app_theme_background.dart`、`assets/backgrounds/`
- **作用：** 选择背景、气泡与字体风格并本地持久化。
- **用户是否可见：** 是；部分选项是展示/预留层级。

### 帮助与反馈

- **状态：** 已完成 / 已展示
- **入口：** 设置、Guide
- **主要文件：** `lib/pages/feedback_page.dart`、`lib/services/feedback_submission_service.dart`、`lib/pages/settings_page.dart`、Android `MainActivity.kt`
- **作用：** App 内提交反馈；另可通过平台通道打开腾讯问卷。
- **用户是否可见：** 是

---

# 2. 页面地图

```text
App 启动
└─ EnvironmentBootstrapPage
   ├─ 无角色 → 创建第一位 AI → CharacterCreationPage
   ├─ 隐藏：Logo 连点 7 次 → 开发者密钥 → 开发沙箱
   └─ 有角色 → HomePage（三屏横向桌面）
      ├─ 角色桌面
      │  ├─ 角色卡 → CharacterDetailPage
      │  │  ├─ 聊天 → ChatPage
      │  │  └─ Echo 空间 → PeiLinkEchoPage(character)
      │  ├─ 聊天 → ChatPage
      │  ├─ Echo → PeiLinkEchoPage(character)
      │  ├─ 电话 → 占位提示
      │  └─ 角色选择 → 角色选择底部弹层
      ├─ Life 桌面
      │  ├─ 当前活动 → TodayPage → ChatPage
      │  ├─ 最近痕迹 → Echo
      │  ├─ 设置 → SettingsPage
      │  └─ 纪念日/若干 App → 部分占位
      └─ Apps 桌面
         ├─ PeiLink → PeiLinkHomePage
         ├─ 设置 → SettingsPage
         └─ 其他桌面 App → 部分占位
```

```text
PeiLinkHomePage
├─ 顶部头像 → PeiLinkProfileDrawer
│  ├─ 用户资料 → ProfilePage → 字段编辑 / 地区 / 完整资料编辑
│  ├─ 消息设置 → Coming Soon
│  ├─ 账号管理 → Coming Soon
│  ├─ 角色管理 → 羁绊页
│  ├─ 收藏 → MemoryPage → MemoryReviewPage
│  ├─ 相册 → PeiLinkEchoPage
│  ├─ 主题装扮 → ThemeDecorationPage
│  └─ 设置 → SettingsPage → API / 帮助反馈 / 外部问卷
├─ 顶部新增 → AiCreationCenterPage
│  ├─ 创建角色 → CharacterCreationPage
│  ├─ 导入角色 → CharacterImportPage
│  └─ 创建群聊 → CreateGroupChatPage
└─ 底部导航
   ├─ 消息 → PeiLinkChatsPage
   │  ├─ 单聊 → ChatPage → ChatSettingsPage
   │  └─ 群聊 → GroupChatPage → GroupChatSettingsPage
   ├─ 羁绊 → RelationshipHubPage
   │  ├─ 角色卡 → 角色 Echo 空间
   │  ├─ 新建/改名/管理分组
   │  └─ 创建 AI → AiCreationCenterPage
   ├─ Echo → 公共时间线
   │  ├─ 发布 → 手动 Echo / AI 草稿
   │  ├─ 动态 → 评论页
   │  └─ 角色 → 角色 Echo 空间
   │     ├─ 封面预览/编辑
   │     ├─ 空间装扮
   │     ├─ 访客列表
   │     ├─ 羁绊成长 → 礼物页
   │     └─ 礼物收藏
   └─ Guide → PeiLinkGuidePage
      ├─ 搜索 / 问阿澈（本地知识库）
      ├─ 创建角色
      ├─ API 设置
      └─ 帮助与反馈
```

说明：仓库仍保留 `PeiLinkContactsPage`、`PeiLinkDiscoverPage`、`PeiLinkMePage` 等早期页面，但当前主导航已改为“消息 / 羁绊 / Echo / Guide”，它们不是当前底栏页面。

---

# 3. 核心系统架构

## 3.1 总体数据流

```text
用户操作 / App 生命周期 / 定时检查
        ↓
页面层（Home、Chat、Echo、Relationship、Guide）
        ↓
领域服务层
├─ Context Builder / Conversation Engine → 聊天 Prompt → Model Hub → 回复
├─ World Tick → World Simulation / Timeline → Life Decision → Life Moment
├─ Life Moment → Echo Engine → Echo Storage → 社交评论 / 访客 / 羁绊成长
├─ 聊天 / Echo / 世界事件 → Shared Experience → Relationship Network / Memory
└─ 用户审核候选记忆 → Long-term Memory → 下一轮 Context
        ↓
本地 JSON 与媒体文件（应用 Documents 目录）
```

项目没有看到 Provider、Riverpod、Bloc 等集中式状态管理包。当前状态主要由：

- 页面内 `StatefulWidget` 和 Controller 管理瞬时 UI 状态；
- Service 负责领域逻辑和持久化；
- `PeiLinkAppearanceController.instance` 等少量单例负责跨页面状态；
- 页面返回值、重新加载和 revision key 负责页面间刷新。

## 3.2 Context Builder

**主要文件：** `lib/services/context_builder.dart`、`lib/context_builder/`、`lib/prompt_composer/`、`lib/conversation/`、`lib/chat_flow/`、`lib/reply_strategy/`

**输入：** 角色 Settings/Profile/Archive、用户 Profile、关系上下文、正式记忆、聊天历史、当前活动、共享世界事件、冷却状态、Echo 上下文。  
**处理：** `ContextBuilder` 按任务与 Profile 组合模块；Conversation Engine 决定会话模式；Chat Flow 和 Reply Strategy 形成回复目标；Prompt Composer 去重并组装最终 Prompt。  
**输出：** 交给 `ModelHub`/聊天 Provider 的结构化提示，并由 `DeepSeekService` 发送请求。  
**回流：** 回复进入聊天存储；可提取为 Pending Memory；真实交互可形成 Life Trace、Shared Experience 和关系成长证据。

## 3.3 Life Engine

**主要文件：** `life_decision_engine_service.dart`、`life_engine_service.dart`、`life_event_pool_service.dart`、`life_moment_storage_service.dart`、`life_event_renderer_service.dart`、`decision_history_service.dart`、`causal_graph_service.dart`

**数据流：** 世界时间线 + 角色资料 + 聊天/记忆/Echo + 可用世界资源 → Life Decision → 候选 Life Moment → 持久化 Moment/因果节点 → Today、Echo 或共享经历消费。  
**约束：** 已确认世界状态作为事实；未来状态只能影响对应时间之后的决定；资源服务避免多个事件争用同一世界资源。

## 3.4 World Timeline

**主要文件：** `world_tick_service.dart`、`world_timeline_service.dart`、`world_simulation_service.dart`、`shared_world_event_service.dart`、`shared_world_resource_service.dart`

**数据流：** App 启动/回前台 → `WorldTickService.advance()` → 补齐当前时间状态、推进模拟、刷新角色决策/事件池 → 输出 Tick Report → 首页触发 Auto Echo 与状态刷新。  
**存储：** `world_tick_state.json`、`world_timeline.json`、`shared_world_events.json`、`shared_world_resources.json`、`causal_graph.json`。

## 3.5 Echo Engine

**主要文件：** `echo_generation_service.dart`、`auto_echo_service.dart`、`auto_echo_policy.dart`、`echo_daily_life_service.dart`、`echo_social_interaction_service.dart`、`auto_echo_comment_service.dart`、各 Echo storage service。

**数据流：** Life Decision/Event Pool → Life Moment → 手动请求或自动策略 → Echo Draft/Item → 用户确认或自动发布 → Echo Storage → AI/虚拟用户评论、回复、点赞、访客 → 互动统计、Shared Experience 与 Relationship Growth。  
**安全阀：** 自动发布状态、两小时级检查保护、每日/相似内容限制、已确认事实来源。

## 3.6 Relationship 系统

**主要文件：** `relationship_growth_service.dart`、`relationship_network_service.dart`、`relationship_memory_service.dart`、`relationship_opportunity_*`、`relationship_cooldown_service.dart`、`shared_experience_service.dart`。

**数据流：** 聊天 + Echo 互动 + 共同经历 + 礼物 → Growth Profile/事件 → 阶段与里程碑 → 羁绊 UI；角色间共同经历 → Network Node/Edge → 关系上下文与社交行为；冷却与边界状态反向约束聊天回复。

## 3.7 Memory 系统

**主要文件：** `memory_storage_service.dart`、`memory_review_service.dart`、`deepseek_service.dart`、`memory_page.dart`、`memory_review_page.dart`。

**数据流：** 聊天内容 → 模型抽取候选记忆 → `pending_memories.json` → 用户批准/编辑/拒绝 → `memories.json` → `ExistingMemoryContextProvider` / Context Builder → 后续对话。  
**原则：** AI 建议、用户决定；支持旧数据兼容和按角色隔离。

## 3.8 数据存储地图

- **全局：** `character_registry.json`、`active_character.json`、`home_display_character.json`、`user_profile.json`、`api_settings.json`、`peilink_appearance.json`。
- **角色目录 `characters/<id>/`：** `character_settings.json`、`character_profile.json`、`character_archive.json`、`user_persona.json`、`chat_history.json`、`memories.json`、`pending_memories.json`、`today_timeline.json`、`life_traces.json`、`life_moments.json`、`life_event_pool.json`、`echo*.json`、`initiative_state.json`、`relationship_growth.json` 及头像/图片/封面目录。
- **关系与世界：** `character_relationships.json`、`relationship_groups.json`、`relationship_memories.json`、`relationship_opportunity_state.json`、`shared_experiences.json`、`shared_world_events.json`、`shared_world_resources.json`、`world_timeline.json`、`world_tick_state.json`、`causal_graph.json`。
- **群聊：** 全局群 Registry；`group_chats/<groupId>/messages.json`。
- **开发环境：** `EnvironmentDataService` 对普通数据与开发沙箱进行切换/初始化，入口受开发者验证保护。

## 3.9 资源文件

- 品牌：Logo、蝴蝶、App Icon，位于 `assets/images/brand/`。
- Guide：阿澈欢迎图与参考图，位于 `assets/images/guide/`。
- Echo 空间：晨雾/草地等封面图，位于 `assets/images/`。
- 桌面 App Icons：Echo、世界、设置、音乐、礼物、相册、日记、相机。
- 主题背景：星空、城市霓虹、镜湖、月夜、晨雾及 simple pack。

---

# 4. 已完成但未暴露功能

| 功能 | 代码状态 | 未暴露判断 | 建议 |
|---|---|---|---|
| 开发环境管理页 | `DeveloperEnvironmentPage`、服务和测试均存在 | 启动页只有隐藏验证逻辑；扫描不到进入该管理页的普通导航 | 保持隐藏；补充内部测试文档，避免公开密钥机制 |
| 完整关系网络图 | Network Snapshot、节点/边和 compact context 已实现 | 羁绊页展示摘要/分组，没有图谱页面 | 若测试用户需要理解 AI 社会，可后续做只读关系图 |
| 关系记忆摘要 | `RelationshipMemoryService` 可生成/重建 pair summary | 没有独立管理 UI | 建议先保留为上下文能力，不急于暴露 |
| 世界时间线/因果图 | Timeline、Simulation、Causal Graph 均有持久化实现 | 当前只通过 Life/Echo 间接呈现 | 可作为开发者诊断页，而非普通用户功能 |
| PeiLinkContactsPage | 页面和角色列表代码存在 | 当前底栏已由 `RelationshipHubPage` 替代 | 标记为旧页面候选，先验证是否仍有测试/设计用途 |
| PeiLinkDiscoverPage | 聚合 Echo 页面存在 | 当前公共 Echo 直接嵌入 `PeiLinkEchoPage` | 可归档或删除前先比较功能差异 |
| PeiLinkMePage | “我”页面存在 | 当前改用资料抽屉 + Guide 底栏 | 属于旧导航残留候选 |
| AddAiPage | 旧的新增 AI 页面存在 | 当前统一使用 `AiCreationCenterPage` | 适合并入清理候选 |
| 语音 TTS/STT Provider | 接口已定义 | 无完整实现和用户入口 | 保留扩展点，状态应写“预留”而非“已上线” |
| Prompt/世界诊断能力 | Context、Decision、Timeline 均能输出结构化信息 | 无 Prompt Inspector / World Inspector 页面 | 建议仅在开发环境内暴露 |

特别说明：Guide 已经接入当前底部导航，不再属于“完成但未暴露”。角色导入和羁绊成长也已有可达入口。

---

# 5. 废弃 / 重复代码

## 可以删除（先独立提交并跑测试）

以下组件名称明确带 `Legacy`，且全仓扫描只发现声明、未发现调用：

- `RelationshipOverviewCardLegacy`
- `RelationshipFeatureCardLegacy`
- `SpaceEchoActionLegacy`

位置均在 `lib/pages/peilink/peilink_echo_page.dart`。建议先以单独清理提交删除，并运行 Echo/关系相关测试确认。

## 建议保留

- 所有 `fromLegacy`、`legacyDefaultFileName`、旧 JSON 字段回退和 `importLegacy`：它们承担用户数据迁移，不能因“legacy”命名直接删除。
- `AppThemeBackground.legacyAtmospherePack`：仍被 `PeiLinkAppearanceService` 合并进可选背景。
- Model Hub 中 TTS/STT/Image Provider 抽象：属于明确的架构扩展点。
- `ResponseStrategyContext` 第一阶段占位：已参与可插拔 Context 架构，删除价值低。

## 暂不处理，待确认产品方向

- `PeiLinkContactsPage` 与 `RelationshipHubPage`：功能重叠，但后者是当前入口。
- `PeiLinkDiscoverPage` 与嵌入式 `PeiLinkEchoPage(showPublicTimeline: true)`：功能重叠。
- `PeiLinkMePage` 与 `PeiLinkProfileDrawer`：旧“我”Tab 与新抽屉重叠。
- `AddAiPage` 与 `AiCreationCenterPage`：旧单入口与新创造中心重叠。
- `character_settings` 与结构化 `character_profile`：目前有迁移依赖，不可直接合并删除。
- 抽屉“收藏”实际打开 Memory、“相册”实际打开 Echo：这是产品语义/路由问题，不能只靠删除代码解决。
- `chat_settings_page.dart` 中“查找聊天记录”等占位条目，以及首页“电话”、纪念日和未来 Apps：应根据路线图决定隐藏、实现或继续占位。

---

# 6. 版本更新记录

## 版本口径说明

仓库同时存在两套版本命名：

1. `pubspec.yaml` / `CHANGELOG.md` 使用 `0.6.x+build`；
2. Git 提交使用 PeiLink 产品/UI 版本，如 `v1.3`、`v1.4.6`、`v2.5`。

下表只按代码和提交证据整理，不推断不存在的版本号。

## v0.5（Roadmap 稳定基线）

- **新增：** 首页、资料、角色编辑器、聊天参数、回复回溯与重新生成。
- **修改：** 无足够提交证据细分。
- **删除：** 无明确证据。

## v0.6.0（Memory 审核闭环）

- **新增：** 自动提取候选记忆、用户审核后进入正式记忆。
- **修改：** 记忆从模型内部信息转为用户可控数据。
- **删除：** 无明确证据。

## v0.6.1+11（Memory Experience）

- **新增：** 记忆搜索、分类筛选、排序、候选数量角标。
- **修改：** 记忆分类与编辑体验；修复弹层生命周期问题。
- **删除：** 无明确证据。

## v0.6.2+12（Life）

- **新增：** Activity Engine、Presence 问候、动态生活状态及聊天上下文。
- **修改：** 首页/聊天从固定在线状态升级为生活活动状态。
- **删除：** 固定“在线”展示逻辑被替代。

## v0.6.3+13（Today）

- **新增：** Today Timeline、Activity Story、Session Reset Service。
- **修改：** 清空聊天升级为“仅清空聊天 / 重新开始”的分级重置。
- **删除：** 无明确证据。

## v0.6.4（Initiative）

- **新增：** 角色主动消息、时间/次数/冷却限制、未读角标。
- **修改：** 示例对话与真实事实隔离；聊天顶部活动状态仅短暂展示。
- **删除：** 示例对话不再作为真实历史轮次发送。

## v0.6.5+15（Trace）

- **新增：** Life Trace、真实互动痕迹、主动消息来源标记。
- **修改：** 首页、聊天、Today 之间形成连续的生活记录。
- **删除：** 无明确证据。

## v0.6.6+16（Model Hub）

- **新增：** 统一聊天/图像/TTS/STT Provider 抽象与能力展示。
- **修改：** DeepSeek、豆包及 OpenAI-compatible 接口统一经过 Provider。
- **删除：** 无明确证据。

## v0.6.7+17（Conversation Engine 1.0）

- **新增：** Conversation Engine、会话模式策略、动作冷却、生活感提示。
- **修改：** 回复顺序、动作重复控制、接话与生活化表达。
- **删除：** 无明确证据。

## PeiLink v1.3（Git：2026-08-03）

- **新增：** Chat 红包系统的 AI 红包接收能力。
- **修改：** 红包权限与事件链路。
- **删除：** 无明确证据。

## PeiLink v1.4.6（Git：2026-07-26）

- **新增/修改：** 提交名仅给出版本号，仓库缺少对应详细说明。
- **删除：** 无明确证据。

## PeiLink v2.x UI 演进

- **2026-08-05：** 完成 PeiLink 桌面三屏 UI 初版。
- **2026-08-09 / v2.5：** 建立 PeiLink v2.5 UI baseline。
- **当前工作区（未提交代码痕迹）：** Guide、羁绊中心/成长/礼物、开发环境、角色导入 `.pei`、Echo 社交生态和空间概览等正在集成；这些不能当作已发布版本更新记录，发布前应由 Git 提交或 Release Note 再确认。
- **删除/替换痕迹：** 早期“通讯录 / 发现 / 我”底栏结构已被“羁绊 / Echo / Guide + 资料抽屉”替代，但旧页面文件仍保留。

---

# 7. 面向测试用户的“PeiLink 现在有什么？”素材

> 本节可直接作为未来功能介绍页或更新公告的数据源草稿。

- ✨ **AI 角色**：创建、导入和管理多个角色，每个角色拥有独立资料、记忆与生活。
- 💬 **单聊与群聊**：角色化对话、主动消息、图片、红包、多角色群聊。
- 🌎 **AI 世界**：世界时间线持续推进，角色会根据时间、事件和经历做生活决定。
- 🦋 **Echo 生活动态**：角色会发布生活回声，也支持手动和 AI 辅助创作。
- 💞 **羁绊成长**：聊天、Echo 互动、共同经历与礼物会沉淀为关系阶段和成长记录。
- 🧠 **长期记忆**：AI 提出记忆候选，由用户审核后才进入长期记忆。
- 📅 **Today 与生活痕迹**：查看角色今天做过什么，以及你们真实发生过的互动。
- 👥 **AI 社交生态**：角色和世界居民可在 Echo 中评论、回复、访问并形成关系网络。
- 🎨 **角色空间与主题**：角色 Echo 空间、封面、访客、相册、礼物和主题背景。
- 🦋 **阿澈 Guide**：搜索功能、查看新手说明，并快速进入创建、API 设置和反馈。
- ⚙️ **模型与 API**：支持统一的模型能力配置；图像与语音能力仍在逐步开放。

---

# 8. Registry 后续维护规则

每次发布建议更新以下字段：

1. 包版本与产品版本是否一致；
2. 新功能的状态、入口和用户可见性；
3. 页面地图是否发生导航替换；
4. 新增的 storage 文件及迁移策略；
5. “未暴露功能”是否已开放；
6. Legacy 清理是否经过测试；
7. 从本 Registry 生成一份面向用户的简短更新公告。

建议公告模板：

```text
PeiLink vX.Y.Z 更新

新增：
🦋 功能名称 —— 一句话说明用户能做什么

优化：
💬 功能名称 —— 一句话说明体验变化

修复：
🛠 问题名称 —— 一句话说明修复结果
```
