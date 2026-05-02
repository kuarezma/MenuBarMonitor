import SwiftUI
import AppKit
import Combine
import ServiceManagement

@main
struct MenuBarMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MonitorModel.shared
    private var statusItem: NSStatusItem?
    private var statusHostView: StatusItemHostView?
    private var popover = NSPopover()
    private var cancellable: AnyCancellable?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPopover()
        setupStatusItem()
        bindStatusLabel()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentSize = NSSize(width: 360, height: 440)
        popover.contentViewController = NSHostingController(
            rootView: MonitorDetailView(model: model).frame(minWidth: 340, minHeight: 420)
        )
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let host = StatusItemHostView()
        host.delegate = self
        host.update(attributedTitle: model.statusBarAttributedTitle)
        item.view = host
        statusItem = item
        statusHostView = host
    }

    private func bindStatusLabel() {
        cancellable = model.$statusBarAttributedTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] attr in
                self?.statusHostView?.update(attributedTitle: attr)
            }
    }

    private func togglePopover(from anchor: NSView) {
        if popover.isShown {
            popover.performClose(nil)
            stopEventMonitor()
            return
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        startEventMonitor()
    }

    private func showRightClickMenu(from anchor: NSView) {
        if popover.isShown {
            popover.performClose(nil)
            stopEventMonitor()
        }

        let menu = NSMenu()
        let autoLaunch = NSMenuItem(
            title: L10n.t("menu.autoLaunch"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        autoLaunch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        autoLaunch.target = self
        menu.addItem(autoLaunch)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: anchor)
    }

    @objc
    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

extension AppDelegate: StatusItemHostViewDelegate {
    func statusItemHostViewDidLeftClick(_ view: StatusItemHostView) {
        togglePopover(from: view)
    }

    func statusItemHostViewDidRightClick(_ view: StatusItemHostView) {
        showRightClickMenu(from: view)
    }
}
