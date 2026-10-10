import Foundation

/// The exact files of one speech model at a pinned Hugging Face revision.
struct TranscriptionModelManifest: Sendable {
    struct File: Sendable {
        let name: String
        let bytes: Int64
        let sha256: String
    }

    let repository: String
    let revision: String
    /// Folder under `AppPaths.modelsDirectory`; names the revision so an upgrade never mixes files.
    let folderName: String
    let files: [File]

    var modelID: String { "\(repository)@\(revision.prefix(7))" }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    func remoteURL(for file: File) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.name)")!
    }

    /// Only what the MLX runtime reads: weights, config, vocabulary and the language map. Sizes and
    /// hashes come from the repository's `checksums.json` at this revision.
    static let nemotron = TranscriptionModelManifest(
        repository: "aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit",
        revision: "5339193d26b1eda4461358c6210f5039e97af213",
        folderName: "nemotron-0.6b-int8-5339193",
        files: [
            // Small files first: a bad URL or revision fails in a second, not after 730 MB.
            File(name: "config.json", bytes: 1_718,
                 sha256: "284d6b51bd2b5a5717ae34caff2ff362535790a853992cd2e06996230699f649"),
            File(name: "vocab.json", bytes: 103_278,
                 sha256: "f7218f3ae2c5baf002974a7babf50ee1f719732fb1f349eeefb86b62219dc0cd"),
            File(name: "languages.json", bytes: 2_020,
                 sha256: "a1efe863e1057d4658bce8175c978020ac35a63a3c9a65ae899f324a32c8e4f6"),
            File(name: "model.safetensors", bytes: 767_629_118,
                 sha256: "4d7598b934dc106dd648b0299cbb7795c5641761bb158abde9d20558808f8050"),
        ]
    )
}
