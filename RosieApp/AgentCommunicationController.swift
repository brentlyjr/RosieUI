//
//  AgentCommunicationController.swift
//  RosieApp
//
//  Created by Brent Cromley on 3/4/25.
//

import Foundation


class AgentCommunicationController: ObservableObject {
    // Published array of messages received from the WebSocket.
    @Published var messages: [Message] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let apiCall: String = "/api/textstream"
    private let rosieUrl: String

    init() {
        // We need to get some of our variables from our configuration to complete the API call
        guard let rosieUrl = Utilities.loadInfoConfig(forKey: "ROSIE_TOPLEVEL_DOMAIN") else {
            print("Failed to load ROSIE_API_URL from Info.plist")
            fatalError("Unable to load ROSIE_API_URL from Info.plist")
        }
        self.rosieUrl = rosieUrl
    }

    // Connect to the WebSocket.
    func connect() {
        // Connect to the Rosie websocket URL for getting the text stream
        let url = URL(string: "wss://" + rosieUrl + apiCall)!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }
    
    // Disconnect from the WebSocket.
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
    
    func startStreamingThread(callSid: String) {
        print("Getting text thread for call ID: \(callSid)")
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
                        self.messages.append(Message(text: text, color: .blue))
                    }
                case .data(let data):
                    // If you expect data messages, try converting them to a string.
                    if let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.messages.append(Message(text: text, color: .blue))
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
