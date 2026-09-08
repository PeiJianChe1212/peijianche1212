# Memory 2.0 Final RC

日期：2026-09-04。结论：**B. Memory 2.0 Final RC PASS WITH KNOWN LIMITATIONS**。

核心 Memory2 功能、角色隔离及当前聊天主路径没有发现已知阻断缺陷，可进入长期体验。历史两次无回复仍无法追溯归因，不能写成已修复。本轮只增加回归证据和维护文档，没有修改生产代码。

## 两次历史聊天未回复：调查结论

| 阶段 | 现有实现与证据 | 结论 |
| --- | --- | --- |
| Provider 请求前 | DeepSeekService 对 Retriever 异常降级；新增 throwing Retriever 测试仍发送 1 次请求 | 未发现异常型 Memory2 阻断 |
| 请求中 | Provider 有 HTTP 状态检查及 45 秒超时 | 网络/服务失败可导致无正常回复；不是历史原因证明 |
| 返回解析 | 空正文、非 JSON、异常结构会抛错；新增 HTTP200 空正文+reasoning、malformed JSON、503 故障注入 | 不伪造正常回复；历史没有相应原始证据 |
| assistant 持久化 | ChatPage 分段逐次保存；保存失败返回 false；页面销毁可终止后续分段 | 存在既有失败边界，未扩大修改 |
| Recall | 异步记录；新增未完成 Future 测试确认调用过且仍返回聊天结果 | 不等待 Recall 保存完成 |
| 自动提取 | 全部分段保存成功后 unawaited 启动 | 不能反向阻塞已落盘回复 |

代码位置：`chat_page.dart` 的 `_requestReply/_saveMessages`，`deepseek_service.dart` 的检索降级、最终 Prompt 与异步 Recall，`openai_compatible_chat_provider.dart` 的 HTTP/解析验证。异常可降级不等同于所有本地 I/O 永不挂起；本轮未发现实际挂起证据。

### 最小真实复现

执行前已说明最多 2 次普通聊天。本轮只使用模拟器既有纯虚构测试角色与临时虚构全局资料；通过只读调试断点记录白名单元数据，没有导出 raw full response 或密钥。

| 请求 | HTTP | finish_reason | content 字符数 | reasoning 字符数 | 持久化 |
| --- | --- | --- | --- | --- | --- |
| 1：虚构剧情/PVE 偏好，要求简短回复 | 200 | stop | 23 | 872 | assistant 分段 1 已保存 |
| 2：简短问候 | 200 | stop | 6 | 1022 | assistant 分段累计 2 已保存 |

两次 maxTokens 参数均为 520；上述字符数不是 Token 数。两次用户消息未达到自动提取最低用户条数，没有产生 Extraction cursor。

调用账本：Chat 2，Extraction 0，Summary 0，Retriever 0；未使用真实语音、ESP32 或 Physical。断点及端口转发已移除；模拟器中全局资料由备份恢复，重新读取逐字节比对通过，本轮启动的模拟器已退出。报告不包含原始全局资料正文。

**历史两次失败仍为未知归属。** 两次受控成功只证明当前路径在这两次运行中正常，不足以追溯否定历史 Memory2 问题，也不足以给 Provider 定责。

## UI 验收

| 项目 | 证据 | 结果 |
| --- | --- | --- |
| active | 真实 MemoryPage widget，无 Opacity 包装 | 通过 |
| fading | 实际 Opacity=.78，与 active 不同 | 通过 |
| pendingForget | Opacity=.62，分区提示“以下记忆逐渐模糊” | 通过；该分区属于 pendingForget，不误报成 fading 分区 |
| forgotten | 普通列表隐藏，管理页显示并可恢复至主列表 | 通过 |
| pinned | 操作后固定图标及“取消固定”菜单变化 | 通过 |
| Summary 编辑 | 既有 Memory Center / Summary / 数据安全回归，本轮全量重跑 | 通过 |
| Legacy 已迁移 | 既有真实页面预览/确认/已迁移标签回归，本轮重跑 | 通过 |
| 内部错误 | 人工注入异常哨兵，仅显示通用保存失败提示，页面无哨兵、无未处理异常 | 通过 |

渲染截图使用测试字体，中文是方块，未作为完整字体和屏幕适配像素验收。没有重新设计 UI。

## 最终边界复核

- 自动记忆：单批一次提取，cursor 成功规则保留，不写 Legacy，不产生新 Pending，不恢复二审。
- Recall：本地检索，7.5 主题切换与扩展规则不变，forgotten 排除，仅最终注入的 Event 计数。
- Summary：手动生成，用户编辑优先，旧预览不能覆盖新编辑。
- Legacy：用户预览确认，原文件保留，幂等去重，未知不猜，零模型调用。
- .pei：默认 v1 纯角色；v2 显式含记忆；运行时资料排除；完整验证后注册，失败不留已注册半成品。
- Physical：生产代码未改，挂起测试未删、未弱化；其余 fake/mock 纳入离线回归。

## Sol / Luna

Sol 负责阶段归属判断、真实 Provider 最小复现、资料恢复核对、源码与所有新增测试 review、全量验收和最终决策。Luna 分别完成只读错误链路复核、4 项聊天故障注入测试、3 项 UI 测试。Sol 要求并复核 Recall 测试确实调用 recordInjectedEvents，UI 测试确实验证操作后状态变化，避免只验证回调的假通过。

## 最终回归

104 个测试文件，**609 项通过，0 失败**，完整运行退出码 0。新增 7 项包含在 609 中，不重复计数。覆盖 Memory2、Context Builder、Prompt Composer、Character/Profile/CoreBridge、.pei、Legacy、删除/数据安全及其他安全离线测试。

唯一整文件排除：`test/physical_release_isolation_test.dart`，原因是用户明确允许排除的历史挂起。本轮未为全绿修改它，不声称“全仓无排除通过”。Fake/Mock 使用无效域名和注入客户端，未调用真实 Provider。

`flutter analyze --no-pub`：No issues found，退出码 0。`git diff --check`：通过。生产代码差异为空。

## 工作树与交付

开始工作树干净，基线 cca1a61；此前 Memory2 和 Physical 属于已有提交内容，不是本轮待提交修改。本轮仅新增下列文件，无生产文件改动：

```text
?? docs/memory2/FINAL_RC_REPORT.md
?? docs/memory2/FINAL_TECHNICAL_BASELINE.md
?? test/memory_final_closure_chat_test.dart
?? test/memory_final_closure_ui_test.dart
```

普通 `git diff --stat` 无输出（新增文件未暂存）；没有恢复、删除或覆盖历史工作，无 commit/push。详细维护基线见 `FINAL_TECHNICAL_BASELINE.md`。

## 已知限制与停止条件

保留：历史两次无回复证据缺口、页面退出/磁盘失败的既有聊天持久化边界、跨文件非断电事务、Physical 单项排除、UI 字体/全尺寸像素验收未全覆盖。本轮未发现足以判为 Memory2 BLOCKED 的可复现缺陷；上述限制不得改写为全面保证。

Memory2 正式冻结，后续仅响应真实 Bug、数据安全问题或明确新版本需求。本轮至此停止，不开始新功能、不展开全仓隐私审计。
