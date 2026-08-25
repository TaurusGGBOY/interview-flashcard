import Foundation

enum AIOperation: String, Codable, Equatable, Sendable {
    case decompose
    case referenceAnswer
    case refine
    case reclassify
    case polish
    case evaluateScore
    case evaluateFeedback
    case evaluate
}

enum PromptCatalog {
    static let decomposeVersion = "decompose-extraction-v6"
    static let finalAnswerDecomposeVersion = "decompose-final-answer-v3"
    static let referenceAnswerVersion = "reference-answer-v1"
    static let refineVersion = "refine-senior-v3"
    static let reclassifyVersion = "reclassify-v2"
    static let polishVersion = "polish-v1"
    static let evaluateScoreVersion = "evaluate-score-v1"
    static let evaluateFeedbackVersion = "evaluate-feedback-v1"
    static let evaluateVersion = "evaluate-senior-v3"

    static func version(for operation: AIOperation) -> String {
        switch operation {
        case .decompose: decomposeVersion
        case .referenceAnswer: referenceAnswerVersion
        case .refine: refineVersion
        case .reclassify: reclassifyVersion
        case .polish: polishVersion
        case .evaluateScore: evaluateScoreVersion
        case .evaluateFeedback: evaluateFeedbackVersion
        case .evaluate: evaluateVersion
        }
    }

