import AppKit
import Carbon

@MainActor
final class CaptureOverlay {
    private var windows: [CaptureWindow] = []
    private var completion: (CaptureOverlayResult) -> Void = { _ in }
    private var didFinish = false

    func begin(completion: @escaping (CaptureOverlayResult) -> Void) {
        self.completion = completion
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let screens = [NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
                       ?? NSScreen.main
                       ?? NSScreen.screens.first].compactMap { $0 }
        windows = screens.map { screen in
            let window = CaptureWindow(screen: screen)
            window.selectionView.onChange = { [weak self, weak window] rect in
                guard let window else { return }
                self?.selectionChanged(rect, from: window)
            }
            window.selectionView.onFinish = { [weak self] result in self?.finish(result) }
            window.selectionView.onCancel = { [weak self] in self?.finish(.cancel) }
            window.displayIfNeeded()
            window.orderFrontRegardless()
            return window
        }
        windows.first?.makeKeyAndOrderFront(nil)
        windows.first?.makeFirstResponder(windows.first?.selectionView)
        NSCursor.crosshair.set()
    }

    private func selectionChanged(_ rect: CGRect?, from source: CaptureWindow) {
        for window in windows where window !== source {
            window.selectionView.externalSelection = rect?.intersection(window.frame)
        }
    }

    private func finish(_ result: CaptureOverlayResult) {
        guard !didFinish else { return }
        didFinish = true
        NSCursor.arrow.set()
        let callback = completion
        completion = { _ in }
        for window in windows {
            window.selectionView.onChange = { _ in }
            window.selectionView.onFinish = { _ in }
            window.selectionView.onCancel = {}
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            callback(result)
        }
    }
}

enum CaptureOverlayResult {
    case cancel
    case save(CaptureRequest)
    case pin(CaptureRequest)
}

struct CaptureRequest {
    let rect: CGRect
    let image: CGImage
    let annotations: [CaptureAnnotationStroke]
}

struct CaptureAnnotationStroke {
    let points: [CGPoint]
    let color: NSColor
    let width: CGFloat
}

final class CaptureWindow: NSPanel {
    let selectionView: CaptureSelectionView

