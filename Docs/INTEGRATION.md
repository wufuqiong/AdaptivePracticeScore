# 在 iOS / macOS 学习 App 中接入

## 1. 安装与定位

在 Xcode 选择 **File → Add Package Dependencies…**，输入：

~~~text
https://github.com/wufuqiong/AdaptivePracticeScore
~~~

将库产品 **AdaptivePracticeScore** 加到你的 App target。支持 iOS 13+、macOS 11+、Swift tools 5.7+。

这是**评分引擎**，不包含题库、出题、UI、动画或音效。题目难度、是否使用了实质性提示，由宿主 App 传入。

## 2. 每个练习技能单独存档

例如 Wonders/Unit1/Week1/short-i 与 HanziFriend/pinyin/ai-ei-ui 应有两份独立进度，不能共用一个分数。

~~~swift
import Foundation
import AdaptivePracticeScore

struct ProgressBook: Codable {
    var scoresBySkill: [String: AdaptivePracticeScore] = [:]

    mutating func submit(
        skillID: String,
        correct: Bool,
        difficulty: Int,
        usedHint: Bool
    ) -> AdaptivePracticeScore.Update {
        var scorer = scoresBySkill[skillID] ?? AdaptivePracticeScore()
        let update = scorer.submit(
            correct: correct,
            questionDifficulty: difficulty,
            usedHint: usedHint
        )
        scoresBySkill[skillID] = scorer
        return update
    }
}
~~~

上面的结构只是业务集成示例，核心库本身不定义 ProgressBook 或 skillID。

## 3. 典型出题与反馈流程

~~~text
读取当前技能的 scorer
       ↓
scorer.nextDifficulty → 取得下一题最低难度 L1...L5
       ↓
题库筛选满足难度的、近期未出现、覆盖所需知识点的题
       ↓
显示题目与可选提示，孩子作答
       ↓
submit(correct:questionDifficulty:usedHint:)
       ↓
根据 Update.delta 显示 +3 / -4 等反馈
       ↓
更新进度条，持久化；达到 100 则显示完全掌握
~~~

**nextDifficulty 是最低要求，不是严格要求等于该等级。** 例如当前最低 L3，题库可挑选 L3、L4、L5。低于要求的题即使答对也不加分；任何难度的题答错都按当前分数区间扣分。

建议将题库分级与评分逻辑分开，并尽量避免让孩子反复遇到相同图片、相同题目，从而仅凭记忆完成高分挑战。

## 4. 小规模存档示例

使用 Codable 可保存到 UserDefaults、JSON 文件或数据库。单设备 Demo：

~~~swift
let saveKey = "adaptivePractice.progress.v1"
var book = ProgressBook()

// 恢复
if let saved = UserDefaults.standard.data(forKey: saveKey) {
    book = (try? JSONDecoder().decode(ProgressBook.self, from: saved))
        ?? ProgressBook()
}

// 题库把正确与否、难度和提示使用状态传进来。
let result = book.submit(
    skillID: "Wonders/Unit1/Week1/short-i",
    correct: true,
    difficulty: 3,
    usedHint: false
)

// 保存（正式项目应处理编码和存储失败）。
let data = try JSONEncoder().encode(book)
UserDefaults.standard.set(data, forKey: saveKey)

// 驱动 UI
print(result.newScore, result.delta, result.nextDifficulty)
print(result.milestoneReached as Any, result.isMastered)
~~~

核心的 AdaptivePracticeScore 已包含挑战连对次数和恢复奖励状态；**不要只保存 score 整数**，否则中途退出后无法精确继续挑战区加分。多设备同步建议采用有版本控制的单技能记录或事件日志，不要简单累加两个设备的 answeredCount。

## 5. UI 设计建议

- 分数显示为**掌握进度**，而不是“正确率”。
- 每题显示清楚 +10 / +3 / -4 和更新后的分数，让孩子感知反馈。
- 达到 70、80、90、100 时使用 Update.milestoneReached 驱动轻量反馈动画。
- **80 分可以视为熟练，90 分进入挑战，100 分为掌握。** App 可以允许孩子在 80/90 分结束当次练习；核心库的 isMastered 仅在 100 分为 true。
- 答错后先降级巩固，避免立即反复抛出同一道难题。
- 不应把重播音频、朗读题干、无障碍阅读视作“用了提示”；如果提示已经透露部分答案，才将 usedHint 设置为 true。
- 达到 100 后 submit 不再计数。若用户希望复习或重新评估，创建新的评分状态。

## 6. 如何定义 L1–L5

难度不能只靠选项数定义，还应考虑干扰项相似性、所需知识点数量、操作步骤与迁移程度。以“看图找词”为例：

| 难度 | 参考定位 | 可用题型举例 |
| --- | --- | --- |
| L1 | 直接识别，干扰极少 | 2 张差异明显的图 |
| L2 | 单一干扰 | 3 张图识别熟悉词 |
| L3 | 常规多项干扰 | 4–5 项配对 |
| L4 | 复杂或相近干扰 | 5 项配对，增加合理干扰 |
| L5 | 迁移和稳定掌握 | 陌生图、更多干扰、综合迁移题 |

这是待校准的建议，不是固定的心理测量难度。需要确保每个技能有足够多、质量稳定的 L5 题。对视觉上难以区分的近义词、图片容易有歧义的词，不要为了提高难度而制造错误或不公平的干扰。

## 7. 常见问题

**为什么正确了没有加分？** 查看 questionDifficulty 是否低于 nextDifficulty、挑战区是否用了 usedHint、或者是否已到 100 分。

**为什么 79 分答对只加了 1？** 普通区存在 80/90 等里程碑封顶；“挑战区 +2～3”只适用于达到 90 后符合要求的题。旧存档 99 分也是 +1 的例外。

**为什么 90 分答错后难度降低？** 答错扣 4 分到 86，下一题最低等级自动回到 L4。重新到 90 后才需要 L5。

**前面错误很多会影响后续加分吗？** 不影响。历史错误数量只用于统计，不进入奖励公式。

**重听题目算提示吗？** 一般不算；提供正确答案线索才算实质性提示。

## 8. 测试

在仓库根目录运行：

~~~bash
swift test
~~~

8 个 XCTest 覆盖：全对 23 题通关、90 分错误回退、96 分错误恢复、早期 15 次错误后的高分加速、提示限制、低难度题阻止刷分、存档恢复、99 分兼容与旧数据钳制。

若后续需要调整评分区间，请同步更新核心代码、Docs/ALGORITHM.md 的规则表、README.md 的示例路径和 XCTest 断言，避免文档与实际行为不一致。
