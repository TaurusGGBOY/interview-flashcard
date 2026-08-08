import Foundation

enum AIOperation: String, Codable, Equatable, Sendable {
    case decompose
    case refine
    case reclassify
    case polish
    case evaluate
}

enum PromptCatalog {
    static let decomposeVersion = "decompose-v1"
    static let refineVersion = "refine-senior-v2"
    static let reclassifyVersion = "reclassify-v1"
    static let polishVersion = "polish-v1"
    static let evaluateVersion = "evaluate-senior-v3"

    static func version(for operation: AIOperation) -> String {
        switch operation {
        case .decompose: decomposeVersion
        case .refine: refineVersion
        case .reclassify: reclassifyVersion
        case .polish: polishVersion
        case .evaluate: evaluateVersion
        }
    }

    static func systemPrompt(for operation: AIOperation) -> String {
        let common = """
        Return one valid JSON object only. Do not wrap JSON in Markdown. Set completionStatus to complete only after every required field is present. Never invent source text, identifiers, topics, or user claims.
        """
        switch operation {
        case .decompose:
            return common + """
            \nFreely identify interview questions in the supplied Markdown chunk. Preserve candidate order. Every candidate must include source-backed answer material and at least one exact source anchor. The owned range decides which chunk owns a candidate; overlapping context is context only.
            """
        case .refine:
            return common + """
            \nPolish and deduplicate only within this batch. You may merge candidates, but every output must list all merged candidate IDs. Produce a standalone question, a full-score answer grounded only in supplied material, one existing topic name, and source anchors. Creating a new topic is forbidden.

            The full-score answer MUST be Markdown with these three sections, in this order: “## 结论”, “## 核心要点”, and “## 边界与取舍”. Under “## 核心要点” provide at least three distinct, non-empty bullet points; empty bullets or repeated wording do not count. Explain the mechanism (why and how it works), operational boundaries and failure modes, and engineering tradeoffs such as consistency, latency, cost, complexity, or maintainability. Include a concrete follow-up direction or interview deepening point. Do not return a generic definition or a one- or two-sentence summary. Keep every claim traceable to the supplied source material; if the material is insufficient, preserve the uncertainty instead of inventing facts.
            """
        case .reclassify:
            return common + """
            \nReturn exactly one assignment for every supplied card. Change only its topic and choose only from availableTopicNames. Do not rewrite card content and do not create topics.
            """
        case .polish:
            return common + """
            \nRepair expression only: punctuation, grammar, obvious transcription errors, repetition, and filler. Preserve facts, negation, uncertainty, and scope. Do not use or infer a reference answer. List every possibly new factual claim in introducedClaims.

            The JSON object MUST use these exact keys and types: requestID (copy the request value), polishedText (the repaired answer), edits (array of {original,replacement,reason}), suspectedTranscriptionIssues (array of {text,alternatives,reason}), introducedClaims (array of {text,reason}), needsUserReview (boolean), warnings (array of strings), modelID (use the configured model name), promptVersion (use polish-v1), and completionStatus (use complete). Never use repairedText or another alternative key. Use [] when an array has no items.
            """
        case .evaluate:
            return common + """
            \nThe submitted answer may be a local speech-to-text transcript or input-method dictation. Score the answer the user actually submitted. Tolerate missing punctuation, filler words, duplicated words, homophones, obvious transcription substitutions, and dropped filler when the intended technical meaning is clear from the question, reference answer, and surrounding rawText. Transcription noise may be forgiven when it does not change meaning, but missing knowledge or missing key points must still lose credit. Do not silently invent a technical claim or complete the user's answer: if a transcription ambiguity could change the meaning, lower confidence, mention it in warnings or gapsAndErrors, and score only the supported interpretation. Every evidence quote must be copied exactly from rawText. The legacy polishedText field is a compatibility copy of rawText and must not be treated as a second source. Include concrete strengths, gaps/errors, improvements, confidence, versions, and score range.

            The JSON object MUST use these exact top-level keys: scorable, notScorableReason, dimensions, factualErrors, strengths, gapsAndErrors, improvements, polishOnlyClaims, confidence, scoreRange, warnings, modelID, promptVersion, rubricVersion, completionStatus. dimensions MUST be an array of exactly six objects in this order: technicalCorrectness, keyPointCoverage, reasoningDepth, structureClarity, applicationTradeoffs, and precisionConciseness. Apply rubric version senior-software-engineer-v2 with weights 35/25/15/10/10/5. Each dimension object has integer score (0-100), evidence (a non-empty array of {quote,explanation}; quote must be copied exactly from rawText), missedPoints (array of concrete strings; it MUST be non-empty when score is below 100), and a non-empty feedback string specific to this answer. If the weighted total is not 100, gapsAndErrors MUST contain at least one concrete gap and improvements MUST contain at least one executable next step. scoreRange has integer low and high (0-100). factualErrors is an array of {statement,explanation,referenceBasis}; every field must explain the conflict with the reference answer or an established mechanism. strengths, gapsAndErrors, improvements, polishOnlyClaims, and warnings are arrays of strings. Keep polishOnlyClaims empty unless the request explicitly contains a separate non-empty introducedClaims field. scorable is true when the answer can be scored; notScorableReason is null when true. confidence is a number from 0 to 1. Use modelID equal to the configured model name, promptVersion evaluate-senior-v3, rubricVersion senior-software-engineer-v2, and completionStatus complete. Do not return dimensions as an object and do not use totalScore. Use [] for empty arrays.
            """
        }
    }
}
