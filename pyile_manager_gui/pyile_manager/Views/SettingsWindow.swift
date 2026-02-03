//
//  SettingsWindow.swift
//  pyile_manager
//
//  Main settings window with liquid glass design
//

import SwiftUI

struct SettingsWindow: View {
    private let apiClient = APIClient()
    @ObservedObject var backendManager: BackendManager
    @ObservedObject var webSocketService: WebSocketService
    
    @State private var config: AppConfig?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isMonitoring = false
    
    // Available AI models
    private let aiModels = ["gemma3:4b", "llama2", "mistral", "deepocr", "phi"]
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Status Section
                statusSection
                
                // Settings Sections
                if let config = config {
                    generalSettingsSection(config: Binding(
                        get: { config },
                        set: { self.config = $0 }
                    ))
                    
                    aiModelsSection(config: Binding(
                        get: { config },
                        set: { self.config = $0 }
                    ))
                    
                    watchlistSection(config: Binding(
                        get: { config },
                        set: { self.config = $0 }
                    ))
                    
                    urlMappingsSection(config: Binding(
                        get: { config },
                        set: { self.config = $0 }
                    ))
                    
                    tagMappingsSection(config: Binding(
                        get: { config },
                        set: { self.config = $0 }
                    ))
                    
                    renameFoldersSection(config: Binding(
                        get: { config },
                        set: { self.config = $0 }
                    ))
                    
                    // Save Button
                    saveButtonSection
                }
                
                // Messages
                if let errorMessage = errorMessage {
                    messageView(errorMessage, isError: true)
                }
                if let successMessage = successMessage {
                    messageView(successMessage, isError: false)
                }
            }
            .padding(20)
        }
        .frame(width: 600, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadConfig()
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text("Pyile Manager Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            Text("Configure file management and AI settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backend Status")
                        .font(.headline)
                    Text(backendManager.isRunning ? "Running on port 8000" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(backendManager.isRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .shadow(color: backendManager.isRunning ? .green : .red, radius: 4)
                
                if backendManager.isRunning {
                    Divider()
                        .frame(height: 30)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monitoring")
                            .font(.headline)
                        Text(isMonitoring ? "Active" : "Inactive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(isMonitoring ? Color.blue : Color.orange)
                        .frame(width: 12, height: 12)
                        .shadow(color: isMonitoring ? .blue : .orange, radius: 4)
                }
            }
        }
    }
    
    // MARK: - General Settings
    private func generalSettingsSection(config: Binding<AppConfig>) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("General Settings")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                ToggleSettingRow(
                    "Remove Duplicates",
                    description: "Automatically remove duplicate files",
                    isOn: config.settings.removeDuplicate
                )
                
                Divider()
                
                ToggleSettingRow(
                    "AI Renaming",
                    description: "Enable intelligent file renaming using AI",
                    isOn: config.settings.renameByAi
                )
            }
        }
    }
    
    // MARK: - AI Models
    private func aiModelsSection(config: Binding<AppConfig>) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Models")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                // Rename AI Model
                VStack(alignment: .leading) {
                    PickerSettingRow(
                        "Rename AI Model",
                        description: "Model used for file renaming",
                        selection: Binding(
                            get: { self.isCustomModel(config.wrappedValue.settings.renameAi) ? "Custom" : config.wrappedValue.settings.renameAi },
                            set: { newValue in
                                if newValue == "Custom" {
                                    // If switching to Custom, verify if current is already custom. If not, clear it to force "Custom" state.
                                    if !self.isCustomModel(config.wrappedValue.settings.renameAi) {
                                        config.wrappedValue.settings.renameAi = "" 
                                    }
                                } else {
                                    config.wrappedValue.settings.renameAi = newValue
                                }
                            }
                        ),
                        options: aiModels + ["Custom"]
                    )
                    
                    if self.isCustomModel(config.wrappedValue.settings.renameAi) {
                        TextField("Enter custom model name (e.g. gemma2:9b)", text: config.settings.renameAi)
                            .textFieldStyle(.roundedBorder)
                            .padding(.leading, 20)
                    }
                }
                
                Divider()
                
                // OCR AI Model
                VStack(alignment: .leading) {
                    PickerSettingRow(
                        "OCR AI Model",
                        description: "Model used for optical character recognition",
                        selection: Binding(
                            get: { self.isCustomModel(config.wrappedValue.settings.ocrAi) ? "Custom" : config.wrappedValue.settings.ocrAi },
                            set: { newValue in
                                if newValue == "Custom" {
                                    if !self.isCustomModel(config.wrappedValue.settings.ocrAi) {
                                        config.wrappedValue.settings.ocrAi = ""
                                    }
                                } else {
                                    config.wrappedValue.settings.ocrAi = newValue
                                }
                            }
                        ),
                        options: aiModels + ["Custom"]
                    )
                    
                    if self.isCustomModel(config.wrappedValue.settings.ocrAi) {
                        TextField("Enter custom model name", text: config.settings.ocrAi)
                            .textFieldStyle(.roundedBorder)
                            .padding(.leading, 20)
                    }
                }
            }
        }
    }
    
    private func isCustomModel(_ model: String) -> Bool {
        return !aiModels.contains(model)
    }
    
    // MARK: - Watchlist
    private func watchlistSection(config: Binding<AppConfig>) -> some View {
        GlassCard {
            WatchlistEditor(folders: config.watchlist)
        }
    }
    
    // MARK: - URL Mappings
    private func urlMappingsSection(config: Binding<AppConfig>) -> some View {
        GlassCard {
            URLMappingEditor(mappings: config.schema.move.url)
        }
    }
    
    // MARK: - Tag Mappings
    private func tagMappingsSection(config: Binding<AppConfig>) -> some View {
        GlassCard {
            TagMappingEditor(mappings: config.schema.move.tag)
        }
    }
    
    // MARK: - Rename Folders
    private func renameFoldersSection(config: Binding<AppConfig>) -> some View {
        GlassCard {
            RenameFoldersEditor(folders: config.schema.rename)
        }
    }
    
    // MARK: - Save Button
    private var saveButtonSection: some View {
        HStack(spacing: 12) {
            Button(action: loadConfig) {
                Label("Reload", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading || isSaving)
            
            Button(action: saveConfig) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Save Settings", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || isSaving || config == nil)
        }
        .padding(.top, 10)
    }
    
    // MARK: - Message View
    private func messageView(_ message: String, isError: Bool) -> some View {
        HStack {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .red : .green)
            Text(message)
                .font(.caption)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
        )
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: errorMessage)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: successMessage)
    }
    
    // MARK: - Actions
    private func loadConfig() {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                let loadedConfig = try await apiClient.getConfig()
                let status = try await apiClient.getStatus()
                
                await MainActor.run {
                    self.config = loadedConfig
                    self.isMonitoring = status.monitoring
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load config: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func saveConfig() {
        guard let config = config else { return }
        
        isSaving = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                try await apiClient.updateConfig(config)
                
                await MainActor.run {
                    self.successMessage = "Settings saved successfully!"
                    self.isSaving = false
                    
                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.successMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to save config: \(error.localizedDescription)"
                    self.isSaving = false
                }
            }
        }
    }
}

