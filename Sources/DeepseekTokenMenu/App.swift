import SwiftUI
import AppKit

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?
    private var didLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// 首次启动弹出设置窗口给用户视觉反馈
    func showOnLaunch(vm: AppViewModel) {
        guard !didLaunch else { return }
        didLaunch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.showSettings(vm: vm)
        }
    }

    func showSettings(vm: AppViewModel) {
        if let w = settingsWindow {
            w.contentView = NSHostingView(rootView: SettingsView(viewModel: vm))
            w.setContentSize(NSSize(width: 440, height: 500))
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            w.title = "DeepSeek Token Menu — 设置"
            w.center()
            w.contentView = NSHostingView(rootView: SettingsView(viewModel: vm))
            w.isReleasedWhenClosed = false
            settingsWindow = w
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - 主 App

@main
struct DeepSeekTokenMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(viewModel: vm, delegate: delegate)
                .fixedSize()
                .task {
                    await vm.initialize()
                    delegate.showOnLaunch(vm: vm)
                }
        } label: {
            Text(vm.menuBarTitle())
                .fixedSize()
        }
        .menuBarExtraStyle(.menu)
    }
}
