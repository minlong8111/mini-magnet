import Carbon
import Cocoa

@MainActor
class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotkeys: [UInt32: () -> Void] = [:]
    private var registeredRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotkeyIDCounter: UInt32 = 0
    private var eventHandlerRef: EventHandlerRef?

    init() {
        setupEventHandler()
    }

    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let callback: EventHandlerUPP = { (_, event, _) -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            if status == noErr {
                let id = hotkeyID.id
                DispatchQueue.main.async {
                    HotkeyManager.shared.trigger(id: id)
                }
                return OSStatus(noErr)
            }
            return OSStatus(eventNotHandledErr)
        }

        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandlerRef)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32? {
        hotkeyIDCounter += 1
        let id = hotkeyIDCounter
        hotkeys[id] = handler

        // "mini" signature: 'm'<<24 | 'i'<<16 | 'n'<<8 | 'i'
        let signature = OSType(1835364968)
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            registeredRefs[id] = ref
            return id
        } else {
            hotkeys.removeValue(forKey: id)
            return nil
        }
    }

    func unregisterAll() {
        for ref in registeredRefs.values {
            UnregisterEventHotKey(ref)
        }
        registeredRefs.removeAll()
        hotkeys.removeAll()
        hotkeyIDCounter = 0
    }

    func trigger(id: UInt32) {
        hotkeys[id]?()
    }
}
