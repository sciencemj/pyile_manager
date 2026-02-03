<div align="center">

# 🗂️ Pyile Manager

**AI-Powered Intelligent File Manager for macOS**

[![Python](https://img.shields.io/badge/Python-3.13+-3776AB?logo=python&logoColor=white)](https://python.org)
[![Swift](https://img.shields.io/badge/Swift-6.0+-FA7343?logo=swift&logoColor=white)](https://swift.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Ollama](https://img.shields.io/badge/Ollama-Local_AI-white?logo=ollama&logoColor=black)](https://ollama.com)
[![macOS](https://img.shields.io/badge/macOS-26.0+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## ✨ Overview

**Pyile Manager** is an intelligent file management system that combines the power of local AI models with macOS automation. It automatically organizes your downloads based on their source URL and uses AI to generate meaningful, descriptive filenames based on actual file content.

<div align="center">

```
┌─────────────────────────────────────┐
│      💻 SwiftUI Frontend            │
│   (Menu Bar + Settings Window)      │
└──────────────┬──────────────────────┘
               │ HTTP/WebSocket
┌──────────────▼──────────────────────┐
│       🐍 FastAPI Backend            │
├─────────────────────────────────────┤
│  • File Monitoring & Auto-Sort      │
│  • AI-Powered Renaming              │
│  • URL Pattern Matching             │
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
- **Duplicate handling**: Optionally remove duplicate downloads
- **Tag-based organization**: Move files based on custom tags

### 🖥️ Native macOS Experience
- **Menu bar app**: Runs quietly in the background
- **Liquid glass design**: Modern, beautiful UI with blur effects
- **Real-time notifications**: WebSocket-powered live updates
- **Settings GUI**: Easy configuration without editing JSON files

### 🔧 Developer Friendly
- **RESTful API**: Full control via HTTP endpoints
- **WebSocket events**: Real-time file activity notifications
- **Single executable**: PyInstaller-bundled for easy distribution
- **Modular architecture**: Clean separation of concerns

---

## 📋 Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| **macOS** | 26.0+ | Tahoe or later |
| **Python** | 3.13+ | For backend development |
| **Ollama** | - | Local AI inference engine for rename |

### Required Ollama Models

```bash
# Install from https://ollama.ai
ollama pull gemma3:4b     # General purpose naming
ollama pull deepseek-ocr  # OCR for images/PDFs
```

---

## 🛠️ Installation for Develop

### Backend Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/pyile_manager.git
cd pyile_manager/pyile_manager_backend

# Install dependencies with uv (recommended)
uv sync

# Or with pip
pip install -r requirements.txt

# Copy and configure settings
cp pyile_manager_setting.json pyile_manager_setting.example.json
# Edit pyile_manager_setting.json with your paths
```

### GUI Setup (Optional)

```bash
cd pyile_manager_gui

# Open in Xcode
open pyile_manager.xcodeproj

# Build and run (⌘R)
```

> 📖 See [pyile_manager_gui/README_GUI.md](pyile_manager_gui/README_GUI.md) for detailed GUI setup instructions.

---

## 🚀 Quick Start
1. Open `pyile_manager_gui/pyile_manager.xcodeproj` in Xcode
2. Press `⌘R` to build and run
3. The app appears in your menu bar (top-right)

---

## 🔄 How It Works

1. **📥 File Downloaded**
   - Watchdog detects new file in monitored directory

2. **🔍 Source Detection**
   - Extracts download URL from macOS metadata (`kMDItemWhereFroms`)

3. **📂 Auto-Sort**
   - Matches URL against configured patterns
   - Moves file to appropriate destination folder

4. **🤖 AI Renaming** (if destination is in `schema.rename`)
   - Extracts text content (OCR for images, text extraction for documents)
   - Sends to Ollama model for intelligent filename generation
   - Renames file on disk

5. **📢 Notification**
   - Broadcasts event via WebSocket to GUI
   - Updates menu bar with recent activity

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

### Backend Executable

```bash
cd pyile_manager_backend
uv run pyinstaller pyile_manager.spec --clean

# Output: dist/pyile_manager (~38 MB)
```

### macOS App

1. Open `pyile_manager_gui/pyile_manager.xcodeproj`
2. Select **Product → Archive**
3. Export as macOS App

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- [Ollama](https://ollama.ai) - Local AI inference
- [FastAPI](https://fastapi.tiangolo.com) - Modern Python web framework
- [Watchdog](https://github.com/gorakhargosh/watchdog) - File system monitoring
- [PyInstaller](https://pyinstaller.org) - Python executable bundling

---