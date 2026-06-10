<div align="center">

# 🗂️ Pyile Manager

**AI-Powered Intelligent File Manager for macOS**

[![Swift](https://img.shields.io/badge/Swift-6.0+-FA7343?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-0A84FF?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Ollama](https://img.shields.io/badge/Ollama-Local_AI-white?logo=ollama&logoColor=black)](https://ollama.com)
[![macOS](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## ✨ Overview

**Pyile Manager** is an intelligent file management app that combines the power of local AI models with macOS automation. It automatically organizes your downloads based on their source URL and uses AI to generate meaningful, descriptive filenames based on actual file content.

The app is **fully native Swift** — a single menu bar app with no separate backend process, no HTTP server, and no Python dependency.

<div align="center">

```
┌─────────────────────────────────────┐
│       💻 Native SwiftUI App         │
│   (Menu Bar + Settings + History)   │
├─────────────────────────────────────┤
│  • FSEvents File Monitoring         │
│  • Auto-Sort by Source URL          │
│  • AI-Powered Renaming              │
│  • Persistent History & Undo        │
└──────────────┬──────────────────────┘
               │
    ┌──────────┴──────────┐
    ▼                     ▼
┌─────────┐         ┌───────────┐
│ 🤖 Ollama│         │ 📁 File   │
│  Models  │         │  System   │
└─────────┘         └───────────┘
```

</div>

---

## 🚀 Features

### 🤖 AI-Powered File Renaming
- Uses local **Ollama** models for privacy-first AI processing
- **Gemma3** for intelligent filename generation
- **DeepOCR** for text extraction from images and scanned documents
- Generates descriptive, meaningful filenames based on actual content

### 📁 Smart File Organization
- **Auto-sort by source URL**: Files are automatically moved based on download source
- **Flexible pattern matching**: Supports variables like `example.com/course/{$var}`
- **Safe duplicate handling**: Duplicates are detected by *content* (SHA-256), not just filename — true duplicates go to the macOS Trash (never permanently deleted), and same-named files with different content are kept side by side

### ⏪ History & Undo
- **Persistent history**: Every move, rename, and trashed duplicate is logged to `~/.config/pyile_manager/history.jsonl` and survives restarts
- **One-click Undo**: Reverse any action from the menu bar or the History window — moves go back, renames revert, trashed duplicates are restored
- **Safety first**: Undo never overwrites existing files and never recreates deleted folders

### 🖥️ Native macOS Experience
- **Menu bar app**: Runs quietly in the background
- **Liquid glass design**: Modern, beautiful UI with blur effects
- **Native notifications**: Instant alerts for every organized file
- **Settings GUI**: Easy configuration without editing JSON files

### 🔧 Fully Self-Contained
- **Single .app bundle**: No backend executable, no localhost server
- **Native Swift services**: FSEvents monitoring, Spotlight metadata, PDFKit text extraction
- **Direct Ollama integration**: Talks to the Ollama REST API natively

---

## 📋 Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| **macOS** | 26.0+ | Tahoe or later |
| **Xcode** | 26.0+ | For building from source |
| **Ollama** | - | Local AI inference engine for rename |

### Required Ollama Models

```bash
# Install from https://ollama.ai
ollama pull gemma3:4b     # General purpose naming
ollama pull deepseek-ocr  # OCR for images/PDFs
```

---

## 🛠️ Installation for Develop

```bash
# Clone the repository
git clone https://github.com/sciencemj/pyile_manager.git
cd pyile_manager/pyile_manager_gui

# Open in Xcode
open pyile_manager.xcodeproj

# Build and run (⌘R)
```

Configuration lives at `~/.config/pyile_manager/pyile_manager_setting.json` and is fully editable from the in-app Settings window.

### Running the Tests

```bash
xcodebuild test -project pyile_manager_gui/pyile_manager.xcodeproj \
  -scheme pyile_manager -destination 'platform=macOS'
```

---

## 🚀 Quick Start
1. Open `pyile_manager_gui/pyile_manager.xcodeproj` in Xcode
2. Press `⌘R` to build and run
3. The app appears in your menu bar (top-right)
4. Open Settings to add watched folders and URL → destination mappings

---

## 🔄 How It Works

1. **📥 File Downloaded**
   - FSEvents detects a new file in a monitored directory

2. **🔍 Source Detection**
   - Extracts download URL from macOS Spotlight metadata (`kMDItemWhereFroms`)

3. **📂 Auto-Sort**
   - Matches URL against configured patterns
   - Moves file to the appropriate destination folder
   - Content-identical duplicates are moved to the Trash instead of being kept or deleted

4. **🤖 AI Renaming** (if destination is in `schema.rename`)
   - Extracts text content (OCR for images, text extraction for documents)
   - Sends to Ollama model for intelligent filename generation
   - Renames file on disk

5. **📢 Notification & History**
   - Posts a native macOS notification
   - Records the event in the persistent history log
   - Shows recent activity in the menu bar — with one-click Undo

---

## 📄 Supported File Types

| Type | Extensions | AI Feature |
|------|------------|------------|
| Images | `.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.webp` | OCR + Rename |
| Documents | `.pdf` | Text extraction + Rename |
| Presentations | `.ppt`, `.pptx` | Text extraction + Rename |
| Text | `.txt`, `.md` | Direct text + Rename |

### Filename Generation Examples

| Before | After |
|--------|-------|
| `IMG_1234.jpg` | `golden_gate_bridge_sunset.jpg` |
| `document.pdf` | `quarterly_sales_report_q4_2024.pdf` |
| `Screenshot 2024-01-30.png` | `python_error_traceback_imports.png` |
| `presentation.pptx` | `product_launch_deck_mobile_app.pptx` |

---

## 📦 Building for Distribution

1. Open `pyile_manager_gui/pyile_manager.xcodeproj`
2. Select **Product → Archive**
3. Export as macOS App

That's it — the app is a single self-contained bundle.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- [Ollama](https://ollama.ai) - Local AI inference
- [PDFKit](https://developer.apple.com/documentation/pdfkit) - PDF text extraction
- [FSEvents](https://developer.apple.com/documentation/coreservices/file_system_events) - File system monitoring

---
