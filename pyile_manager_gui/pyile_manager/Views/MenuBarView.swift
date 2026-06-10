//
//  MenuBarView.swift
//  pyile_manager
//
//  Menu bar extra content and recent activity
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var fileMonitor: FileMonitorService
    @Binding var showSettingsWindow: Bool

    @Environment(\.openWindow) private var openWindow

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

                // Status Indicator
                HStack(spacing: 16) {
                    StatusIndicator(
                        label: "Monitoring",
                        isActive: fileMonitor.isMonitoring,
                        activeColor: .blue,
                        inactiveColor: .orange
                    )
                }
                .font(.caption)
            }
            .padding()

            Divider()

            // Recent Activity
            if !fileMonitor.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(fileMonitor.recentEvents.prefix(5))) { entry in
                                EventRow(entry: entry)
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

                Button(action: toggleMonitoring) {
                    Label(
                        fileMonitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                        systemImage: fileMonitor.isMonitoring ? "pause.circle" : "play.circle"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

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
    }

    private func toggleMonitoring() {
        if fileMonitor.isMonitoring {
            fileMonitor.stop()
        } else {
            fileMonitor.start()
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
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.event.displayIcon)
                .foregroundStyle(entry.event.type == "file_moved" ? .blue : .green)
                .font(.caption)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.event.displayText)
                    .font(.caption)
                    .lineLimit(1)
                    .strikethrough(entry.undone)
                    .foregroundStyle(entry.undone ? .secondary : .primary)
                Text(timeAgo(from: entry.event.timestamp))
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
