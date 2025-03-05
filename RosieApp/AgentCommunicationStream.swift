//
//  AgentCommunicationStream.swift
//  RosieApp
//
//  Created by Brent Cromley on 3/4/25.
//

import Foundation

class AgentCommunicationStream: ObservableObject {
    // Published array of messages received from the WebSocket.
    @Published var messages: [String] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let apiCall: String = "/api/textstream"
    
    // Connect to the WebSocket.
    func connect() {
        // We need to get some of our variables from our configuration to complete the API call
        guard let rosieUrl = Utilities.loadInfoConfig(forKey: "ROSIE_API_URL") else {
            print("Failed to load ROSIE_API_URL from Info.plist")
            return // "Unable to load ROSIE_API_URL from Info.plist"
        }

        // Replace with your WebSocket URL.
        let url = URL(string: rosieUrl + apiCall)!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }
    
    // Disconnect from the WebSocket.
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
    
    // Continuously receive messages.
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("WebSocket error: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    // Append the received text to the messages array on the main thread.
                    DispatchQueue.main.async {
                        self.messages.append(text)
                    }
                case .data(let data):
                    // If you expect data messages, try converting them to a string.
                    if let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.messages.append(text)
                        }
                    }
                @unknown default:
                    break
                }
                // Continue receiving messages.
                self.receiveMessage()
            }
        }
    }
}
