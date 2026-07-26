import AppKit
import CoreGraphics

@MainActor
final class RecordingRegionOverlayController {
    private var window: RecordingRegionOverlayWindow?

    func show(selection: CaptureSelection) {
        hide()

        let borderWidth = RecordingRegionOverlayView.borderWidth
        let frame = Self.windowFrame(
            for: selection.region,
            borderWidth: borderWidth
        )
        let window = RecordingRegionOverlayWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.setFrame(frame, display: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.animationBehavior = .none
        window.contentView = RecordingRegionOverlayView()
        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    nonisolated static func windowFrame(
        for region: CGRect,
        borderWidth: CGFloat
    ) -> CGRect {
        region.insetBy(dx: -borderWidth, dy: -borderWidth)
    }
}

private final class RecordingRegionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class RecordingRegionOverlayView: NSView {
    static let borderWidth: CGFloat = 3

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let inset = Self.borderWidth / 2
        let borderRect = bounds.insetBy(dx: inset, dy: inset)

        NSColor.black.withAlphaComponent(0.5).setStroke()
        let contrastBorder = NSBezierPath(rect: borderRect)
        contrastBorder.lineWidth = Self.borderWidth + 2
        contrastBorder.stroke()

        NSColor.controlAccentColor.setStroke()
        let accentBorder = NSBezierPath(rect: borderRect)
        accentBorder.lineWidth = Self.borderWidth
        accentBorder.stroke()
    }
}
