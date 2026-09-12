# PeiLink Beta2 最后一轮 Visual Polish

范围：主题/聊天背景扩充与群聊视觉收尾。完成后停止，等待真机反馈；**未进入最终封板审计，未构建任何 APK**。

## A. 主题背景

全部现有背景保留：原 builtInPack 六款及 legacyAtmospherePack 六款的 ID、资源、默认选择含义未改。旧背景仍由原 appearance 控制器按 ID 恢复；legacy 列表原有兼容读取方式不变。

新增十二款：

| 名称 | ID | 实现 |
| --- | --- | --- |
| 月光蝴蝶 | moon_butterfly | 淡蓝紫底、稀疏原创蝶形 |
| 白桃花瓣 | white_peach | 浅白桃底、低对比花瓣 |
| 桂花碎影 | osmanthus_shade | 暖白底、四瓣细碎花形 |
| 银杏微叶 | ginkgo_leaf | 浅灰绿底、扇形微叶 |
| 细雪 | quiet_snow | 雾蓝底、轻白雪点 |
| 雨滴玻璃 | rain_glass | 淡灰蓝底、低密度水滴与小高光；无实时 blur |
| 海盐波纹 | sea_salt | 海盐浅色、轻线条波纹 |
| 极光微粒 | aurora_dust | 淡蓝绿底、稀疏点粒 |
| 纯净白 | pure_white | 纯色 |
| 柔雾灰 | soft_fog_gray | 轻渐变 |
| 淡暖白 | warm_white | 轻渐变 |
| 深夜蓝灰 | midnight_slate | 低饱和深色渐变 |

使用确定性 Canvas 绘制（每幅固定 32 个低密度元素），无图片纹理、外部素材或网络下载。新增图片/字体资源为 **0 文件、0 字节**；增加少量 Dart 绘制代码，未构建 APK，故没有 APK 增量实测。

ThemeBackgroundSurface 统一负责渐变、原图片 opacity 和新纹样。聊天背景、主题大预览、背景缩略图共用同一组件；纹样按同一 360×780 构图 cover 裁切，不在缩略图伪造样式。旧缩略图原来未应用 opacity，现在与真实背景一致。

## B. 群聊主页面

- 增加群头像/占位图标、群名称与人数双层 AppBar，长群名省略，随文字缩放调整高度。
- 保留角色头像和成员昵称；昵称增加浅色衬底，在深色背景上清晰可读。连续消息省略重复身份的既有逻辑不变。
- 时间提示、系统提示、正在输入提示增加清晰柔和衬底。
- 输入区使用圆角浅卡片、轻边缘阴影、蓝紫按钮；@ 仍保留在输入框旁，所有回调不变。
- 空状态改为可滚动轻卡片，避免键盘挤压时固定高度溢出。
- 原有 ChatBubbleSurface、ThemeBackgroundContainer、ChatMorePanel 继续复用；不替换群聊的引用、@、发送状态、重试等逻辑。
- 群聊刻意保留成员身份、人数、@、引用与角色头像入口，不复制成没有身份层次的单聊。

## C. 群聊设置页

原页已有基础分组，但白色容器、原生管理列表与低层次身份入口不统一。现在使用共享 GroupVisuals 的浅背景、22 圆角、轻边框和柔影：

1. 顶部群名/人数及横向头像列，支持多成员横向滚动；不改变成员顺序。
2. 群聊身份图标 + 当前群昵称摘要，小型入口而非 Banner。
3. 群名称、免打扰、置顶保留，长文本转为可换行副信息，避免右侧摘要挤压标题。
4. 清空记录使用温和警示色与说明；删除退出独立红色卡片，保留原二次确认。
5. 开关使用主题强调色，卡片内 Material 保证点击涟漪可见；底部留出系统安全区。

## D. 群成员管理

头像 + 昵称（最多两行）+ AI/用户辅助说明 + 右侧自定义勾选/锁定图标，取消 CheckboxListTile 样板视觉。弹层保留 72% 屏高、内部滚动与完成操作。

用户单独显示为固定成员，无 onTap；不会加入 selected AI ID 集合。完成按钮仍采用原 selected.length >= 2 条件，旧 GroupMember 复用/新增规则完全保留；测试确认减少到一名 AI 时无法完成，用户不计入这两名。保存成功显示轻量反馈。

## E. 群聊身份

头像卡、字段卡、页面色与设置页统一，继续支持群昵称、头像、身份说明与保存。加载期间暂禁保存按钮，避免空白界面误点；保存方法、字段和值来源未改。

GroupUserProfile 的 groupId/displayName/avatarPath/selfDescription/updatedAt schema 与存储服务没有变化。既有 loadResolved 只在缺省时读取全局 UserProfile 用于显示，不写回；没有读取某角色的 CharacterUserProfile，也没有修改全局资料、角色关系或身份作用域。

