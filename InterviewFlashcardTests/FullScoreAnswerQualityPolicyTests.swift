import Foundation
import XCTest

final class FullScoreAnswerQualityPolicyTests: XCTestCase {
    func testRejectsAnswerShorterThanMinimumNonWhitespaceCharacters() {
        let answer = """
        ## 结论
        值语义会让复制后的值彼此独立。

        ## 核心要点
        - 复制会产生独立状态。
        - 修改副本不会影响原值。
        - 调用方可以安全地隔离状态。

        ## 边界与取舍
        小对象复制成本低，但大型对象可能需要权衡性能。
        """

        guard case .failure(let error) = FullScoreAnswerQualityPolicy.assess(answer) else {
            return XCTFail("expected a short answer to be rejected")
        }
        XCTAssertEqual(error, .tooShort)
    }

    func testRejectsAnswerWithOnlyOneOrTwoSentences() {
        let answer = """
        ## 结论
        线程安全需要保护共享状态。

        ## 核心要点
        - 通过锁保护共享状态
        - 通过隔离减少竞争
        - 通过测试验证并发行为

        ## 边界与取舍
        竞争激烈时需要在一致性和吞吐之间权衡
        """
        let paddedAnswer = answer + String(repeating: " 额外说明", count: 30)

        guard case .failure(let error) = FullScoreAnswerQualityPolicy.assess(paddedAnswer) else {
            return XCTFail("expected an answer with fewer than three sentences to be rejected")
        }
        XCTAssertEqual(error, .tooFewSentences)
    }

    func testRejectsGenericDefinitionWithoutMechanismOrTradeoff() {
        let answer = """
        ## 结论
        缓存是一种保存数据的技术，缓存可以提升系统性能。

        ## 核心要点
        - 缓存保存数据
        - 缓存提升性能
        - 缓存减少访问时间

        ## 边界与取舍
        缓存保存数据，缓存提升性能，缓存减少访问时间。
        """
        let paddedAnswer = answer + String(repeating: " 缓存是一种常见技术。", count: 20)

        guard case .failure(let error) = FullScoreAnswerQualityPolicy.assess(paddedAnswer) else {
            return XCTFail("expected a generic definition to be rejected")
        }
        XCTAssertEqual(error, .genericDefinition)
    }

    func testRequiresThreeDistinctNonEmptyCorePointBullets() {
        let emptyBulletAnswer = """
        ## 结论
        事务需要明确隔离边界，并根据失败模式恢复。

        ## 核心要点
        - 使用日志记录状态变化。
        -
        - 使用幂等键避免重复提交。

        ## 边界与取舍
        失败重试会增加延迟，因此要在可用性和成本之间权衡；当下游不可用时应快速失败。
        通过补偿机制恢复未完成的事务，并用监控暴露异常。
        """

        let duplicateAnswer = """
        ## 结论
        事务需要明确隔离边界，并根据失败模式恢复。

        ## 核心要点
        - 使用日志记录状态变化。
        - 使用日志记录状态变化。
        - 使用幂等键避免重复提交。

        ## 边界与取舍
        失败重试会增加延迟，因此要在可用性和成本之间权衡；当下游不可用时应快速失败。
        通过补偿机制恢复未完成的事务，并用监控暴露异常。
        """

        guard case .failure(let emptyError) = FullScoreAnswerQualityPolicy.assess(emptyBulletAnswer) else {
            return XCTFail("expected an empty bullet to be rejected")
        }
        XCTAssertEqual(emptyError, .insufficientKeyPoints)

        guard case .failure(let duplicateError) = FullScoreAnswerQualityPolicy.assess(duplicateAnswer) else {
            return XCTFail("expected duplicate bullets to be rejected")
        }
        XCTAssertEqual(duplicateError, .insufficientKeyPoints)
    }

    func testRequiresFixedMarkdownSections() {
        let answer = """
        ## 结论
        这是一段足够长的结论，说明机制、边界和工程取舍。

        ## 核心要点
        - 机制通过状态隔离降低竞争。
        - 失败时通过重试恢复。
        - 取舍是在延迟和一致性之间权衡。
        """ + String(repeating: " 边界说明。", count: 30)

        guard case .failure(let error) = FullScoreAnswerQualityPolicy.assess(answer) else {
            return XCTFail("expected a missing section to be rejected")
        }
        XCTAssertEqual(error, .missingSection("边界与取舍"))
    }

    func testAcceptedAnswerReturnsKeyPointsThatRoundTripAsJSON() throws {
        let answer = Self.validAnswer

        guard case .success(let keyPoints) = FullScoreAnswerQualityPolicy.assess(answer) else {
            return XCTFail("expected a senior answer to pass")
        }
        XCTAssertEqual(keyPoints.count, 3)
        XCTAssertEqual(keyPoints, [
            "通过隔离共享状态降低并发竞争，并用锁或 actor 明确访问边界。",
            "失败时使用幂等重试和补偿机制恢复，避免重复副作用。",
            "根据一致性、延迟与成本做工程取舍，并通过监控和压测验证方案。"
        ])

        let data = try JSONEncoder().encode(keyPoints)
        let decoded = try JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(decoded, keyPoints)
    }

    private static let validAnswer = """
    ## 结论
    可靠的并发服务要先隔离共享状态，再用可观测的失败恢复流程保证结果一致；实现选择必须结合吞吐、延迟和运维成本。

    ## 核心要点
    - 通过隔离共享状态降低并发竞争，并用锁或 actor 明确访问边界。
    - 失败时使用幂等重试和补偿机制恢复，避免重复副作用。
    - 根据一致性、延迟与成本做工程取舍，并通过监控和压测验证方案。

    ## 边界与取舍
    当下游超时、重复投递或部分失败时，重试可能放大流量，因此应设置超时、退避和上限；强一致方案会牺牲部分吞吐，最终一致方案则需要处理读到旧数据的窗口。后续可以追问如何设计幂等键、如何观测恢复进度，以及怎样在容量受限时降级。
    """
}
