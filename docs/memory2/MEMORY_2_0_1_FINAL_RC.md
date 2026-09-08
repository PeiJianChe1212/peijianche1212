# Memory 2.0.1 Final RC

日期：2026-09-04。

最终判定：**PASS WITH KNOWN LIMITATIONS**。

Memory 2.0.1 正式冻结。本次 Hotfix 2 的真实 E / F、剩余 Source 实机验收、47 个文件的 363 项最终安全回归全部通过。保留本文列出的证据边界，不把受控样本成功解释为所有 Provider 永远可靠。没有 commit 或 push。

## 版本范围

第一批：直接保存意图绕过普通 8/3 阈值，复用 Event pinned / User confirmed 保护；显式失败标记与有限恢复；UserMemory 变化保留 superseded 历史关系，普通与历史召回分离，Memory Center 提供确认状态与历史入口。

第二批：按需解析 sourceMessageIds、来源预览与不可用降级；从最近 100 条中选择最多 16 条、12,000 字符重新整理；本地内容边界防止引用、资料、代码、视觉描述错误归因；重处理不破坏普通 cursor 或显式状态。

Hotfix 1：Retriever 对已知结构化 key 提供确定性本地别名。覆盖颜色、食物、饮品、游戏、爱好、忌口、习惯、称呼八组；精确匹配 key 组，并要求问句具有主题及个人事实信号。未知 key 保持原词面匹配。未降低 relevance 阈值，未使用 embedding 或模型检索，未改变 current / historical 状态门控、数量和检索预算。

Hotfix 2：只修改 Memory2ChatContextBuilder 的事实优先级呈现。声明 Summary 是可能滞后的概括，即使包含“目前”也不能压过 active 事实；在原记忆文本之后，对本次已经 selected 的 active UserMemory 单独显示“当前用户事实”区块。保留用户手写角色世界设定的更高优先级。

## 阻断历史与本次只读审计

此前经历了三种不同结果，不能混为同一问题：

1. 原始 E：currentCount=0，结构化英文 key 与中文问题的词面匹配失败，Provider 回答旧颜色。Hotfix 1 已修复检索问题。
2. Hotfix 1 后首次 E：currentCount=1、绿色已注入，但 Provider HTTP 200 / finish_reason=length / 正文 0 字，触发 ChatEmptyResponseException。这是截断空响应。
3. 后续 E：检索仍正确，Provider HTTP 200 / stop / 正文 54 字，但最终回复出现橙色而没有绿色。问题转为当前事实已召回后的 Prompt 冲突处理。

Hotfix 2 修改前，在全新虚构数据目录中运行正式 DeepSeekService → ContextBuilder → PromptComposer → Provider 请求组装。HTTP 边界使用本地假响应截取元信息，没有真实模型调用，没有输出完整 Prompt。

| 审计项 | 实际结构与证据 |
| --- | --- |
| 最终 system 顺序 | 基础事实 → peilink_v2_core → memory2_context → conversation_provider_adapter；随后单条 user 问句 |
| Summary 位置 | Memory 内先呈现“长期记忆汇总” |
| active UserMemory 位置 | 随后呈现“关于用户的记忆” |
| 原优先级规则 | Memory2ChatContextBuilder 开头的普通说明文字；不是程序级冲突处理 |
| 旧 Summary 片段 | 肯定句“用户目前最喜欢橙色。” |
| active 呈现 | `- favorite_color：绿色` |
| 其他橙色来源 | Memory 外 0 次；对话消息内 0 次 |
| 其他干扰源 | selected Legacy=0、Event=0；虚构 CharacterUserProfile 为空；本次请求只含当前问句，没有带入旧聊天 |

这次虚构请求中，旧事实的当前表述仅来自 Summary。未将其他 current 来源误判为 Summary 问题。

## 最小修复选择

选择方案 A：Prompt 优先级强化与明确的当前事实区块。没有实施方案 B 的语义冲突检测，也没有按关键词删除 Summary 句子。

原 Summary 文本、非冲突内容、正确历史描述均保留。当前事实区块仅从 selectedUserMemories 中过滤 active 条目，最多 4 条，每条展示最多 180 字，不重新读取整个 Memory，也不把 superseded 提升为 current。

