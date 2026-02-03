# Swift Integration Guide for Pyile Manager

## Overview

This guide explains how to integrate the Pyile Manager Python backend into your Swift/SwiftUI macOS application.

## Build Artifacts

After building with PyInstaller, you'll find the following in the `dist/` directory:

- **`pyile_manager`** - Standalone executable (38 MB) - **Use this for Swift integration**
- **`PyileManager.app`** - macOS application bundle

## Integration Options

### Option 1: Embed Executable in Swift App Bundle (Recommended)

1. **Copy the executable to your Swift project:**
   ```bash
   cp dist/pyile_manager YourSwiftApp/Resources/
   ```

2. **Add to Xcode:**
   - Drag `pyile_manager` into your Xcode project
   - In "Target Membership", ensure it's included
   - In "Build Phases" → "Copy Bundle Resources", add `pyile_manager`

3. **Start the backend from Swift:**
   ```swift
   import Foundation
   
   class PyileManagerBackend {
       private var process: Process?
       
       func start() {
           guard let executablePath = Bundle.main.path(forResource: "pyile_manager", ofType: nil) else {
               print("Error: pyile_manager executable not found")
               return
           }
           
           // Make executable if needed
           let chmod = Process()
           chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
           chmod.arguments = ["+x", executablePath]
           try? chmod.run()
           chmod.waitUntilExit()
           
           // Start the backend
           process = Process()
           process?.executableURL = URL(fileURLWithPath: executablePath)
           process?.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
           
           try? process?.run()
           
           // Wait a moment for server to start
           sleep(2)
           
           print("Pyile Manager backend started on port 8000")
       }
       
       func stop() {
           process?.terminate()
           process = nil
       }
   }
   ```

4. **Communicate with the API:**
   ```swift
   import Foundation
   
   struct PyileManagerAPI {
       let baseURL = "http://localhost:8000"
       
       func getStatus() async throws -> StatusResponse {
           let url = URL(string: "\(baseURL)/api/status")!
           let (data, _) = try await URLSession.shared.data(from: url)
           return try JSONDecoder().decode(StatusResponse.self, from: data)
       }
       
       func startMonitoring() async throws {
           let url = URL(string: "\(baseURL)/api/start-monitor")!
           var request = URLRequest(url: url)
           request.httpMethod = "POST"
           let (_, _) = try await URLSession.shared.data(for: request)
       }
       
       func stopMonitoring() async throws {
           let url = URL(string: "\(baseURL)/api/stop-monitor")!
           var request = URLRequest(url: url)
           request.httpMethod = "POST"
           let (_, _) = try await URLSession.shared.data(for: request)
       }
       
       func renameFile(path: String) async throws -> RenameResponse {
           let url = URL(string: "\(baseURL)/api/rename")!
           var request = URLRequest(url: url)
           request.httpMethod = "POST"
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           
           let body = ["file_path": path]
           request.httpBody = try JSONEncoder().encode(body)
           
           let (data, _) = try await URLSession.shared.data(for: request)
           return try JSONDecoder().decode(RenameResponse.self, from: data)
       }
   }
   
   // Response models
   struct StatusResponse: Codable {
       let status: String
       let monitoring: Bool
       let watchlist: [String]
   }
   
   struct RenameResponse: Codable {
       let success: Bool
       let old_name: String
       let new_name: String?
       let error: String?
   }
   ```

### Option 2: Run as Separate Process

Simply run the executable separately:
```bash
./dist/pyile_manager
```

The API will be available at `http://localhost:8000`

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Root endpoint with version info |
| `/api/status` | GET | Get current monitoring status |
| `/api/start-monitor` | POST | Start file monitoring |
| `/api/stop-monitor` | POST | Stop file monitoring |
| `/api/config` | GET | Get current configuration |
| `/api/config` | PUT | Update configuration |
| `/api/rename` | POST | Manually trigger AI renaming |
| `/ws` | WebSocket | Real-time notifications for file events |

## WebSocket Notifications

The backend now supports real-time notifications via WebSocket for file move and rename events.

### WebSocket Endpoint

**URL**: `ws://localhost:8000/ws`

### Connection

Connect to the WebSocket endpoint to receive real-time notifications when files are moved or renamed:

```swift
import Foundation

class FileNotificationService: ObservableObject {
    private var webSocket: URLSessionWebSocketTask?
    @Published var lastNotification: FileEvent?
    
    func connect() {
        let url = URL(string: "ws://localhost:8000/ws")!
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Send periodic ping to keep connection alive
        sendPing()
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf-8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessage()
                
            case .failure(let error):
                print("WebSocket error: \(error)")
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(FileEvent.self, from: data) else {
            return
        }
        
        DispatchQueue.main.async {
            self.lastNotification = event
        }
    }
    
    private func sendPing() {
        webSocket?.send(.string("ping")) { error in
            if let error = error {
                print("Ping error: \(error)")
            }
        }
        
        // Send ping every 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.sendPing()
        }
    }
}

// Event models
struct FileEvent: Codable {
    let type: String  // "file_moved" or "file_renamed"
    let timestamp: Double
    
    // For file_moved events
    let filename: String?
    let from: String?
    let to: String?
    let destination: String?
    
    // For file_renamed events
    let old_name: String?
    let new_name: String?
    let path: String?
    let full_path: String?
}
```

### Event Types

#### 1. File Moved Event

Sent when a file is automatically moved to a destination folder based on URL patterns.

