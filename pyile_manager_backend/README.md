# Pyile Manager

AI-powered intelligent file manager for macOS with automatic file organization and AI-based renaming.

## Features

- 🤖 **AI-Powered Renaming**: Uses local Ollama models (Gemma3 & DeepOCR) to intelligently rename files based on content
- 📁 **Auto-Sort by Source URL**: Automatically organize downloaded files based on their source URL with flexible pattern matching
- 🔍 **OCR Support**: Extract text from images and scanned PDFs for accurate renaming
- 📄 **Multi-Format Support**: Images, PDFs, PowerPoint presentations, and text files
- 🚀 **FastAPI Backend**: RESTful API for easy integration with SwiftUI frontend
- 📦 **Single Executable**: Built with PyInstaller for seamless Swift app integration

## Quick Start

### Prerequisites

1. **Ollama** with required models:
   ```bash
   # Install Ollama from https://ollama.ai
   # Pull required models
   ollama pull gemma3:4b
   ollama pull deepocr
   ```

2. **Python 3.13+** (for development)

### Installation

```bash
# Clone the repository
cd pyile_manager

# Install dependencies with uv
uv sync

# Configure settings
cp pyile_manager_setting.json.example pyile_manager_setting.json
# Edit pyile_manager_setting.json with your preferences
```

### Running

#### Development Mode
```bash
uv run python main.py
```

#### Production (Standalone Executable)
```bash
# Build the executable
uv run pyinstaller pyile_manager.spec --clean

# Run the executable
./dist/pyile_manager
```

The API server will start on `http://localhost:8000`

## Configuration

Edit `pyile_manager_setting.json`:

```json
{
    "settings": {
        "remove_duplicate": true,
        "ai_rename": true
    },
    "watchlist": [
        "/Users/yourusername/Downloads/"
    ],
    "schema": {
        "move": {
            "url": {
                "github.com": "/Users/yourusername/Downloads/GitHub",
                "example.com/course/{$var}": "/Users/yourusername/Downloads/Courses"
            }
        },
        "rename": [
            "/Users/yourusername/Downloads/GitHub"
        ]
    }
}
```

### URL Pattern Matching

Supports flexible patterns with variables:
- `github.com` - Simple substring match
- `example.com/course/{$var}` - Match any value in place of `{$var}`
- `domain.com/{$*}` - Match any path

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | Get monitoring status |
| `/api/start-monitor` | POST | Start file monitoring |
| `/api/stop-monitor` | POST | Stop file monitoring |
| `/api/config` | GET | Get configuration |
| `/api/config` | PUT | Update configuration |
| `/api/rename` | POST | Manually rename a file |

## Swift Integration

See [SWIFT_INTEGRATION.md](SWIFT_INTEGRATION.md) for detailed guide on integrating the Python backend into your SwiftUI macOS application.

**Key files for Swift integration:**
- `dist/pyile_manager` - Standalone executable (38 MB)
- `SWIFT_INTEGRATION.md` - Complete integration guide with code examples

## Project Structure

```
pyile_manager/
├── main.py              # FastAPI server & file monitoring
├── ollama_api.py        # AI renaming with Ollama
├── file_extractor.py    # Content extraction utilities
├── setting.py           # Pydantic configuration models
├── pyile_manager.spec   # PyInstaller build configuration
├── test_ai_rename.py    # Test script for AI renaming
└── SWIFT_INTEGRATION.md # Swift integration guide
```

## How It Works

1. **File Monitoring**: Watches specified directories for new files
2. **Source Detection**: Extracts download source URL from macOS metadata
3. **Auto-Sort**: Matches URL against configured patterns and moves file
4. **AI Renaming**: Uses Ollama models to analyze file content and generate descriptive names
   - Images: DeepOCR extracts text → Gemma3 generates filename
   - PDFs: Text extraction (or OCR if scanned) → Gemma3 generates filename
   - PowerPoint/Text: Direct text extraction → Gemma3 generates filename

## Testing

Test AI renaming with example files:
```bash
uv run python test_ai_rename.py
```

## Building for Distribution

```bash
# Build standalone executable
uv run pyinstaller pyile_manager.spec --clean

# Output: dist/pyile_manager (38 MB single file)
```

## License

MIT License

## Contributing

Contributions welcome! Please open an issue or submit a pull request.
