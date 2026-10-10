import SwiftUI

@MainActor @Observable
final class CountdownModel {
    var remaining: Int

    init(remaining: Int) {
        self.remaining = remaining
    }
}

/// Dimmed backdrop with the recording area left clear and a glass dial counting down.
struct CountdownView: View {
    private static let dialDiameter: CGFloat = 160
    private static let hintGap: CGFloat = 20
    private static let hintHeight: CGFloat = 32
    private static let edgeMargin: CGFloat = 16
    private static let fullDisplayDim = 0.25

    let model: CountdownModel
    let screenSize: CGSize
    /// Screen-local, top-left origin (SwiftUI's own space); nil counts down over the whole display.
    let area: CGRect?

    var body: some View {
        ZStack {
            // Near-transparent base: fully clear window pixels would let clicks reach the apps below.
            Color.black.opacity(0.01)
            backdrop
            dial.position(dialCenter)
            hint.position(x: dialCenter.x, y: dialCenter.y + Self.dialDiameter / 2 + Self.hintGap + Self.hintHeight / 2)
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let area {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: screenSize))
                path.addRect(area)
            }
            .fill(Theme.scrim, style: FillStyle(eoFill: true))
            Rectangle().strokeBorder(.white, lineWidth: 1.5).frame(width: area.width, height: area.height).position(x: area.midX, y: area.midY)
        } else {
            Color.black.opacity(Self.fullDisplayDim)
        }
    }

    private var dial: some View {
        ZStack {
            Text("\(model.remaining)")
                .font(.system(size: 72, weight: .light))
                .monospacedDigit()
                .id(model.remaining)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.78).combined(with: .opacity),
                    removal: .scale(scale: 1.18).combined(with: .opacity)
                ))
        }
        .animation(.easeOut(duration: 0.4), value: model.remaining)
        .frame(width: Self.dialDiameter, height: Self.dialDiameter)
        .glassEffect(.regular, in: .circle)
    }

    private var hint: some View {
        HStack(spacing: 6) {
            OverlayKeyCap(label: "Esc")
            Text("to cancel · click to skip")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: Self.hintHeight)
        .glassEffect(.regular, in: .capsule)
    }

    /// Centered on the area (or display), nudged so the dial and its hint always stay on screen.
    private var dialCenter: CGPoint {
        let focus = area ?? CGRect(origin: .zero, size: screenSize)
        let halfDial = Self.dialDiameter / 2
        let stackHeight = Self.dialDiameter + Self.hintGap + Self.hintHeight
        let minX = halfDial + Self.edgeMargin
        let minY = halfDial + Self.edgeMargin
        let maxX = max(minX, screenSize.width - halfDial - Self.edgeMargin)
        let maxY = max(minY, screenSize.height - stackHeight + halfDial - Self.edgeMargin)
        return CGPoint(x: min(max(focus.midX, minX), maxX), y: min(max(focus.midY, minY), maxY))
    }
}
