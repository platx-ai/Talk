//
//  SettingsView+Statistics.swift
//  Talk
//
//  统计设置视图
//

import SwiftUI

/// 统计设置视图
struct StatisticsView: View {
    @ObservationIgnored
    private let statsManager = UsageStatisticsManager.shared
    
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 总览卡片
                OverviewSection(stats: statsManager.getAggregateStats())
                
                Divider()
                
                // 最近 7 天图表
                Last7DaysChart(stats: statsManager.getStatsForLast7Days())
                
                Divider()
                
                // 详细数据表
                DetailedStatsTable(stats: statsManager.getStatsForLast30Days())
                
                Divider()
                
                // 清除数据按钮
                ClearStatsButton()
            }
            .padding()
        }
        .frame(width: 550, height: 450)
    }
}

// MARK: - 总览卡片

struct OverviewSection: View {
    let stats: AggregateStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("总览")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatCard(
                    title: String(localized: "总使用次数"),
                    value: "\(stats.totalSessions)",
                    icon: "mic.fill",
                    color: .blue
                )
                
                StatCard(
                    title: String(localized: "总录音时长"),
                    value: stats.totalDurationFormatted,
                    icon: "clock.fill",
                    color: .green
                )
                
                StatCard(
                    title: String(localized: "编辑率"),
                    value: String(format: "%.1f%%", stats.averageEditRate * 100),
                    icon: "pencil.tip.crop.circle",
                    color: .orange
                )
                
                StatCard(
                    title: String(localized: "错误率"),
                    value: String(format: "%.1f%%", stats.averageErrorRate * 100),
                    icon: "exclamationmark.triangle.fill",
                    color: .red
                )
            }
        }
    }
}

// MARK: - 统计卡片

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 7 天图表

struct Last7DaysChart: View {
    let stats: [DailyStats]
    
    private let dayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近 7 天")
                .font(.headline)
            
            if stats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(stats) { day in
                        VStack(spacing: 4) {
                            Text("\(day.sessionCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Rectangle()
                                .fill(Color.blue.opacity(0.6))
                                .frame(height: min(CGFloat(day.sessionCount) * 10, 100))
                                .frame(maxWidth: .infinity)
                            
                            Text(dayDateFormatter.string(from: day.date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(height: 150)
            }
        }
    }
}

// MARK: - 详细数据表

struct DetailedStatsTable: View {
    let stats: [DailyStats]
    
    private let dayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("详细数据")
                .font(.headline)
            
            if stats.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(stats) { day in
                    HStack {
                        Text(dayDateFormatter.string(from: day.date))
                            .frame(width: 60, alignment: .leading)
                        
                        Text(String(localized: "\(day.sessionCount) 次"))
                            .frame(width: 60)
                        
                        Text(formatDuration(day.totalRecordingDuration))
                            .frame(width: 80)
                        
                        Text(String(format: "%.0f%%", day.editRate * 100))
                            .frame(width: 50)
                        
                        Spacer()
                    }
                    .font(.caption)
                }
                .frame(height: min(CGFloat(stats.count) * 30, 200))
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(localized: "\(minutes):\(String(format: "%02d", seconds))")
    }
}

// MARK: - 清除数据按钮

struct ClearStatsButton: View {
    @State private var showConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("危险操作")
                .font(.headline)
            
            Button("清除所有统计数据", role: .destructive) {
                showConfirmation = true
            }
            
            Text("此操作不可逆，将删除所有历史使用数据")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(String(localized: "确认清除"), isPresented: $showConfirmation) {
            Button(String(localized: "清除"), role: .destructive) {
                UsageStatisticsManager.shared.clearAllStats()
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "确定要清除所有统计数据吗？此操作不可逆。"))
        }
    }
}

#Preview {
    StatisticsView()
}
