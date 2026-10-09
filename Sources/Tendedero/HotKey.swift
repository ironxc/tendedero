import Carbon

/// A single global shortcut through the Carbon hot key API. Unlike a global
/// key monitor, it needs no Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var nextID: UInt32 = 1
    private static var actions: [UInt32: () -> Void] = [:]
    private static var isHandlerInstalled = false

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action
        Self.installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5445_4E44), id: id) // "TEND"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        HotKey.actions[id] = nil
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        isHandlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            if let event {
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            }
            DispatchQueue.main.async { HotKey.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
