import Foundation

/// "Launch at login" as one per-user LaunchAgent, the same plist `./install` writes, so the installer and the
/// Settings toggle never disagree. It runs `open <app>` once at login (no KeepAlive, so Quit stays quit); `open`
/// also makes loading it while the app runs harmless, since LaunchServices won't start a second copy.
struct LoginLaunchAgent: Sendable {
    let label: String
    let appURL: URL
    let plistURL: URL

    static let current = LoginLaunchAgent(
        label: AppPaths.identifier,
        appURL: Bundle.main.bundleURL,
        plistURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(AppPaths.identifier).plist")
    )

    var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    func enable() throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", appURL.path],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
        // Reload so an older plist (e.g. pointing at another app path) is replaced in launchd too.
        try? launchctl("bootout", "\(domain)/\(label)")
        try launchctl("bootstrap", domain, plistURL.path)
    }

    func disable() throws {
        // Not loaded is fine: the plist alone is what launchd reads at the next login.
        try? launchctl("bootout", "\(domain)/\(label)")
        if isEnabled { try FileManager.default.removeItem(at: plistURL) }
    }

    private var domain: String { "gui/\(getuid())" }

    private func launchctl(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let error = Pipe()
        process.standardError = error
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LaunchAgentError.launchctlFailed(arguments.first ?? "", message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum LaunchAgentError: LocalizedError {
    case launchctlFailed(String, String)

    var errorDescription: String? {
        switch self {
        case let .launchctlFailed(command, message):
            "launchctl \(command) failed\(message.isEmpty ? "" : ": \(message)")"
        }
    }
}
