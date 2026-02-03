//
//  URLMappingEditor.swift
//  pyile_manager
//
//  Editor for URL pattern to folder mappings
//

import SwiftUI
import AppKit

struct URLMappingEditor: View {
    @Binding var mappings: [String: String]
    @State private var editingKey: String?
    @State private var newPattern = ""
    @State private var newDestination = ""
    @State private var showingAddDialog = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("URL Mappings")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddDialog = true }) {
                    Label("Add Mapping", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
            }
            
            if mappings.isEmpty {
                Text("No URL mappings configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(mappings.keys.sorted()), id: \.self) { pattern in
                            if let destination = mappings[pattern] {
                                MappingRow(
                                    pattern: pattern,
                                    destination: destination,
                                    onDelete: { removeMapping(pattern) }
                                )
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .sheet(isPresented: $showingAddDialog) {
            AddMappingDialog(
                pattern: $newPattern,
                destination: $newDestination,
                onSave: {
                    if !newPattern.isEmpty && !newDestination.isEmpty {
                        mappings[newPattern] = newDestination
                        newPattern = ""
                        newDestination = ""
                        showingAddDialog = false
                    }
                },
                onCancel: {
                    newPattern = ""
                    newDestination = ""
                    showingAddDialog = false
                }
            )
        }
    }
    
    private func removeMapping(_ pattern: String) {
        mappings.removeValue(forKey: pattern)
    }
}

struct MappingRow: View {
    let pattern: String
    let destination: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(.blue)
                    Text(pattern)
                        .font(.body)
                        .lineLimit(1)
                }
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct AddMappingDialog: View {
    @Binding var pattern: String
    @Binding var destination: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add URL Mapping")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("URL Pattern")
                    .font(.caption)
                TextField("e.g., github.com or example.com/{$var}", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                
                Text("Destination Folder")
                    .font(.caption)
                HStack {
                    TextField("/path/to/folder", text: $destination)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        
                        panel.begin { response in
                            if response == .OK, let url = panel.url {
                                destination = url.path
                            }
                        }
                    }
                }
            }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pattern.isEmpty || destination.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview {
    GlassCard {
        URLMappingEditor(mappings: .constant([
            "github.com": "/Users/test/Downloads/GitHub",
            "example.com/course/{$var}": "/Users/test/Downloads/Courses"
        ]))
    }
    .padding()
    .frame(width: 500)
}
