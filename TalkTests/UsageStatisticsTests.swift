//
//  UsageStatisticsTests.swift
//  Talk
//
//  使用统计测试
//

import Testing
import Foundation
@testable import Talk

@Suite("UsageStatistics Tests")
@MainActor
struct UsageStatisticsTests {
    
    @Test("单例共享")
    func sharedInstance() {
        let manager1 = UsageStatisticsManager.shared
        let manager2 = UsageStatisticsManager.shared
        #expect(manager1 === manager2)
    }
    
    @Test("记录单次使用")
    func recordSingleSession() async throws {
        let manager = UsageStatisticsManager.shared
        let initialCount = manager.dailyStats.count
        
        manager.recordSession(
            recordingDuration: 10.0,
            processingTime: 5.0,
            asrTime: 2.0,
            llmTime: 3.0,
            hadError: false
        )
        
        // 验证统计数据已更新
        let today = Calendar.current.startOfDay(for: Date())
        let todayStats = manager.dailyStats.first { 
            Calendar.current.isDate($0.date, inSameDayAs: today) 
        }
        
        #expect(todayStats != nil)
        #expect(todayStats?.sessionCount ?? 0 == 1)
        #expect(todayStats?.totalRecordingDuration == 10.0)
        #expect(todayStats?.asrInferenceTime == 2.0)
        #expect(todayStats?.llmInferenceTime == 3.0)
        #expect(todayStats?.errorCount ?? 0 == 0)
    }
    
    @Test("记录错误会话")
    func recordSessionWithError() async throws {
        let manager = UsageStatisticsManager.shared
        
        manager.recordSession(
            recordingDuration: 10.0,
            processingTime: 5.0,
            asrTime: 2.0,
            llmTime: 3.0,
            hadError: true
        )
        
        let today = Calendar.current.startOfDay(for: Date())
        let todayStats = manager.dailyStats.first { 
            Calendar.current.isDate($0.date, inSameDayAs: today) 
        }
        
        #expect(todayStats?.errorCount ?? 0 >= 1)
    }
    
    @Test("记录编辑")
    func recordEdit() async throws {
        let manager = UsageStatisticsManager.shared
        
        // 先记录一次使用
        manager.recordSession(
            recordingDuration: 10.0,
            processingTime: 5.0,
            asrTime: 2.0,
            llmTime: 3.0,
            hadError: false
        )
        
        // 记录编辑
        manager.recordEdit()
        
        let today = Calendar.current.startOfDay(for: Date())
        let todayStats = manager.dailyStats.first { 
            Calendar.current.isDate($0.date, inSameDayAs: today) 
        }
        
        #expect(todayStats?.editCount ?? 0 >= 1)
    }
    
    @Test("获取最近 7 天数据 - 验证排序")
    func getStatsForLast7Days() async throws {
        let manager = UsageStatisticsManager.shared
        let stats = manager.getStatsForLast7Days()
        
        // 验证按日期排序
        if stats.count > 1 {
            for i in 0..<(stats.count - 1) {
                #expect(stats[i].date <= stats[i + 1].date)
            }
        }
    }
    
    @Test("聚合统计计算")
    func getAggregateStats() async throws {
        let manager = UsageStatisticsManager.shared
        let initialStats = manager.getAggregateStats()
        
        // 记录多次使用
        manager.recordSession(
            recordingDuration: 10.0,
            processingTime: 5.0,
            asrTime: 2.0,
            llmTime: 3.0,
            hadError: false
        )
        manager.recordSession(
            recordingDuration: 20.0,
            processingTime: 10.0,
            asrTime: 4.0,
            llmTime: 6.0,
            hadError: true
        )
        manager.recordEdit()
        
        let aggregate = manager.getAggregateStats()
        
        // 验证至少增加了 2 次会话
        #expect(aggregate.totalSessions >= initialStats.totalSessions + 2)
        // 验证至少有 1 次编辑
        #expect(aggregate.totalEdits >= initialStats.totalEdits + 1)
        // 验证至少有 1 次错误
        #expect(aggregate.totalErrors >= initialStats.totalErrors + 1)
    }
    
    @Test("清空统计")
    func clearAllStats() async throws {
        let manager = UsageStatisticsManager.shared
        let initialCount = manager.dailyStats.count
        
        // 清空
        manager.clearAllStats()
        
        #expect(manager.dailyStats.isEmpty)
    }
    
    @Test("编辑率计算")
    func editRateCalculation() async throws {
        let manager = UsageStatisticsManager.shared
        
        // 记录 10 次使用
        for _ in 0..<10 {
            manager.recordSession(
                recordingDuration: 10.0,
                processingTime: 5.0,
                asrTime: 2.0,
                llmTime: 3.0,
                hadError: false
            )
        }
        
        // 记录 5 次编辑
        for _ in 0..<5 {
            manager.recordEdit()
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        let todayStats = manager.dailyStats.first { 
            Calendar.current.isDate($0.date, inSameDayAs: today) 
        }
        
        // 编辑率应该是 50%
        if let editRate = todayStats?.editRate {
            #expect(abs(editRate - 0.5) < 0.01)
        } else {
            Issue.record("todayStats is nil or editRate is nil")
        }
    }
    
    @Test("平均会话时长计算")
    func averageSessionDurationCalculation() async throws {
        let manager = UsageStatisticsManager.shared
        
        // 记录 2 次使用，每次 10 秒
        manager.recordSession(
            recordingDuration: 10.0,
            processingTime: 5.0,
            asrTime: 2.0,
            llmTime: 3.0,
            hadError: false
        )
        manager.recordSession(
            recordingDuration: 10.0,
            processingTime: 5.0,
            asrTime: 2.0,
            llmTime: 3.0,
            hadError: false
        )
        
        let today = Calendar.current.startOfDay(for: Date())
        let todayStats = manager.dailyStats.first { 
            Calendar.current.isDate($0.date, inSameDayAs: today) 
        }
        
        // 平均时长应该是 10 秒
        if let avgDuration = todayStats?.averageSessionDuration {
            #expect(abs(avgDuration - 10.0) < 0.01)
        } else {
            Issue.record("todayStats is nil or averageSessionDuration is nil")
        }
    }
}
