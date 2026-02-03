//
//  WebSocketService.swift
//  pyile_manager
//
//  Real-time file event notifications via WebSocket
//

import Foundation
import Combine

import UserNotifications

class WebSocketService: ObservableObject {
    @Published var lastEvent: FileEvent?
    @Published var recentEvents: [FileEvent] = []
    @Published var isConnected = false
    
    private var webSocket: URLSessionWebSocketTask?
    private let maxRecentEvents = 10
    
    init() {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
        
        // Listen for backend readiness
        NotificationCenter.default.addObserver(self, selector: #selector(handleBackendReady), name: NSNotification.Name("BackendReady"), object: nil)
    }
    
    @objc private func handleBackendReady() {
        print("WebSocketService: Backend ready notification received, connecting...")
        // Add a small delay to ensure server is fully accepting connections
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.connect()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func connect() {
        guard let url = URL(string: "ws://127.0.0.1:8000/ws") else {
            print("Invalid WebSocket URL")
            return
        }
        
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        
        DispatchQueue.main.async {
            self.isConnected = true
        }
        
        print("WebSocket connecting...")
        
        // Start receiving messages
        receiveMessage()
        
        // Send periodic ping to keep connection alive
        sendPing()
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
        print("WebSocket disconnected")
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessage()
                
            case .failure(let error):
                print("WebSocket error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        // Ignore ping responses
        guard text != "pong" else { return }
        
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(FileEvent.self, from: data) else {
            print("Failed to decode WebSocket message: \(text)")
            return
        }
        
        DispatchQueue.main.async {
            self.lastEvent = event
            self.recentEvents.insert(event, at: 0)
            
            // Keep only recent events
            if self.recentEvents.count > self.maxRecentEvents {
                self.recentEvents = Array(self.recentEvents.prefix(self.maxRecentEvents))
            }
            
            print("Received event: \(event.type) - \(event.displayText)")
            
            // Show notification
            self.showNotification(for: event)
        }
    }
    
    private func showNotification(for event: FileEvent) {
        let content = UNMutableNotificationContent()
        content.title = "Pyile Manager"
        content.subtitle = event.type == "file_moved" ? "File Organized" : "New File Detected"
        content.body = event.displayText
        content.sound = .default
        
        // Add icon based on event type if possible (requires Notification Service Extension for dynamic images, 
        // but we can use standard app icon)
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Show immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }
    
    private func sendPing() {
        webSocket?.send(.string("ping")) { error in
            if let error = error {
                print("Ping error: \(error.localizedDescription)")
            }
        }
        
        // Send ping every 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.isConnected == true {
                self?.sendPing()
            }
        }
    }
}
