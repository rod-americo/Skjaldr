import AppKit
import SwiftUI

@MainActor
final class VideoCompletionBannerController {
    private var panel: VideoCompletionBannerPanel?
    private var dismissalTask: Task<Void, Never>?

    func present(url: URL) {
        dismissalTask?.cancel()
        panel?.orderOut(nil)

        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        guard let screen else { return }

        let size = CGSize(width: 330, height: 78)
        let frame = Self.frame(
            in: screen.visibleFrame,
            bannerSize: size
        )
        let panel = VideoCompletionBannerPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(
            rootView: VideoCompletionBanner(url: url)
        )
        panel.orderFrontRegardless()
        self.panel = panel

        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }

    nonisolated static func frame(
        in visibleFrame: CGRect,
        bannerSize: CGSize,
        margin: CGFloat = 16
    ) -> CGRect {
        CGRect(
            x: visibleFrame.maxX - bannerSize.width - margin,
            y: visibleFrame.minY + margin,
            width: bannerSize.width,
            height: bannerSize.height
        )
    }
}

private final class VideoCompletionBannerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct VideoCompletionBanner: View {
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Vídeo pronto")
                    .font(.headline)
                Text("Link criado e copiado")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.12))
        }
    }
}