原 Retriever 的 2,600 字符预算、4 条 current、2 条 historical 上限不变。Context Builder 新增了有界的当前事实重复呈现及说明，因此最终 Prompt 会增加少量字符；没有宣称整个最终 Prompt 仍严格等于 Retriever 的预算。

新增 7 项离线测试覆盖：当前冲突；非冲突 Summary 保留；正确历史描述保留；多个 active 事实；无 selected active 时仍保留 Summary；historical recall；新增当前事实区块的数量与长度边界。专项 62/62 通过。

## 虚构环境与证据类型

旧临时环境已清理。本次通过正常 Memory2Engine、ChatStorageService 和 Summary 编辑入口重建相同语义状态；不调用 Extraction，不把重建当成新的 A/B/C/D 真实提取验收。

- A：橙色，superseded，来源 old-source。
- B：绿色，active / userConfirmed=true，来源 change-source。
- A.supersededById 指向 B；B.mergedFromIds 包含 A。
- Summary 始终包含旧橙色，不自动重写。

重定向整个文档根目录到全新虚构缓存，虚构 registry、角色及用户资料均独立。仅复用现有 Provider 凭据，没有读取或替换私人 Profile、私人聊天或其他角色 Memory。关闭正文诊断，不记录 API Key、完整 Prompt 或推理正文。

E / F 使用正式单聊服务与真实 Provider，不是从 ChatPage 手工键入的全 UI 端到端测试。Source 验收使用正式 Memory Center UI。上轮 A/D 使用已落盘的虚构 user / assistant 短窗口调用正式提取服务，B/C 由正式重新整理 UI 触发真实提取；这些证据继续沿用，未重复消耗调用。

## 真实 Provider E / F

Provider：DeepSeek，主机 api.deepseek.com，模型 deepseek-v4-flash-vision-exp。沿用原聊天参数，max_tokens=520，没有为了验收提高输出上限。

| 项目 | E 当前问题 | F 历史问题 |
| --- | --- | --- |
| 问句 | 我现在最喜欢什么颜色？ | 我以前最喜欢什么颜色？ |
| HTTP / finish_reason | 200 / stop | 200 / stop |
| Provider 正文字数 | 3 | 19 |
| currentCount | 1 | 1 |
| historicalCount | 0 | 1（不超过 2） |
| active 绿色 selected / injected | true / true | true / true |
| superseded 橙色作为 current | false | false |
| historical 橙色 | 未选择 | 已选择，附当前绿色 |
| stale Summary | 仍保留橙色 | 仍保留橙色 |
| 回复语义 | 当前为绿色，不含橙色 | 明确以前橙色、现在绿色 |
| 结论 | PASS | PASS |

F 的 superseded 选择经既有 historical intent 门控，未绕过状态限制。没有重复加 Prompt 或反复试到通过：本次只有一个生产修复版本，E/F 各调用一次，均首次通过。

## Source 实机验收

正式 Memory Center 主列表显示当前绿色及确认保护；管理区历史列表显示橙色为已被替代事实。

| 操作 | 结果 |
| --- | --- |
| 查看当前 B 来源 | 解析 change-source，预览是明确变化依据；时间、聊天文字类型正常 |
| 查看历史 A 来源 | 解析 old-source，预览仍是旧颜色依据；未被 B 的来源覆盖 |
| 清空仅虚构角色聊天 | Chat 为空；全部 UserMemory 序列化字段比较完全相同 |
| 再查看 A 来源 | 显示“原始来源已不可用”，无错误 |
| 再查看 B 来源 | 同样正常降级，不删除 Memory |

比较包含 id、value、createdAt、sourceMessageIds、status、userConfirmed、isPinned、supersededById、mergedFromIds 等字段。没有在 Memory 中新增聊天全文副本。清理后的来源预览不再依赖已删除的原件。

## 体验验收矩阵

