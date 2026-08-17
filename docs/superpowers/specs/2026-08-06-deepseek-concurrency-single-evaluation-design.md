# DeepSeek 单请求评分与导入受控并发设计

## 目标

- 作答提交从两次 DeepSeek 请求（润色、评分）降为一次评分请求。
- 在评分提示词中明确：回答可能来自设备端语音转文字，可能含同音字、漏词、错别字、断句错误；模型应结合上下文判断，但不能凭空补充事实。
- Markdown 题库导入的独立分块、50 题 refine 批次，以及 Others 重新分类的 50 题批次并发处理，默认最多 3 个 DeepSeek 请求同时进行。
- 保持 SwiftData 的状态变更和持久化在 `@MainActor` 串行完成，避免并发写入模型上下文。

## 方案

### 作答评分

`AnswerProcessingService` 直接创建 `EvaluationRequest`：

- `rawText` 保留用户原始文字（也是语音转写确认文本）。
- `polishedText` 不再调用润色服务，直接等于 `rawText`。
- `introducedClaims` 为空数组。
- 评分提示词新增 ASR 容错规则，并要求引用必须来自 `rawText`。

处理状态由 `saved → evaluating → completed/failed` 变化；不再创建 `PolishResultRecord`。已有历史数据继续保留，新的回答历史只创建评价记录。

### 题库导入

对每一阶段建立通用的有界并发执行器：

1. 在主 actor 上读取并冻结待处理 chunk/batch 的输入快照，同时把状态设为 `processing` 并保存。
2. 使用 `TaskGroup` 并发调用 AI 客户端，最多 3 个任务同时运行；任务只返回可编码的响应或错误，不触碰 SwiftData。
3. 主 actor 按返回结果更新对应记录、插入候选/题目草稿并保存。失败只标记对应 chunk/batch；阶段仍遵循现有“失败即暂停当前导入”的恢复语义。
4. 结果按 ordinal 排序后再 stage/activate，保证题目顺序和去重行为不受完成先后影响。

`decompose` 的 chunk 之间相互独立，可以并发；`refine` 的 50 题 batch 之间相互独立，也可以并发。`createRefinementBatches` 和 `activate` 仍保持串行。

`ReclassificationService` 的 50 题批次也使用同一并发上限。每个批次只在 AI 请求阶段并发；Topic 关系修改、失败计数、进度回调和最终 run 状态仍在主 actor 上按 ordinal 串行提交。

### 并发与限流

- 并发上限定义为常量 `3`，后续可从设置或配置注入。
- 单个请求仍由 `RetryingAIClient` 负责瞬时错误重试；并发层不重复重试。
- 收到限流或瞬时错误时，保留现有错误摘要和恢复入口，避免无限排队。
- 取消导入时取消 task group，未完成记录回到可恢复状态。

## 数据与兼容性

- `PolishResultRecord` 模型不删除，兼容已有历史记录和迁移；新提交不生成润色记录。
- `EvaluationRecord.polishResultID` 改为可选，新的评价记录置空。
- 评价请求仍使用六维 rubric、原始回答证据和满分答案，不改变评分维度及历史展示格式。

## 验证

- 单元测试：确认单题 process 只调用 `evaluate` 一次、不调用 `polish`，并保存原始文本为评分输入。
- 并发测试：确认最多 3 个任务同时运行、所有 chunk/batch 均处理、结果按 ordinal 排序、单个失败不会造成数据竞争。
- 回归测试：现有导入恢复、50 题分批、重试和答案历史测试继续通过。
- 真机/模拟器真实联调：使用 DeepSeek API，记录单题提交耗时、导入阶段并发请求数、评分结果和持久化状态；不使用 stub 作为性能结论。
