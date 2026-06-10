//
//  pyile_managerApp.swift
//  pyile_manager
//
//  Created by Minjun Park on 2/2/26.
//

import SwiftUI
import UserNotifications

@main
struct pyile_managerApp: App {
    @StateObject private var configManager = ConfigManager()
    @StateObject private var fileMonitor: FileMonitorService

    @State private var showSettingsWindow = false

    init() {
        let cm = ConfigManager()
        _configManager = StateObject(wrappedValue: cm)
        _fileMonitor = StateObject(wrappedValue: FileMonitorService(configManager: cm))

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        // Menu Bar Extra (runs in background)
        MenuBarExtra("Pyile Manager", systemImage: "folder.fill.badge.gearshape") {
            MenuBarView(
                configManager: configManager,
                fileMonitor: fileMonitor,
                showSettingsWindow: $showSettingsWindow
            )
            .onAppear {
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    handleQuit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Settings Window (shown on demand)
        Window("Settings", id: "settings") {
            SettingsWindow(
                configManager: configManager,
                fileMonitor: fileMonitor
            )
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .keyboardShortcut("s", modifiers: [.command])
        .commands {

            CommandGroup(replacing: .newItem) {
                Button("Open Settings") {
                    showSettingsWindow = true
                    NSApp.activate(ignoringOtherApps: true)

                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        let settingsWindow = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                            styleMask: [.titled, .closable, .miniaturizable],
                            backing: .buffered,
                            defer: false
                        )
                        settingsWindow.identifier = NSUserInterfaceItemIdentifier("settings")
                        settingsWindow.center()
                        settingsWindow.contentView = NSHostingView(
                            rootView: SettingsWindow(
                                configManager: configManager,
                                fileMonitor: fileMonitor
                            )
                        )
                        settingsWindow.makeKeyAndOrderFront(nil)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }

        // History Window (shown on demand)
        Window("History", id: "history") {
            HistoryWindow(fileMonitor: fileMonitor)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private func handleQuit() {
        print("=== QUIT HANDLER CALLED ===")
        fileMonitor.stop()
        print("File monitor stopped, app terminating")
    }
}
