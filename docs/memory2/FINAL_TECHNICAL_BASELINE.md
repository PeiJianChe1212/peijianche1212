# PeiLink Memory 2.0 Final Technical Baseline

日期：2026-09-04。基线提交：`cca1a61`。判定：**Memory 2.0 Final RC PASS WITH KNOWN LIMITATIONS**。

Memory 2.0 可以进入长期实际体验。本轮没有确认需要修改生产代码的 Memory2 阻断缺陷；历史两次未回复的原因仍未确定。本判定不是对所有 Provider、网络条件或磁盘故障的无条件保证。

## 1. 最终架构

```text
ChatPage → 完整 assistant 分段保存成功 → unawaited 自动提取
  → AutoMemoryExtractionService → cursor / threshold / cooldown
  → Memory2ModelExtractor（至多一次模型请求）
  → Memory2Engine → 角色独立 Event / User 文件 → 成功 cursor

正式单聊 → DeepSeekService → Memory2Retriever
  → 惰性 Lifecycle refresh → 本地相关性与预算选择
  → CharacterUserProfile + Summary + User + Event + 必要 Legacy
  → Context Builder / Prompt Composer → Provider
  → 对最终注入 Event 异步记录 Recall（写入失败不阻断聊天）

Memory Center → 显式编辑 / 固定 / 恢复 / Summary 生成 / Legacy 预览确认
```

维护入口：`lib/pages/chat_page.dart`、`lib/services/deepseek_service.dart`、`lib/services/auto_memory_extraction_service.dart`、`lib/services/memory2_retriever.dart`、`lib/services/memory2_engine.dart`、`lib/services/memory2_storage_service.dart`、`lib/services/memory_center_controller.dart`。

## 2. EventMemory / UserMemory / 存储

EventMemory 保存具体共同经历：id、characterId、content、occurredAt、createdAt、updatedAt、sourceMessageIds、status、lastRecalledAt、recallCount、isPinned、sourceType、legacySourceId、metadata。

UserMemory 保存角色对用户的稳定认识：key/value、状态 active/superseded/archived、supersededById、mergedFromIds、userConfirmed、来源和时间字段。它不是全局 UserProfile 的覆盖写入接口。冲突优先级为 CharacterUserProfile > UserMemory > 全局 UserProfile；空值不输出“未填写”。

Memory2 使用角色作用域文件 `event_memories.json`、`user_memories.json`、`memory_summary.json`，容器 schemaVersion=2。读取降级与严格写入前读取分开，避免把损坏文件当空数据覆盖。角色内修改通过协调队列重新读取最新状态；旧 Legacy 文件不是自动提取的写入目标。

## 3. 自动提取

完整回复保存成功后才异步启动。阈值为 8 条有效消息且至少 3 条用户消息，冷却 10 分钟；使用 cursor 防止重复批次。每批至多一次 Extraction 请求，无 reason/importance/confidence、无二次模型审核，不制造新 PendingMemory。

接受纯 JSON、JSON/普通 fenced JSON、唯一完整目标对象外包少量文字；多个候选不猜测。eventMemories 和 userMemories 均必须存在且类型正确；不从自然语言补字段。解析/存储失败不推进成功 cursor；合法空结果可推进。明确稳定喜好、生活/互动习惯及完整共同事件可保存，普通闲聊和模型幻想不应保存。

## 4. Lifecycle

基准时间为 createdAt 与 lastRecalledAt 中较晚者；有效年龄再减 recallCount×3 天，最多减 30 天。有效年龄 <30 天 active，<60 天 fading，<90 天 pendingForget，其后 forgotten。固定记忆保持 active，但固定不绕过 Retriever 相关性。

refresh 是惰性执行，不新增 Timer。forgotten 是保留数据的状态，不是物理删除；普通列表隐藏，管理页可恢复。恢复更新参考时间但不增加 recallCount。真正 Recall 更新 lastRecalledAt、recallCount 并恢复 active；forgotten 不直接参与 Recall。

## 5. Retriever / Recall

纯本地检索，零模型请求、无 Embedding。当前消息权重为主要信号；仅模糊指代允许最近四条上下文辅助，近到远权重 0.30/0.14/0.08/0.04，取最大贡献而非累加。明确主题切换不使用历史扩展。Recall intent 提供轻量加成，不使完全无关事件通过门槛。

active/fading 按相关性进入；pendingForget 要求更高相关性；forgotten 排除。User 最多 4 条、Event 最多 3 条；Legacy fallback 共用相应名额，新结构重复优先，legacyUnclassified 默认不注入。Summary 使用 effectiveText。

Memory2 文本总预算 2600 字符；Summary 1200，User 单条 180，Event 单条 240，Legacy 单条 180。这里是字符预算，不是精确 tokenizer，也不是整个 Provider Prompt 的总预算。

只有最终组成发送上下文的 Event ID 进入异步 Recall。候选扫描、UI、Extractor hints、被预算裁掉的条目均不计数。该语义是“注入请求上下文”，不是“Provider 已成功回复”；请求随后失败时也可能已记录 Recall。Recall 保存失败不影响聊天主流程。

