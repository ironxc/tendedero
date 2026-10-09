import AppKit
import Carbon

struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: Int

    static let defaultCapture = Shortcut(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey)
    static let defaultToggleLine = Shortcut(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey)

    var keyEquivalent: String {
        Self.keyEquivalent(for: keyCode)
    }

    var modifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        return flags
    }

    var display: String {
        var parts = ""
        if modifiers & controlKey != 0 { parts += "⌃" }
        if modifiers & optionKey != 0 { parts += "⌥" }
        if modifiers & shiftKey != 0 { parts += "⇧" }
        if modifiers & cmdKey != 0 { parts += "⌘" }
        return parts + Self.keyLabel(for: keyCode)
    }

    var isUsable: Bool {
        let hasPrimaryModifier = modifiers & (controlKey | optionKey | cmdKey) != 0
        let isFunctionKey = Self.functionKeyLabel(for: keyCode) != nil
        return (hasPrimaryModifier || isFunctionKey) && !keyEquivalent.isEmpty
    }

    static func capture() -> Shortcut {
        load(key: "captureShortcut", default: .defaultCapture)
    }

    static func toggleLine() -> Shortcut {
        load(key: "toggleLineShortcut", default: .defaultToggleLine)
    }

    func saveAsCapture() {
        save(key: "captureShortcut")
    }

    func saveAsToggleLine() {
        save(key: "toggleLineShortcut")
    }

    private static func load(key: String, default fallback: Shortcut) -> Shortcut {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "\(key)KeyCode") != nil else { return fallback }
        return Shortcut(keyCode: defaults.integer(forKey: "\(key)KeyCode"),
                        modifiers: defaults.integer(forKey: "\(key)Modifiers"))
    }

    private func save(key: String) {
        UserDefaults.standard.set(keyCode, forKey: "\(key)KeyCode")
        UserDefaults.standard.set(modifiers, forKey: "\(key)Modifiers")
    }

    static func from(_ event: NSEvent) -> Shortcut? {
        let isFunctionKey = functionKeyLabel(for: Int(event.keyCode)) != nil
        let chars = event.charactersIgnoringModifiers ?? ""
        guard event.keyCode != 53, isFunctionKey || !chars.isEmpty else { return nil }

        var modifiers = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }

        let shortcut = Shortcut(keyCode: Int(event.keyCode), modifiers: modifiers)
        return shortcut.isUsable ? shortcut : nil
    }

    private static func keyEquivalent(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return " "
        case kVK_F1: return String(Character(UnicodeScalar(NSF1FunctionKey)!))
        case kVK_F2: return String(Character(UnicodeScalar(NSF2FunctionKey)!))
        case kVK_F3: return String(Character(UnicodeScalar(NSF3FunctionKey)!))
        case kVK_F4: return String(Character(UnicodeScalar(NSF4FunctionKey)!))
        case kVK_F5: return String(Character(UnicodeScalar(NSF5FunctionKey)!))
        case kVK_F6: return String(Character(UnicodeScalar(NSF6FunctionKey)!))
        case kVK_F7: return String(Character(UnicodeScalar(NSF7FunctionKey)!))
        case kVK_F8: return String(Character(UnicodeScalar(NSF8FunctionKey)!))
        case kVK_F9: return String(Character(UnicodeScalar(NSF9FunctionKey)!))
        case kVK_F10: return String(Character(UnicodeScalar(NSF10FunctionKey)!))
        case kVK_F11: return String(Character(UnicodeScalar(NSF11FunctionKey)!))
        case kVK_F12: return String(Character(UnicodeScalar(NSF12FunctionKey)!))
        case kVK_F13: return String(Character(UnicodeScalar(NSF13FunctionKey)!))
        case kVK_F14: return String(Character(UnicodeScalar(NSF14FunctionKey)!))
        case kVK_F15: return String(Character(UnicodeScalar(NSF15FunctionKey)!))
        case kVK_F16: return String(Character(UnicodeScalar(NSF16FunctionKey)!))
        case kVK_F17: return String(Character(UnicodeScalar(NSF17FunctionKey)!))
        case kVK_F18: return String(Character(UnicodeScalar(NSF18FunctionKey)!))
        case kVK_F19: return String(Character(UnicodeScalar(NSF19FunctionKey)!))
        case kVK_F20: return String(Character(UnicodeScalar(NSF20FunctionKey)!))
        default: return ""
        }
    }

    private static func keyLabel(for keyCode: Int) -> String {
        if let functionKey = functionKeyLabel(for: keyCode) { return functionKey }
        let equivalent = keyEquivalent(for: keyCode)
        if equivalent == " " { return "Space" }
        return equivalent.uppercased()
    }

    private static func functionKeyLabel(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default: return nil
        }
    }
}

@MainActor
final class ShortcutPicker: NSObject, NSWindowDelegate {
    private var panel: NSPanel!
    private let recorder = ShortcutRecorderView()
    private var result: Shortcut?

    static func pick(title: String, current: Shortcut) -> Shortcut? {
        let picker = ShortcutPicker(title: title, current: current)
        return picker.run()
    }

    private let titleText: String

    init(title: String, current: Shortcut) {
        titleText = title
        super.init()
        recorder.shortcut = current
    }

    private func run() -> Shortcut? {
        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let hint = NSTextField(labelWithString: L("Press a new shortcut. F1-F20 can be used alone; letters, numbers and Space need Control, Option or Command.",
                                                 "按下新的快捷键。F1-F20 可以单独使用；字母、数字和空格需要搭配 Control、Option 或 Command。"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        let cancel = NSButton(title: L("Cancel", "取消"), target: self, action: #selector(cancel))
        let save = NSButton(title: L("Save", "保存"), target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        recorder.onChange = { shortcut in
            save.isEnabled = shortcut?.isUsable == true
        }

        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let stack = NSStackView(views: [title, hint, recorder, buttons])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        recorder.widthAnchor.constraint(equalToConstant: 320).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 54).isActive = true

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 190),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L("Shortcut", "快捷键")
        panel.contentView = stack
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(recorder)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return result
    }

    @objc private func cancel() {
        result = nil
        NSApp.stopModal()
    }

    func windowWillClose(_ notification: Notification) {
        result = nil
        NSApp.stopModal()
    }

    @objc private func save() {
        result = recorder.shortcut
        NSApp.stopModal()
    }
}

final class ShortcutRecorderView: NSView {
    var shortcut: Shortcut? {
        didSet { needsDisplay = true; onChange(shortcut) }
    }
    var onChange: (Shortcut?) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.close()
            NSApp.stopModal()
            return
        }
        shortcut = Shortcut.from(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.keyboardFocusIndicatorColor.setStroke()
        let stroke = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        stroke.lineWidth = window?.firstResponder === self ? 2 : 1
        stroke.stroke()

        let text = shortcut?.display ?? L("Press shortcut", "按下快捷键")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let size = attributed.size()
        attributed.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}