## F. 扩展面板

继续使用 AnimatedSize + ChatMorePanel 在输入栏下方就地展开，未改成 BottomSheet。增加群聊专用可选 highlightPersona 视觉参数，默认 false，不改变单聊样式或功能。

“我的群聊身份”使用浅紫图标块突出。相册、红包、让 Ta 换头像、礼物、文件、虚拟定位、音乐、语音/视频通话保持 disabled，无 ComingSoon 或新业务回调。面板设屏幕相关最大高度并允许内部滚动，输入框获得焦点仍关闭面板。

## G. 本轮修改文件

- lib/theme/theme_background.dart
- lib/theme/app_theme_background.dart
- lib/theme/theme_background_surface.dart（新增）
- lib/pages/peilink/theme_decoration_page.dart
- lib/pages/peilink/group_chat_page.dart
- lib/pages/peilink/group_chat_settings_page.dart
- lib/pages/peilink/group_user_profile_page.dart
- lib/widgets/chat/chat_more_panel.dart
- lib/widgets/group/group_visuals.dart（新增）
- test/group_visual_polish_test.dart（新增）
- docs/release/ANDROID_BETA2_FINAL_VISUAL_POLISH.md（本报告）

工作区在开始前已有多个其他任务改动，本轮在其现状上修改，没有还原或覆盖那些业务改动。

## H. schema / storage

无持久化 schema、存储格式、路径或存储服务变更。ThemeBackground 的 pattern 仅为内存视觉属性，不写入持久化 JSON；仍只保存 backgroundId。

## I. G3.1～G3.5 保护

未修改 GroupConversationCoordinator、participation、character voice、group memory、reply target、planner/generateStep、上下文、模型调用次数、Relationship、Life Engine、Echo 或 API。

开始时记录 240 个 lib/services 与 lib/models 文件 SHA-256，完成后全部一致。群聊页面主 build 前的加载、发送、回复、引用处理、导航及事件方法，去除格式化空白后与开始时相同。验证记录：build/visual_polish_protection.json。

这是本轮范围保护检查，不是 Beta2 最终封板审计；没有重跑 G3.4/G3.5 外部完整测试。

## J. 定向验证

- test/theme_background_test.dart：3 项通过（默认配置、层级、全部 built-in 绘制）。
- test/group_visual_polish_test.dart：5 项通过（旧背景/新增恢复、成员管理约束、主页面深色/键盘/就地面板、身份页、背景预览）。
- 为更新图标字体后的截图，额外执行其中 4 项页面用例，全部通过。
- 首轮设置页发现卡片 DecoratedBox 遮挡 SwitchListTile 的 Material 涟漪；已修复并通过复验，没有隐藏或吞掉异常。
- 对本轮 10 个源码/测试文件定向 analyze：No issues found。
- git diff --check：通过。
- 没有工具挂起、没有无限等待、没有 flutter clean、没有删除 .dart_tool/build。
- 没有执行完整测试、全项目 analyze、Android 构建或 release signing。

日志：build/visual_polish_tests.log、build/visual_polish_tests_final.log、build/visual_polish_preview.log、build/visual_polish_analyze.log、build/visual_polish_diff_check.log。

## K. 未验证项与预览

截图为 360×800 Flutter 测试画布（页面文字 1.3 倍），不是 Android 真机。已查看背景、主页面、面板、设置、管理和身份截图。测试画布的 Emoji 字形可能显示占位框，未改应用字体，须由设备最终确认。

预览：

- build/visual_polish_backgrounds.png
- build/visual_polish_chat.png
- build/visual_polish_panel.png
- build/visual_polish_settings.png
- build/visual_polish_members.png
- build/visual_polish_identity.png

未做真机状态栏/导航栏、实际软键盘、头像选择系统相册、2 倍以上字号、长列表流畅度和 Android Emoji 字形验收。未发送消息触发模型，也未清空或删除真实数据；未构建 APK，资源包增量未实测。

## L. 建议真机检查的七处

1. 装扮背景网格与聊天背景：新纹样密度、缩略图一致性、原选择是否保留。
2. 深夜蓝灰背景：昵称、时间、系统提示、正文与 Emoji 是否清晰。
3. 长群名/长角色名及多成员：AppBar、省略/换行、头像横向滚动及管理入口。
4. 输入栏 + / @：就地展开、收起、键盘切换，面板不盖住输入框。
5. 群聊设置：身份摘要、开关点击效果、清空和退出的危险分级及二次确认。
6. 成员管理：用户锁定、选中状态、少于两名 AI 不可完成、多人列表滚动。
7. 我的群聊身份：头像选择、昵称/说明编辑、键盘下保存可见，以及不同群仍各自独立。

至此停止，等待用户真机截图反馈；不自动进入 Beta2 最终封板。