    static func systemPrompt(
        for operation: AIOperation,
        decomposeOutputMode: DecomposeOutputMode = .extraction,
        availableTopicNames: [String] = []
    ) -> String {
        let common = """
        Return one valid JSON object only. Do not wrap JSON in Markdown. Set completionStatus to complete only after every required field is present. Never invent source text, identifiers, topics, or user claims.
        """
        switch operation {
        case .decompose:
            switch decomposeOutputMode {
            case .extraction:
                return common + """
                \nExtract every distinct interview question from the entire owned Markdown range. This is stage 1 of a two-stage import: identify questions, assign each question to an existing Topic, and collect concise source-backed material only. Do not write a polished or full-score answer, do not summarize the whole document, and do not stop after representative examples. Preserve source order and include later sections. Ignore prose that is not an interview question.

                Every returned question MUST be a complete, standalone question that a reader can understand without seeing the source document. Rewrite fragments into a natural full question when needed. If the source uses pronouns, shorthand, a section title, or omitted context such as “它如何实现？”、“有什么区别？” or “优缺点？”，replace them with the specific subject and scope from the surrounding Markdown (for example, name the technology, component, protocol, or design being discussed). Add only context that is explicitly supported by the supplied Markdown; never guess. Do not leave references such as “上述方案”“这个问题”“它”“该组件” unresolved. Each question must make clear what is being asked and about which subject.

                Never create a candidate from a bare noun, component name, acronym, technology name, heading, list label, or short noun phrase. Examples that MUST be omitted as candidates include “Pod”, “Custom Resources”, “Persistent Volumes”, and “Resource Management”. A candidate must be independently answerable as an interview question: include question punctuation or an explicit interrogative/action such as “什么/如何/为什么/哪些/区别/原理/解释/设计/排查” or “what/how/why/explain/design/troubleshoot”. If a heading names a concept but does not ask anything, omit it even when the following paragraph contains useful material.

                \(topicInstructions(availableTopicNames))

                For each candidate, sourceBackedAnswerMaterial must be short evidence notes copied or tightly paraphrased from the owned Markdown, with a hard target of at most 800 characters. Include only the mechanism, important details, examples, limits, or tradeoffs that are actually present in the source. Do not invent missing facts and do not add the final-answer sections. Every candidate must have at least one short exact source anchor, preferably the question heading or the most relevant source sentence. The exactQuote must be a verbatim substring of ownedMarkdown; the coordinator will repair offsets and identifiers from that quote. The owned range decides which chunk owns a candidate; overlapping context is context only. Review the entire owned range before setting completionStatus to complete.

                The JSON object MUST use exactly these top-level keys and types: candidates (array) and completionStatus ("complete" or "truncated"). Each candidate MUST use exactly these keys: id (a new UUID string), ordinal (zero-based integer in source order), question (string), sourceBackedAnswerMaterial (string), topicName (string selected exactly from the Topic whitelist), and sourceAnchors (array). Each sourceAnchors item MUST use exactly these keys: sourceDocumentID (copy the request value), chunkID (copy the request value), startOffset (integer), endOffset (integer), and exactQuote (a non-empty verbatim substring of ownedMarkdown). Do not use alternative names such as answer, topic, category, sourceStart, sourceEnd, or exactSource. Return no top-level chunkID and no extra candidate fields. Set completionStatus to complete only when every candidate has all required fields.
                """
            case .finalAnswer:
                return common + """
                \nFreely identify every distinct interview question in the supplied Markdown chunk. This is complete extraction, not summarization: do not cap the number of questions, skip later sections, or stop after finding representative examples. Preserve candidate order. For each candidate, assign an existing Topic and make sourceBackedAnswerMaterial the final concise reference answer, not notes: use Markdown sections “## 结论”, “## 核心要点”, and “## 边界与取舍”, with at least three distinct bullets under “## 核心要点”, at least three sentences, the mechanism, and an evidence-based boundary or tradeoff. Every candidate must include at least one exact source anchor. The owned range decides which chunk owns a candidate; overlapping context is context only. Review the entire owned range before setting completionStatus to complete.

                Every question MUST be complete and independently understandable without the original Markdown. Expand pronouns, shorthand, headings, and context-dependent fragments into a natural full question using the explicit surrounding context. For example, rewrite “它如何实现？” or “有什么区别？” to name the exact technology, component, protocol, or design under discussion. Add only context supported by the supplied Markdown; never guess or leave “上述方案”“这个问题”“它”“该组件”等 unresolved.

                \(topicInstructions(availableTopicNames))

                The JSON object MUST use exactly these top-level keys and types: candidates (array) and completionStatus ("complete" or "truncated"). Each candidate MUST use exactly these keys: id (a new UUID string), ordinal (zero-based integer in source order), question (string), sourceBackedAnswerMaterial (string), topicName (string selected exactly from the Topic whitelist), and sourceAnchors (array). Each sourceAnchors item MUST use exactly these keys: sourceDocumentID (copy the request value), chunkID (copy the request value), startOffset (integer), endOffset (integer), and exactQuote (a non-empty verbatim substring of ownedMarkdown). Do not use alternative names such as answer, topic, category, sourceStart, sourceEnd, or exactSource. Return no top-level chunkID and no extra candidate fields. Set completionStatus to complete only when every candidate has all required fields.
                """
            }
        case .referenceAnswer:
            return common + """
            \nGenerate the full-score reference answer for exactly one supplied interview question. This request happens when the user first starts answering, not during Markdown import. Use only the supplied question and sourceBackedMaterial; if the material is incomplete, explicitly preserve that uncertainty instead of inventing source facts.

            The answerText MUST be concise Markdown with these sections in this order: “## 结论”, “## 核心要点”, and “## 边界与取舍”. Include at least three distinct non-empty bullets under “## 核心要点”, at least three complete sentences, an explanation of the mechanism, and an explicit boundary, failure mode, limitation, risk, or engineering tradeoff. The keyPoints array must contain the same three substantive bullets. Do not return a generic definition, a one-sentence answer, or any question-generation metadata.

            The JSON object MUST use exactly these top-level keys and types: answerText (string), keyPoints (array of strings), modelID (string), promptVersion (use reference-answer-v1), and completionStatus (“complete” or “truncated”).
            """
        case .refine:
            return common + """
            \nPolish and deduplicate only within this batch. Preserve one card for every distinct candidate; merge only exact duplicates, never merge related questions that should remain separately answerable. Every output must list all merged candidate IDs. Produce a standalone question, a concise full-score answer grounded only in supplied material, one existing topic name, and source anchors. Creating a new topic is forbidden. The question must be a complete question that a reader understands without the source document: resolve pronouns, shorthand, headings, and omitted subjects with explicit context from the supplied material. Never leave “上述方案”“这个问题”“它”“该组件” unresolved, and never invent context not present in the material.

            \(topicInstructions(availableTopicNames))

            The JSON object MUST use exactly these top-level keys and types: cards (array) and completionStatus ("complete" or "truncated"). Each card MUST use exactly these keys: id (a new UUID string), mergedCandidateIDs (array of candidate UUID strings), question (string), fullScoreAnswer (string), topicName (one of availableTopicNames), and sourceAnchors (array of objects with sourceDocumentID, chunkID, startOffset, endOffset, and exactQuote). Do not use alternative names such as answer, candidates, or sourceStart.

            The full-score answer MUST be concise Markdown with these three sections, in this order: “## 结论”, “## 核心要点”, and “## 边界与取舍”. Under “## 核心要点” provide exactly or nearly three distinct, non-empty bullet points; empty bullets or repeated wording do not count. The conclusion must explain the mechanism with wording such as “因为”, “通过”, “机制”, or “原理”. The boundary section must explicitly discuss a boundary, failure, limitation, risk, tradeoff, or what the source does not establish. Include at least three complete sentences and one concrete follow-up direction or interview deepening point. Before returning, check that all three section headings, three bullets, the mechanism explanation, and the boundary/tradeoff are present. Do not return a generic definition or a one- or two-sentence summary. Keep every claim traceable to the supplied source material; if the material is insufficient, say that the original Markdown does not establish it instead of inventing facts.
            """
        case .reclassify:
            return common + """
            \nReturn exactly one assignment for every supplied card. Change only its topic and choose only from the exact Topic whitelist below. If a card clearly belongs to an existing Topic, use that Topic's exact name. If no existing Topic is a confident match, use the exact system Topic name “Others”. Do not rewrite card content and do not create topics.

            \(topicInstructions(availableTopicNames))

            The JSON object MUST use exactly these top-level keys and types: assignments (array) and completionStatus ("complete" or "truncated"). assignments MUST contain exactly one object for every supplied card, in the same order. Each assignment MUST use exactly these keys and types: cardID (the supplied card UUID string) and topicName (one exact string from the Topic whitelist). Do not return question text, answer text, or any extra assignment fields. Set completionStatus to complete only after every supplied card has one assignment.
            """
        case .polish:
            return common + """
            \nRepair expression only: punctuation, grammar, obvious transcription errors, repetition, and filler. Preserve facts, negation, uncertainty, and scope. Do not use or infer a reference answer. List every possibly new factual claim in introducedClaims.

            The JSON object MUST use these exact keys and types: requestID (copy the request value), polishedText (the repaired answer), edits (array of {original,replacement,reason}), suspectedTranscriptionIssues (array of {text,alternatives,reason}), introducedClaims (array of {text,reason}), needsUserReview (boolean), warnings (array of strings), modelID (use the configured model name), promptVersion (use polish-v1), and completionStatus (use complete). Never use repairedText or another alternative key. Use [] when an array has no items.
            """
        case .evaluateScore:
            return common + """
            \nThis is the fast first stage of answer evaluation. Return only the total-scoring inputs: decide whether the answer is scorable and assign one integer 0-100 score to each of the six rubric dimensions. Do not generate evidence, explanations, feedback, improvements, or a full-score answer in this stage. The app will render these scores immediately and request the detailed feedback separately.

            Use the supplied question, sourceBackedMaterial, and referenceAnswer when it is non-empty. If referenceAnswer is empty, score against the sourceBackedMaterial and the question rather than refusing to score. Score the user's rawText only; do not repair or add claims. Apply rubric version senior-software-engineer-v2 with weights 35/25/15/10/10/5.

            The JSON object MUST use exactly these top-level keys: scorable, notScorableReason, dimensions, confidence, scoreRange, warnings, modelID, promptVersion, rubricVersion, completionStatus. dimensions MUST contain exactly six objects in this order, each with only key and score: technicalCorrectness, keyPointCoverage, reasoningDepth, structureClarity, applicationTradeoffs, precisionConciseness. scoreRange MUST be an object with integer low and integer high fields, both from 0 to 100, with low less than or equal to high. Use promptVersion evaluate-score-v1. If scorable is false, dimensions MUST be [] and notScorableReason must explain why. Do not return totalScore; the app computes the weighted total locally.
            """
        case .evaluateFeedback:
            return common + """
            \nThis is the second stage of answer evaluation. The score for each dimension has already been fixed by a previous request. Do not change or recompute those scores. Generate concrete, answer-specific feedback for every dimension, including exact evidence copied from rawText, missed points when that dimension is below 100, and one concise feedback string. Also provide strengths, gapsAndErrors, improvements, factualErrors, and warnings for the overall result. Do not generate a full-score answer in this stage; that is a later request.

            Use the supplied question, sourceBackedMaterial, referenceAnswer when non-empty, rawText, and fixed scores. Every evidence quote MUST be a non-empty verbatim substring of rawText. Do not credit facts that appear only in sourceBackedMaterial or referenceAnswer. The six dimensions MUST be returned in this order and their key values must match the supplied fixed scores. Use rubric version senior-software-engineer-v2, promptVersion evaluate-feedback-v1, and the configured modelID.

            The JSON object MUST use exactly these top-level keys: dimensions, factualErrors, strengths, gapsAndErrors, improvements, polishOnlyClaims, confidence, scoreRange, warnings, modelID, promptVersion, rubricVersion, completionStatus. Each dimension MUST use exactly these keys: key, evidence, missedPoints, feedback. scoreRange MUST be an object with integer low and high (0-100), never a string or array. factualErrors MUST be an array of objects each with statement, explanation, and referenceBasis; never a flat array of strings. Use [] for empty arrays. Keep polishOnlyClaims empty because no separate polishing request is part of this flow.

            Inside every JSON string, never use the ASCII double-quote character ("). If you need to quote wording, use Chinese corner quotes 「」 or 『』. This keeps the returned JSON parseable.
            """
        case .evaluate:
            return common + """
            \nThe submitted answer may be a local speech-to-text transcript or input-method dictation. Score the answer the user actually submitted. Tolerate missing punctuation, filler words, duplicated words, homophones, obvious transcription substitutions, and dropped filler when the intended technical meaning is clear from the question, reference answer, and surrounding rawText. Transcription noise may be forgiven when it does not change meaning, but missing knowledge or missing key points must still lose credit. Do not silently invent a technical claim or complete the user's answer: if a transcription ambiguity could change the meaning, lower confidence, mention it in warnings or gapsAndErrors, and score only the supported interpretation. Every evidence quote must be copied exactly from rawText. The legacy polishedText field is a compatibility copy of rawText and must not be treated as a second source. Include concrete strengths, gaps/errors, improvements, confidence, versions, and score range.

            The JSON object MUST use these exact top-level keys: scorable, notScorableReason, dimensions, factualErrors, strengths, gapsAndErrors, improvements, polishOnlyClaims, confidence, scoreRange, warnings, modelID, promptVersion, rubricVersion, completionStatus. dimensions MUST be an array of exactly six objects in this order: technicalCorrectness, keyPointCoverage, reasoningDepth, structureClarity, applicationTradeoffs, and precisionConciseness. Apply rubric version senior-software-engineer-v2 with weights 35/25/15/10/10/5. Each dimension object has integer score (0-100), evidence (a non-empty array of {quote,explanation}; quote must be copied exactly from rawText), missedPoints (array of concrete strings; it MUST be non-empty when score is below 100), and a non-empty feedback string specific to this answer. If the weighted total is not 100, gapsAndErrors MUST contain at least one concrete gap and improvements MUST contain at least one executable next step. scoreRange has integer low and high (0-100). factualErrors is an array of {statement,explanation,referenceBasis}; every field must explain the conflict with the reference answer or an established mechanism. strengths, gapsAndErrors, improvements, polishOnlyClaims, and warnings are arrays of strings. Keep polishOnlyClaims empty unless the request explicitly contains a separate non-empty introducedClaims field. scorable is true when the answer can be scored; notScorableReason is null when true. confidence is a number from 0 to 1. Use modelID equal to the configured model name, promptVersion evaluate-senior-v3, rubricVersion senior-software-engineer-v2, and completionStatus complete. Do not return dimensions as an object and do not use totalScore. Use [] for empty arrays.
            """
        }
    }

    private static func topicInstructions(_ names: [String]) -> String {
        let whitelist = names.isEmpty
            ? "[]"
            : "[" + names.map { "\"\(escapeJSON($0))\"" }.joined(separator: ", ") + "]"
        return """
        当前数据库中已经存在的 Topic 白名单（只能原样复制其中一个值，不能翻译、改大小写、加前后缀或自行创建新标签）：
        \(whitelist)
        每个题目的 topicName 必须是上述白名单中的精确字符串。先根据题目和 sourceBackedAnswerMaterial 判断归属，再复制标签。只要题目或材料明确出现 Kubernetes/K8S、Pod、kubectl、Deployment、Service、Ingress、CRD、RBAC、Namespace、Kubelet、Helm 等 Kubernetes 信号，并且白名单中存在名称包含 Kubernetes 或等于 K8S 的 Topic，就必须选择该 Topic，绝不能把这类题目放入 “Others”。只有确实无法匹配已有 Topic 时才选择白名单中的 “Others”。
        """
    }

    private static func escapeJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