    init(screen: NSScreen) {
        let sampler = ScreenSampler(screen: screen)
        selectionView = CaptureSelectionView(screenFrame: screen.frame, sampler: sampler)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        animationBehavior = .none
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CaptureSelectionView: NSView {
    var onChange: (CGRect?) -> Void = { _ in }
    var onFinish: (CaptureOverlayResult) -> Void = { _ in }
    var onCancel: () -> Void = {}

    var externalSelection: CGRect? {
        didSet { needsDisplay = true }
    }

    private let screenFrame: CGRect
    private let sampler: ScreenSampler
    private var start: CGPoint?
    private var current: CGPoint?
    private var finalizedSelection: CGRect?
    private var hover: CGPoint?
    private var isSelecting = false
    private var drawingStrokeIndex: Int?
    private var consumedMouseDown = false
    private var annotations: [CaptureAnnotationStroke] = []
    private var brushColor = NSColor.systemRed
    private var brushWidth: CGFloat = 5
    private var useRGBA = false
    private var wasShiftDown = false

    fileprivate init(screenFrame: CGRect, sampler: ScreenSampler) {
        self.screenFrame = screenFrame
        self.sampler = sampler
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else if event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter, let selection {
            if let request = captureRequest(for: selection) { onFinish(.save(request)) }
        } else if event.keyCode == kVK_ANSI_P, let selection {
            if let request = captureRequest(for: selection) { onFinish(.pin(request)) }
        } else if event.keyCode == kVK_ANSI_C, let colorText {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(colorText, forType: .string)
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        let isShiftDown = event.modifierFlags.contains(.shift)
        if isShiftDown && !wasShiftDown {
            useRGBA.toggle()
            needsDisplay = true
        }
        wasShiftDown = isShiftDown
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let p = globalPoint(event)
        if let selection = finalizedSelection {
            let local = window?.convertPoint(fromScreen: p) ?? p
            if handleToolbarClick(at: local, selectionRect: localRect(for: selection)) {
                consumedMouseDown = true
                needsDisplay = true
                return
            }
            if selection.contains(p) {
                annotations.append(CaptureAnnotationStroke(points: [p], color: brushColor, width: brushWidth))
                drawingStrokeIndex = annotations.indices.last
                consumedMouseDown = true
                hover = p
                needsDisplay = true
                return
            }
            consumedMouseDown = true
            hover = p
            needsDisplay = true
            return
        }
        consumedMouseDown = false
        finalizedSelection = nil
        start = p
        current = p
        hover = p
        isSelecting = true
        annotations.removeAll()
        onChange(selection)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = globalPoint(event)
        if let drawingStrokeIndex {
            annotations[drawingStrokeIndex] = CaptureAnnotationStroke(
                points: annotations[drawingStrokeIndex].points + [p],
                color: annotations[drawingStrokeIndex].color,
                width: annotations[drawingStrokeIndex].width)
            hover = p
            needsDisplay = true
            return
        }
        guard isSelecting else {
            hover = p
            needsDisplay = true
            return
        }
        current = p
        hover = p
        onChange(selection)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = globalPoint(event)
        if drawingStrokeIndex != nil {
            drawingStrokeIndex = nil
            consumedMouseDown = false
            hover = p
            needsDisplay = true
            return
        }
        if consumedMouseDown {
            consumedMouseDown = false
            hover = p
            needsDisplay = true
            return
        }
        guard isSelecting else {
            hover = p
            needsDisplay = true
            return
        }
        current = p
        hover = p
        isSelecting = false
        guard let selection, selection.width >= 3, selection.height >= 3 else {
            onCancel()
            return
        }
        finalizedSelection = selection
        onChange(selection)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        hover = globalPoint(event)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        sampler.drawSnapshot(of: screenFrame, in: bounds)
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let global = selection ?? externalSelection,
              let rect = localRect(for: global) else { return }
        sampler.drawSnapshot(of: global, in: rect)

        NSColor.white.withAlphaComponent(0.92).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()
        NSColor.black.withAlphaComponent(0.45).setStroke()
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()

        drawAnnotations(in: rect)
        drawPrompt(for: rect)
        drawBrushToolbar(for: rect)
    }

    private var selection: CGRect? {
        if let finalizedSelection { return finalizedSelection }
        guard let start, let current else { return nil }
        let rect = CGRect(x: min(start.x, current.x),
                          y: min(start.y, current.y),
                          width: abs(start.x - current.x),
                          height: abs(start.y - current.y))
        return rect.intersection(screenFrame).standardized
    }

    private func captureRequest(for rect: CGRect) -> CaptureRequest? {
        guard let image = sampler.croppedImage(of: rect) else { return nil }
        return CaptureRequest(rect: rect, image: image, annotations: annotations)
    }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        guard let window else { return event.locationInWindow }
        let p = window.convertPoint(toScreen: event.locationInWindow)
        return CGPoint(x: min(max(p.x, screenFrame.minX), screenFrame.maxX),
                       y: min(max(p.y, screenFrame.minY), screenFrame.maxY))
    }

    private func localRect(for global: CGRect?) -> CGRect? {
        guard let global, !global.isNull, global.width > 0, global.height > 0, let window else { return nil }
        let a = window.convertPoint(fromScreen: CGPoint(x: global.minX, y: global.minY))
        let b = window.convertPoint(fromScreen: CGPoint(x: global.maxX, y: global.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func drawPrompt(for rect: CGRect) {
        guard let selection else { return }
        let action = isSelecting ? "松开后按 Enter 保存并复制截图，P 固定，Esc 取消" : "拖动画笔标记，Enter 保存并复制，P 固定，C 复制颜色，Shift 切换格式，Esc 取消"
        let text = "\(Int(selection.width)) × \(Int(selection.height))  \(action)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let size = attributed.size()
        var label = CGRect(x: rect.minX, y: rect.minY - size.height - 12,
                           width: size.width + 14, height: size.height + 8)
        if label.minY < 8 { label.origin.y = rect.maxY + 8 }
        if label.maxX > bounds.maxX - 8 { label.origin.x = bounds.maxX - label.width - 8 }
        let bubble = NSBezierPath(roundedRect: label, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.62).setFill()
        bubble.fill()
        attributed.draw(at: CGPoint(x: label.minX + 7, y: label.minY + 4))

        if let color = pickedColor, let colorText, let localHover = localPoint(for: hover) {
            drawColorPicker(color, text: colorText, at: localHover)
        }
    }

    private var pickedColor: PickedColor? {
        guard let selection, let hover, selection.contains(hover) else { return nil }
        return sampler.color(at: hover)
    }

    private var colorText: String? {
        pickedColor.map { useRGBA ? $0.rgba : $0.hex }
    }

    private func localPoint(for global: CGPoint?) -> CGPoint? {
        guard let global, let window else { return nil }
        return window.convertPoint(fromScreen: global)
    }

    private func drawColorPicker(_ color: PickedColor, text: String, at point: CGPoint) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.82),
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let helpAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.68),
        ]
        let titleText = NSAttributedString(string: "取色", attributes: titleAttrs)
        let valueText = NSAttributedString(string: text, attributes: valueAttrs)
        let helpText = NSAttributedString(string: "C 复制并退出 · Shift 切换", attributes: helpAttrs)

        let width = max(178, valueText.size().width + 58)
        var panel = CGRect(x: point.x + 18, y: point.y - 74, width: width, height: 70)
        if panel.maxX > bounds.maxX - 10 { panel.origin.x = point.x - panel.width - 18 }
        if panel.minY < 10 { panel.origin.y = point.y + 18 }
        if panel.maxY > bounds.maxY - 10 { panel.origin.y = bounds.maxY - panel.height - 10 }

        NSColor.black.withAlphaComponent(0.78).setFill()
        let background = NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8)
        background.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        background.lineWidth = 1
        background.stroke()

        let swatch = CGRect(x: panel.minX + 12, y: panel.minY + 21, width: 34, height: 34)
        let swatchPath = NSBezierPath(roundedRect: swatch, xRadius: 6, yRadius: 6)
        color.nsColor.setFill()
        swatchPath.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        swatchPath.lineWidth = 1
        swatchPath.stroke()

        titleText.draw(at: CGPoint(x: panel.minX + 56, y: panel.minY + 45))
        valueText.draw(at: CGPoint(x: panel.minX + 56, y: panel.minY + 25))
        helpText.draw(at: CGPoint(x: panel.minX + 56, y: panel.minY + 9))

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
        ring.lineWidth = 2
        ring.stroke()
        NSColor.black.withAlphaComponent(0.75).setStroke()
        let inner = NSBezierPath(ovalIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
        inner.lineWidth = 1
        inner.stroke()
    }

    private func drawAnnotations(in selectionRect: CGRect) {
        guard !annotations.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        for stroke in annotations {
            draw(stroke)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ stroke: CaptureAnnotationStroke) {
        guard stroke.points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = stroke.width
        for (index, point) in stroke.points.enumerated() {
            guard let local = localPoint(for: point) else { continue }
            if index == 0 { path.move(to: local) } else { path.line(to: local) }
        }
        stroke.color.setStroke()
        path.stroke()
    }

    private func drawBrushToolbar(for rect: CGRect) {
        guard selection != nil, !isSelecting else { return }
        let layout = toolbarLayout(for: rect)
        NSColor.black.withAlphaComponent(0.72).setFill()
        let background = NSBezierPath(roundedRect: layout.frame, xRadius: 7, yRadius: 7)
        background.fill()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.82),
        ]
        NSAttributedString(string: "画笔", attributes: labelAttrs)
            .draw(at: CGPoint(x: layout.frame.minX + 10, y: layout.frame.minY + 10))

        for item in layout.colors {
            item.color.setFill()
            NSBezierPath(ovalIn: item.rect).fill()
            let selected = item.color.isEqual(brushColor)
            (selected ? NSColor.white : NSColor.white.withAlphaComponent(0.45)).setStroke()
            let ring = item.rect.insetBy(dx: selected ? -3 : -1, dy: selected ? -3 : -1)
            let path = NSBezierPath(ovalIn: ring)
            path.lineWidth = selected ? 2 : 1
            path.stroke()
        }

        for item in layout.widths {
            NSColor.white.withAlphaComponent(item.width == brushWidth ? 0.95 : 0.5).setFill()
            NSBezierPath(ovalIn: item.rect.insetBy(dx: (item.rect.width - item.width) / 2,
                                                   dy: (item.rect.height - item.width) / 2)).fill()
            if item.width == brushWidth {
                NSColor.white.withAlphaComponent(0.9).setStroke()
                NSBezierPath(ovalIn: item.rect.insetBy(dx: -2, dy: -2)).stroke()
            }
        }
    }