```json
{
    "type": "file_moved",
    "filename": "document.pdf",
    "from": "/Users/username/Downloads/document.pdf",
    "to": "/Users/username/Downloads/GitHub/document.pdf",
    "destination": "/Users/username/Downloads/GitHub",
    "timestamp": 1738573200.123
}
```

#### 2. File Renamed Event

Sent when a file is automatically renamed using AI.

```json
{
    "type": "file_renamed",
    "old_name": "IMG_1234.jpg",
    "new_name": "golden_gate_bridge_sunset.jpg",
    "path": "/Users/username/Downloads/Photos",
    "full_path": "/Users/username/Downloads/Photos/golden_gate_bridge_sunset.jpg",
    "timestamp": 1738573200.456
}
```

### SwiftUI Integration Example

```swift
import SwiftUI

struct NotificationView: View {
    @StateObject private var notificationService = FileNotificationService()
    
    var body: some View {
        VStack {
            Text("File Activity Monitor")
                .font(.headline)
            
            if let event = notificationService.lastNotification {
                VStack(alignment: .leading, spacing: 5) {
                    if event.type == "file_moved" {
                        Label("File Moved", systemImage: "arrow.right.square")
                            .foregroundColor(.blue)
                        Text(event.filename ?? "Unknown")
                            .font(.caption)
                        Text("→ \(event.destination ?? "Unknown")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if event.type == "file_renamed" {
                        Label("File Renamed", systemImage: "pencil.circle")
                            .foregroundColor(.green)
                        Text("\(event.old_name ?? "Unknown")")
                            .font(.caption)
                            .strikethrough()
                        Text("→ \(event.new_name ?? "Unknown")")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Text(formatTimestamp(event.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                Text("No activity")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            notificationService.connect()
        }
        .onDisappear {
            notificationService.disconnect()
        }
    }
    
    func formatTimestamp(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

```
## Configuration

The executable looks for `pyile_manager_setting.json` in the current working directory. 

**Example configuration:**
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
            },
            "tag": {
                "school": "/Users/yourusername/Downloads/School"
            }
        },
        "rename": [
            "/Users/yourusername/Downloads/GitHub"
        ]
    }
}
```

## Required External Dependencies

The Python backend requires **Ollama** to be running with the following models:

```bash
# Install Ollama from https://ollama.ai
# Then pull the required models:
ollama pull gemma3:4b
ollama pull deepocr
```

## Testing the Integration

1. **Test API availability:**
   ```swift
   Task {
       do {
           let api = PyileManagerAPI()
           let status = try await api.getStatus()
           print("Backend status: \(status.status)")
       } catch {
           print("Error: \(error)")
       }
   }
   ```

2. **Test file monitoring:**
   ```swift
   Task {
       let api = PyileManagerAPI()
       try await api.startMonitoring()
       print("Monitoring started")
   }
   ```

## Troubleshooting

### Backend won't start
- Check that the executable has execute permissions: `chmod +x pyile_manager`
- Verify Ollama is running: `ollama list`
- Check port 8000 is not in use: `lsof -i :8000`

### API requests failing
- Ensure backend is fully started (wait 2-3 seconds after launch)
- Check API is accessible: `curl http://localhost:8000/api/status`
- Verify network permissions in your Swift app's entitlements

### AI renaming not working
- Confirm Ollama models are installed: `ollama list`
- Check Ollama is running: `ollama serve` (should already be running)
- Look at backend logs for error messages

## SwiftUI Example

Here's a complete SwiftUI view example:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var backend = PyileManagerBackend()
    @State private var isMonitoring = false
    @State private var status: String = "Stopped"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Pyile Manager")
                .font(.largeTitle)
            
            HStack {
                Text("Status:")
                Text(status)
                    .foregroundColor(isMonitoring ? .green : .red)
            }
            
            HStack(spacing: 10) {
                Button("Start Backend") {
                    backend.start()
                    checkStatus()
                }
                
                Button("Stop Backend") {
                    backend.stop()
                    status = "Stopped"
                    isMonitoring = false
                }
            }
            
            if isMonitoring {
                Button("Stop Monitoring") {
                    Task {
                        try? await PyileManagerAPI().stopMonitoring()
                        checkStatus()
                    }
                }
            } else {
                Button("Start Monitoring") {
                    Task {
                        try? await PyileManagerAPI().startMonitoring()
                        checkStatus()
                    }
                }
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
    
    func checkStatus() {
        Task {
            do {
                let response = try await PyileManagerAPI().getStatus()
                status = response.status
                isMonitoring = response.monitoring
            } catch {
                status = "Error: \(error.localizedDescription)"
            }
        }
    }
}

class PyileManagerBackend: ObservableObject {
    private var process: Process?
    
    func start() {
        guard let executablePath = Bundle.main.path(forResource: "pyile_manager", ofType: nil) else {
            print("Error: executable not found")
            return
        }
        
        process = Process()
        process?.executableURL = URL(fileURLWithPath: executablePath)
        try? process?.run()
        
        // Wait for server to start
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("Backend started")
        }
    }
    
    func stop() {
        process?.terminate()
        process = nil
    }
}
```

## Next Steps

1. Copy the `dist/pyile_manager` executable to your Swift project
2. Implement the backend starter and API client
3. Create your SwiftUI interface
4. Test with real files

## Notes

- The executable is 38 MB and includes all Python dependencies
- No Python installation required on the target system
- Ollama must be installed separately
- The backend runs on port 8000 by default
- File monitoring is automatic when started
