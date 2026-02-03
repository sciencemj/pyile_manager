"""
Pyile Manager - AI-powered intelligent file manager.
Main entry point with FastAPI server and file monitoring.
"""

import time
import json
import os
import re
import shutil
import subprocess
import threading
from pathlib import Path
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from ollama_api import rename_file_on_disk, rename_file_with_ai, load_models_from_settings
from setting import AppConfig
from watchdog.events import DirCreatedEvent, FileCreatedEvent, FileSystemEventHandler
from watchdog.observers import Observer

# ============================================================================
# Configuration Loading
# ============================================================================


def load_setting(path: str) -> AppConfig:
    """Load configuration from JSON file."""
    try:
        with open(path, "r", encoding="utf-8") as file:
            data: dict = json.load(file)
            return AppConfig(**data)
    except FileNotFoundError:
        return AppConfig()
    except Exception as e:
        print(f"Error while loading setting files: {e}")
        return AppConfig()


setting = load_setting("pyile_manager_setting.json")

# Load AI model names from settings
load_models_from_settings(setting)

# ============================================================================
# WebSocket Connection Manager
# ============================================================================


class ConnectionManager:
    """Manage WebSocket connections for real-time notifications."""

    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        """Accept and store a new WebSocket connection."""
        await websocket.accept()
        self.active_connections.append(websocket)
        print(f"WebSocket connected. Total connections: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        """Remove a WebSocket connection."""
        self.active_connections.remove(websocket)
        print(f"WebSocket disconnected. Total connections: {len(self.active_connections)}")

    async def broadcast(self, message: dict):
        """Broadcast a message to all connected clients."""
        disconnected = []
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception as e:
                print(f"Error sending to websocket: {e}")
                disconnected.append(connection)
        
        # Remove disconnected clients
        for conn in disconnected:
            if conn in self.active_connections:
                self.active_connections.remove(conn)


# Global WebSocket manager
ws_manager = ConnectionManager()


# ============================================================================
# URL Pattern Matching with Variable Support
# ============================================================================


def parse_url_pattern(pattern: str) -> re.Pattern:
    """
    Parse URL pattern with variable support like {$var}.
    Converts pattern to regex for flexible matching.

    Example: 'example.com/course/{$var}' -> matches 'example.com/course/python'
    """
    # Escape special regex characters except {$var}
    escaped = re.escape(pattern)
    # Replace escaped {$var} patterns with regex wildcard
    regex_pattern = escaped.replace(r"\{\$var\}", r"[^/]+")
    regex_pattern = escaped.replace(r"\{\$\*\}", r".*")
    return re.compile(regex_pattern)


def match_url_to_destination(url: str, url_schemas: dict[str, str]) -> str | None:
    """
    Match a URL against configured schemas and return destination path.
    Supports both exact matches and pattern matching with variables.
    """
    for pattern, destination in url_schemas.items():
        if "{$" in pattern:
            # Pattern matching
            regex = parse_url_pattern(pattern)
            if regex.search(url):
                return destination
        else:
            # Simple substring match
            if pattern in url:
                return destination
    return None


# ============================================================================
# Metadata Extraction
# ============================================================================


def get_metadata_mdls(path: str) -> str | None:
    """Extract download source URL from file metadata using macOS mdls command."""
    try:
        result = subprocess.run(["mdls", path], capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        print(f"Error while getting metadata by mdls: {e.stderr}")
    except FileNotFoundError:
        print("File not found")
    else:
        # wherefrom: 1st object = download file link, 2nd object = viewing page when download
        result_lines = result.stdout.strip().split("kMDItemWhereFroms")
        if len(result_lines) < 2:
            return None
        result_data = result_lines[1].strip()[1:-2].strip()[1:].strip()
        urls = result_data.split(",\n")
        if len(urls) >= 2:
            return urls[1].strip().strip('"')
    return None


def get_domain_name(url: str, loc: int = 1) -> str:
    """Extract domain name from URL."""
    parsed_url = urlparse(url=url)
    domain_subdomain = parsed_url.netloc
    parts = domain_subdomain.split(".")
    if loc < len(parts):
        return parts[loc]
    return domain_subdomain


# ============================================================================
# File System Event Handler
# ============================================================================


class NewFileHandler(FileSystemEventHandler):
    """Handle new file creation events for auto-sorting and renaming."""

    def __init__(self, config: AppConfig) -> None:
        super().__init__()
        self.config = config
        self.recently_renamed = set()  # Track recently renamed files to avoid double-rename

    def on_created(self, event: FileCreatedEvent | DirCreatedEvent) -> None:
        """Process newly created files."""
        if event.is_directory:
            return None

        src_path = str(event.src_path)
        filename = os.path.basename(src_path)

        # Skip temporary download files
        if filename.endswith((".crdownload", ".tmp", ".part")):
            return

        # Wait a moment for file to be fully written
        time.sleep(0.5)

        # Try to get source URL from metadata
        source_url = get_metadata_mdls(src_path)
        
        # Track the current file path (it may change after moving)
        current_path = src_path

        if source_url:
            new_path = self._sort_file_by_url(src_path, filename, source_url)
            if new_path:
                current_path = new_path  # Update path after moving
                time.sleep(0.5)  # Wait for file system to settle after move

        # Check if file is in a rename directory (use current path, not original)
        if self._should_rename_file(current_path):
            self._rename_file_with_ai(current_path)

    def _sort_file_by_url(self, src_path: str, filename: str, source_url: str) -> str | None:
        """
        Sort file into appropriate directory based on source URL.
        Returns the new file path if moved, None otherwise.
        """
        # Match URL to destination
        destination = match_url_to_destination(source_url, self.config.schema.move.url)

        if not destination:
            # Fallback: use domain name
            domain = get_domain_name(source_url, loc=1)
            # Check if there's a simple domain match
            for pattern, dest in self.config.schema.move.url.items():
                if domain.lower() in pattern.lower():
                    destination = dest
                    break

        if destination:
            # Create destination directory if needed
            Path(destination).mkdir(parents=True, exist_ok=True)

            dest_path = Path(destination) / filename

            # Handle duplicate files
            if dest_path.is_file():
                print(f"File already exists: {dest_path}")
                if self.config.settings.remove_duplicate:
                    os.remove(src_path)
                    print(f"Duplicate file removed: {filename}")
                return None

            # Move file
            shutil.move(src_path, str(dest_path))
            print(f"File moved: {filename} -> {destination}")
            
            # Broadcast notification
            self._broadcast_notification({
                "type": "file_moved",
                "filename": filename,
                "from": src_path,
                "to": str(dest_path),
                "destination": destination,
                "timestamp": time.time()
            })
            
            # Return the new path
            return str(dest_path)
        
        return None

    def _should_rename_file(self, file_path: str) -> bool:
        """Check if file should be renamed based on configuration."""
        
        # Skip if this file was just renamed (prevents double-rename)
        if file_path in self.recently_renamed:
            print(f"Skipping recently renamed file: {Path(file_path).name}")
            self.recently_renamed.discard(file_path)
            return False
        
        if not self.config.settings.rename_by_ai:
            print(f"AI rename disabled in settings for: {file_path}")
            return False

        file_dir = str(Path(file_path).parent)
        print(f"Checking rename for file: {file_path}")
        print(f"  File directory: {file_dir}")
        print(f"  Rename directories in config: {self.config.schema.rename}")
        
        for rename_dir in self.config.schema.rename:
            if file_dir.startswith(rename_dir):
                print(f"  ✓ Match found with: {rename_dir}")
                return True
        
        print(f"  ✗ No match found")
        return False

    def _rename_file_with_ai(self, file_path: str) -> None:
        """Rename file using AI."""
        print(f"AI renaming: {file_path}")
        new_name = rename_file_with_ai(file_path)

        if new_name:
            new_path = rename_file_on_disk(file_path, new_name)
            if new_path:
                # Add OLD path to recently_renamed to prevent double-rename
                # (the second event comes with the old filename, not the new one)
                self.recently_renamed.add(file_path)
                
                # Broadcast notification
                self._broadcast_notification({
                    "type": "file_renamed",
                    "old_name": Path(file_path).name,
                    "new_name": Path(new_path).name,
                    "path": str(Path(new_path).parent),
                    "full_path": new_path,
                    "timestamp": time.time()
                })
        else:
            print(f"Failed to rename file: {file_path}")
    
    def _broadcast_notification(self, message: dict):
        """Broadcast notification to all WebSocket clients."""
        import asyncio
        try:
            # Run async broadcast in the event loop
            loop = asyncio.new_event_loop()
            loop.run_until_complete(ws_manager.broadcast(message))
            loop.close()
        except Exception as e:
            print(f"Error broadcasting notification: {e}")


# ============================================================================
# File Monitor Management
# ============================================================================


class FileMonitor:
    """Manage file system monitoring."""

    def __init__(self, config: AppConfig):
        self.config = config
        self.observer: Observer | None = None
        self.is_running = False

    def start(self) -> None:
        """Start file monitoring."""
        if self.is_running:
            print("Monitor already running")
            return

        self.observer = Observer()
        event_handler = NewFileHandler(config=self.config)

        for path in self.config.watchlist:
            if Path(path).exists():
                self.observer.schedule(event_handler=event_handler, path=path, recursive=False)
                print(f"Monitoring: {path}")

        self.observer.start()
        self.is_running = True
        print("File monitor started")

    def stop(self) -> None:
        """Stop file monitoring."""
        if self.observer and self.is_running:
            self.observer.stop()
            self.observer.join()
            self.is_running = False
            print("File monitor stopped")

    def is_active(self) -> bool:
        """Check if monitor is active."""
        return self.is_running
    
    def update_config(self, new_config: AppConfig) -> None:
        """Update configuration and restart monitor if running."""
        self.config = new_config
        if self.is_running:
            print("Restarting monitor with new configuration...")
            self.stop()
            self.start()


# Global monitor instance
file_monitor = FileMonitor(config=setting)

# ============================================================================
# FastAPI Application
# ============================================================================

app = FastAPI(title="Pyile Manager API", version="1.0.0")


# Request/Response Models
class StatusResponse(BaseModel):
    status: str
    monitoring: bool
    watchlist: list[str]


class ConfigUpdateRequest(BaseModel):
    settings: dict | None = None
    watchlist: list[str] | None = None
    schema: dict | None = None


class RenameRequest(BaseModel):
    file_path: str


class RenameResponse(BaseModel):
    success: bool
    old_name: str
    new_name: str | None = None
    error: str | None = None


@app.get("/")
async def root():
    """Root endpoint."""
    return {"message": "Pyile Manager API", "version": "1.0.0"}


@app.get("/api/status", response_model=StatusResponse)
async def get_status():
    """Get current system status."""
    return StatusResponse(
        status="running" if file_monitor.is_active() else "stopped",
        monitoring=file_monitor.is_active(),
        watchlist=setting.watchlist,
    )


@app.post("/api/start-monitor")
async def start_monitor():
    """Start file monitoring."""
    try:
        file_monitor.start()
        return {"success": True, "message": "Monitor started"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.post("/api/stop-monitor")
async def stop_monitor():
    """Stop file monitoring."""
    try:
        file_monitor.stop()
        return {"success": True, "message": "Monitor stopped"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/api/config")
async def get_config():
    """Get current configuration."""
    return setting.model_dump()


@app.put("/api/config")
async def update_config(request: ConfigUpdateRequest):
    """Update configuration."""
    try:
        global setting
        config_dict = setting.model_dump()

        if request.settings:
            config_dict["settings"].update(request.settings)
        if request.watchlist:
            config_dict["watchlist"] = request.watchlist
        if request.schema:
            config_dict["schema"].update(request.schema)

        setting = AppConfig(**config_dict)
        
        # Load AI model names from updated settings
        load_models_from_settings(setting)
        
        # Update file monitor with new config
        file_monitor.update_config(setting)

        # Save to file
        with open("pyile_manager_setting.json", "w", encoding="utf-8") as f:
            json.dump(config_dict, f, indent=4)

        return {"success": True, "message": "Configuration updated and applied"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for real-time notifications.
    
    Clients will receive JSON messages for file events:
    - file_moved: When a file is moved to a destination folder
    - file_renamed: When a file is renamed by AI
    """
    await ws_manager.connect(websocket)
    try:
        while True:
            # Keep connection alive and wait for messages (ping/pong)
            data = await websocket.receive_text()
            # Echo back for ping/pong
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)
    except Exception as e:
        print(f"WebSocket error: {e}")
        ws_manager.disconnect(websocket)


