import Cocoa

@MainActor
class SnappingManager {
    static let shared = SnappingManager()
    
    private var eventMonitor: Any?
    private var isDragging = false
    private var activeSnapPosition: WindowPosition?
    
    func startMonitoring() {
        // We monitor mouse dragged and mouse up events globally
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleMouseEvent(event)
            }
        }
    }
    
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleMouseEvent(_ event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation // Bottom-left based coordinate system
        
        switch event.type {
        case .leftMouseDown:
            isDragging = true
            activeSnapPosition = nil
            
        case .leftMouseDragged:
            guard isDragging else { return }
            if let screen = findScreen(for: mouseLocation) {
                activeSnapPosition = checkSnapZone(at: mouseLocation, on: screen)
            }
            
        case .leftMouseUp:
            if isDragging {
                isDragging = false
                if let position = activeSnapPosition {
                    // Perform the actual snap using our WindowManager
                    WindowManager.shared.positionActiveWindow(to: position)
                }
                activeSnapPosition = nil
            }
            
        default:
            break
        }
    }
    
    private func findScreen(for point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return NSScreen.main
    }
    
    private func checkSnapZone(at point: CGPoint, on screen: NSScreen) -> WindowPosition? {
        let frame = screen.frame
        let padding: CGFloat = 8 // Boundary distance to trigger snap detection
        let cornerRange: CGFloat = 100 // Larger range for the corners to make it easy to trigger corner snaps
        
        let isLeft = point.x <= frame.minX + padding
        let isRight = point.x >= frame.maxX - padding
        let isTop = point.y >= frame.maxY - padding
        let isBottom = point.y <= frame.minY + padding
        
        let nearLeftCorner = point.x <= frame.minX + cornerRange
        let nearRightCorner = point.x >= frame.maxX - cornerRange
        let nearTopCorner = point.y >= frame.maxY - cornerRange
        let nearBottomCorner = point.y <= frame.minY + cornerRange
        
        if isTop {
            if nearLeftCorner { return .topLeftQuarter }
            if nearRightCorner { return .topRightQuarter }
            return .maximize
        }
        
        if isBottom {
            if nearLeftCorner { return .bottomLeftQuarter }
            if nearRightCorner { return .bottomRightQuarter }
            return .bottomHalf
        }
        
        if isLeft {
            if nearTopCorner { return .topLeftQuarter }
            if nearBottomCorner { return .bottomLeftQuarter }
            return .leftHalf
        }
        
        if isRight {
            if nearTopCorner { return .topRightQuarter }
            if nearBottomCorner { return .bottomRightQuarter }
            return .rightHalf
        }
        
        return nil
    }
}