| 场景 | 结果 | 证据类型 |
| --- | --- | --- |
| Explicit-important retention | PASS | 前轮真实 A + 本次完整离线保护回归；未声称已观察真实 90 天留存 |
| Ordinary-event forgetting 未被破坏 | PASS | Lifecycle 离线 30/60/90 回归，生产逻辑未改 |
| False attribution | PASS | 前轮真实 B + Content Boundary 离线回归 |
| Current fact recall | PASS | 本次真实 E，保留 stale Summary |
| Historical fact recall | PASS | 本次真实 F + 历史门控回归 |
| Duplicate reprocessing | PASS | 前轮真实 C 返回合法 empty，原有数量、保护、来源及 cursor 不变；非空去重由离线测试覆盖 |
| Source traceback | PASS | 前轮显式来源 UI + 本次 A/B 当前与历史来源 UI |
| Missing source degradation | PASS | 本次实机清空虚构原件，Memory 保留且 UI 正常降级 |

图片 / visionDescription 边界使用第二批及本次完整离线 Fake/Mock 证据，本次未调用真实 Vision。

## 调用账本

| 阶段 | 显式提取 | 重新整理 | 聊天 | 合计 |
| --- | ---: | ---: | ---: | ---: |
| 最初 A/B/C/D/E | 2 | 2 | 1 | 5 |
| Hotfix 1 后 E 截断空响应 | 0 | 0 | 1 | 1 |
| 后续 E 正常正文但旧事实 | 0 | 0 | 1 | 1 |
| 本次 Hotfix 2 E/F | 0 | 0 | 2 | 2 |
| Memory 2.0.1 RC 各轮累计 | 2 | 2 | 5 | 9 |

本次真实调用共 2，重试 0；Extraction / Summary / Vision / Retriever 模型调用均为 0。修改前请求组装审计的本地假响应不计入真实调用。该账本不包含更早 Memory 2.0 基础版本的独立验收。

## 最终回归

47 个测试文件，**363 项通过，0 失败**，Flutter 测试结果 success=true。

覆盖 Memory 2.0 Final RC、第一/二批、两个 Hotfix、Explicit Remember、Auto Extraction、User history、current/historical Retriever、Source Resolver、Reprocessing、Content Boundary、Lifecycle、Summary、Legacy、.pei v1/v2、Context/Prompt、Character/Profile/CoreBridge、Memory Center。

- `flutter analyze --no-pub`：No issues found。
- `git diff --check`：通过。
- `physical_release_isolation_test.dart`：沿用历史已知挂起处理，不列入本次通过数量，没有修改或弱化该测试。
- Legacy / .pei schema / Lifecycle / Physical / Source / Reprocessing / Retriever alias 均未在 Hotfix 2 修改。

## 工作树分类与清理

开始时记录 git status 和完整 diff。工作树包含既有第一/二批、Hotfix 1 及其他历史开发差异，不把这些列为 Hotfix 2 新改动。

Hotfix 2 持久交付仅三项：

1. 修改 `lib/services/memory2_chat_context_builder.dart`。
2. 新增 `test/memory201_summary_priority_test.dart`。
3. 新增本报告 `docs/memory2/MEMORY_2_0_1_FINAL_RC.md`。

与开始基线相比，其他已跟踪文件的 diff 完全一致。临时验收入口及虚构缓存已删除，Dev 正式入口已重新安装，端口转发已移除，本次启动的模拟器已关闭。没有提交、推送或改动用户私人资料。

## Known limitations

- 本次采用 Prompt 权威呈现，不是确定性语义冲突消除；没有证明任意 Summary 和任意模型永不出错。单一 Provider、单组 E/F 不能构成统计可靠性结论。
- 前轮确有一次 Provider 截断空正文，本次两次成功不抹除该稳定性历史；没有扩大为 Provider 修复。
- 当前事实核对区块有界重复 selected active 内容，增加少量 Prompt 长度；不会把全量 UserMemory 注入。
- Alias 仅覆盖已知小范围 key，未知事实类型仍可能依赖原词面匹配；不自行扩充 NLP 系统。
- 不自动清除或刷新旧 Summary；非冲突信息与正确历史句子保持可用。
- 来源仍依赖聊天原件；原件删除后按设计显示不可用，不恢复原文。
- 真实图像归因、长时间留存及所有聊天 UI 交互不在本次真实样本范围内，相应功能证据已明确区分为离线或服务链路。

## 冻结

Memory 2.0.1 正式冻结。不得因理论完善继续新增 Maintenance Engine、自动 Summary、embedding、向量数据库、Source 第四层、审核层或 Memory 3.0。

只有真实 PeiLink 使用中出现具体 Memory 体验问题，才重新讨论解除冻结。本次工作至此结束。
