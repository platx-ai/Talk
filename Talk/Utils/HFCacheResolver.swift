//
//  HFCacheResolver.swift
//  Talk
//
//  Resolves a HuggingFace model id (e.g. "mlx-community/Qwen3.5-4B-MLX-4bit")
//  to its local snapshot directory under ~/.cache/huggingface/hub/.
//
//  Why this exists: by default mlx-swift-lm + swift-transformers go through
//  HubApi.snapshot(...), which (a) writes models to ~/Documents/huggingface/
//  (triggering a Documents permission prompt on macOS 14+) and (b) ETag-checks
//  every file against huggingface.co on each load — adding 20+ seconds even
//  when the model is fully cached. By passing
//      ModelConfiguration(directory: snapshotDir)
//  to the model factory, the loader's downloadModel() short-circuits to
//  `case .directory: return directory` and we get a pure mmap load.
//
//  HuggingFace cache layout (used by python `huggingface_hub` and the
//  HuggingFace CLI; ~/.cache/huggingface/hub is where existing users have
//  93GB of weights pre-downloaded):
//
//      ~/.cache/huggingface/hub/
//          models--<org>--<name>/
//              snapshots/
//                  <commit-hash>/    ← what this resolver returns
//                      config.json
//                      *.safetensors
//                      tokenizer.json
//                      ...
//

import Foundation

enum HFCacheResolver {

    /// Returns the on-disk path of the most recent snapshot for the given
    /// HuggingFace model id under ~/.cache/huggingface/hub/, or nil if no
    /// usable snapshot exists.
    ///
    /// "Usable" = the snapshot directory contains config.json. We don't
    /// touch model.safetensors here because some quantized models split
    /// weights into shards and naming varies — config.json is enough for
    /// mlx-swift-lm to discover the rest.
    static func snapshotDirectory(for modelId: String) -> URL? {
        let dirName = "models--" + modelId.replacingOccurrences(of: "/", with: "--")
        let cacheRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent(dirName)
        let snapshotsDir = cacheRoot.appendingPathComponent("snapshots")

        guard FileManager.default.fileExists(atPath: snapshotsDir.path) else {
            return nil
        }

        // Pick the most recently modified snapshot. swift-huggingface only
        // keeps one but the python CLI may keep several; take the freshest.
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return nil
        }

        let snapshots = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !snapshots.isEmpty else { return nil }

        let sorted = snapshots.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }

        return sorted.first { url in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path)
        }
    }
}
