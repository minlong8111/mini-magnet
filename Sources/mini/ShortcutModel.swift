import Carbon
import Cocoa

public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum WindowAction: String, CaseIterable, Codable {
    case maximize = "maximize"
    case center = "center"
    case leftHalf = "leftHalf"
    case rightHalf = "rightHalf"
    case topHalf = "topHalf"
    case bottomHalf = "bottomHalf"
    case topLeftQuarter = "topLeftQuarter"
    case topRightQuarter = "topRightQuarter"
    case bottomLeftQuarter = "bottomLeftQuarter"
    case bottomRightQuarter = "bottomRightQuarter"
    case leftThird = "leftThird"
    case centerThird = "centerThird"
    case rightThird = "rightThird"
    case leftTwoThirds = "leftTwoThirds"
    case rightTwoThirds = "rightTwoThirds"
    case nextDisplay = "nextDisplay"
    case prevDisplay = "prevDisplay"
    
    public var defaultShortcut: Shortcut {
        let co = UInt32(controlKey | optionKey)
        let cs = UInt32(controlKey | optionKey | shiftKey)
        let cm = UInt32(controlKey | optionKey | cmdKey)
        
        switch self {
        case .maximize:          return Shortcut(keyCode: 126, modifiers: co)
        case .center:            return Shortcut(keyCode: 125, modifiers: co)
        case .leftHalf:          return Shortcut(keyCode: 123, modifiers: co)
        case .rightHalf:         return Shortcut(keyCode: 124, modifiers: co)
        case .topHalf:           return Shortcut(keyCode: 126, modifiers: cs)
        case .bottomHalf:        return Shortcut(keyCode: 125, modifiers: cs)
        case .topLeftQuarter:    return Shortcut(keyCode: 32,  modifiers: co) // U
        case .topRightQuarter:   return Shortcut(keyCode: 34,  modifiers: co) // I
        case .bottomLeftQuarter: return Shortcut(keyCode: 38,  modifiers: co) // J
        case .bottomRightQuarter:return Shortcut(keyCode: 40,  modifiers: co) // K
        case .leftThird:         return Shortcut(keyCode: 2,   modifiers: co) // D
        case .centerThird:       return Shortcut(keyCode: 3,   modifiers: co) // F
        case .rightThird:        return Shortcut(keyCode: 5,   modifiers: co) // G
        case .leftTwoThirds:     return Shortcut(keyCode: 14,  modifiers: co) // E
        case .rightTwoThirds:    return Shortcut(keyCode: 17,  modifiers: co) // T
        case .nextDisplay:       return Shortcut(keyCode: 124, modifiers: cm)
        case .prevDisplay:       return Shortcut(keyCode: 123, modifiers: cm)
        }
    }
    
    public var label: String {
        switch self {
        case .maximize:          return "Maximize"
        case .center:            return "Center"
        case .leftHalf:          return "Left Half"
        case .rightHalf:         return "Right Half"
        case .topHalf:           return "Top Half"
        case .bottomHalf:        return "Bottom Half"
        case .topLeftQuarter:    return "Top Left"
        case .topRightQuarter:   return "Top Right"
        case .bottomLeftQuarter: return "Bottom Left"
        case .bottomRightQuarter:return "Bottom Right"
        case .leftThird:         return "Left Third"
        case .centerThird:       return "Center Third"
        case .rightThird:        return "Right Third"
        case .leftTwoThirds:     return "Left Two Thirds"
        case .rightTwoThirds:    return "Right Two Thirds"
        case .nextDisplay:       return "Next Display"
        case .prevDisplay:       return "Previous Display"
        }
    }
}

// MARK: - Shortcut Utility Functions

public func cocoaToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbonFlags: UInt32 = 0
    if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
    if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
    if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
    if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
    return carbonFlags
}

public func shortcutDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
    if keyCode == 0 && modifiers == 0 {
        return "Click to Record"
    }
    var str = ""
    if (modifiers & UInt32(controlKey)) != 0 { str += "⌃" }
    if (modifiers & UInt32(optionKey)) != 0 { str += "⌥" }
    if (modifiers & UInt32(shiftKey)) != 0 { str += "⇧" }
    if (modifiers & UInt32(cmdKey)) != 0 { str += "⌘" }
    
    str += keyName(keyCode: keyCode)
    return str
}

public func keyName(keyCode: UInt32) -> String {
    switch keyCode {
    case 126: return "↑"
    case 125: return "↓"
    case 123: return "←"
    case 124: return "→"
    case 49: return "Space"
    case 36: return "↩"
    case 51: return "⌫"
    case 53: return "⎋"
    default:
        if let char = keyCodeToString(keyCode) {
            return char.uppercased()
        }
        return "Key \(keyCode)"
    }
}

private func keyCodeToString(_ keyCode: UInt32) -> String? {
    let maxLen = 4
    var chars = [UniChar](repeating: 0, count: maxLen)
    var actualLen = 0
    
    guard let keyboardLayout = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    let layoutData = TISGetInputSourceProperty(keyboardLayout, kTISPropertyUnicodeKeyLayoutData)
    
    guard let layoutDataRef = unsafeBitCast(layoutData, to: CFData?.self) else { return nil }
    let rawLayoutData = CFDataGetBytePtr(layoutDataRef)
    
    var keysDown: UInt32 = 0
    
    let result = UCKeyTranslate(
        unsafeBitCast(rawLayoutData, to: UnsafePointer<UCKeyboardLayout>.self),
        UInt16(keyCode),
        UInt16(kUCKeyActionDown),
        0,
        UInt32(LMGetKbdType()),
        UInt32(kUCKeyTranslateNoDeadKeysMask),
        &keysDown,
        maxLen,
        &actualLen,
        &chars
    )
    
    if result == noErr && actualLen > 0 {
        return String(utf16CodeUnits: chars, count: actualLen)
    }
    return nil
}
