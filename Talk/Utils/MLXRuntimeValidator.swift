//
//  MLXRuntimeValidator.swift
//  Talk
//
//  MLX 运行时依赖检查
//

import Foundation

enum MLXRuntimeValidator {
    static func missingMetalLibraryReason() -> String? {
        let fileManager = FileManager.default

        var candidates: [URL] = []

        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDir.appendingPathComponent("mlx.metallib"))
            candidates.append(executableDir.appendingPathComponent("default.metallib"))
            candidates.append(executableDir.appendingPathComponent("Resources/mlx.metallib"))
            candidates.append(executableDir.appendingPathComponent("Resources/default.metallib"))
            candidates.append(executableDir.appendingPathComponent("mlx-swift_Cmlx.bundle/default.metallib"))
            candidates.append(executableDir.appendingPathComponent("Cmlx.bundle/default.metallib"))
        }

        if let mainResourceURL = Bundle.main.resourceURL {
            candidates.append(mainResourceURL.appendingPathComponent("mlx.metallib"))
            candidates.append(mainResourceURL.appendingPathComponent("default.metallib"))
            candidates.append(mainResourceURL.appendingPathComponent("mlx-swift_Cmlx.bundle/default.metallib"))
            candidates.append(mainResourceURL.appendingPathComponent("Cmlx.bundle/default.metallib"))
        }

        for bundle in (Bundle.allBundles + Bundle.allFrameworks) {
            guard let resourceURL = bundle.resourceURL else { continue }
            candidates.append(resourceURL.appendingPathComponent("default.metallib"))
            candidates.append(resourceURL.appendingPathComponent("mlx.metallib"))
        }

        if candidates.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            return nil
        }

        let searched = candidates.prefix(6).map { $0.path }.joined(separator: "; ")
        return "未找到 MLX Metal 库文件（default.metallib/mlx.metallib）。已检查路径示例: \(searched)"
    }
}
