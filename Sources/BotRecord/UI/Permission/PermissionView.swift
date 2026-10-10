import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class PermissionModel {
    enum Phase { case waiting, granted }

    var phase = Phase.waiting
    var didOpenSettings = false
    var relaunchError: String?
}

/// First-run card explaining the one permission BotRecord needs and reconnecting as soon as it is granted.
struct PermissionView: View {
    let model: PermissionModel
    let onOpenSettings: () -> Void
    let onRelaunch: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch model.phase {
            case .waiting: waitingContent
            case .granted: grantedContent
            }
        }
        .padding(24)
        .frame(width: 380)
        .overlay(alignment: .topTrailing) { closeButton }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .animation(.snappy(duration: 0.25), value: model.phase)
    }

    private var waitingContent: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(spacing: 6) {
                Text("Allow screen recording").font(.system(size: 18, weight: .bold))
                Text("BotRecord only captures when you press Record. macOS asks for this once.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                PermissionStep(number: 1, title: "Open System Settings", isDone: model.didOpenSettings)
                PermissionStep(number: 2, title: "Privacy & Security → Screen & System Audio Recording", isDone: false)
                PermissionStep(number: 3, title: "Turn on BotRecord, then relaunch it", detail: "macOS applies the permission on restart", isDone: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onOpenSettings) {
                Text("Open System Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Theme.accent)
            if model.didOpenSettings {
                Button(action: onRelaunch) {
                    Label("Turned it on? Relaunch BotRecord", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
            if let relaunchError = model.relaunchError {
                Text(relaunchError).font(.system(size: 12)).foregroundStyle(Theme.warning).multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for permission…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var grantedContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.success)
            Text("BotRecord is connected").font(.system(size: 18, weight: .bold))
            Text("Press Record whenever you're ready.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 28)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("Close")
    }
}

private struct PermissionStep: View {
    let number: Int
    let title: String
    var detail: String?
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(isDone ? Theme.success : Color.primary.opacity(0.1))
                if isDone {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
