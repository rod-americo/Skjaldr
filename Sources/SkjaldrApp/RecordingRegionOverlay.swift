import AppKit
import CoreGraphics

@MainActor
final class RecordingRegionOverlayController {
    private var windows: [RecordingRegionOverlayWindow] = []

    func show(selection: CaptureSelection) {
        hide()

        let borderWidth = RecordingRegionOverlayView.borderWidth
        let frames = Self.borderFrames(
            for: selection.region,
            borderWidth: borderWidth
        )
        windows = frames.enumerated().map { index, frame in
            let window = RecordingRegionOverlayWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.setFrame(frame, display: false)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
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
            window.contentView = RecordingRegionOverlayView(
                orientation: index < 2 ? .horizontal : .vertical
            )
            window.orderFrontRegardless()
            return window
        }
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
    }

    nonisolated static func borderFrames(
        for region: CGRect,
        borderWidth: CGFloat
    ) -> [CGRect] {
        let thickness = borderWidth + 2
        return [
            CGRect(
                x: region.minX - thickness,
                y: region.maxY,
                width: region.width + (2 * thickness),
                height: thickness
            ),
            CGRect(
                x: region.minX - thickness,
                y: region.minY - thickness,
                width: region.width + (2 * thickness),
                height: thickness
            ),
            CGRect(
                x: region.minX - thickness,
                y: region.minY,
                width: thickness,
                height: region.height
            ),
            CGRect(
                x: region.maxX,
                y: region.minY,
                width: thickness,
                height: region.height
            )
        ]
    }
}

private final class RecordingRegionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class RecordingRegionOverlayView: NSView {
    static let borderWidth: CGFloat = 3
    enum Orientation {
        case horizontal
        case vertical
    }

    private let orientation: Orientation

    init(orientation: Orientation) {
        self.orientation = orientation
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.setFill()
        bounds.fill()

        let accentRect: CGRect
        switch orientation {
        case .horizontal:
            accentRect = bounds.insetBy(dx: 0, dy: 1)
        case .vertical:
            accentRect = bounds.insetBy(dx: 1, dy: 0)
        }
        NSColor.controlAccentColor.setFill()
        accentRect.fill()
    }
}