@app.post("/api/rename", response_model=RenameResponse)
async def rename_file_endpoint(request: RenameRequest):
    """Manually trigger AI renaming for a specific file."""
    try:
        file_path = request.file_path

        if not Path(file_path).exists():
            raise HTTPException(status_code=404, detail="File not found")

        old_name = Path(file_path).name
        new_name = rename_file_with_ai(file_path)

        if new_name:
            new_path = rename_file_on_disk(file_path, new_name)
            return RenameResponse(
                success=True,
                old_name=old_name,
                new_name=Path(new_path).name if new_path else None,
            )
        else:
            return RenameResponse(success=False, old_name=old_name, error="AI renaming failed")

    except HTTPException:
        raise
    except Exception as e:
        return RenameResponse(success=False, old_name="", error=str(e))


# ============================================================================
# Main Entry Point
# ============================================================================


def run_monitor_in_background():
    """Run file monitor in background thread."""
    file_monitor.start()
    try:
        while file_monitor.is_active():
            import time

            time.sleep(1)
    except KeyboardInterrupt:
        file_monitor.stop()


def main():
    """Main entry point - runs both API server and file monitor."""
    import uvicorn

    # Start file monitor in background thread
    monitor_thread = threading.Thread(target=run_monitor_in_background, daemon=True)
    monitor_thread.start()

    # Start FastAPI server
    print("Starting Pyile Manager API server on http://localhost:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")


if __name__ == "__main__":
    main()
