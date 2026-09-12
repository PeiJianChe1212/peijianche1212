# Phase 3.1：原四款气泡身份增强

日期：2026-09-10。

## 视觉结果

| ID | 结构调整 |
| --- | --- |
| minimal | 保留蓝紫品牌填充；14 中圆角、0.8 浅蓝紫边框、短翼形尾巴和克制投影。作为官方款的视觉定位；未改变已保存选择或控制器默认值。 |
| qq_rounded | 保留粉色用户侧；32 胶囊圆角、8×10 短圆尾巴、集中柔软投影，与蓝蝶的轮廓区别不依赖颜色。 |
| soft_cloud | 保留淡蓝/浅白；30/14/12/28 不对称圆角，左右镜像，无尾巴，18 模糊半径的低饱和扩散阴影。 |
| glass | 10 圆角、原半透明填充、1.3 浅白高光边框、斜向多段透明白高光与两层轻投影；使用 Decoration 模拟折光层次。 |

九款同规格预览已重新生成，840×750 逻辑尺寸、1.5 倍输出，即 1260×1125；字体、文案、排列、画布与 Phase 3 一致：

- 彩色：build/bubble_phase31_preview.png
- 灰度：build/bubble_phase31_grayscale.png

灰度由同一已渲染画面按亮度矩阵转换，不替换预览样式。已人工查看两图：四款可通过边框、尾巴、轮廓、阴影与高光区别。云朵没有尾巴且圆角不对称，QQ 保留规则胶囊和短圆尾；玻璃的角更明确，有亮边及可见高光层次。其余五款视觉定义未改。

## 玻璃实时模糊审计

ChatBubbleSurface 当前为 Stack（Clip.none），尾巴绘制在外侧，Container 的 BoxDecoration 自身不裁切背景。安全引入 BackdropFilter 至少需要将模糊限定在单个 ClipRRect 内，尾巴/阴影则留在外层；直接放入未裁切 Stack 会带来超出气泡区域的背景采样问题。

长消息列表中可能同时存在多个背景滤镜；当前没有共享滤镜分组，也没有目标 Android 设备的帧耗时证据，不能保证逐消息模糊不影响滚动。因此本轮采用纯 Decoration 模拟，不引入 BackdropFilter、ImageFilter.blur 或额外离屏裁切。此判断基于实现结构，**未声称已测得实时 blur 的具体性能损耗**。

## 复用与范围

ChatBubbleTheme.decoration 统一定义边框、圆角、阴影与玻璃 highlight 渐变。ChatBubbleSurface 使用该定义，并在原尾巴 painter 中追加短翼/短圆路径。预览仍直接使用 ChatBubbleSurface，没有新增预览专用样式。

保留 none、rounded 枚举原顺序，在后面追加 brandWing、softRound；旧 rounded 路径保留供奶糖使用。所有九款稳定 ID、目录顺序、持久化字段和默认值均不变。没有修改持久化、消息业务、字体、背景、Memory、Echo、群聊或其它页面。

本轮源码/测试修改：

- lib/theme/chat_visual_theme.dart
- lib/widgets/chat/chat_bubble_surface.dart
- test/chat_bubble_theme_test.dart
- docs/release/ANDROID_BETA2_PHASE31_BUBBLES.md（本报告）

仅 QA 预览脚本位于 build/bubble_phase31_preview_test.dart。读取本机字体只供截图，不随应用分发。

## 验收

- 13 个 bubble/theme/chat/appearance/message 相关测试文件：65 项全部通过。
- 预览生成测试：1 项通过。
- 新增四款非颜色结构差异与玻璃高光合成对比度测试；保留九款保存/恢复、真实预览复用、双方即时刷新、窄屏长文本和系统/红包边界覆盖。
- flutter analyze：无新增 lint/error，仅 memory2_storage_service.dart:290、298 两条原有 info，退出码 1。按要求未改 Memory。
- Android user debug：通过。
- Android dev debug：通过。
- git diff --check：通过。

日志：build/bubble_phase31_tests.log、build/bubble_phase31_preview.log、build/bubble_phase31_analyze.log、build/bubble_phase31_user_build.log、build/bubble_phase31_dev_build.log。

预览为 Flutter 测试画布，不是真机截图；本轮不做正式 release、持久化迁移或 Android 设备滚动性能基准测试。
