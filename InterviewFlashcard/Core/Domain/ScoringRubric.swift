import Foundation

enum ScoreDimension: String, Codable, CaseIterable, Sendable {
    case correctness = "technicalCorrectness"
    case coverage = "keyPointCoverage"
    case reasoning = "reasoningDepth"
    case structure = "structureClarity"
    case tradeoffs = "applicationTradeoffs"
    case precision = "precisionConciseness"
}

struct DimensionScores: Codable, Equatable, Sendable {
    var correctness: Int
    var coverage: Int
    var reasoning: Int
    var structure: Int
    var tradeoffs: Int
    var precision: Int

    subscript(dimension: ScoreDimension) -> Int {
        switch dimension {
        case .correctness: correctness
        case .coverage: coverage
        case .reasoning: reasoning
        case .structure: structure
        case .tradeoffs: tradeoffs
        case .precision: precision
        }
    }
}

struct ScoringRubric: Equatable, Sendable {
    static let general = ScoringRubric(weights: [
        .correctness: 35,
        .coverage: 25,
        .reasoning: 15,
        .structure: 10,
        .tradeoffs: 10,
        .precision: 5,
    ])

    let weights: [ScoreDimension: Int]

    var dimensions: [ScoreDimension] {
        ScoreDimension.allCases
    }

    func total(for scores: DimensionScores) -> Int {
        let weightedTotal = dimensions.reduce(0.0) { partial, dimension in
            let score = min(max(scores[dimension], 0), 100)
            return partial + Double(score * (weights[dimension] ?? 0)) / 100.0
        }
        return Int(weightedTotal.rounded())
    }
}
