//
//  UsageStatisticsTests.swift
//  Talk
//
//  Tests for UsageStatisticsManager. Serialized + clean-slate per test
//  because the manager is a singleton with persistent file state.
//

import Foundation
import Testing

@testable import Talk

@Suite("UsageStatistics Tests", .serialized)
@MainActor
struct UsageStatisticsTests {

    /// Reset the singleton's state so each test starts from zero.
    /// Safe because the test bundle's Application Support dir is shared
    /// with the dev build, but stats are append-only and the test deletes
    /// only its own appended entries via clearAllStats.
    private func freshManager() -> UsageStatisticsManager {
        let manager = UsageStatisticsManager.shared
        manager.clearAllStats()
        return manager
    }

    @Test("singleton returns same instance")
    func sharedInstance() {
        #expect(UsageStatisticsManager.shared === UsageStatisticsManager.shared)
    }

    @Test("recordSession populates today's row")
    func recordSingleSession() async throws {
        let manager = freshManager()
        manager.recordSession(
            recordingDuration: 10.0, processingTime: 5.0,
            asrTime: 2.0, llmTime: 3.0, hadError: false
        )

        #expect(manager.dailyStats.count == 1)
        let today = manager.dailyStats[0]
        #expect(today.sessionCount == 1)
        #expect(today.totalRecordingDuration == 10.0)
        #expect(today.asrInferenceTime == 2.0)
        #expect(today.llmInferenceTime == 3.0)
        #expect(today.errorCount == 0)
    }

    @Test("recordSession with error increments errorCount")
    func recordSessionWithError() async throws {
        let manager = freshManager()
        manager.recordSession(
            recordingDuration: 10.0, processingTime: 5.0,
            asrTime: 2.0, llmTime: 3.0, hadError: true
        )
        #expect(manager.dailyStats.first?.errorCount == 1)
    }

    @Test("recordEdit increments editCount")
    func recordEdit() async throws {
        let manager = freshManager()
        manager.recordSession(
            recordingDuration: 10.0, processingTime: 5.0,
            asrTime: 2.0, llmTime: 3.0, hadError: false
        )
        manager.recordEdit()
        #expect(manager.dailyStats.first?.editCount == 1)
    }

    @Test("recordEdit with no prior session creates a row")
    func recordEditWithoutSession() async throws {
        let manager = freshManager()
        manager.recordEdit()
        #expect(manager.dailyStats.count == 1)
        #expect(manager.dailyStats[0].editCount == 1)
        #expect(manager.dailyStats[0].sessionCount == 0)
    }

    @Test("getStatsForLast7Days is sorted ascending by date")
    func getStatsForLast7Days() async throws {
        let manager = freshManager()
        manager.recordSession(
            recordingDuration: 1, processingTime: 1, asrTime: 1, llmTime: 1
        )
        let stats = manager.getStatsForLast7Days()
        for i in 1..<stats.count {
            #expect(stats[i - 1].date <= stats[i].date)
        }
    }

    @Test("getAggregateStats sums across days")
    func getAggregateStats() async throws {
        let manager = freshManager()
        manager.recordSession(
            recordingDuration: 10, processingTime: 5,
            asrTime: 2, llmTime: 3, hadError: false
        )
        manager.recordSession(
            recordingDuration: 20, processingTime: 10,
            asrTime: 4, llmTime: 6, hadError: true
        )
        manager.recordEdit()

        let agg = manager.getAggregateStats()
        #expect(agg.totalSessions == 2)
        #expect(agg.totalDuration == 30)
        #expect(agg.totalEdits == 1)
        #expect(agg.totalErrors == 1)
        #expect(abs(agg.averageEditRate - 0.5) < 0.001)
        #expect(abs(agg.averageErrorRate - 0.5) < 0.001)
    }

    @Test("clearAllStats wipes everything")
    func clearAllStats() async throws {
        let manager = freshManager()
        manager.recordSession(
            recordingDuration: 1, processingTime: 1, asrTime: 1, llmTime: 1
        )
        #expect(!manager.dailyStats.isEmpty)
        manager.clearAllStats()
        #expect(manager.dailyStats.isEmpty)
    }

    @Test("editRate computed at 50% for 10 sessions + 5 edits")
    func editRateCalculation() async throws {
        let manager = freshManager()
        for _ in 0..<10 {
            manager.recordSession(
                recordingDuration: 10, processingTime: 5,
                asrTime: 2, llmTime: 3, hadError: false
            )
        }
        for _ in 0..<5 {
            manager.recordEdit()
        }
        let today = manager.dailyStats.first
        #expect(today != nil)
        #expect(abs((today?.editRate ?? 0) - 0.5) < 0.001)
    }

    @Test("averageSessionDuration is total / count")
    func averageSessionDurationCalculation() async throws {
        let manager = freshManager()
        manager.recordSession(
            recordingDuration: 10, processingTime: 5,
            asrTime: 2, llmTime: 3, hadError: false
        )
        manager.recordSession(
            recordingDuration: 10, processingTime: 5,
            asrTime: 2, llmTime: 3, hadError: false
        )
        let today = manager.dailyStats.first
        #expect(today != nil)
        #expect(abs((today?.averageSessionDuration ?? 0) - 10) < 0.001)
    }
}
