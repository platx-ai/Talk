//
//  HotwordExtractionTests.swift
//  TalkTests
//
//  热词提取提示词质量测试（需要模型加载，仅本地运行）
//

import Testing
import Foundation
@testable import Talk

/// 热词提取测试用例
struct HotwordTestCase {
    let original: String
    let edited: String
    let expectedCorrections: [(original: String, corrected: String)]  // ASR错误 → 正确形式
    let shouldBeEmpty: Bool  // 期望无修正（纯润色编辑）
}

@Suite("Hotword Extraction Tests")
struct HotwordExtractionTests {

    // MARK: - 真实测试用例（从日志提取）

    static let testCases: [HotwordTestCase] = [
        // Case 1: skill → SQL（ASR 同音错误）
        HotwordTestCase(
            original: "触发一下这个 skill 吧。",
            edited: "触发一下这个 SQL 吧。",
            expectedCorrections: [("skill", "SQL")],
            shouldBeEmpty: false
        ),
        // Case 2: 纯标点/润色编辑，不应提取
        HotwordTestCase(
            original: "你好世界",
            edited: "你好，世界。",
            expectedCorrections: [],
            shouldBeEmpty: true
        ),
        // Case 3: 口语词删减，不应提取
        HotwordTestCase(
            original: "嗯，就是说，我觉得这个方案可以。",
            edited: "我觉得这个方案可以。",
            expectedCorrections: [],
            shouldBeEmpty: true
        ),
        // Case 4: 专有名词修正
        HotwordTestCase(
            original: "我们用的是 Cloud Code 来开发。",
            edited: "我们用的是 Claude Code 来开发。",
            expectedCorrections: [("Cloud Code", "Claude Code")],
            shouldBeEmpty: false
        ),
        // Case 5: 技术术语同音错误
        HotwordTestCase(
            original: "这个 OOS 获取用户名密码的。",
            edited: "这个 OAuth 获取用户名密码的。",
            expectedCorrections: [("OOS", "OAuth")],
            shouldBeEmpty: false
        ),
        // Case 6: 多个修正
        HotwordTestCase(
            original: "用 Cloud Code 连接 skill 数据库。",
            edited: "用 Claude Code 连接 SQL 数据库。",
            expectedCorrections: [("Cloud Code", "Claude Code"), ("skill", "SQL")],
            shouldBeEmpty: false
        ),
        // Case 7: 语序调整，不应提取
        HotwordTestCase(
            original: "明天下午三点我们开会。",
            edited: "我们明天下午三点开会。",
            expectedCorrections: [],
            shouldBeEmpty: true
        ),
    ]

    @Test @MainActor
    func extractHotwordsQuality() async {
        let llm = LLMService.shared
        guard llm.isModelLoaded else {
            // 模型未加载时跳过（CI 环境）
            return
        }

        var passed = 0
        var failed = 0

        for (i, tc) in Self.testCases.enumerated() {
            let corrections = await llm.extractHotwords(original: tc.original, edited: tc.edited)

            if tc.shouldBeEmpty {
                if corrections.isEmpty {
                    passed += 1
                } else {
                    failed += 1
                    Issue.record("Case \(i+1): expected empty, got \(corrections.map { "\($0.original)→\($0.corrected)" })")
                }
            } else {
                // 检查方向是否正确（original=ASR错误，corrected=正确形式）
                for expected in tc.expectedCorrections {
                    let found = corrections.contains { c in
                        c.original.lowercased().contains(expected.original.lowercased()) &&
                        c.corrected.lowercased().contains(expected.corrected.lowercased())
                    }
                    if found {
                        passed += 1
                    } else {
                        // 检查是否方向反了
                        let reversed = corrections.contains { c in
                            c.corrected.lowercased().contains(expected.original.lowercased()) &&
                            c.original.lowercased().contains(expected.corrected.lowercased())
                        }
                        if reversed {
                            failed += 1
                            Issue.record("Case \(i+1): REVERSED direction! Expected \(expected.original)→\(expected.corrected)")
                        } else {
                            failed += 1
                            Issue.record("Case \(i+1): missing \(expected.original)→\(expected.corrected), got \(corrections.map { "\($0.original)→\($0.corrected)" })")
                        }
                    }
                }
            }
        }

        print("Hotword extraction: \(passed) passed, \(failed) failed out of \(passed + failed) checks")
        // 至少 70% 通过率
        #expect(passed > 0, "No test cases passed — model may not be loaded")
        if passed + failed > 0 {
            let passRate = Double(passed) / Double(passed + failed)
            #expect(passRate >= 0.7, "Pass rate \(String(format: "%.0f", passRate * 100))% below 70% threshold")
        }
    }
}