    private func handleToolbarClick(at point: CGPoint, selectionRect: CGRect?) -> Bool {
        guard let selectionRect else { return false }
        let layout = toolbarLayout(for: selectionRect)
        for item in layout.colors where item.rect.contains(point) {
            brushColor = item.color
            return true
        }
        for item in layout.widths where item.rect.contains(point) {
            brushWidth = item.width
            return true
        }
        return layout.frame.contains(point)
    }

    private func toolbarLayout(for rect: CGRect) -> ToolbarLayout {
        let colorOptions: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black]
        let widthOptions: [CGFloat] = [3, 6, 10]
        let width = 48 + CGFloat(colorOptions.count) * 24 + 8 + CGFloat(widthOptions.count) * 28 + 12
        var frame = CGRect(x: rect.minX, y: rect.maxY + 8, width: width, height: 36)
        if frame.maxY > bounds.maxY - 8 { frame.origin.y = rect.minY - frame.height - 8 }
        if frame.maxX > bounds.maxX - 8 { frame.origin.x = bounds.maxX - frame.width - 8 }
        if frame.minX < 8 { frame.origin.x = 8 }

        var x = frame.minX + 48
        let colors = colorOptions.map { color -> ColorToolbarItem in
            defer { x += 24 }
            return ColorToolbarItem(rect: CGRect(x: x, y: frame.minY + 10, width: 16, height: 16), color: color)
        }
        x += 8
        let widths = widthOptions.map { width -> WidthToolbarItem in
            defer { x += 28 }
            return WidthToolbarItem(rect: CGRect(x: x, y: frame.minY + 8, width: 20, height: 20), width: width)
        }
        return ToolbarLayout(frame: frame, colors: colors, widths: widths)
    }
}

