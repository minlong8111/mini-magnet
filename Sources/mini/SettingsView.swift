import SwiftUI
import ServiceManagement

// MARK: - Settings State (shared, persisted via UserDefaults)

@available(macOS 11.0, *)
@MainActor
class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var snappingEnabled: Bool {
        didSet { UserDefaults.standard.set(snappingEnabled, forKey: "snappingEnabled")
                 snappingEnabled ? SnappingManager.shared.startMonitoring()
                                 : SnappingManager.shared.stopMonitoring() }
    }
    @Published var hoverOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(hoverOverlayEnabled, forKey: "hoverOverlayEnabled")
                 hoverOverlayEnabled ? TitlebarHoverManager.shared.startMonitoring()
                                     : TitlebarHoverManager.shared.stopMonitoring() }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            if #available(macOS 13.0, *) {
                if launchAtLogin {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
            }
        }
    }
    
    private var isInitialized = false
    
    @Published var shortcuts: [String: Shortcut] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(shortcuts) {
                UserDefaults.standard.set(data, forKey: "customShortcuts")
            }
            if isInitialized {
                NotificationCenter.default.post(name: NSNotification.Name("ShortcutsChanged"), object: nil)
            }
        }
    }

    init() {
        snappingEnabled     = UserDefaults.standard.object(forKey: "snappingEnabled") as? Bool ?? true
        hoverOverlayEnabled = UserDefaults.standard.object(forKey: "hoverOverlayEnabled") as? Bool ?? false
        launchAtLogin       = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? false
        
        let loadedShortcuts: [String: Shortcut]
        if let data = UserDefaults.standard.data(forKey: "customShortcuts"),
           let decoded = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            loadedShortcuts = decoded
        } else {
            var defaultDict: [String: Shortcut] = [:]
            for action in WindowAction.allCases {
                defaultDict[action.rawValue] = action.defaultShortcut
            }
            loadedShortcuts = defaultDict
        }
        
        self.shortcuts = loadedShortcuts
        self.isInitialized = true
    }
}

// MARK: - Settings Window Controller

@available(macOS 11.0, *)
@MainActor
class SettingsWindowController: NSWindowController {
    static var shared: SettingsWindowController?

    static func show() {
        if shared == nil {
            let hostingView = NSHostingView(rootView: SettingsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Mini Magnet Settings"
            window.contentView = hostingView
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            let wc = SettingsWindowController(window: window)
            shared = wc
        }
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Settings View

@available(macOS 11.0, *)
struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var selectedTab = 0
    @State private var recordingAction: String? = nil
    @State private var localMonitor: Any? = nil

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            headerView

            // ── Tab Bar ─────────────────────────────────────────────────────
            tabBar

            Divider()

            // ── Content ─────────────────────────────────────────────────────
            Group {
                switch selectedTab {
                case 0:  generalTab
                case 1:  shortcutsTab
                default: aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)

            Spacer(minLength: 0)
        }
        .frame(width: 480, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Header
    private var headerView: some View {
        HStack(spacing: 16) {
            let iconPath = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("AppIcon.png").path ?? ""
            if let img = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .cornerRadius(12)
            } else {
                Image(systemName: "uiwindow.split.2x1")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Mini Magnet")
                    .font(.title2).fontWeight(.semibold)
                Text("Window Manager for macOS")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // MARK: Tab Bar
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(["General", "Shortcuts", "About"].indices, id: \.self) { idx in
                let label = ["General", "Shortcuts", "About"][idx]
                Button(action: { selectedTab = idx }) {
                    Text(label)
                        .font(.system(size: 13, weight: selectedTab == idx ? .semibold : .regular))
                        .foregroundColor(selectedTab == idx ? .primary : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == idx
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    // MARK: General Tab
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsSection("Behaviour") {
                toggleRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Window Snapping",
                    subtitle: "Drag windows to screen edges to snap them",
                    binding: $store.snappingEnabled
                )
                Divider().padding(.leading, 44)
                toggleRow(
                    icon: "cursorarrow.rays",
                    title: "Zoom Button Overlay",
                    subtitle: "Show layout picker when hovering the green zoom button",
                    binding: $store.hoverOverlayEnabled
                )
            }

            Spacer().frame(height: 20)

            settingsSection("System") {
                toggleRow(
                    icon: "bolt.fill",
                    title: "Launch at Login",
                    subtitle: "Start Mini Magnet automatically when you log in",
                    binding: $store.launchAtLogin
                )
            }
        }
    }

    // MARK: Shortcuts Tab
    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                shortcutSection("Maximize & Center", actions: [.maximize, .center])
                Spacer().frame(height: 16)
                shortcutSection("Halves", actions: [.leftHalf, .rightHalf, .topHalf, .bottomHalf])
                Spacer().frame(height: 16)
                shortcutSection("Quarters", actions: [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter])
                Spacer().frame(height: 16)
                shortcutSection("Thirds", actions: [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds])
                Spacer().frame(height: 16)
                shortcutSection("Display", actions: [.nextDisplay, .prevDisplay])
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: About Tab
    private var aboutTab: some View {
        let iconPath = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("AppIcon.png").path ?? ""
        return VStack(spacing: 20) {
            Spacer()
            if let img = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .cornerRadius(18)
                    .shadow(radius: 8)
            }
            VStack(spacing: 6) {
                Text("Mini Magnet").font(.title).fontWeight(.bold)
                Text("Version 1.0").foregroundColor(.secondary)
                Text("A lightweight window manager for macOS.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Quit Mini Magnet") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    private func toggleRow(icon: String, title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func shortcutSection(_ title: String, actions: [WindowAction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.1.rawValue) { idx, action in
                    HStack {
                        Text(action.label).font(.system(size: 13))
                        Spacer()
                        
                        let isRecording = recordingAction == action.rawValue
                        let shortcut = store.shortcuts[action.rawValue]
                        let displayStr = isRecording ? "Press Shortcut..." : shortcutDisplayString(keyCode: shortcut?.keyCode ?? 0, modifiers: shortcut?.modifiers ?? 0)
                        
                        Button(action: {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording(for: action.rawValue)
                            }
                        }) {
                            Text(displayStr)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(isRecording ? .accentColor : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(isRecording ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    if idx < actions.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
    
    // MARK: - Shortcut Recording Logic
    
    private func startRecording(for actionId: String) {
        recordingAction = actionId
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // ESC key to cancel
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            
            let flags = event.modifierFlags
            let carbonMods = cocoaToCarbonModifiers(flags)
            
            // Require at least one modifier key (control, option, shift, or command)
            let hasModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control) || flags.contains(.shift)
            
            if hasModifier {
                let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
                store.shortcuts[actionId] = shortcut
                stopRecording()
                return nil
            }
            
            return event
        }
    }
    
    private func stopRecording() {
        recordingAction = nil
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
