import AppKit
import SwiftUI

@main
struct CronHarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DashboardModel.makeDefault()

    var body: some Scene {
        Window("CronHarbor", id: "dashboard") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1_120, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Cron Job") {
                    model.beginCreatingJob()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.isSourceBusy)

                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isSourceBusy || !model.pendingChanges.isEmpty)
            }
        }

        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(model)
        } label: {
            Label("CronHarbor", systemImage: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
