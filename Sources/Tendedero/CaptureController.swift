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
                try autoreleasepool {
                    switch result {
                    case .cancel:
                        return
                    case .save(let request):
                        let url = try Self.capture(request)
                        Self.copyToPasteboard(url)
                        completion(url)
                    case .pin(let request):
                        let image = Self.annotatedImage(request.image, rect: request.rect,
                                                        annotations: request.annotations) ?? request.image
                        self?.pin(image, near: request.rect)
                    }
                }
            } catch {
                Self.showError(error)
            }
        }
    }

    private func pin(_ image: CGImage, near rect: CGRect) {
        let window = PinnedImageWindow(image: image, frame: rect)
        pinnedWindows.append(window)
        window.onClose = { [weak self, weak window] in
            self?.pinnedWindows.removeAll { $0 === window }
        }
    }

    private static func capture(_ request: CaptureRequest) throws -> URL {
        let rect = request.rect
        guard request.image.width >= 2, request.image.height >= 2 else {
            throw CaptureError.emptySelection
        }

        let output = annotatedImage(request.image, rect: rect, annotations: request.annotations) ?? request.image

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
        let width = image.width
        let height = image.height
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let scaleX = CGFloat(width) / rect.width
        let scaleY = CGFloat(height) / rect.height
        for stroke in annotations where stroke.points.count > 1 {
            let color = stroke.color.usingColorSpace(.deviceRGB) ?? stroke.color
            context.setStrokeColor(CGColor(red: color.redComponent,
                                           green: color.greenComponent,
                                           blue: color.blueComponent,
                                           alpha: color.alphaComponent))
            context.setLineWidth(stroke.width * max(scaleX, scaleY))
            context.beginPath()
            for (index, point) in stroke.points.enumerated() {
                let local = CGPoint(x: (point.x - rect.minX) * scaleX,
                                    y: (point.y - rect.minY) * scaleY)
                if index == 0 { context.move(to: local) } else { context.addLine(to: local) }
            }
            context.strokePath()
        }
        return context.makeImage()
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
