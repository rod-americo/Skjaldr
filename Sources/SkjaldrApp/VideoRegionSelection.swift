import AppKit
import CoreGraphics

@MainActor
final class VideoRegionSelectionController {
    private var windows: [SelectionOverlayWindow] = []
    private var continuation: CheckedContinuation<CaptureSelection?, Never>?
    private var keyMonitor: Any?
    private weak var activeView: SelectionOverlayView?
    private var activeRegion: CGRect?

    func selectRegion(
        preset: PhoneVideoPreset,
        restoring storedRegion: StoredCaptureRegion?
    ) async -> CaptureSelection? {
        cancel()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            presentOverlays(preset: preset, storedRegion: storedRegion)
        }
    }

    func cancel() {
        finish(with: nil)
    }

    private func presentOverlays(
        preset: PhoneVideoPreset,
        storedRegion: StoredCaptureRegion?
    ) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finish(with: nil)
            return
        }

        for screen in screens {
            let window = SelectionOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            // `screen.frame` já está no espaço global do AppKit. Não passar
            // `screen:` evita que a origem seja aplicada uma segunda vez.
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            // A janela é possuída pelo array Swift. Impedir que AppKit também
            // a libere ao fechar evita uma dupla liberação ao encerrar a seleção.
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.animationBehavior = .none

            let view = SelectionOverlayView(preset: preset)
            view.onSelectionChanged = { [weak self, weak view] region in
                guard let self, let view else { return }
                self.activate(view: view, region: region)
            }
            view.onConfirm = { [weak self] in
                self?.confirm()
            }
            window.contentView = view

            if let storedRegion,
               screen.displayID == storedRegion.displayID,
               let globalRegion = storedRegion.region(in: screen.frame) {
                let localRegion = window.convertFromScreen(globalRegion)
                view.region = localRegion
                activeView = view
                activeRegion = localRegion
            }

            windows.append(window)
            window.orderFrontRegardless()
        }

        let mouseLocation = NSEvent.mouseLocation
        let preferredWindow = windows.first {
            $0.screen?.frame.contains(mouseLocation) == true
        } ?? windows.first
        preferredWindow?.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 36, 76:
                self?.confirm()
                return nil
            case 53:
                self?.finish(with: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func activate(view: SelectionOverlayView, region: CGRect?) {
        activeView = view
        activeRegion = region
        for window in windows {
            guard let otherView = window.contentView as? SelectionOverlayView,
                  otherView !== view
            else {
                continue
            }
            otherView.region = nil
        }
    }

    private func confirm() {
        guard let view = activeView,
              let localRegion = activeRegion,
              VideoRegionGeometry.isValid(
                localRegion,
                aspectRatio: view.preset.aspectRatio
              ),
              let window = view.window,
              let screen = window.screen,
              let displayID = screen.displayID
        else {
            NSSound.beep()
            return
        }

        let globalRegion = window.convertToScreen(localRegion)
        finish(
            with: CaptureSelection(
                displayID: displayID,
                screenFrame: screen.frame,
                region: globalRegion
            )
        )
    }

    private func finish(with result: CaptureSelection?) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        activeView = nil
        activeRegion = nil

        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}

private final class SelectionOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayView: NSView {
    let preset: PhoneVideoPreset
    var onSelectionChanged: ((CGRect?) -> Void)?
    var onConfirm: (() -> Void)?

    var region: CGRect? {
        didSet {
            needsDisplay = true
            if let window {
                window.invalidateCursorRects(for: self)
            }
        }
    }

    private enum Interaction {
        case none
        case creating(anchor: CGPoint)
        case moving(pointer: CGPoint, original: CGRect)
        case resizing(anchor: CGPoint)
    }

    private var interaction: Interaction = .none
    private let handleHitRadius: CGFloat = 14

