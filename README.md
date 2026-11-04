# AdaptivePracticeScore

一套面向低龄儿童练习 App 的 **0–100 分自适应评分引擎**，使用 Swift 实现，可作为 Swift Package 接入 iOS/macOS 项目。

设计借鉴 IXL SmartScore 公开的「答对积累掌握度、答错扣分、随表现调整题目难度」理念，**不是 IXL 官方算法或其内部公式的复刻**。本项目特别优化了儿童在高分阶段的挫折体验：**90–100 分独立答对每题通常 +2～3 分**，而不是常规 +1。

## 特性

- **前快后稳**：起步答对 +10，随后按分数逐步降低增幅；分数越高，要求的题目难度越高。
- **温和回退**：90 分后答错扣 4 分，难度按新分数自动调整；重新答对后可快速恢复。
- **不惩罚历史失误**：前面错得多，不会拖慢后面连续正确时的加分。
- **防简单题刷分**：低于要求难度的题目答对不加分；在挑战区，使用实质性提示答对也不加分。
- **进度可保存**：`Codable` 支持 JSON/本地数据库；可解码旧版没有挑战区字段的记录。
- **无第三方依赖**：可直接通过 Swift Package Manager 集成；包含 XCTest 测试。

## 评分规则速览（v1.1）

| 当前分数 | 答对基础加分 | 答错扣分 | 下一题最低难度 |
| --- | ---: | ---: | --- |
| 0–19 | +10 | -2 | L1 |
| 20–39 | +8 | -2 | L2 |
| 40–59 | +6 | -3 | L3 |
| 60–69 | +4 | -3 | L3 |
| 70–79 | +3 | -4 | L4 |
| 80–89 | +2 | -4 | L4 |
| 90–99 | **+2～3** | **-4** | L5 |

加分受里程碑上限（70、80、90、100）、题目难度与是否使用提示影响。比如从 79 分答对只会到 80 分；达到 99 分的旧存档，最后一题需要 +1 才能恰好达到 100。详情见 [评分算法文档](Docs/ALGORITHM.md)。

**典型路径**（全部使用当前要求的难度、全部独立答对）：

```text
0 → 10 → 20 → 28 → 36 → 44 → 50 → 56 → 62 → 66 → 70
  → 73 → 76 → 79 → 80 → 82 → 84 → 86 → 88 → 90
  → 92 → 94 → 97 → 100
```

共 **23 题**。90 分挑战区只需要 4 道连续正确题（`90 → 92 → 94 → 97 → 100`）。

## 安装

Xcode 中选择 **File → Add Package Dependencies…**，输入：

```text
https://github.com/wufuqiong/AdaptivePracticeScore
```

然后将 `AdaptivePracticeScore` library 添加到 App target。支持 iOS 13+、macOS 11+；Package 的 Swift tools 版本为 5.7。

## 最简接入

```swift
import AdaptivePracticeScore

var scorer = AdaptivePracticeScore()  // 每个练习技能分别维护一份状态

// 由你的题库根据分数挑选下一题（评分引擎本身不生成题目）。
let difficulty = scorer.nextDifficulty  // 1...5，代表最低要求难度

// 孩子答题后更新进度。
let update = scorer.submit(
    correct: true,
    questionDifficulty: difficulty,
    usedHint: false
)

print(update.previousScore, update.newScore, update.delta)
print(update.nextDifficulty, update.milestoneReached as Any)
print(update.isMastered)

// 保存和恢复：包含挑战区连对次数等内部状态。
let data = try JSONEncoder().encode(scorer)
scorer = try JSONDecoder().decode(AdaptivePracticeScore.self, from: data)
```

`usedHint` 只应表示**提供了答案线索的提示**；单纯重播音频、再次朗读题干通常不算提示。`questionDifficulty` 必须在 `1...5`，否则触发 `precondition`。达到 100 分后状态固定；需要新一轮评估时创建新的 `AdaptivePracticeScore()`。

## 文档与目录

```text
Package.swift
Sources/AdaptivePracticeScore/AdaptivePracticeScore.swift
Tests/AdaptivePracticeScoreTests/AdaptivePracticeScoreTests.swift
Docs/ALGORITHM.md       # 评分区间、状态转移、挑战区、恢复和边界
Docs/INTEGRATION.md     # 题库分级、存档、UI、接入示例与注意事项
```

- [算法与边界条件](Docs/ALGORITHM.md)
- [在 iOS 学习 App 中接入](Docs/INTEGRATION.md)

## 测试

安装 Swift 工具链后在仓库根目录运行：

```bash
swift test
```

现有 8 组 XCTest 覆盖：连续全对到 100、挑战区错误恢复、前期大量错误、提示限制、低难度题限制、编码恢复、旧存档的 99 分处理和损坏旧数据的基本钳制。

## 适用范围

这是一个**技能熟练度反馈算法**，不是百分比正确率，也不是标准化测评。题目的真实质量、难度标注以及重复题控制，由宿主 App 的题库负责。建议在 UI 中将 **80 分视为熟练、90 分视为挑战、100 分视为完全掌握**；也可以让孩子在 80/90 分结束当次练习，不必每次刷到 100。