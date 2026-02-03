//
//  WatchlistEditor.swift
//  pyile_manager
//
//  Editor for managing watched folders
//

import SwiftUI
import AppKit

struct WatchlistEditor: View {
    @Binding var folders: [String]
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Watched Folders")
                    .font(.headline)
                Spacer()
                Button(action: addFolder) {
                    Label("Add Folder", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
            }
            
            if folders.isEmpty {
                Text("No folders added yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(folders, id: \.self) { folder in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(folder)
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: { removeFolder(folder) }) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .alert("Error", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to watch"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let path = url.path
                if folders.contains(path) {
                    alertMessage = "This folder is already in the watchlist"
                    showingAlert = true
                } else {
                    folders.append(path)
                }
            }
        }
    }
    
    private func removeFolder(_ folder: String) {
        folders.removeAll { $0 == folder }
    }
}

#Preview {
    GlassCard {
        WatchlistEditor(folders: .constant([
            "/Users/test/Downloads",
            "/Users/test/Documents"
        ]))
    }
    .padding()
    .frame(width: 500)
}
