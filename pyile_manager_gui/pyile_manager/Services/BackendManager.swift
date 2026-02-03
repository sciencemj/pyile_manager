//
//  BackendManager.swift
//  pyile_manager
//
//  Manages the pyile_manager backend process lifecycle
//

import Foundation
import Combine

class BackendManager: ObservableObject {
    @Published var isRunning = false
    @Published var errorMessage: String?
    
    var process: Process?  // Changed from private to allow AppDelegate to check
    private let executableName = "pyile_manager"
    
    // Start the backend process
    func start() {
        guard !isRunning else {
            print("Backend already running")
            return
        }
        
        guard let executablePath = Bundle.main.path(forResource: executableName, ofType: nil) else {
            errorMessage = "Backend executable not found in app bundle"
            print("Error: \(errorMessage ?? "")")
            return
        }
        
        // Make executable if needed
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", executablePath]
        try? chmod.run()
        chmod.waitUntilExit()
        
        // Start the backend process
        process = Process()
        process?.executableURL = URL(fileURLWithPath: executablePath)
        process?.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        
        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe
        
        // Read output asynchronously
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                print("[Backend OUT]: \(output.trimmingCharacters(in: .newlines))")
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                print("[Backend ERR]: \(output.trimmingCharacters(in: .newlines))")
            }
        }
        
        // Monitor process termination
        process?.terminationHandler = { process in
            print("Backend process terminated with status: \(process.terminationStatus)")
            DispatchQueue.main.async {
                self.isRunning = false
                if process.terminationStatus != 0 {
                    self.errorMessage = "Backend exited with code \(process.terminationStatus)"
                }
            }
        }
        
        do {
            try process?.run()
            isRunning = true
            errorMessage = nil
            print("Backend started successfully at PID: \(process?.processIdentifier ?? 0)")
            print("Backend executable: \(executablePath)")
            print("Backend working directory: \(NSHomeDirectory())")
            
            // Wait a moment for server to start
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print("Backend should be ready on port 8000")
            }
        } catch {
            errorMessage = "Failed to start backend: \(error.localizedDescription)"
            print("Error: \(errorMessage ?? "")")
            isRunning = false
        }
    }
    
    // Stop the backend process
    func stop() {
        guard let process = process, isRunning else {
            print("Backend not running")
            return
        }
        
        process.terminate()
        
        // Wait for termination
        DispatchQueue.global().async {
            process.waitUntilExit()
            DispatchQueue.main.async {
                self.isRunning = false
                self.process = nil
                print("Backend stopped")
            }
        }
    }
    
    // Stop the backend process synchronously (for app termination)
    func stopSynchronously() {
        // Check if there's actually a process, regardless of flag
        guard let process = process else {
            print("No backend process to stop")
            return
        }
        
        let pid = process.processIdentifier
        print("Terminating backend process (PID: \(pid), isRunning flag: \(isRunning))...")
        
        // For PyInstaller apps, we need to kill the entire process group
        // First try graceful termination
        process.terminate() // Sends SIGTERM
        
        // Wait synchronously for termination (max 3 seconds)
        var waited = 0.0
        while process.isRunning && waited < 3.0 {
            Thread.sleep(forTimeInterval: 0.1)
            waited += 0.1
        }
        
        if process.isRunning {
            print("Backend didn't stop gracefully, sending SIGKILL to process group...")
            
            // Kill the entire process group (this gets PyInstaller children too)
            // Negative PID means process group
            kill(-pid, SIGKILL)
            
            // Also directly kill the main process
            kill(pid, SIGKILL)
            
            // Wait a bit more
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        isRunning = false
        self.process = nil
        print("Backend stopped (PID \(pid) terminated)")
    }
    
    // Check if backend is responsive
    func checkHealth() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8000/api/status") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            print("Health check failed: \(error.localizedDescription)")
        }
        
        return false
    }
}
