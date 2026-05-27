import Cocoa
import ApplicationServices

enum WindowPosition {
    // Halves
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    // Quarters
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    // Thirds
    case leftThird
    case centerThird
    case rightThird
    // Two-thirds
    case leftTwoThirds
    case rightTwoThirds
    // Full
    case maximize
    // Center
    case center
    // Next / Previous display
    case nextDisplay
    case prevDisplay
}

@MainActor
class WindowManager {
    static let shared = WindowManager()
    private var lastRect: CGRect? = nil
    private var lastWindow: AXUIElement? = nil

    // Check if the application has accessibility permissions
    func checkAccessibilityPermissions(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt" as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // Get the window that currently has focus
    private func getFocusedWindow() -> AXUIElement? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontmostApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        if result == .success, let window = focusedWindow {
            return (window as! AXUIElement)
        }
        return nil
    }

    // Get current window rect in screen (bottom-left) coordinates
    private func getWindowRect(_ window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        let primaryHeight = NSScreen.screens[0].frame.height
        return CGRect(x: point.x, y: primaryHeight - point.y - size.height, width: size.width, height: size.height)
    }

    // Get the NSScreen that best fits the current window
    private func getTargetScreen(for window: AXUIElement) -> NSScreen {
        var targetScreen = NSScreen.main ?? NSScreen.screens[0]

        if let windowRect = getWindowRect(window) {
            var maxArea: CGFloat = 0
            for screen in NSScreen.screens {
                let area = screen.frame.intersection(windowRect).width * screen.frame.intersection(windowRect).height
                if area > maxArea {
                    maxArea = area
                    targetScreen = screen
                }
            }
            if maxArea > 0 { return targetScreen }
        }

        // Fallback: screen under cursor
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouse) { return screen }
        }
        return targetScreen
    }

    // Move window to another display, preserving relative position ratio
    private func moveToDisplay(_ targetScreen: NSScreen, window: AXUIElement, currentScreen: NSScreen) {
        guard let windowRect = getWindowRect(window) else { return }
        let srcFrame = currentScreen.visibleFrame
        let dstFrame = targetScreen.visibleFrame

        let ratioX = (windowRect.minX - srcFrame.minX) / srcFrame.width
        let ratioY = (windowRect.minY - srcFrame.minY) / srcFrame.height
        let ratioW = windowRect.width / srcFrame.width
        let ratioH = windowRect.height / srcFrame.height

        let newRect = CGRect(
            x: dstFrame.minX + ratioX * dstFrame.width,
            y: dstFrame.minY + ratioY * dstFrame.height,
            width: ratioW * dstFrame.width,
            height: ratioH * dstFrame.height
        )
        applyRect(newRect, to: window)
    }

    // Apply a rect (bottom-left coords) to a window via AX API
    private func applyRect(_ rect: CGRect, to window: AXUIElement) {
        let primaryHeight = NSScreen.screens[0].frame.height
        var axPos = CGPoint(x: rect.minX, y: primaryHeight - rect.minY - rect.height)
        var axSize = CGSize(width: rect.width, height: rect.height)

        if let sizeVal = AXValueCreate(.cgSize, &axSize),
           let posVal = AXValueCreate(.cgPoint, &axPos) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    // Main API to position the active window
    func positionActiveWindow(to position: WindowPosition) {
        guard checkAccessibilityPermissions(prompt: false) else {
            _ = checkAccessibilityPermissions(prompt: true)
            return
        }
        guard let window = getFocusedWindow() else { return }
        let currentScreen = getTargetScreen(for: window)

        // Handle multi-display moves
        if position == .nextDisplay || position == .prevDisplay {
            let screens = NSScreen.screens
            guard screens.count > 1,
                  let idx = screens.firstIndex(of: currentScreen) else { return }
            let nextIdx = position == .nextDisplay
                ? (idx + 1) % screens.count
                : (idx - 1 + screens.count) % screens.count
            moveToDisplay(screens[nextIdx], window: window, currentScreen: currentScreen)
            return
        }

        let f = currentScreen.visibleFrame
        var targetRect = CGRect.zero

        switch position {
        // --- Halves ---
        case .leftHalf:
            targetRect = CGRect(x: f.minX, y: f.minY, width: f.width / 2, height: f.height)
        case .rightHalf:
            targetRect = CGRect(x: f.midX, y: f.minY, width: f.width / 2, height: f.height)
        case .topHalf:
            targetRect = CGRect(x: f.minX, y: f.midY, width: f.width, height: f.height / 2)
        case .bottomHalf:
            targetRect = CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height / 2)
        // --- Quarters ---
        case .topLeftQuarter:
            targetRect = CGRect(x: f.minX, y: f.midY, width: f.width / 2, height: f.height / 2)
        case .topRightQuarter:
            targetRect = CGRect(x: f.midX, y: f.midY, width: f.width / 2, height: f.height / 2)
        case .bottomLeftQuarter:
            targetRect = CGRect(x: f.minX, y: f.minY, width: f.width / 2, height: f.height / 2)
        case .bottomRightQuarter:
            targetRect = CGRect(x: f.midX, y: f.minY, width: f.width / 2, height: f.height / 2)
        // --- Thirds ---
        case .leftThird:
            targetRect = CGRect(x: f.minX, y: f.minY, width: f.width / 3, height: f.height)
        case .centerThird:
            targetRect = CGRect(x: f.minX + f.width / 3, y: f.minY, width: f.width / 3, height: f.height)
        case .rightThird:
            targetRect = CGRect(x: f.minX + 2 * f.width / 3, y: f.minY, width: f.width / 3, height: f.height)
        // --- Two-thirds ---
        case .leftTwoThirds:
            targetRect = CGRect(x: f.minX, y: f.minY, width: 2 * f.width / 3, height: f.height)
        case .rightTwoThirds:
            targetRect = CGRect(x: f.minX + f.width / 3, y: f.minY, width: 2 * f.width / 3, height: f.height)
        // --- Full / Center ---
        case .maximize:
            targetRect = f
        case .center:
            let w = f.width * 0.7
            let h = f.height * 0.7
            targetRect = CGRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h)
        case .nextDisplay, .prevDisplay:
            break // handled above
        }

        applyRect(targetRect, to: window)
    }
}
