//
//  UpdateChecker.swift
//  Talk
//
//  启动时检查 GitHub 是否有新版本
//
//  注意: 版本比较依赖 MARKETING_VERSION (CFBundleShortVersionString)，
//  每次发布新版本时需在 Xcode 项目设置中同步更新 MARKETING_VERSION。
//

import Foundation
import AppKit

@MainActor
class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "platx-ai"
    private let repoName = "Talk"
    private let currentVersion: String

    /// UserDefaults keys
    private static let skippedVersionKey = "skippedVersion"
    private static let lastCheckDateKey = "lastUpdateCheckDate"

    /// Minimum interval between checks (24 hours)
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check GitHub for latest release. Call on app launch (fire-and-forget).
    func checkForUpdates() {
        Task.detached(priority: .background) {
            await self.performCheck()
        }
    }

    private func performCheck() async {
        // Throttle: skip if checked within the last 24 hours
        if let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckDateKey) as? Date,
           Date().timeIntervalSince(lastCheck) < Self.checkInterval {
            AppLogger.debug("距上次检查不足 24 小时，跳过更新检查", category: .general)
            return
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            // Record successful check time
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckDateKey)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            // Strip "v" prefix: "v0.2.1" -> "0.2.1"
            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // Respect "skip this version"
            if let skipped = UserDefaults.standard.string(forKey: Self.skippedVersionKey),
               skipped == latestVersion {
                AppLogger.debug("用户已跳过版本 \(latestVersion)", category: .general)
                return
            }

            if Self.isNewerVersion(latestVersion, than: currentVersion) {
                await MainActor.run {
                    showUpdateAlert(latestVersion: latestVersion, releaseURL: htmlURL)
                }
            } else {
                AppLogger.info("已是最新版本 (\(currentVersion))", category: .general)
            }
        } catch {
            // Silently fail — network issues shouldn't bother the user
            AppLogger.debug("更新检查失败: \(error.localizedDescription)", category: .general)
        }
    }

    /// Compare semantic versions: "0.2.1" > "0.2.0" -> true
    static func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv > cv { return true }
            if lv < cv { return false }
        }
        return false
    }

    private func showUpdateAlert(latestVersion: String, releaseURL: String) {
        let alert = NSAlert()
        alert.messageText = "Talk 有新版本"
        alert.informativeText = "当前版本: \(currentVersion)\n最新版本: \(latestVersion)\n\n是否前往下载？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后提醒")
        alert.addButton(withTitle: "跳过此版本")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if let url = URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(latestVersion, forKey: Self.skippedVersionKey)
        default:
            break
        }
    }
}
