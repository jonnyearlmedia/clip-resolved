import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ClipResolvedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("Clip Resolved", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandMenu("Clip Resolved") {
                Button("Scan Source") {
                    Task { await store.scanSource() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.sourcePath.isEmpty || store.isBusy)

                Button("Search Footage") {
                    store.selection = .search
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Project Chat") {
                    store.selection = .chat
                }
                .keyboardShortcut("j", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(store: store)
                .frame(width: 640, height: 620)
        }
    }
}
