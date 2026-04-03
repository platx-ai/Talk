//
//  EditObserver.swift
//  Talk
//
//  注入文本后被动观察用户编辑，收集 (original, edited) 对
//  启发式设计：能检测到就收集，检测不到静默放弃
//

import Foundation
import AppKit
import ApplicationServices

extension Notification.Name {
    static let hotwordLearned = Notification.Name("hotwordLearned")
}

/// 编辑观察结果
struct EditDiff: Sendable {
    let original: String
    let edited: String
    let appBundleId: String?
    let timestamp: Date
}

/// 被动观察注入文本后用户的编辑行为
@Observable
@MainActor
final class EditObserver {
    static let shared = EditObserver()

    // MARK: - 公开状态

    /// 待处理的编辑对比队列（后台 LLM 空闲时消费）
    private(set) var pendingDiffs: [EditDiff] = []

    /// 是否正在观察
    private(set) var isObserving = false

    // MARK: - 配置

    /// 轮询间隔
    private let pollInterval: TimeInterval = 0.5
    /// 去抖时间：文本稳定多久后认为编辑完成
    private let debounceInterval: TimeInterval = 1.5
    /// 队列最大长度（超出时丢弃最旧的）
    private let maxPendingDiffs = 10

    // MARK: - 内部状态

    private var observeTask: Task<Void, Never>?
    private var injectedText: String = ""
    private var prefixAnchor: String?
    private var targetBundleId: String?
    private var targetPID: pid_t = 0

    private init() {}

    // MARK: - 公开接口

    /// 注入完成后开始观察
    /// - Parameters:
    ///   - injectedText: 注入到目标应用的文本
    ///   - targetApp: 目标应用
    ///   - prefixContext: 注入位置前的锚点文本（可选）
    func startObserving(
        injectedText: String,
        targetApp: NSRunningApplication,
        prefixContext: String?
    ) {
        // 停止上一次观察
        stopObserving()

        guard !injectedText.isEmpty else { return }

        let bundleId = targetApp.bundleIdentifier ?? ""

        // 终端类应用直接跳过
        if Self.isTerminalApp(bundleId) {
            AppLogger.debug("EditObserver: 跳过终端应用 \(bundleId)", category: .storage)
            return
        }

        self.injectedText = injectedText
        self.prefixAnchor = prefixContext
        self.targetBundleId = bundleId
        self.targetPID = targetApp.processIdentifier
        self.isObserving = true

        AppLogger.info("EditObserver: 开始观察 (app=\(bundleId), text=\(injectedText.prefix(30))...)", category: .storage)

        observeTask = Task { [weak self] in
            await self?.observeLoop()
        }
    }

    /// 停止观察（新录音开始、或手动停止）
    func stopObserving() {
        guard isObserving else { return }
        observeTask?.cancel()
        observeTask = nil
        isObserving = false
        AppLogger.debug("EditObserver: 停止观察", category: .storage)
    }

    /// 取出并移除队列中的下一个待处理 diff
    func dequeueDiff() -> EditDiff? {
        guard !pendingDiffs.isEmpty else { return nil }
        return pendingDiffs.removeFirst()
    }

    /// 队列是否有待处理项
    var hasPendingDiffs: Bool { !pendingDiffs.isEmpty }

    // MARK: - 观察循环

    private func observeLoop() async {
        // 等待粘贴生效
        try? await Task.sleep(for: .milliseconds(600))

        guard !Task.isCancelled else { return }

        // 获取焦点元素
        let axApp = AXUIElementCreateApplication(targetPID)
        guard let element = Self.getFocusedElement(axApp) else {
            AppLogger.debug("EditObserver: 无法获取焦点元素，放弃观察", category: .storage)
            await MainActor.run { isObserving = false }
            return
        }

        // 读取 baseline
        guard let baseline = Self.getElementValue(element) else {
            AppLogger.debug("EditObserver: 无法读取 kAXValueAttribute，放弃观察", category: .storage)
            await MainActor.run { isObserving = false }
            return
        }

        // 文本太长时放弃（避免大文档的性能问题）
        if baseline.count > 10_000 {
            AppLogger.debug("EditObserver: 控件文本过长 (\(baseline.count) 字符)，放弃观察", category: .storage)
            await MainActor.run { isObserving = false }
            return
        }

        var lastText = baseline
        var lastChangeTime = Date()
        var hasUserEdited = false

        // 轮询循环
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(UInt64(pollInterval * 1000)))
            guard !Task.isCancelled else { break }

            // 检查前台应用是否还是目标应用
            let frontApp = NSWorkspace.shared.frontmostApplication
            if frontApp?.processIdentifier != targetPID {
                AppLogger.debug("EditObserver: 前台应用已切换，结束观察", category: .storage)
                break
            }

            // 检查焦点元素是否还能读取
            guard let currentText = Self.getElementValue(element) else {
                AppLogger.debug("EditObserver: 焦点元素不可读，结束观察", category: .storage)
                break
            }

            // 文本有变化
            if currentText != lastText {
                lastText = currentText
                lastChangeTime = Date()
                hasUserEdited = true
            }

