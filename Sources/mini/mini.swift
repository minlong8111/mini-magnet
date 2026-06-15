import Cocoa
import SwiftUI

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = WindowManager.shared.checkAccessibilityPermissions(prompt: true)
        setupMenuBar()
        setupGlobalHotkeys()
        if SettingsStore.shared.snappingEnabled {
            SnappingManager.shared.startMonitoring()
        }
        if SettingsStore.shared.hoverOverlayEnabled {
            TitlebarHoverManager.shared.startMonitoring()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = makeMenuBarIcon()
        }
        statusItem?.menu = buildMenu()
    }

    /// Build an 18×18 template image for the menu bar.
    /// Primary: resize AppIcon.png from the bundle to 18×18 and mark as template.
    /// Fallback: SF Symbol.
    private func makeMenuBarIcon() -> NSImage? {
        // Use the native macOS 'magnet' system symbol for a sleek, pixel-perfect, and system-integrated menu bar icon
        if #available(macOS 11.0, *) {
            if let img = NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: "Mini Magnet") ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Mini Magnet") {
                img.isTemplate = true
                return img
            }
        }
        
        return makeFallbackIcon()
    }

    private func makeFallbackIcon() -> NSImage? {
        // Ultimate fallback: unicode glyph rendered into an image
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: "⊞", attributes: attrs).draw(at: NSPoint(x: 2, y: 1))
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    /// Get the display string for a WindowAction from SettingsStore (dynamic)
    private func shortcutTip(for action: WindowAction) -> String {
        if #available(macOS 11.0, *) {
            if let s = SettingsStore.shared.shortcuts[action.rawValue] {
                return shortcutDisplayString(keyCode: s.keyCode, modifiers: s.modifiers)
            }
        }
        let d = action.defaultShortcut
        return shortcutDisplayString(keyCode: d.keyCode, modifiers: d.modifiers)
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // ─── Header ───────────────────────────────────────────────────────────
        let header = NSMenuItem(title: "Mini Magnet", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // ─── Maximise ─────────────────────────────────────────────────────────
        menu.addItem(makeItem("Maximize",          symbol: "rectangle",                     action: #selector(actMaximize),   tip: shortcutTip(for: .maximize)))
        menu.addItem(makeItem("Center",            symbol: "rectangle.center.inset.filled", action: #selector(actCenter),     tip: shortcutTip(for: .center)))
        menu.addItem(.separator())

        // ─── Halves ───────────────────────────────────────────────────────────
        menu.addItem(sectionLabel("Halves"))
        menu.addItem(makeItem("Left Half",         symbol: "rectangle.lefthalf.filled",     action: #selector(actLeft),       tip: shortcutTip(for: .leftHalf)))
        menu.addItem(makeItem("Right Half",        symbol: "rectangle.righthalf.filled",    action: #selector(actRight),      tip: shortcutTip(for: .rightHalf)))
        menu.addItem(makeItem("Top Half",          symbol: "rectangle.tophalf.filled",      action: #selector(actTop),        tip: shortcutTip(for: .topHalf)))
        menu.addItem(makeItem("Bottom Half",       symbol: "rectangle.bottomhalf.filled",   action: #selector(actBottom),     tip: shortcutTip(for: .bottomHalf)))
        menu.addItem(.separator())

        // ─── Quarters ─────────────────────────────────────────────────────────
        menu.addItem(sectionLabel("Quarters"))
        menu.addItem(makeItem("Top Left",          symbol: "rectangle.topleft.inset.filled",    action: #selector(actTopLeft),  tip: shortcutTip(for: .topLeftQuarter)))
        menu.addItem(makeItem("Top Right",         symbol: "rectangle.topright.inset.filled",   action: #selector(actTopRight), tip: shortcutTip(for: .topRightQuarter)))
        menu.addItem(makeItem("Bottom Left",       symbol: "rectangle.bottomleft.inset.filled", action: #selector(actBotLeft),  tip: shortcutTip(for: .bottomLeftQuarter)))
        menu.addItem(makeItem("Bottom Right",      symbol: "rectangle.bottomright.inset.filled",action: #selector(actBotRight), tip: shortcutTip(for: .bottomRightQuarter)))
        menu.addItem(.separator())

        // ─── Thirds ───────────────────────────────────────────────────────────
        menu.addItem(sectionLabel("Thirds"))
        menu.addItem(makeItem("Left Third",        symbol: "rectangle.lefthalf.filled",     action: #selector(actLeftThird),   tip: shortcutTip(for: .leftThird)))
        menu.addItem(makeItem("Center Third",      symbol: "rectangle.center.inset.filled", action: #selector(actCenterThird), tip: shortcutTip(for: .centerThird)))
        menu.addItem(makeItem("Right Third",       symbol: "rectangle.righthalf.filled",    action: #selector(actRightThird),  tip: shortcutTip(for: .rightThird)))
        menu.addItem(makeItem("Left Two Thirds",   symbol: "rectangle.lefthalf.filled",     action: #selector(actLeftTwo),     tip: shortcutTip(for: .leftTwoThirds)))
        menu.addItem(makeItem("Right Two Thirds",  symbol: "rectangle.righthalf.filled",    action: #selector(actRightTwo),    tip: shortcutTip(for: .rightTwoThirds)))
        menu.addItem(.separator())

        // ─── Display ──────────────────────────────────────────────────────────
        menu.addItem(sectionLabel("Display"))
        menu.addItem(makeItem("Next Display",      symbol: "display.2", action: #selector(actNextDisplay), tip: shortcutTip(for: .nextDisplay)))
        menu.addItem(makeItem("Previous Display",  symbol: "display",   action: #selector(actPrevDisplay), tip: shortcutTip(for: .prevDisplay)))
        menu.addItem(.separator())

        // ─── Footer ───────────────────────────────────────────────────────────
        let settings = NSMenuItem(title: "Settings…", action: #selector(actSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Mini Magnet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)

        return menu
    }

    // Helper: section label (greyed-out, non-clickable)
    private func sectionLabel(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }

    // Helper: menu item with SF Symbol + shortcut label
    private func makeItem(_ title: String,
                           symbol: String,
                           action: Selector,
                           tip: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self

        // SF Symbol icon (template = adapts to dark/light)
        if #available(macOS 11.0, *),
           let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            img.isTemplate = true
            item.image = img
        }

        // Shortcut display (shown in tooltip, not as real keyEquivalent to avoid conflicts)
        if !tip.isEmpty {
            item.toolTip = tip
        }
        return item
    }

    // MARK: - Hotkeys

    private func setupGlobalHotkeys() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onShortcutsChanged),
            name: NSNotification.Name("ShortcutsChanged"),
            object: nil
        )
        registerAllHotkeys()
    }

    @objc private func onShortcutsChanged() {
        registerAllHotkeys()
        // Rebuild menu bar to reflect updated shortcut labels
        statusItem?.menu = buildMenu()
    }

    @objc private func registerAllHotkeys() {
        if #available(macOS 11.0, *) {
            HotkeyManager.shared.unregisterAll()
            
            let store = SettingsStore.shared
            for action in WindowAction.allCases {
                guard let shortcut = store.shortcuts[action.rawValue] else { continue }
                // Skip registering if keycode is 0 (unset/disabled)
                guard shortcut.keyCode != 0 else { continue }
                
                let pos: WindowPosition
                switch action {
                case .maximize:          pos = .maximize
                case .center:            pos = .center
                case .leftHalf:          pos = .leftHalf
                case .rightHalf:         pos = .rightHalf
                case .topHalf:           pos = .topHalf
                case .bottomHalf:        pos = .bottomHalf
                case .topLeftQuarter:    pos = .topLeftQuarter
                case .topRightQuarter:   pos = .topRightQuarter
                case .bottomLeftQuarter: pos = .bottomLeftQuarter
                case .bottomRightQuarter:pos = .bottomRightQuarter
                case .leftThird:         pos = .leftThird
                case .centerThird:       pos = .centerThird
                case .rightThird:        pos = .rightThird
                case .leftTwoThirds:     pos = .leftTwoThirds
                case .rightTwoThirds:    pos = .rightTwoThirds
                case .nextDisplay:       pos = .nextDisplay
                case .prevDisplay:       pos = .prevDisplay
                }
                
                HotkeyManager.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) {
                    WindowManager.shared.positionActiveWindow(to: pos)
                }
            }
        }
    }

    // MARK: - Actions

    @objc func actMaximize()     { WindowManager.shared.positionActiveWindow(to: .maximize) }
    @objc func actCenter()       { WindowManager.shared.positionActiveWindow(to: .center) }
    @objc func actLeft()         { WindowManager.shared.positionActiveWindow(to: .leftHalf) }
    @objc func actRight()        { WindowManager.shared.positionActiveWindow(to: .rightHalf) }
    @objc func actTop()          { WindowManager.shared.positionActiveWindow(to: .topHalf) }
    @objc func actBottom()       { WindowManager.shared.positionActiveWindow(to: .bottomHalf) }
    @objc func actTopLeft()      { WindowManager.shared.positionActiveWindow(to: .topLeftQuarter) }
    @objc func actTopRight()     { WindowManager.shared.positionActiveWindow(to: .topRightQuarter) }
    @objc func actBotLeft()      { WindowManager.shared.positionActiveWindow(to: .bottomLeftQuarter) }
    @objc func actBotRight()     { WindowManager.shared.positionActiveWindow(to: .bottomRightQuarter) }
    @objc func actLeftThird()    { WindowManager.shared.positionActiveWindow(to: .leftThird) }
    @objc func actCenterThird()  { WindowManager.shared.positionActiveWindow(to: .centerThird) }
    @objc func actRightThird()   { WindowManager.shared.positionActiveWindow(to: .rightThird) }
    @objc func actLeftTwo()      { WindowManager.shared.positionActiveWindow(to: .leftTwoThirds) }
    @objc func actRightTwo()     { WindowManager.shared.positionActiveWindow(to: .rightTwoThirds) }
    @objc func actNextDisplay()  { WindowManager.shared.positionActiveWindow(to: .nextDisplay) }
    @objc func actPrevDisplay()  { WindowManager.shared.positionActiveWindow(to: .prevDisplay) }

    @objc func actCheckPerm() {
        let ok = WindowManager.shared.checkAccessibilityPermissions(prompt: true)
        let a = NSAlert()
        a.messageText = ok ? "Accessibility Permission Granted" : "Accessibility Permission Required"
        a.informativeText = ok
            ? "Mini Magnet has full permission to manage windows."
            : "Go to System Settings › Privacy & Security › Accessibility and enable Mini Magnet."
        a.alertStyle = ok ? .informational : .warning
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    @objc func actSettings() {
        if #available(macOS 11.0, *) {
            SettingsWindowController.show()
        }
    }
}