## 6. Summary

用户主动生成，非后台定时任务。generatedText 与 userEditedText 分离，effectiveText 优先用户编辑。生成预览不是无条件覆盖；保存时检查最新状态，旧预览不能覆盖后来用户编辑。每次显式生成至多一次模型调用。

## 7. Legacy / Archive

Legacy 必须用户主动预览、确认迁移；原 memories.json 保留，迁移无模型调用。来源 ID 用于幂等及避免已迁移内容重复 fallback；未知分类不猜测。历史 Pending 审核保留兼容入口，但自动链路不再产生它。

Archive 不是 EventMemory 的别名，不随此次收口删除、迁移或并入 .pei 记忆载荷。其他既有模块的读取边界维持原样，本轮未扩大接入范围。

## 8. .pei v1/v2

默认 v1 为纯角色导出；只有用户明确选择包含记忆才使用 v2。v2 可携带该角色 Legacy、Event、User、Summary，不携带聊天、Archive、Diagnostics、Extraction cursor/state、Provider/API 配置等运行时数据。

读取兼容 v1。含记忆导入先完整验证，再准备新角色数据，最后注册；失败清理未完成内容，不能留下已注册半成品角色。不会把旧 v1 描述成曾经包含 Legacy 的协议。

## 9. Diagnostics / 数据安全

Extraction 提供 rawResponseShape（pureJson/fencedJson/wrappedJson/invalid）和 parseOutcome。Retriever 提供候选选择/排除原因、当前 query 和历史扩展贡献、预算与注入信息。普通日志不保存 API key 或 raw full response。

删除角色清理其 Memory2 与相关角色数据，删除保护防止正在执行的异步提取重新写回角色；绑定校验防止跨角色混写。损坏文件、并发更新、删除及导入回滚有专项回归。跨多个文件的操作不是数据库级断电事务，仍是已知边界。

## 10. Provider 调用规则

- Retriever、Lifecycle、Legacy migration：0 次。
- Extraction：每批最多 1 次，无第二次审核。
- Summary：用户主动操作最多 1 次。
- 正式 Full 聊天没有质量二次请求；其他已有质量重试路径可能额外请求一次，不能把所有聊天统一宣称为永远一次。
- 自动提取在完整回复保存成功之后 unawaited 执行，不反向等待聊天；未达到阈值不请求模型。

## 11. Final Closure 验收

详细阶段证据见 `FINAL_RC_REPORT.md`。本轮两次真实聊天均 HTTP 200 / finish_reason=stop / 非空 content / assistant 已落盘；Extraction 0、Summary 0。全局用户资料先备份、再换纯虚构夹具，结束后恢复并逐字节核对一致；原始正文没有进入报告或测试请求。本轮启动的模拟器已关闭，无 Physical/语音调用。

104 个安全离线测试文件：609 项通过，退出码 0。包含 Memory2 全专项、Context/Prompt/Character/Profile/CoreBridge、.pei/Legacy/删除与数据安全，以及其他安全离线测试。唯一整文件排除项：`test/physical_release_isolation_test.dart`（约定的历史挂起，不改动、不弱化断言）。`flutter analyze --no-pub` 无问题；`git diff --check` 通过。

## 12. 已知限制与冻结

1. 历史 6 次聊天中 2 次未落盘缺少阶段证据；本轮 2 次成功不能追溯证明其原因或宣称修复。
2. ChatPage 销毁可能中止尚未显示/保存的后续回复分段；聊天保存失败可能导致已显示而未持久化。这是现有聊天链路边界，本轮未确认其造成历史两次失败，也未修改无关系统。
3. UI fading/pending 的实际透明度和恢复/固定操作通过 widget 测试；测试截图字体为方块，不能作为中文字体/所有屏幕尺寸的像素验收。轻微审美后续另议。
4. Physical 历史挂起测试明确排除，不声称全仓无排除通过。
5. 本地词法检索不是语义 Embedding；字符预算不是 Token 精确预算；跨文件操作非断电事务。

进入冻结：除真实 Bug、数据安全问题或用户明确的新版本需求外，不主动重构 Memory2。不开展新功能、全仓隐私审计或下一批开发。

## 13. 本轮文件与工作树

本轮开始 `git status --short` 和 `git diff --stat` 均为空，HEAD=cca1a61；此前 Memory2 与 Physical 内容已在该基线中，不能归为本轮新增差异。

Final Closure 仅新增四个文件：

- `test/memory_final_closure_chat_test.dart`（4 项故障注入测试）
- `test/memory_final_closure_ui_test.dart`（3 项 UI 状态/交互/安全提示测试）
- `docs/memory2/FINAL_TECHNICAL_BASELINE.md`
- `docs/memory2/FINAL_RC_REPORT.md`

无 lib/ 或 Physical 生产修改，无历史差异回滚，无意外差异，无 commit/push。以上四个文件交付时为 untracked；因此普通 git diff --stat 为空不等于没有新增文件。