private struct ToolbarLayout {
    let frame: CGRect
    let colors: [ColorToolbarItem]
    let widths: [WidthToolbarItem]
}

private struct ColorToolbarItem {
    let rect: CGRect
    let color: NSColor
}

private struct WidthToolbarItem {
    let rect: CGRect
    let width: CGFloat
}

private final class ScreenSampler {
    private let screenFrame: CGRect
    private let image: CGImage?
    private let samplePixel: UnsafeMutableRawPointer
    private var sampleContext: CGContext?

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        image = displayID.flatMap(CGDisplayCreateImage)
        samplePixel = UnsafeMutableRawPointer.allocate(byteCount: 4, alignment: 1)
        samplePixel.initializeMemory(as: UInt8.self, repeating: 0, count: 4)
        sampleContext = CGContext(data: samplePixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        sampleContext?.interpolationQuality = .none
    }

    deinit {
        sampleContext = nil
        samplePixel.deallocate()
    }

    func drawSnapshot(of rect: CGRect, in destination: CGRect) {
        guard let image, let context = NSGraphicsContext.current?.cgContext else {
            NSColor.clear.setFill()
            destination.fill()
            return
        }
        let clipped = rect.intersection(screenFrame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return }

        context.saveGState()
        context.clip(to: destination)
        context.draw(image, in: CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height))
        context.restoreGState()
    }

    func croppedImage(of rect: CGRect) -> CGImage? {
        guard let image else { return nil }
        let clipped = rect.intersection(screenFrame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        let sx = CGFloat(image.width) / screenFrame.width
        let sy = CGFloat(image.height) / screenFrame.height
        let crop = CGRect(x: (clipped.minX - screenFrame.minX) * sx,
                          y: (screenFrame.maxY - clipped.maxY) * sy,
                          width: clipped.width * sx,
                          height: clipped.height * sy).integral
        return image.cropping(to: crop)
    }

    func color(at point: CGPoint) -> PickedColor? {
        guard let image, let sampleContext else { return nil }
        let sx = CGFloat(image.width) / screenFrame.width
        let sy = CGFloat(image.height) / screenFrame.height
        let x = Int((point.x - screenFrame.minX) * sx)
        let y = Int((screenFrame.maxY - point.y) * sy)
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        samplePixel.initializeMemory(as: UInt8.self, repeating: 0, count: 4)
        let yBottom = image.height - y - 1
        sampleContext.draw(image, in: CGRect(x: -x, y: -yBottom, width: image.width, height: image.height))
        let bytes = samplePixel.bindMemory(to: UInt8.self, capacity: 4)
        return PickedColor(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
    }
}

private struct PickedColor {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgba: String {
        String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, Double(a) / 255.0)
    }

    var nsColor: NSColor {
        NSColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0, alpha: CGFloat(a) / 255.0)
    }
}
