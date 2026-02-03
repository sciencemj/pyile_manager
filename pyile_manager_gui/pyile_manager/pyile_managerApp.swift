//
//  pyile_managerApp.swift
//  pyile_manager
//
//  Created by Minjun Park on 2/2/26.
//

import SwiftUI

@main
struct pyile_managerApp: App {
    @StateObject private var backendManager = BackendManager()
    @StateObject private var webSocketService = WebSocketService()
    @State private var showSettingsWindow = false
    
    var body: some Scene {
        // Menu Bar Extra (runs in background)
        MenuBarExtra("Pyile Manager", systemImage: "folder.fill.badge.gearshape") {
            MenuBarView(
                backendManager: backendManager,
                webSocketService: webSocketService,
                showSettingsWindow: $showSettingsWindow
            )
            .onAppear {
                // Start backend when menu bar appears
                if !backendManager.isRunning {
                    backendManager.start()
                    
                    // Wait for backend to start, then connect WebSocket
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if backendManager.isRunning {
                            webSocketService.connect()
                        }
                    }
                }
                
                // Setup quit handler via notification
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    self.handleQuit()
                }
            }
        }
        .menuBarExtraStyle(.window)
        
        // Settings Window (shown on demand)
        Window("Settings", id: "settings") {
            SettingsWindow(
                backendManager: backendManager,
                webSocketService: webSocketService
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
                    
                    // Open settings window
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        // Create new window if doesn't exist
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
                                backendManager: backendManager,
                                webSocketService: webSocketService
                            )
                        )
                        settingsWindow.makeKeyAndOrderFront(nil)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
    }
    
    private func handleQuit() {
        print("=== QUIT HANDLER CALLED ===")
        
        // Get process info before stopping
        let pid = backendManager.process?.processIdentifier ?? 0
        print("Backend PID: \(pid)")
        print("Backend isRunning: \(backendManager.isRunning)")
        
        // Disconnect WebSocket
        webSocketService.disconnect()
        
        // Kill backend process if it exists
        if let process = backendManager.process, process.isRunning {
            let pid = process.processIdentifier
            print("Killing backend process group (PID: \(pid))...")
            
            // Kill process group (includes PyInstaller children)
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
            
            Thread.sleep(forTimeInterval: 0.3)
            print("Backend terminated")
        } else if pid > 0 {
            // Process reference might be gone but we have PID
            print("Killing backend via stored PID: \(pid)...")
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        } else {
            print("No backend process to kill")
        }
    }
}

// Window helper extension
extension NSWindow {
    static func showSettings(backendManager: BackendManager, webSocketService: WebSocketService) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pyile Manager Settings"
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsWindow(
                backendManager: backendManager,
                webSocketService: webSocketService
            )
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

