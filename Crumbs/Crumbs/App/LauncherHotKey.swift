import Carbon

/// Register just the launcher's chord so other keyboard input stays with the active app.
final class LauncherHotKey {
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let toggle: () -> Void
    private var isDown = false
    private static let identifier = EventHotKeyID(signature: 0x43726D62, id: 1) // Crmb

    init(toggle: @escaping () -> Void) {
        self.toggle = toggle
    }

    func register() -> Bool {
        let target = GetEventDispatcherTarget()
        var events = [UInt32(kEventHotKeyPressed), UInt32(kEventHotKeyReleased)].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: $0)
        }
        let status = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == LauncherHotKey.identifier.signature, id.id == LauncherHotKey.identifier.id else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<LauncherHotKey>.fromOpaque(context).takeUnretainedValue()
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                let shouldToggle = pressed && !hotKey.isDown
                hotKey.isDown = pressed
                if shouldToggle { hotKey.toggle() }
                return noErr
            }
        }, 2, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | shiftKey),
                                         Self.identifier, target, 0, &registration)
        if result != noErr { unregister() }
        return result == noErr
    }

    func unregister() {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
        registration = nil
        handler = nil
        isDown = false
    }
}
