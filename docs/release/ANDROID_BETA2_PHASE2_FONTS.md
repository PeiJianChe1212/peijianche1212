# Android 第二轮内测 Phase 2：字体链路审计与修复

日期：2026-09-10。

## 结论与未完成项

已修复“缺失字体仍可选择且伪装成真实预览”的问题，保护聊天正文、代码与系统文本的字体边界。**没有完成五种真实字体效果**：项目没有任何可用于聊天正文的字体资源，按要求没有下载或从本机系统复制字体。四种装扮字体的真实预览/应用，必须等项目提供含中文 glyph 且可分发的本地字体后完成。不能用 fontFamily 字符串测试通过代替真实字体加载与视觉验收。

## 根因与完整链路

1. 搜索项目源资源以及包含构建目录的 ttf/otf/ttc/woff/woff2 文件，只有构建产物中的 MaterialIcons 与 CupertinoIcons 图标字体；没有聊天字体。user debug 的 FontManifest.json 同样仅注册两个图标字体。
2. pubspec.yaml 的自定义 fonts 配置只是注释示例，没有实际注册。
3. 五个 UI 选项原本确实有不同 family：PingFang SC、FZKai-Z03、KaiTi、YouYuan、Consolas，但只是设备字体名称，并非包内资源。
4. _FontChoice 的原示例 TextStyle 已读取各自 family 和 fallback；TextMessageRenderer 原本也已读取当前 family。根因不是漏传字段，而是 Android 无法从应用包找到这些字形。
5. PeiLinkAppearanceController.setFontTheme 更新内存、notifyListeners、保存 fontThemeId；文件是应用文档目录 peilink_appearance.json。
6. main.dart 启动时调用 load，并在 MaterialApp 外包裹 PeiLinkAppearanceScope；页面及正文读取该 InheritedNotifier。正常 IO 条件下保存、重载、即时刷新链路存在且测试通过。
7. 作用域为 A：全 App 用户级。无角色/会话 ID；切换角色共用同一选择。本轮未改作用域、字段、存储服务或格式。
8. 单聊用户与角色均经过 MessageRenderer → TextMessageRenderer；图片附带的文字也复用该渲染器。
9. 群聊使用 group_chat_page.dart 私有 _GroupMessageBubble / _Bubble，未复用单聊文本组件，未读取字体装扮。本轮遵守不改群聊的边界，没有替换它。
10. 原 TextMessageRenderer 没有 Markdown 渲染器，代码也是普通原文；本轮只把反引号行内代码、反引号/波浪号围栏代码隔离为 monospace，保留原文与标记，不引入 Markdown UI。

## 字体资源与映射

| UI 名称 | ID | 原 family | 当前声明 family | 当前实际处理 |
| --- | --- | --- | --- | --- |
| 清爽黑体 | system | PingFang SC | sans-serif | 使用设备系统无衬线，正常预览“今天天气真好呀～”；与 App 原全局默认 family 一致 |
| 硬笔行书 | hard_pen | FZKai-Z03 | FZKai-Z03 | 缺资源，禁用选择，显示暂无预览；旧选择有效渲染回退 system |
| 楷体 | kai | KaiTi | KaiTi | 缺资源，禁用选择，显示暂无预览；旧选择有效渲染回退 system |
| 温柔圆体 | gentle_rounded | YouYuan | YouYuan | 缺资源，禁用选择，显示暂无预览；旧选择有效渲染回退 system |
| 科技字体 | tech | Consolas | Consolas | 缺资源，禁用选择，显示暂无预览；旧选择有效渲染回退 system |

未以字号、字重、颜色或字距伪造不同字体。保留旧 ID 与 family 声明用于兼容；effectiveFont 明确返回可用系统字体。已保存的缺失字体在装扮卡片显示“已选字体资源缺失，当前使用系统字体”，不会自动改写旧选择。推荐页的字体卡也复用同一可用性判断，其聊天文字预览使用 effectiveFont。

中文覆盖：**没有任何项目内聊天字体可宣称完整中文支持**。清爽黑体依赖 Android 系统中文字形与系统 fallback，不能保证所有 Unicode 汉字覆盖。其余四项连字体文件都不存在，无法读取 cmap 确认中文覆盖，更不能声称完整中文支持。科技字体的英文等宽名称与 monospace fallback 不能证明中文科技字形存在。

Fallback：旧五项均存在依赖设备字体/系统 fallback 的路径。原清爽黑体依赖 PingFang SC，现显式使用系统 sans-serif。四项缺失字体现在显式回退且 UI 告知；没有在真机抓取实际使用的字体文件，因此不声称测得某一设备上的具体 fallback 字体名称。图标字体不可代替中文正文资源。

## 应用与排除范围

- 应用：单聊 user / assistant 的普通正文、括号说明、图片附带纯文本；即时刷新继续通过现有 Scope。
- 排除：system/error 文本不消费装扮 family；代码使用 monospace。原独立系统消息、撤回提示、标题、按钮、弹窗、时间戳、用户名、状态标签均没有新增字体装扮。
- 群聊保持原行为（独立组件）。没有改气泡颜色/圆角/布局、背景、全局 ThemeData、Memory、Echo、Life Engine。
- 保存和重新 load 测试验证持久化；真正 App 进程重启、返回单聊的设备操作与中文 glyph 视觉验收未在真机执行。缺资源时无法验收四种真实字形切换。

## 本阶段修改文件

1. lib/theme/chat_visual_theme.dart：可用性声明、显式有效字体及系统默认 family。
2. lib/pages/peilink/theme_decoration_page.dart：缺资源说明、禁用缺失选项、真实可用预览、统一有效字体。
3. lib/widgets/chat/renderers/text_message_renderer.dart：正文 family、系统/错误文本排除、代码字体隔离。
4. test/chat_font_test.dart：新增字体目录/预览/持久化/即时通知/正文边界测试。
5. docs/release/ANDROID_BETA2_PHASE2_FONTS.md：本报告。

Phase 1 已有未提交文件未在本阶段修改。pubspec.yaml、字体配置存储服务、群聊与气泡组件未修改。

## 验证

- theme/chat/font/appearance/message 名称匹配的 12 个测试文件：56 项全部通过，含新增 7 项字体测试。
- 测试覆盖全部 ID 与 family 映射、缺资源阻止选择、可用字体预览、旧 ID 保存/恢复与其它装扮字段保留、UI 选择系统字体保存、user/assistant 即时更新、system/error 排除、代码等宽与原文保留、默认字体恢复。
- 正文测试使用 TestBodyFont 作为合成 family 验证字段传播，**该名称不是实际字体资源，不证明中文字形可用**。
- flutter analyze：无新增 lint/warning/error；退出码 1，仅 Phase 1 已记录的 memory2_storage_service.dart:290、298 两条原有 info；按本轮限制未修改 Memory 文件。
- Android user debug：通过，build/app/outputs/flutter-apk/app-user-debug.apk。
- Android dev debug：通过，build/app/outputs/flutter-apk/app-dev-debug.apk。
- git diff --check：通过。
- 本阶段未尝试正式 release。

日志：build/font_phase2_tests.log、build/font_phase2_analyze.log、build/font_phase2_user_build.log、build/font_phase2_dev_build.log。
