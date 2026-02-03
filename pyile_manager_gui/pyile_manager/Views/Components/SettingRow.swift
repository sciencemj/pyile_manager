//
//  SettingRow.swift
//  pyile_manager
//
//  Reusable setting row with label and control
//

import SwiftUI

// Toggle setting row
struct ToggleSettingRow: View {
    let label: String
    let description: String?
    @Binding var isOn: Bool
    
    init(_ label: String, description: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.description = description
        self._isOn = isOn
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.body)
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

// Picker setting row
struct PickerSettingRow: View {
    let label: String
    let description: String?
    @Binding var selection: String
    let options: [String]
    
    init(_ label: String, description: String? = nil, selection: Binding<String>, options: [String]) {
        self.label = label
        self.description = description
        self._selection = selection
        self.options = options
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.body)
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

// TextField setting row
struct TextFieldSettingRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.body)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        GlassCard {
            VStack(spacing: 12) {
                ToggleSettingRow("Remove Duplicates", description: "Automatically remove duplicate files", isOn: .constant(true))
                Divider()
                PickerSettingRow("AI Model", description: "Select the AI model for renaming", selection: .constant("gemma3:4b"), options: ["gemma3:4b", "llama2", "mistral"])
                Divider()
                TextFieldSettingRow(label: "Custom Path", placeholder: "/Users/username/Downloads", text: .constant(""))
            }
        }
    }
    .padding()
    .frame(width: 400)
}
