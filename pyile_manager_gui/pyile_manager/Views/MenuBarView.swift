//
//  MenuBarView.swift
//  pyile_manager
//
//  Menu bar extra content and recent activity
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var backendManager: BackendManager
    @ObservedObject var webSocketService: WebSocketService
    @Binding var showSettingsWindow: Bool
    
    @State private var isMonitoring = false
    @Environment(\.openWindow) private var openWindow
    private let apiClient = APIClient()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Pyile Manager")
                        .font(.headline)
                }
                
                // Status Indicators
                HStack(spacing: 16) {
                    StatusIndicator(
                        label: "Backend",
                        isActive: backendManager.isRunning,
                        activeColor: .green,
                        inactiveColor: .red
                    )
                    
                    if backendManager.isRunning {
                        StatusIndicator(
                            label: "Monitoring",
                            isActive: isMonitoring,
                            activeColor: .blue,
                            inactiveColor: .orange
                        )
                    }
                }
                .font(.caption)
            }
            .padding()
            
            Divider()
            
            // Recent Activity
            if !webSocketService.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(webSocketService.recentEvents.prefix(5))) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .padding(.horizontal, 8)
                }
                
                Divider()
            }
            
            // Actions
            VStack(spacing: 4) {
                Button(action: openSettingsWindow) {
                    Label("Open Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                if backendManager.isRunning {
                    Button(action: toggleMonitoring) {
                        Label(
                            isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                            systemImage: isMonitoring ? "pause.circle" : "play.circle"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                
                Divider()
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Label("Quit", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        .onAppear {
            checkMonitoringStatus()
        }
    }
    
    private func checkMonitoringStatus() {
        guard backendManager.isRunning else { return }
        
        Task {
            do {
                let status = try await apiClient.getStatus()
                await MainActor.run {
                    isMonitoring = status.monitoring
                }
            } catch {
                print("Failed to get status: \(error)")
            }
        }
    }
    
    private func toggleMonitoring() {
        Task {
            do {
                if isMonitoring {
                    try await apiClient.stopMonitoring()
                } else {
                    try await apiClient.startMonitoring()
                }
                
                // Update status
                let status = try await apiClient.getStatus()
                await MainActor.run {
                    isMonitoring = status.monitoring
                }
            } catch {
                print("Failed to toggle monitoring: \(error)")
            }
        }
    }
    
    private func openSettingsWindow() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Supporting Views
struct StatusIndicator: View {
    let label: String
    let isActive: Bool
    let activeColor: Color
    let inactiveColor: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? activeColor : inactiveColor)
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? activeColor : inactiveColor, radius: 2)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

struct EventRow: View {
    let event: FileEvent
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.displayIcon)
                .foregroundStyle(event.type == "file_moved" ? .blue : .green)
                .font(.caption)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayText)
                    .font(.caption)
                    .lineLimit(1)
                Text(timeAgo(from: event.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
    
    private func timeAgo(from timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let seconds = Date().timeIntervalSince(date)
        
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    MenuBarView(
        backendManager: BackendManager(),
        webSocketService: WebSocketService(),
        showSettingsWindow: .constant(false)
    )
}
