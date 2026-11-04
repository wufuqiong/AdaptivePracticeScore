import XCTest
@testable import AdaptivePracticeScore

final class AdaptivePracticeScoreTests: XCTestCase {
    func testPerfectRunAndMilestones() throws {
        var scorer = AdaptivePracticeScore()
        var path = [scorer.score]
        var milestones: [Int] = []
        while !scorer.isMastered {
            let update = scorer.submit(correct: true, questionDifficulty: scorer.nextDifficulty)
            XCTAssertGreaterThan(update.delta, 0)
            if let milestone = update.milestoneReached { milestones.append(milestone) }
            path.append(scorer.score)
            XCTAssertLessThan(path.count, 100)
        }
        XCTAssertEqual(Array(path.prefix(6)), [0, 10, 20, 28, 36, 44])
        XCTAssertEqual(milestones, [70, 80, 90, 100])
        XCTAssertEqual(Array(path[path.firstIndex(of: 90)!...]), [90, 92, 94, 97, 100])
        XCTAssertEqual(scorer.answeredCount, 23)
        XCTAssertEqual(scorer.correctCount, 23)
        XCTAssertEqual(scorer.stage, .mastered)
        XCTAssertEqual(scorer.nextDifficulty, 5)

        let unchanged = scorer.submit(correct: false, questionDifficulty: 5)
        XCTAssertEqual(unchanged.delta, 0)
        XCTAssertEqual(scorer.answeredCount, 23)
        let data = try JSONEncoder().encode(scorer)
        XCTAssertEqual(try JSONDecoder().decode(AdaptivePracticeScore.self, from: data), scorer)
    }

    func testChallengeMistakeAndDifficultyFallback() {
        var scorer = reach90()
        XCTAssertEqual(scorer.stage, .challenge)
        XCTAssertEqual(scorer.submit(correct: false, questionDifficulty: 5).newScore, 86)
        XCTAssertEqual(scorer.nextDifficulty, 4)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 4).newScore, 88)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 4).newScore, 90)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 4).delta, 0)
        XCTAssertEqual(scorer.nextDifficulty, 5)
        var path = [scorer.score]
        while !scorer.isMastered {
            let result = scorer.submit(correct: true, questionDifficulty: 5)
            XCTAssertTrue((2...3).contains(result.delta))
            path.append(result.newScore)
        }
        XCTAssertEqual(path, [90, 92, 95, 98, 100])
    }

    func testEarlierErrorsDoNotSlowFinalChallenge() {
        var scorer = AdaptivePracticeScore()
        for _ in 0..<15 {
            XCTAssertEqual(scorer.submit(correct: false, questionDifficulty: 1).newScore, 0)
        }
        while scorer.score < 90 {
            scorer.submit(correct: true, questionDifficulty: scorer.nextDifficulty)
        }
        var gains: [Int] = []
        while !scorer.isMastered {
            gains.append(scorer.submit(correct: true, questionDifficulty: 5).delta)
        }
        XCTAssertEqual(gains, [2, 2, 3, 3])
        XCTAssertEqual(scorer.answeredCount, 38)
    }

    func testRecoveryFrom96() throws {
        let legacy = Data(#"{"score":96,"answeredCount":23,"correctCount":20,"unassistedCorrectStreak":4}"#.utf8)
        var scorer = try JSONDecoder().decode(AdaptivePracticeScore.self, from: legacy)
        XCTAssertEqual(scorer.challengeCorrectStreak, 0)
        XCTAssertEqual(scorer.submit(correct: false, questionDifficulty: 5).newScore, 92)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5).newScore, 94)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5).newScore, 97)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5).newScore, 100)
    }

    func testHintsAndTooEasyQuestions() {
        var scorer = AdaptivePracticeScore()
        while scorer.score < 88 {
            scorer.submit(correct: true, questionDifficulty: scorer.nextDifficulty)
        }
        XCTAssertEqual(scorer.score, 88)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 4, usedHint: true).newScore, 89)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 4, usedHint: true).newScore, 89)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 4).newScore, 90)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5, usedHint: true).newScore, 90)
        let easier = scorer.submit(correct: true, questionDifficulty: 4)
        XCTAssertEqual(easier.delta, 0)
        XCTAssertFalse(easier.wasEligibleForPoints)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5).newScore, 92)
    }

    func testPersistencePreservesChallengeStreak() throws {
        var scorer = reach90()
        scorer.submit(correct: true, questionDifficulty: 5)
        scorer.submit(correct: true, questionDifficulty: 5)
        XCTAssertEqual(scorer.score, 94)
        XCTAssertEqual(scorer.challengeCorrectStreak, 2)
        let restored = try JSONDecoder().decode(AdaptivePracticeScore.self, from: JSONEncoder().encode(scorer))
        XCTAssertEqual(restored, scorer)
        var next = restored
        XCTAssertEqual(next.submit(correct: true, questionDifficulty: 5).newScore, 97)
    }

    func testAvoid99AndLegacy99() throws {
        let from96 = Data(#"{"score":96,"answeredCount":23,"correctCount":22,"unassistedCorrectStreak":5,"challengeCorrectStreak":3,"recoveryBonusAvailable":false}"#.utf8)
        var scorer = try JSONDecoder().decode(AdaptivePracticeScore.self, from: from96)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5).newScore, 98)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5).newScore, 100)
        let from99 = Data(#"{"score":99,"answeredCount":25,"correctCount":22,"unassistedCorrectStreak":3}"#.utf8)
        var old = try JSONDecoder().decode(AdaptivePracticeScore.self, from: from99)
        XCTAssertEqual(old.submit(correct: true, questionDifficulty: 5).delta, 1)
        XCTAssertTrue(old.isMastered)
    }

    func testCorruptLegacyScoreClampingAndHintNonCountingStreak() throws {
        let legacy = Data(#"{"score":-12,"answeredCount":-5,"correctCount":7,"unassistedCorrectStreak":-2}"#.utf8)
        let restored = try JSONDecoder().decode(AdaptivePracticeScore.self, from: legacy)
        XCTAssertEqual(restored.score, 0)
        XCTAssertEqual(restored.answeredCount, 0)
        XCTAssertEqual(restored.correctCount, 0)
        XCTAssertEqual(restored.unassistedCorrectStreak, 0)

        var scorer = reach90()
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5).newScore, 92)
        XCTAssertEqual(scorer.challengeCorrectStreak, 1)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5, usedHint: true).newScore, 92)
        XCTAssertEqual(scorer.challengeCorrectStreak, 0)
        XCTAssertEqual(scorer.submit(correct: true, questionDifficulty: 5).newScore, 94)
    }

    private func reach90() -> AdaptivePracticeScore {
        var scorer = AdaptivePracticeScore()
        while scorer.score < 90 {
            scorer.submit(correct: true, questionDifficulty: scorer.nextDifficulty)
        }
        return scorer
    }
}
