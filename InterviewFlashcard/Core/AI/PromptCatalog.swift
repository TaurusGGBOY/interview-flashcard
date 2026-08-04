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
    static let refineVersion = "refine-v1"
    static let reclassifyVersion = "reclassify-v1"
    static let polishVersion = "polish-v1"
    static let evaluateVersion = "evaluate-general-v1"

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
            """
        case .reclassify:
            return common + """
            \nReturn exactly one assignment for every supplied card. Change only its topic and choose only from availableTopicNames. Do not rewrite card content and do not create topics.
            """
        case .polish:
            return common + """
            \nRepair expression only: punctuation, grammar, obvious transcription errors, repetition, and filler. Preserve facts, negation, uncertainty, and scope. Do not use or infer a reference answer. List every possibly new factual claim in introducedClaims.
            """
        case .evaluate:
            return common + """
            \nReturn exactly the rubric's six dimensions with integer scores from 0 through 100. Do not return a total score. Evidence must quote the supplied raw or polished answer. Correctness and coverage credit must be traceable to rawText; content present only in polishedText or introducedClaims earns no credit. Include concrete strengths, gaps/errors, improvements, confidence, versions, and score range.
            """
        }
    }
}
