//
//  VocabularyManagerTests.swift
//  TalkTests
//
//  VocabularyManager correction learning tests
//

import Testing
import Foundation
@testable import Talk

struct VocabularyManagerTests {

    // MARK: - learnCorrection

    @Test @MainActor func learnCorrectionCreatesVocabularyEntries() {
        let manager = VocabularyManager.shared

        // Remember initial count
        let initialCount = manager.items.count

        // Learn a correction: "la laam" should become "LLM"
        manager.learnCorrection(original: "这是一个 la laam 测试", corrected: "这是一个 LLM 测试")

        // Should have at least one new correction entry
        let newItems = manager.items.dropFirst(initialCount)
        let correctionItems = newItems.filter { $0.isCorrection }

        #expect(!correctionItems.isEmpty, "Should create at least one correction entry")

        // Find the specific correction
        let llmCorrection = correctionItems.first { $0.correctedForm == "LLM" }
        #expect(llmCorrection != nil, "Should have a correction mapping to LLM")
        #expect(llmCorrection?.word == "la laam", "Original should be 'la laam'")

        // Clean up
        for item in newItems {
            manager.delete(item)
        }
    }

    @Test @MainActor func learnCorrectionSkipsIdenticalText() {
        let manager = VocabularyManager.shared
        let initialCount = manager.items.count

        manager.learnCorrection(original: "完全相同的文本", corrected: "完全相同的文本")

        #expect(manager.items.count == initialCount, "Should not add entries for identical text")
    }

    @Test @MainActor func learnCorrectionBoostsFrequencyOnRepeat() {
        let manager = VocabularyManager.shared
        let initialCount = manager.items.count

        manager.learnCorrection(original: "错误词汇A", corrected: "正确词汇A")

        let firstItem = manager.items.first { $0.word == "错误词汇A" && $0.correctedForm == "正确词汇A" }
        let firstFrequency = firstItem?.frequency ?? 0

        // Learn same correction again
        manager.learnCorrection(original: "错误词汇A", corrected: "正确词汇A")

        let updatedItem = manager.items.first { $0.word == "错误词汇A" && $0.correctedForm == "正确词汇A" }
        #expect((updatedItem?.frequency ?? 0) > firstFrequency, "Frequency should increase on repeated correction")

        // Clean up
        let newItems = manager.items.dropFirst(initialCount)
        for item in newItems {
            manager.delete(item)
        }
    }

    // MARK: - getHighFrequencyItems

    @Test @MainActor func getHighFrequencyItemsReturnsCorrectionEntries() {
        let manager = VocabularyManager.shared
        let initialCount = manager.items.count

        // learnCorrection creates items with frequency above threshold
        manager.learnCorrection(original: "测试原文B", corrected: "测试修正B")

        let highFreq = manager.getHighFrequencyItems(limit: 100)
        let found = highFreq.contains { $0.word == "测试原文B" && $0.correctedForm == "测试修正B" }

        #expect(found, "High frequency items should include recently learned corrections")

        // All returned items should be corrections
        for item in highFreq {
            #expect(item.isCorrection, "getHighFrequencyItems should only return correction entries")
        }

        // Clean up
        let newItems = manager.items.dropFirst(initialCount)
        for item in newItems {
            manager.delete(item)
        }
    }

    @Test @MainActor func getHighFrequencyItemsRespectsLimit() {
        let manager = VocabularyManager.shared
        let initialCount = manager.items.count

        // Add several corrections
        for i in 0..<5 {
            manager.learnCorrection(original: "限制测试\(i)", corrected: "限制修正\(i)")
        }

        let limited = manager.getHighFrequencyItems(limit: 2)
        #expect(limited.count <= 2, "Should respect the limit parameter")

        // Clean up
        let newItems = manager.items.dropFirst(initialCount)
        for item in newItems {
            manager.delete(item)
        }
    }

    // MARK: - VocabularyItem.isCorrection

    @Test func vocabularyItemIsCorrectionFlag() {
        let correctionItem = VocabularyItem(word: "wrong", correctedForm: "right")
        #expect(correctionItem.isCorrection == true)

        let normalItem = VocabularyItem(word: "normal")
        #expect(normalItem.isCorrection == false)
    }
}
