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
