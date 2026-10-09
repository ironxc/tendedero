import AppKit

@MainActor
final class PinnedImageWindow: NSPanel {
    private let pinnedView: PinnedImageView
    var onClose: (() -> Void)?

    init(image: NSImage, frame: CGRect) {
        pinnedView = PinnedImageView(image: image)
        super.init(contentRect: Self.windowFrame(for: frame),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = pinnedView
        pinnedView.onClose = { [weak self] in self?.closePinned() }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(pinnedView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { closePinned() } else { super.keyDown(with: event) }
    }

    private func closePinned() {
        orderOut(nil)
        onClose?()
    }

    private static func windowFrame(for rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY,
               width: max(32, rect.width), height: max(32, rect.height))
    }
}

private final class PinnedImageView: NSView {
    let image: NSImage
    var onClose: () -> Void = {}
    private var dragStart: CGPoint?
    private var windowStart: CGPoint?
    private var hoveringClose = false

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        hoveringClose = closeHotZone.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveringClose = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeRect.contains(point) {
            onClose()
            return
        }
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let windowStart, let window else { return }
        let mouse = NSEvent.mouseLocation
        let delta = CGPoint(x: mouse.x - dragStart.x, y: mouse.y - dragStart.y)
        window.setFrameOrigin(CGPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        windowStart = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        let raw = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
        guard raw != 0 else { return }
        let factor = max(0.82, min(1.22, exp(raw * 0.012)))
        let frame = window.frame
        let minSide: CGFloat = 48
        let maxSide: CGFloat = 2400
        let proposed = CGSize(width: frame.width * factor, height: frame.height * factor)
        guard proposed.width >= minSide, proposed.height >= minSide,
              proposed.width <= maxSide, proposed.height <= maxSide else { return }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let resized = CGRect(x: center.x - proposed.width / 2,
                             y: center.y - proposed.height / 2,
                             width: proposed.width, height: proposed.height)
        window.setFrame(resized, display: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose() } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        image.draw(in: bounds)

        guard hoveringClose else { return }
        let badge = closeRect
        NSColor.black.withAlphaComponent(hoveringClose ? 0.72 : 0.48).setFill()
        NSBezierPath(ovalIn: badge).fill()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.move(to: CGPoint(x: badge.minX + 7, y: badge.minY + 7))
        path.line(to: CGPoint(x: badge.maxX - 7, y: badge.maxY - 7))
        path.move(to: CGPoint(x: badge.maxX - 7, y: badge.minY + 7))
        path.line(to: CGPoint(x: badge.minX + 7, y: badge.maxY - 7))
        path.stroke()
    }

    private var closeRect: CGRect {
        CGRect(x: 8, y: bounds.height - 28, width: 20, height: 20)
    }

    private var closeHotZone: CGRect {
        CGRect(x: 0, y: max(0, bounds.height - 40), width: 40, height: 40)
    }
}