            // 去抖：文本稳定 debounceInterval 后触发收集
            if hasUserEdited && Date().timeIntervalSince(lastChangeTime) >= debounceInterval {
                AppLogger.debug("EditObserver: 文本稳定，触发收集", category: .storage)
                break
            }
        }

        guard !Task.isCancelled else { return }

        // 收集结果
        if hasUserEdited {
            await collectDiff(baseline: baseline, currentText: lastText)
        } else {
            AppLogger.debug("EditObserver: 用户未编辑，不收集", category: .storage)
        }

        await MainActor.run { isObserving = false }
    }

    // MARK: - 收集 Diff

    private func collectDiff(baseline: String, currentText: String) async {
        // 在控件全文中定位注入区域
        let editedRegion = locateInjectedRegion(in: currentText)

        guard let edited = editedRegion, edited != injectedText else {
            AppLogger.debug("EditObserver: 注入区域未变化或无法定位", category: .storage)
            return
        }

        let diff = EditDiff(
            original: injectedText,
            edited: edited,
            appBundleId: targetBundleId,
            timestamp: Date()
        )

        await MainActor.run {
            pendingDiffs.append(diff)
            // 队列溢出时丢弃最旧的
            if pendingDiffs.count > maxPendingDiffs {
                pendingDiffs.removeFirst()
            }
            AppLogger.info("EditObserver: 收集到编辑 diff (队列: \(pendingDiffs.count))", category: .storage)
        }
    }

    /// 在控件全文中定位注入区域
    private func locateInjectedRegion(in fullText: String) -> String? {
        // 策略 1: 使用锚点定位
        if let anchor = prefixAnchor, !anchor.isEmpty,
           let anchorRange = fullText.range(of: anchor) {
            let afterAnchor = fullText[anchorRange.upperBound...]
            // 取注入文本长度附近的内容（允许长度变化 ±50%）
            let expectedLength = injectedText.count
            let maxLength = Int(Double(expectedLength) * 1.5) + 10
            let endIndex = afterAnchor.index(
                afterAnchor.startIndex,
                offsetBy: min(maxLength, afterAnchor.count)
            )
            return String(afterAnchor[afterAnchor.startIndex..<endIndex])
        }

        // 策略 2: 无锚点时，如果全文与注入文本相似度高，直接用全文
        // （适用于空白输入框中注入的场景）
        if fullText.count <= injectedText.count * 2 + 20 {
            return fullText
        }

        // 策略 3: 尝试模糊匹配注入文本在全文中的位置
        // 找到与注入文本最相似的子串
        if let range = fullText.range(of: injectedText) {
            // 注入文本原样存在（用户没改）
            return nil
        }

        // 如果注入文本的前几个词能匹配到
        let firstWords = String(injectedText.prefix(min(20, injectedText.count)))
        if let matchRange = fullText.range(of: firstWords) {
            let afterMatch = fullText[matchRange.lowerBound...]
            let expectedLength = injectedText.count
            let maxLength = Int(Double(expectedLength) * 1.5) + 10
            let endIndex = afterMatch.index(
                afterMatch.startIndex,
                offsetBy: min(maxLength, afterMatch.count)
            )
            return String(afterMatch[afterMatch.startIndex..<endIndex])
        }

        // 定位失败
        AppLogger.debug("EditObserver: 无法定位注入区域", category: .storage)
        return nil
    }

    // MARK: - AX 辅助方法

    private static func getFocusedElement(_ axApp: AXUIElement) -> AXUIElement? {
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success else { return nil }
        return (focusedElement as! AXUIElement)
    }

    private static func getElementValue(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )
        guard result == .success else { return nil }
        return value as? String
    }

    // MARK: - 后台队列处理

    private var processingTask: Task<Void, Never>?

    /// 启动后台处理循环（app 启动时调用一次）
    func startProcessingLoop() {
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            await self?.processingLoop()
        }
    }

    private func processingLoop() async {
        while !Task.isCancelled {
            // 每 5 秒检查一次
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { break }

            // 条件：有待处理项 + LLM 空闲 + 功能开启
            guard hasPendingDiffs,
                  !LLMService.shared.isPolishing,
                  LLMService.shared.isModelLoaded,
                  AppSettings.shared.enableAutoHotwordLearning else {
                continue
            }

            // 取出一条
            guard let diff = dequeueDiff() else { continue }

            AppLogger.info("EditObserver: 后台处理热词提取 (原文=\(diff.original.prefix(30))...)", category: .storage)

            // 调用 LLM 提取
            let corrections = await LLMService.shared.extractHotwords(
                original: diff.original,
                edited: diff.edited
            )

            guard !corrections.isEmpty else {
                AppLogger.debug("EditObserver: 未提取到有效热词", category: .storage)
                continue
            }

            // 学习到词库
            for correction in corrections {
                VocabularyManager.shared.addCorrection(
                    original: correction.original,
                    corrected: correction.corrected
                )
            }

            // 通知 UI
            let summaries = corrections.map { "\($0.original) → \($0.corrected)" }
            let message = summaries.joined(separator: ", ")
            AppLogger.info("EditObserver: 已收录 \(corrections.count) 个热词: \(message)", category: .storage)

            // 发送通知供 UI 显示闪电胶囊
            NotificationCenter.default.post(
                name: .hotwordLearned,
                object: nil,
                userInfo: ["corrections": summaries]
            )
        }
    }

    // MARK: - 应用过滤

    private static func isTerminalApp(_ bundleId: String) -> Bool {
        let keywords = ["terminal", "iterm", "kitty", "wezterm", "hyper", "warp", "alacritty"]
        let lower = bundleId.lowercased()
        return keywords.contains { lower.contains($0) }
    }
}
