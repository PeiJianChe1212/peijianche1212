# Android 第二轮内测 Phase 3：气泡扩充与真实预览

日期：2026-09-10。

## A / B：架构与作用域

审计先于修改。主题由 lib/theme/chat_visual_theme.dart 的 ChatBubbleTheme / ChatVisualThemeCatalog 定义，尾巴枚举 ChatBubbleTailStyle 仅有 none / rounded。原模型包含双方颜色、统一圆角、尾巴；实际 MessageBubble 另外硬编码阴影与 padding，而装扮页预览另外硬编码边框，确实存在预览和实聊不同步风险。

PeiLinkAppearanceController 使用应用文档目录 peilink_appearance.json 的 bubbleThemeId 字符串保存，全 App 用户级，与 backgroundId、fontThemeId 同文件。setBubbleTheme 立即更新并通知，随后保存；main.dart 启动 load，通过 PeiLinkAppearanceScope 通知实聊刷新。没有角色/会话 ID 维度。本轮未修改控制器、持久化格式、作用域、启动逻辑或消息业务。

## C / D / E：主题

原四款保持 ID、顺序、双方颜色、圆角和尾巴配置：

| 名称 | 稳定 ID | 实现 |
| --- | --- | --- |
| PeiLink 蓝蝶 | minimal | 蓝紫用户色，浅白角色色，18 圆角，有尾巴 |
| QQ圆润款 | qq_rounded | 粉色用户色，浅白角色色，18 圆角，有尾巴；默认不变 |
| 云朵款 | soft_cloud | 淡蓝用户色，浅白角色色，22 圆角，有尾巴 |
| 玻璃款 | glass | 原有半透明蓝白填充，16 圆角，无尾巴；原本就是透明色而非背景模糊 |

新增五款追加在原四款之后：

| 名称 | 稳定 ID | 视觉特征 |
| --- | --- | --- |
| 纸笺 | paper_note | 暖纸色，8 圆角，细暖灰边框，贴纸式低模糊下投影，无尾巴 |
| 奶糖 | milk_candy | 柔粉/淡紫，28 大圆角，浅白边缘，柔软宽阴影，有尾巴 |
| 极简线框 | minimal_outline | 接近白色底，12 圆角，1.2 细灰蓝边框，无阴影/尾巴 |
| 微光 | soft_glimmer | 淡青/浅蓝，18 圆角，白色细边框，低饱和柔和边缘光与轻投影，无尾巴 |
| 手账 | journal_card | 浅绿/暖纸色，3/16/16/6 不对称圆角，左右镜像，细边框与右下硬质浅投影，无尾巴 |

没有新增夜幕款，五款都沿用深色正文，不触及全局深色模式。没有图片、纹理素材或网络下载。

## F / G：消息类型边界

- 单聊 user / assistant：继续 MessageRenderer → MessageBubble，字体与内容渲染器不变。
- text：应用气泡主题。
- image：原设计已使用同一外壳，继续应用；内部图片裁剪、尺寸与失效提示不改。
- voice / card：现有代码回退为文本渲染，继续原有气泡范围；没有新增专用语音/文件卡片业务。
- redPacket：继续专用红包卡片，外壳透明、无普通主题装饰/尾巴、零 padding。
- system：MessageRenderer 原有独立提示布局绕过气泡。
- error：保留红色提示底与原有行为，不套新增装饰。
- recalled：原有撤回文本/收藏/主动消息标记条件保持原样。
- 引用：单聊当前统一渲染路径没有独立引用组件；群聊的 quotedMessage 属于独立 _GroupMessageBubble / _Bubble，与这里的主题无关，没有修改。
- 群聊：不共用此主题，保持原样。没有改变 API、Life Engine、Memory、Echo 或其它页面。

## H：预览复用

ChatBubbleTheme.decoration(isUser: ...) 是双方颜色、边框、阴影、圆角的唯一来源。ChatBubbleSurface 为实聊与预览共同渲染外壳，复用尾巴 painter、margin、padding 与 decoration。

MessageBubble 继续负责长按、宽度上限（屏宽 72%）和原有消息标记，只将纯视觉外壳交给 ChatBubbleSurface。MessageRenderer 完全未修改。

装扮页每卡显示主题名称、简短特征、选中标记，以及左“今天过得怎么样？”、右“还不错呀～”两条消息。BubbleThemePreview → _PreviewBubble → ChatBubbleSurface，主文字大小/颜色与聊天正文一致，选中底色不改变气泡文字色。没有头像、时间戳或用户名。推荐页已有预览同步改用该外壳，背景绘制不变。

## 可读性与布局检查

- 全九款双方主正文颜色（现有 #171717）与气泡颜色在黑/白/深蓝背景上按透明度合成后，对比度测试均 >= 4.5:1；没有白字或高饱和渐变。
- 320 宽窄屏下，双方长中文、标点、Emoji 和括号内容正常换行，无布局溢出。
- 短预览气泡按内容收缩，无固定最小宽高；选择页卡片采用两行紧凑预览。
- 已渲染并人工检查九款共享预览组件截图 build/bubble_phase3_preview.png，含真实阴影；这是桌面 Flutter 测试画布，并非 Android 真机截图。仅截图时读取本机字体显示中文，未复制或注册到应用。
- 上述对比度断言针对主正文；没有把已有次要标签的颜色调整扩大到本轮。未声称所有设备、所有图片背景的真机视觉验收已完成。

## I：本阶段修改文件

1. lib/theme/chat_visual_theme.dart：扩展气泡视觉属性、统一 decoration、新增五款；字体部分未改。
2. lib/widgets/chat/chat_bubble_surface.dart：新增共用视觉外壳，复用旧尾巴 painter。
3. lib/widgets/chat/message_bubble.dart：使用共用外壳，保留业务和宽度/padding 规则。
4. lib/pages/peilink/theme_decoration_page.dart：双消息真实预览与选中标记，字体/背景功能未改。
5. test/chat_bubble_theme_test.dart：新增 7 项气泡验收测试。
6. docs/release/ANDROID_BETA2_PHASE3_BUBBLES.md：本报告。

前两阶段已有未提交变更保留；本阶段未修改其 Memory 文件、字体资源、字体渲染器或字体测试。

## J / K：测试与构建

- 13 个 theme/chat/bubble/appearance/message 相关测试文件，63 项通过。
- 新增覆盖：旧 ID/顺序/颜色/圆角，九款保存和重载，即时通知，字体/背景字段保留，真实外壳与预览 decoration 相等，双方即时应用，窄屏长文本，主正文对比度，系统与红包排除，以及选择卡预览/标记。
- flutter analyze：无新增 lint/warning/error；仅原有 memory2_storage_service.dart:290、298 两条 info，退出码 1；没有修改 Memory 消除旧提示。
- Android user debug：通过，build/app/outputs/flutter-apk/app-user-debug.apk。
- Android dev debug：通过，build/app/outputs/flutter-apk/app-dev-debug.apk。
- git diff --check：通过。
- 未执行正式 release；真实进程重启及真机返回聊天操作未单独执行，恢复与刷新由控制器和 Widget 测试验证。

日志位于 build/bubble_phase3_tests.log、build/bubble_phase3_analyze.log、build/bubble_phase3_user_build.log、build/bubble_phase3_dev_build.log。

## L：index 兼容风险

没有发现 index 型配置：存储和读取都使用 bubbleThemeId 字符串，列表位置不参与恢复。旧四款 ID 和顺序都保留，新款仅追加；无 schema 变更或迁移。
