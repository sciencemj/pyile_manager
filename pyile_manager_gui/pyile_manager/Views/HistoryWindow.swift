//
//  HistoryWindow.swift
//  pyile_manager
//
//  Full history list with per-entry undo and error reporting
//

import SwiftUI

struct HistoryWindow: View {
    @ObservedObject var fileMonitor: FileMonitorService

    var body: some View {
        Group {
            if fileMonitor.recentEvents.isEmpty {
                Text("No file activity yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(fileMonitor.recentEvents) { entry in
                    EventRow(entry: entry) {
                        Task { await fileMonitor.undo(entry) }
                    }
                    .disabled(fileMonitor.isUndoing)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .navigationTitle("History")
        .alert(
            "Undo Failed",
            isPresented: Binding(
                get: { fileMonitor.undoError != nil },
                set: { if !$0 { fileMonitor.undoError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { fileMonitor.undoError = nil }
        } message: {
            Text(fileMonitor.undoError ?? "")
        }
    }
}
