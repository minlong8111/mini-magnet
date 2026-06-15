import Cocoa
import ApplicationServices

// MARK: - TitlebarHoverManager

/// Monitors mouse position globally.
/// When the cursor enters the green zoom button area of the frontmost window,
/// shows a non-modal LayoutMenuPanel. Hides it when the mouse leaves both
/// the zoom button area and the panel.
@MainActor
class TitlebarHoverManager {
    static let shared = TitlebarHoverManager()

    private var moveMonitor: Any?
    private var panel: LayoutMenuPanel?
    private var highlightOverlay: ZoomHighlightOverlay?
    private var currentZoomRect: CGRect = .zero
    private var isShowing = false

    // Zoom button hotspot relative to window top-left (AX coords, Y grows down)
    private let zoomOffsetX: CGFloat = 50   // left edge of zoom button
    private let zoomWidth:   CGFloat = 34
    private let titleBarH:   CGFloat = 28

    func startMonitoring() {
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            DispatchQueue.main.async { self?.handleMouseMove() }
        }
    }

    func stopMonitoring() {
        if let m = moveMonitor { NSEvent.removeMonitor(m); moveMonitor = nil }
    }

    private func handleMouseMove() {
        let mouse = NSEvent.mouseLocation

        if !isShowing {
            guard let zoomRect = getZoomButtonScreenRect() else { return }
            if zoomRect.insetBy(dx: -4, dy: -4).contains(mouse) {
                showPanel(zoomRect: zoomRect)
            }
        } else {
            let panelRect = panel?.frame ?? .zero
            let expanded = currentZoomRect.insetBy(dx: -8, dy: -8)
            if !expanded.contains(mouse) && !panelRect.insetBy(dx: 4, dy: 4).contains(mouse) {
                hidePanel()
            }
        }
    }

    // MARK: - AX helpers

    private func getZoomButtonScreenRect() -> CGRect? {
        guard WindowManager.shared.checkAccessibilityPermissions(prompt: false) else { return nil }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }

        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success else { return nil }
        let axWin = winRef as! AXUIElement

        // Ignore non-standard windows (popups, floating panels, tooltips)
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWin, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            guard subrole == kAXStandardWindowSubrole as String else { return nil }
        } else {
            return nil
        }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }

        var winPos = CGPoint.zero
        var winSize = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &winPos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &winSize)

        // AX origin = top-left of primary screen (Y grows down)
        // NSEvent.mouseLocation origin = bottom-left (Y grows up)
        let primaryH = NSScreen.screens[0].frame.height
        let winTopInScreen = primaryH - winPos.y  // top edge in NSEvent coords

        return CGRect(
            x: winPos.x + zoomOffsetX,
            y: winTopInScreen - titleBarH,
            width: zoomWidth,
            height: titleBarH
        )
    }

    // MARK: - Show / Hide

    private func showPanel(zoomRect: CGRect) {
        isShowing = true
        currentZoomRect = zoomRect

        // Zoom button highlight
        let hl = ZoomHighlightOverlay.show(at: zoomRect)
        highlightOverlay = hl

        // Layout list panel
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        let menu = delegate.buildMenu()
        let p = LayoutMenuPanel.make(from: menu)
        panel = p

        // Position the panel to avoid overlapping with macOS native green button menu (which expands bottom-right)
        let panelSize = p.frame.size
        var xPos = zoomRect.minX - panelSize.width - 8
        if xPos < 10 { // if offscreen to the left, put it to the right of the native menu (~220px width for native menu)
            xPos = zoomRect.maxX + 220
        }
        let origin = NSPoint(
            x: xPos,
            y: zoomRect.minY - panelSize.height + zoomRect.height
        )
        p.setFrameOrigin(origin)
        p.orderFront(nil)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
        highlightOverlay?.orderOut(nil)
        highlightOverlay = nil
        isShowing = false
    }
}

// MARK: - Zoom Button Highlight Overlay

/// A tiny borderless window that draws a blue ring around the zoom button
/// to give visual feedback that the hover zone is active.
class ZoomHighlightOverlay: NSWindow {
    static func show(at rect: CGRect) -> ZoomHighlightOverlay {
        let w = ZoomHighlightOverlay(
            contentRect: rect.insetBy(dx: -2, dy: -2),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.contentView = HighlightView(frame: NSRect(origin: .zero, size: w.frame.size))
        w.orderFront(nil)
        return w
    }
}

private class HighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.systemBlue.withAlphaComponent(0.35).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

// MARK: - Layout Menu Panel

/// A non-modal floating panel that mirrors the menu bar menu as a list of clickable rows.
class LayoutMenuPanel: NSPanel {
    private var trackingArea: NSTrackingArea?

