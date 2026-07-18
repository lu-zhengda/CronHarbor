import AppKit
import SwiftUI

@main
struct CronHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DashboardModel.makeDefault()
    @AppStorage("showsNextRunInMenuBar") private var showsNextRunInMenuBar = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(model)
        } label: {
            if showsNextRunInMenuBar, let countdown = model.menuBarCountdownText {
                Label("CronHarbor", systemImage: model.menuBarSymbol)
                Text(countdown)
            } else {
                Label("CronHarbor", systemImage: model.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
