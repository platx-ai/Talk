//
//  VocabularyItem.swift
//  Talk
//
//  个人词库项
//

import Foundation

struct VocabularyItem: Codable, Identifiable {
    let id: UUID
    let word: String
    var frequency: Int
    var lastUsed: Date
    let context: String?
    /// For correction entries: the corrected form (word stores the original/wrong form)
    var correctedForm: String?

    init(
        id: UUID = UUID(),
        word: String,
        frequency: Int = 1,
        lastUsed: Date = Date(),
        context: String? = nil,
        correctedForm: String? = nil
    ) {
        self.id = id
        self.word = word
        self.frequency = frequency
        self.lastUsed = lastUsed
        self.context = context
        self.correctedForm = correctedForm
    }

    /// Whether this item is a correction entry (has a corrected form different from the word)
    var isCorrection: Bool {
        correctedForm != nil
    }

    var formattedLastUsed: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: lastUsed)
    }
}
