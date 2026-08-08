# Prompt 3 产品改进设计

## 目标

把 `docs/prompt/prompt_3.md` 中的练习、导入、语音回答、历史搜索和题库搜索需求落实为真实可用的本地 iOS 工作流，并保持现有 SwiftUI + SwiftData 架构稳定。

## 已确认的产品决定

- Debug 默认使用真实 DeepSeek；Stub 只在测试或显式 `-IFAIProvider stub` / 环境配置下使用。
- 没有 API Key 时不自动回退到 Stub，而是显示可理解的错误，用户到设置页配置 Key。
- 回答历史搜索位于“历史”Tab，搜索题目、回答文本和 Topic。
- 题库搜索位于“题库”Tab，搜索结果可打开题目详情并直接开始回答。
- 语音录音与本地转写嵌入“回答”页：第一次点击开始录音，第二次点击停止并转写，转写文本自动追加到回答编辑框；不跳转、不弹确认、不自动提交评分。

## 设计方案

### 1. 练习页

`PracticeFeedView` 保留导航标题“练习”，将卡片内的“随机练习”改为“随机”，消除标题重复。卡片区域使用练习页剩余高度并提高最小高度，扩大滑动触控区域；底部按钮保持跳过和开始回答两个动作并使用至少 48pt 的触控高度。

`QuestionCardView` 移除题目文本内部的纵向滚动容器。题目使用可换行、可缩放的文本布局，在更大的卡片内直接显示；左右滑动仍由 `PracticeSwipeActionLayer` 处理。这样示例长题目不会因为卡片内部滚动而要求用户先滚动再滑动。

### 2. 真实 AI 与 Markdown 导入

现有 Markdown 导入链路已经使用 Files 选择器、`MarkdownChunker`、`ImportCoordinator`、SwiftData 持久化和 AI 分解/整理流程；问题是 Debug 的默认 Provider 是 `StubAIClient`。只调整 Provider 组合根：Debug 默认创建 `DeepSeekAIClient`，显式 Stub 参数继续服务测试和故障注入，Release 行为保持 DeepSeek。

AI 调用失败时沿用现有导入失败记录和错误展示；不创建伪题目、不静默激活不完整结果。设置页显示当前使用的 Provider，并保留 Keychain API Key 管理。Fixture seeder、Fixture speech 和 Stub client 只作为测试/验收注入点，不作为正常用户流程。

### 3. 内嵌语音回答

复用现有本地语音协议、`AppleSpeechTranscriber` 和 `M4AAudioRecorder`，把 `VoiceAnswerController` 的录音/转写状态嵌入 `AnswerEditorView`，不再以 sheet 或独立确认页承载正常流程。

控制器完成转写后通过回调返回文本；编辑器在当前光标文本末尾追加一个空格或换行，再写入转写文本。录音中显示停止按钮，转写中显示进度，设备不支持或权限失败时显示错误和重试入口。停止后立即追加，不创建 `AnswerAttemptRecord`，用户仍可修改合并后的回答并通过原有提交按钮评分。已有语音提交服务与模型保留用于兼容和测试；混合回答以最终编辑框文本为准。

### 4. 历史搜索

`HistoryView` 增加 SwiftUI 原生 `.searchable`。过滤范围为未删除题目的 `questionTextSnapshot`、`rawText` 和关联 Topic 名称，保留现有 Topic Picker、时间倒序、评分状态和详情导航。搜索为空时保持现有完整历史列表，搜索无结果时使用本地空状态提示。

### 5. 题库搜索与直接回答

`LibraryView` 增加 `.searchable`。无搜索文本时保持 Topic 分组列表；有搜索文本时从所有未删除卡片中建立扁平结果列表，匹配题目文本或 Topic 名称。结果仍可进入 `QuestionDetailView`。

`QuestionDetailView` 增加“开始回答”主操作，直接导航到现有 `AnswerEditorView`，不要求先从练习页抽卡。题库搜索结果和 Topic 内题目列表沿用同一详情入口，因此所有题目来源都能进入同一真实回答流程。

## 数据流与错误处理

- 题库搜索和历史搜索只在内存中对 SwiftData 已查询记录做过滤，不新增数据库字段或网络请求。
- 语音音频在本地录制并由设备端转写；转写完成前不提交回答。录音/转写错误保持在当前回答页内，用户可重试。
- AI 缺少 Key、鉴权失败、限流或结构化响应无效时，沿用 `AIError` 与导入/评分失败状态；禁止回退到 Stub 伪造成功。
- 任何入口创建的回答都使用现有 `AnswerSubmissionService` 和 `AnswerProcessingService`，保证历史与统计继续读取同一模型。

## 验收标准

1. 练习页不再同时出现“练习”和“随机练习”，题目卡片明显变大，常见长题目不需要内部下滑。
2. Debug 未指定 Provider 时，Markdown 导入、整理、重新分类和评分都走 DeepSeek；没有 Key 时明确失败而不是生成示例题。
3. 回答页点击录音开始，再点击停止后，转写文本自动追加到当前回答编辑框且没有新页面或确认按钮。
4. 历史页可按题目、回答和 Topic 搜索；题库页可按题目和 Topic 搜索。
5. 搜索结果和题目详情可直接进入回答页并提交评分。
6. 现有单元测试、导入/回答流程测试和真实 Debug 构建通过；物理 iPhone 验证练习卡片、搜索和语音入口的关键交互。
