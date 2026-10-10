import SwiftUI

/// 16:9 preview. Click opens the file; dragging hands the file itself to any app.
struct ToastThumbnail: View {
    let model: SavedToastModel

    var body: some View {
        ZStack {
            if let image = model.thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color.indigo.opacity(0.6), Color.purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Image(systemName: "play.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: Circle())
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            Text(model.durationText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: ToastLayout.cornerRadius - 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: model.openRecording)
        .onDrag { NSItemProvider(object: model.recording.result.url as NSURL) }
        .help("Click to play, or drag into any app")
        .accessibilityLabel("Recording preview")
        .accessibilityAddTraits(.isButton)
    }
}
