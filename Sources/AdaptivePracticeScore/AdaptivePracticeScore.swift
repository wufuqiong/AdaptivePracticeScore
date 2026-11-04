import Foundation

/// 借鉴 IXL SmartScore 的公开理念，为儿童练习设计的独立评分算法。
/// 不是 IXL 的内部公式。一个实例对应一个技能的一次掌握进度。
public struct AdaptivePracticeScore: Codable, Equatable {
    public private(set) var score: Int = 0
    public private(set) var answeredCount: Int = 0
    public private(set) var correctCount: Int = 0
    public private(set) var unassistedCorrectStreak: Int = 0

    /// 进入 90 分挑战区后，连续答对、且不使用提示的 L5 题目数量。
    /// 与全局连续答对次数分开记录，避免 L4 的连续正确直接带来 L5 加速。
    public private(set) var challengeCorrectStreak: Int = 0

    /// 在挑战区答错后，连续正确 2 道 L5 题即可获得一次恢复加速。
    /// 加速仅可消费一次，避免通过故意答错反复刷奖励。
    public private(set) var recoveryBonusAvailable: Bool = false

    public init() {}

    /// 兼容旧版本持久化的 JSON：旧数据没有挑战区的两个新字段。
    private enum CodingKeys: String, CodingKey {
        case score, answeredCount, correctCount, unassistedCorrectStreak
        case challengeCorrectStreak, recoveryBonusAvailable
    }

    public init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        score = try data.decodeIfPresent(Int.self, forKey: .score) ?? 0
        answeredCount = try data.decodeIfPresent(Int.self, forKey: .answeredCount) ?? 0
        correctCount = try data.decodeIfPresent(Int.self, forKey: .correctCount) ?? 0
        unassistedCorrectStreak = try data.decodeIfPresent(Int.self, forKey: .unassistedCorrectStreak) ?? 0
        challengeCorrectStreak = try data.decodeIfPresent(Int.self, forKey: .challengeCorrectStreak) ?? 0
        recoveryBonusAvailable = try data.decodeIfPresent(Bool.self, forKey: .recoveryBonusAvailable) ?? false
        // 防止损坏的旧数据导致负分/超过上限的成绩。
        score = min(100, max(0, score))
        answeredCount = max(0, answeredCount)
        correctCount = min(answeredCount, max(0, correctCount))
        unassistedCorrectStreak = max(0, unassistedCorrectStreak)
        challengeCorrectStreak = max(0, challengeCorrectStreak)
        if score < 90 || score == 100 { challengeCorrectStreak = 0 }
    }

    /// 下一道题所需的最低难度，1 最简单，5 最难。
    public var nextDifficulty: Int {
        switch score {
        case ..<20: return 1
        case ..<40: return 2
        case ..<70: return 3
        case ..<90: return 4
        default: return 5
        }
    }

    public var isMastered: Bool { score == 100 }

    public enum Stage: String, Codable {
        case learning         // 0...69
        case consolidation    // 70...89
        case challenge        // 90...99
        case mastered         // 100
    }

    public var stage: Stage {
        if score == 100 { return .mastered }
        if score >= 90 { return .challenge }
        if score >= 70 { return .consolidation }
        return .learning
    }

    public struct Update: Equatable {
        public let previousScore: Int
        public let newScore: Int
        public let delta: Int
        public let nextDifficulty: Int
        /// 第一次跨过的里程碑：70 / 80 / 90 / 100。
        public let milestoneReached: Int?
        public let isMastered: Bool
        /// 题目低于当前要求难度时，答对不计分。
        public let wasEligibleForPoints: Bool
    }

    /// 记录一次作答，并返回分数与下一题的难度。
    /// - Parameters:
    ///   - correct: 是否正确。
    ///   - questionDifficulty: 题库标注的难度 1...5。
    ///   - usedHint: 是否使用了泄露解题线索的提示；重播音频不算提示。
    /// - Note: 提示后答对可得部分分数，但不能借提示跨过 90 分，或在挑战区得分。
    @discardableResult
    public mutating func submit(
        correct: Bool,
        questionDifficulty: Int,
        usedHint: Bool = false
    ) -> Update {
        precondition((1...5).contains(questionDifficulty), "questionDifficulty must be 1...5")

        let old = score
        let expectedDifficulty = nextDifficulty
        let eligible = questionDifficulty >= expectedDifficulty

        // 100 分为已完成状态，复习时应开始新的评估会话。
        if isMastered {
            return Update(
                previousScore: old,
                newScore: score,
                delta: 0,
                nextDifficulty: nextDifficulty,
                milestoneReached: nil,
                isMastered: true,
                wasEligibleForPoints: false
            )
        }

        answeredCount += 1
        let band = scoringBand(for: score)

        if correct {
            correctCount += 1
            unassistedCorrectStreak = (!usedHint && eligible) ? unassistedCorrectStreak + 1 : 0

            if score >= 90 {
                if eligible && !usedHint {
                    challengeCorrectStreak += 1
                    var gain = challengeCorrectStreak >= 3 ||
                        (recoveryBonusAvailable && challengeCorrectStreak >= 2) ? 3 : 2

                    // 规避通过正常计分进入 99，避免最后一题只能 +1。
                    // 已从旧版本恢复到 99 分的极少数情况仍允许 +1 达到 100。
                    if score <= 98 && (100 - (score + gain)) == 1 {
                        gain = gain == 3 ? 2 : 3
                    }
                    score = min(100, score + gain)
                    if recoveryBonusAvailable && challengeCorrectStreak >= 2 {
                        recoveryBonusAvailable = false
                    }
                } else {
                    // 低于挑战难度的题目或提示后答对不算连续独立掌握。
                    challengeCorrectStreak = 0
                }
            } else if eligible {
                if usedHint {
                    let discountedGain = max(1, band.reward / 2)
                    score = min(89, min(band.nextMilestone, score + discountedGain))
                } else {
                    score = min(band.nextMilestone, score + band.reward)
                }
                // L4 跨过 90 不应提前计入 L5 连续正确。
                challengeCorrectStreak = 0
            } else {
                challengeCorrectStreak = 0
            }
        } else {
            unassistedCorrectStreak = 0
            challengeCorrectStreak = 0
            if old >= 90 { recoveryBonusAvailable = true }
            score = max(0, score - band.penalty)
        }

        // 统一已掌握状态的可持久化表示；保存后重新载入的状态应相等。
        if isMastered {
            challengeCorrectStreak = 0
            recoveryBonusAvailable = false
        }

        let milestone = [70, 80, 90, 100].first { old < $0 && score >= $0 }
        return Update(
            previousScore: old,
            newScore: score,
            delta: score - old,
            nextDifficulty: nextDifficulty,
            milestoneReached: milestone,
            isMastered: isMastered,
            wasEligibleForPoints: eligible
        )
    }

    private struct Band {
        let reward: Int
        let penalty: Int
        let nextMilestone: Int
    }

    private func scoringBand(for score: Int) -> Band {
        switch score {
        case ..<20: return Band(reward: 10, penalty: 2, nextMilestone: 70)
        case ..<40: return Band(reward: 8, penalty: 2, nextMilestone: 70)
        case ..<60: return Band(reward: 6, penalty: 3, nextMilestone: 70)
        case ..<70: return Band(reward: 4, penalty: 3, nextMilestone: 70)
        case ..<80: return Band(reward: 3, penalty: 4, nextMilestone: 80)
        case ..<90: return Band(reward: 2, penalty: 4, nextMilestone: 90)
        default: return Band(reward: 2, penalty: 4, nextMilestone: 100)
        }
    }
}