    static func make(from menu: NSMenu) -> LayoutMenuPanel {
        // Calculate height: each visible non-separator item = 28pt, separator = 8pt
        var totalH: CGFloat = 8  // top+bottom padding
        for item in menu.items where !item.isHidden {
            totalH += item.isSeparatorItem ? 6 : 28
        }
        let screenH = NSScreen.main?.visibleFrame.height ?? 800
        let clampedH = min(totalH, screenH - 100)
        
        let width: CGFloat = 220
        let panel = LayoutMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: clampedH),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.buildContent(from: menu)
        return panel
    }

    private func buildContent(from menu: NSMenu) {
        var totalH: CGFloat = 8
        for item in menu.items where !item.isHidden {
            totalH += item.isSeparatorItem ? 6 : 28
        }
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: totalH))

        // Blurred background for the whole panel
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        bg.material = .menu
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 8
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]

        // Build rows top-down inside the container (NSView coordinate: y=0 is bottom, so top is totalH)
        var yOffset: CGFloat = totalH - 4
        let items = menu.items.filter { !$0.isHidden }

        for item in items {
            if item.isSeparatorItem {
                yOffset -= 6
                let sep = NSBox(frame: NSRect(x: 8, y: yOffset + 2, width: frame.width - 16, height: 1))
                sep.boxType = .separator
                container.addSubview(sep)
            } else {
                yOffset -= 28
                let row = MenuRowButton(frame: NSRect(x: 4, y: yOffset, width: frame.width - 8, height: 26))
                row.setup(with: item)
                container.addSubview(row)
            }
        }
        
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = container
        scroll.autoresizingMask = [.width, .height]

        let wrapper = NSView(frame: NSRect(origin: .zero, size: frame.size))
        wrapper.addSubview(bg)
        wrapper.addSubview(scroll)

        contentView = wrapper
        setupTracking(on: container)
    }

    private func setupTracking(on view: NSView) {
        if let old = trackingArea { view.removeTrackingArea(old) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }
}

// MARK: - Menu Row Button

private class MenuRowButton: NSView {
    private var isHovered = false { didSet { needsDisplay = true } }
    private var action: Selector?
    private var target: AnyObject?
    private var trackingArea: NSTrackingArea?
    private var label: String = ""
    private var itemImage: NSImage?       // store the NSImage directly
    private var isSectionHeader = false

    func setup(with item: NSMenuItem) {
        label = item.title
        action = item.action
        target = item.target as AnyObject?
        itemImage = item.image            // keep reference to the actual NSImage
        isSectionHeader = !item.isEnabled && item.action == nil
        toolTip = item.toolTip
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSectionHeader { isHovered = true }
    }
    override func mouseExited(with event: NSEvent)  { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        guard !isSectionHeader, let action, let target else { return }
        NSApp.sendAction(action, to: target, from: self)
        // Dismiss panel
        (window as? LayoutMenuPanel)?.orderOut(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSectionHeader {
            // Greyed section label
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let str = NSAttributedString(string: label.uppercased(), attributes: attrs)
            str.draw(at: NSPoint(x: 12, y: (bounds.height - 12) / 2))
            return
        }

        if isHovered {
            let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            NSColor.controlAccentColor.setFill()
            bg.fill()
        }

        // Icon — use the stored NSImage directly, tinted for hover state
        var textX: CGFloat = 10
        if let img = itemImage {
            let tint: NSColor = isHovered ? .white : .labelColor
            let tinted = tintImage(img, with: tint)
            tinted.draw(in: NSRect(x: 10, y: (bounds.height - 15) / 2, width: 15, height: 15),
                        from: .zero, operation: .sourceOver, fraction: 1)
            textX = 30
        }

        // Label
        let textColor: NSColor = isHovered ? .white : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: textColor
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        str.draw(at: NSPoint(x: textX, y: (bounds.height - 15) / 2))

        // Shortcut hint (from toolTip)
        if let shortcut = toolTip, !shortcut.isEmpty {
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: isHovered ? NSColor.white.withAlphaComponent(0.7) : NSColor.tertiaryLabelColor
            ]
            let hint = NSAttributedString(string: shortcut, attributes: hintAttrs)
            let hintW = hint.size().width
            hint.draw(at: NSPoint(x: bounds.width - hintW - 10, y: (bounds.height - 15) / 2))
        }
    }

    private func tintImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let result = image.copy() as! NSImage
        result.lockFocus()
        color.set()
        NSRect(origin: .zero, size: result.size).fill(using: .sourceAtop)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}