// MARK: - Tag Mapping Editor
struct TagMappingEditor: View {
    @Binding var mappings: [String: String]
    @State private var newTag = ""
    @State private var newDestination = ""
    @State private var showingAddDialog = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tag Mappings")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddDialog = true }) {
                    Label("Add Mapping", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
            }
            
            if mappings.isEmpty {
                Text("No tag mappings configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(mappings.keys.sorted()), id: \.self) { tag in
                            if let destination = mappings[tag] {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: "tag.fill")
                                                .foregroundStyle(.purple)
                                            Text(tag)
                                                .font(.body)
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
                                    Button(action: { mappings.removeValue(forKey: tag) }) {
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
                }
                .frame(maxHeight: 150)
            }
        }
        .sheet(isPresented: $showingAddDialog) {
            AddTagMappingDialog(
                tag: $newTag,
                destination: $newDestination,
                onSave: {
                    if !newTag.isEmpty && !newDestination.isEmpty {
                        mappings[newTag] = newDestination
                        newTag = ""
                        newDestination = ""
                        showingAddDialog = false
                    }
                },
                onCancel: {
                    newTag = ""
                    newDestination = ""
                    showingAddDialog = false
                }
            )
        }
    }
}

struct AddTagMappingDialog: View {
    @Binding var tag: String
    @Binding var destination: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Tag Mapping")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Tag Name")
                    .font(.caption)
                TextField("e.g., school, work, personal", text: $tag)
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
                    .disabled(tag.isEmpty || destination.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Rename Folders Editor
struct RenameFoldersEditor: View {
    @Binding var folders: [String]
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Rename Folders")
                    .font(.headline)
                Spacer()
                Button(action: addFolder) {
                    Label("Add Folder", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
            }
            
            Text("Files in these folders will be automatically renamed using AI")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if folders.isEmpty {
                Text("No folders configured for AI renaming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(folders, id: \.self) { folder in
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
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
                .frame(maxHeight: 150)
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
        panel.message = "Select a folder for AI renaming"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let path = url.path
                if folders.contains(path) {
                    alertMessage = "This folder is already configured"
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
    SettingsWindow(
        backendManager: BackendManager(),
        webSocketService: WebSocketService()
    )
}
