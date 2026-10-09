import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class CaptureController {
    private var overlay: CaptureOverlay?
    private var pinnedWindows: [PinnedImageWindow] = []

    func captureArea(completion: @escaping (URL) -> Void) {
        guard overlay == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            Self.showError(CaptureError.permissionOrCaptureFailed)
            return
        }
        let overlay = CaptureOverlay()
        self.overlay = overlay
        overlay.begin { [weak self] result in
            self?.overlay = nil
            do {
                switch result {
                case .cancel:
                    return
                case .save(let request):
                    let url = try Self.capture(request)
                    Self.copyToPasteboard(url)
                    completion(url)
                case .pin(let request):
                    let url = try Self.capture(request)
                    try self?.pin(url, near: request.rect)
                }
            } catch {
                Self.showError(error)
            }
        }
    }

    private func pin(_ url: URL, near rect: CGRect) throws {
        guard let image = NSImage(contentsOf: url) else { throw CaptureError.couldNotWrite }
        let window = PinnedImageWindow(image: image, frame: rect)
        pinnedWindows.append(window)
        window.onClose = { [weak self, weak window] in
            self?.pinnedWindows.removeAll { $0 === window }
        }
    }

    private static func capture(_ request: CaptureRequest) throws -> URL {
        let rect = request.rect
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let image = CGDisplayCreateImage(displayID) else {
            throw CaptureError.permissionOrCaptureFailed
        }

        let clipped = rect.intersection(screen.frame)
        let sx = CGFloat(image.width) / screen.frame.width
        let sy = CGFloat(image.height) / screen.frame.height
        let crop = CGRect(x: (clipped.minX - screen.frame.minX) * sx,
                          y: (screen.frame.maxY - clipped.maxY) * sy,
                          width: clipped.width * sx,
                          height: clipped.height * sy).integral

        guard crop.width >= 2, crop.height >= 2,
              let cropped = image.cropping(to: crop) else {
            throw CaptureError.emptySelection
        }

        let output = annotatedImage(cropped, rect: clipped, annotations: request.annotations) ?? cropped

        try FileManager.default.createDirectory(at: Inbox.folder, withIntermediateDirectories: true)
        let url = uniqueURL(in: Inbox.folder, named: filename())
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.couldNotWrite
        }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.couldNotWrite }
        return url
    }

    private static func annotatedImage(_ image: CGImage, rect: CGRect,
                                       annotations: [CaptureAnnotationStroke]) -> CGImage? {
        guard !annotations.isEmpty else { return image }
        let size = rect.size
        let base = NSImage(cgImage: image, size: size)
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        base.draw(in: CGRect(origin: .zero, size: size))
        for stroke in annotations where stroke.points.count > 1 {
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.lineWidth = stroke.width
            for (index, point) in stroke.points.enumerated() {
                let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
                if index == 0 { path.move(to: local) } else { path.line(to: local) }
            }
            stroke.color.setStroke()
            path.stroke()
        }
        canvas.unlockFocus()
        return canvas.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func copyToPasteboard(_ url: URL) {
        let item = NSPasteboardItem()
        if let data = try? Data(contentsOf: url) {
            item.setData(data, forType: .png)
        }
        item.setString(url.absoluteString, forType: .fileURL)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private static func filename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).png"
    }

    private static func uniqueURL(in folder: URL, named name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    private static func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("Could not capture the screen", "无法截取屏幕")
        alert.informativeText = L(
            "Allow Tendedero to record the screen in System Settings, then quit and reopen Tendedero.",
            "请在系统设置中允许 Tendedero 录制屏幕，然后退出并重新打开 Tendedero。")
        alert.addButton(withTitle: L("Open Settings", "打开设置"))
        alert.addButton(withTitle: L("Cancel", "取消"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}

private enum CaptureError: Error {
    case emptySelection
    case permissionOrCaptureFailed
    case couldNotWrite
}