    init(preset: PhoneVideoPreset) {
        self.preset = preset
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é usado")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if let region, !region.isEmpty {
            addCursorRect(region, cursor: .openHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let region, let resizeAnchor = oppositeCorner(for: point, in: region) {
            interaction = .resizing(anchor: resizeAnchor)
        } else if let region, region.contains(point) {
            interaction = .moving(pointer: point, original: region)
        } else {
            region = .zero
            interaction = .creating(anchor: point)
            onSelectionChanged?(region)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch interaction {
        case .none:
            break
        case let .creating(anchor), let .resizing(anchor):
            region = VideoRegionGeometry.region(
                from: anchor,
                to: point,
                aspectRatio: preset.aspectRatio,
                inside: bounds
            )
            onSelectionChanged?(region)
        case let .moving(pointer, original):
            let delta = CGPoint(x: point.x - pointer.x, y: point.y - pointer.y)
            region = VideoRegionGeometry.moved(original, by: delta, inside: bounds)
            onSelectionChanged?(region)
        }
    }

    override func mouseUp(with event: NSEvent) {
        interaction = .none
        guard let region,
              VideoRegionGeometry.isValid(region, aspectRatio: preset.aspectRatio)
        else {
            self.region = nil
            onSelectionChanged?(nil)
            return
        }
        onSelectionChanged?(region)
        if event.clickCount == 2 {
            onConfirm?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.46).setFill()
        let dimmingPath = NSBezierPath(rect: bounds)
        if let region, !region.isEmpty {
            dimmingPath.appendRect(region)
            dimmingPath.windingRule = .evenOdd
        }
        dimmingPath.fill()

        if let region, !region.isEmpty {
            drawSelection(region)
        }
        drawInstructions()
    }

    private func drawSelection(_ region: CGRect) {
        // O preenchimento quase transparente mantém toda a área interna
        // interativa. Sem ele, uma janela não opaca pode deixar o clique
        // atravessar pelo recorte visual até o aplicativo que está abaixo.
        NSColor.controlAccentColor.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: region, xRadius: 8, yRadius: 8).fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(roundedRect: region, xRadius: 8, yRadius: 8)
        border.lineWidth = 3
        border.stroke()

        for corner in corners(of: region) {
            let handle = CGRect(
                x: corner.x - 5,
                y: corner.y - 5,
                width: 10,
                height: 10
            )
            NSColor.white.setFill()
            NSBezierPath(ovalIn: handle).fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(ovalIn: handle)
            outline.lineWidth = 2
            outline.stroke()
        }

        let dimensions = "\(Int(region.width)) × \(Int(region.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = dimensions.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: region.midX - size.width / 2 - 8,
            y: max(bounds.minY + 8, region.minY - size.height - 16),
            width: size.width + 16,
            height: size.height + 8
        )
        NSColor.black.withAlphaComponent(0.74).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 7, yRadius: 7).fill()
        dimensions.draw(
            at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4),
            withAttributes: attributes
        )
    }

    private func drawInstructions() {
        let title = preset.title
        let detail = if region == nil {
            "Arraste para selecionar • Enter inicia • Esc cancela"
        } else {
            "Arraste dentro para mover • alças redimensionam • Enter inicia"
        }
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8)
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let detailSize = detail.size(withAttributes: detailAttributes)
        let width = max(titleSize.width, detailSize.width) + 32
        let panel = CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - 92,
            width: width,
            height: 62
        )
        NSColor.black.withAlphaComponent(0.76).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14).fill()
        title.draw(
            at: CGPoint(x: panel.midX - titleSize.width / 2, y: panel.maxY - 27),
            withAttributes: titleAttributes
        )
        detail.draw(
            at: CGPoint(x: panel.midX - detailSize.width / 2, y: panel.minY + 10),
            withAttributes: detailAttributes
        )
    }

    private func oppositeCorner(for point: CGPoint, in region: CGRect) -> CGPoint? {
        let corners = corners(of: region)
        guard let index = corners.firstIndex(where: {
            hypot(point.x - $0.x, point.y - $0.y) <= handleHitRadius
        }) else {
            return nil
        }
        return corners[[2, 3, 0, 1][index]]
    }

    private func corners(of region: CGRect) -> [CGPoint] {
        [
            CGPoint(x: region.minX, y: region.minY),
            CGPoint(x: region.maxX, y: region.minY),
            CGPoint(x: region.maxX, y: region.maxY),
            CGPoint(x: region.minX, y: region.maxY)
        ]
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
