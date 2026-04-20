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
        // Match the other settings tabs (RecordingSettingsTab, ASRSettingsTab,
        // …) which use Form{} as the top-level container — Form gives consistent
        // padding, divider rendering, and a single scrollbar that only appears
        // when content overflows. The previous ScrollView+List combo produced
        // two visible scrollbars on the right side.
        Form {
            Section {
                OverviewSection(stats: statsManager.getAggregateStats())
            } header: {
                Text(String(localized: "总览"))
            }

            Section {
                Last7DaysChart(stats: statsManager.getStatsForLast7Days())
            } header: {
                Text(String(localized: "最近 7 天"))
            }

            Section {
                DetailedStatsTable(stats: statsManager.getStatsForLast30Days())
            } header: {
                Text(String(localized: "详细数据"))
            }

            Section {
                ClearStatsButton()
            } header: {
                Text(String(localized: "危险操作"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 总览卡片

struct OverviewSection: View {
    let stats: AggregateStats

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(
                    title: String(localized: "总使用次数"),
                    value: "\(stats.totalSessions)",
                    icon: "mic.fill",
                    color: .blue
                )
                StatCard(
                    title: String(localized: "总输入字数"),
                    value: formatCharacterCount(stats.totalCharacters),
                    icon: "text.cursor",
                    color: .purple
                )
                StatCard(
                    title: String(localized: "累计节省时间"),
                    value: stats.estimatedTimeSavedFormatted,
                    icon: "bolt.fill",
                    color: .yellow
                )
            }
            HStack(spacing: 12) {
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

    private func formatCharacterCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
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
                .minimumScaleFactor(0.8)
                .lineLimit(1)
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
        if stats.isEmpty {
            Text(String(localized: "暂无数据"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            // Scale bars relative to the max for the visible range so light
            // usage days don't end up as zero-height invisible bars.
            let peak = max(1, stats.map(\.sessionCount).max() ?? 1)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(stats) { day in
                    VStack(spacing: 4) {
                        Text("\(day.sessionCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(height: max(2, CGFloat(day.sessionCount) / CGFloat(peak) * 100))
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

// MARK: - 详细数据表

struct DetailedStatsTable: View {
    let stats: [DailyStats]

    private let dayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    var body: some View {
        if stats.isEmpty {
            Text(String(localized: "暂无数据"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // Use ForEach (not List) inside Form so the parent Form provides
            // the single scrollbar — List would add a second nested scroll view.
            VStack(spacing: 6) {
                // header row
                HStack {
                    Text(String(localized: "日期"))
                        .frame(width: 60, alignment: .leading)
                    Text(String(localized: "次数"))
                        .frame(width: 60, alignment: .trailing)
                    Text(String(localized: "录音时长"))
                        .frame(width: 80, alignment: .trailing)
                    Text(String(localized: "编辑率"))
                        .frame(width: 60, alignment: .trailing)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(stats) { day in
                    HStack {
                        Text(dayDateFormatter.string(from: day.date))
                            .frame(width: 60, alignment: .leading)
                        Text("\(day.sessionCount)")
                            .frame(width: 60, alignment: .trailing)
                        Text(formatDuration(day.totalRecordingDuration))
                            .frame(width: 80, alignment: .trailing)
                            .monospacedDigit()
                        Text(String(format: "%.0f%%", day.editRate * 100))
                            .frame(width: 60, alignment: .trailing)
                            .monospacedDigit()
                        Spacer()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - 清除数据按钮

struct ClearStatsButton: View {
    @State private var showConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(String(localized: "清除所有统计数据"), role: .destructive) {
                showConfirmation = true
            }
            Text(String(localized: "此操作不可逆，将删除所有历史使用数据"))
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
