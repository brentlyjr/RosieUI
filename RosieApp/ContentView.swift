//
//  ContentView.swift
//  RosieApp
//
//  Created by Brent Cromley on 12/6/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var webSocketManager = WebSocketManager(urlString: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17")
    @State private var messageToSend: String = ""
    @State private var isMicrophoneStreaming: Bool = false // Tracks microphone state

    var body: some View {
        VStack {
            // Microphone control button
            Button(action: {
                toggleMicrophone()
            }) {
                Image(systemName: "mic.fill") // Microphone icon
                    .foregroundColor(.white)
                    .font(.system(size: 48))
                    .padding()
                    .background(isMicrophoneStreaming ? Color.red : Color.blue) // Change color based on state
                    .clipShape(Circle())
                    .shadow(radius: 5)
                    .overlay(
                        // Add a glowing effect when active
                        Circle()
                            .stroke(isMicrophoneStreaming ? Color.red.opacity(0.7) : Color.clear, lineWidth: 8)
                            .scaleEffect(isMicrophoneStreaming ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isMicrophoneStreaming)
                    )
            }
            .padding()
            .disabled(!webSocketManager.isConnected) // Disable if WebSocket is not connected
            
            ScrollViewReader { scrollProxy in
                ScrollView {
                    Text(webSocketManager.receivedMessages)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("Bottom") // Anchor for scrolling
                }
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .border(Color.gray, width: 1)
                .frame(height: 300)
                .onChange(of: webSocketManager.receivedMessages) {
                    scrollProxy.scrollTo("Bottom", anchor: .bottom)
                }
            }

            HStack {
                TextField("Message to send", text: $messageToSend)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    webSocketManager.send(text: messageToSend)
                    messageToSend = ""
                }
                .disabled(!webSocketManager.isConnected)
            }
            .padding()
            
            HStack {
                Button("Connect") {
                    webSocketManager.connect()
                }
                .disabled(webSocketManager.isConnected)
                
                Button("Disconnect") {
                    // Don't send any more data from the microphone if we are disconnecting
                    if isMicrophoneStreaming {
                        stopMicrophone()
                    }
                    webSocketManager.disconnect()
                }
                .disabled(!webSocketManager.isConnected)
            }
            .padding()
            Text("WebSocket Connection")
                .font(.headline)
            
            if webSocketManager.isConnected {
                Text("Status: Connected")
                    .foregroundColor(.green)
            } else {
                Text("Status: Disconnected")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
    
    // Toggles the microphone streaming state
    private func toggleMicrophone() {
        if isMicrophoneStreaming {
            stopMicrophone()
        } else {
            startMicrophone()
        }
    }
    
    // Starts the microphone streaming
    private func startMicrophone() {
        if webSocketManager.isConnected {
            webSocketManager.startMicrophoneStreaming()
            isMicrophoneStreaming = true
        } else {
            print("Cannot start microphone. WebSocket is not connected.")
        }
    }
    
    // Stops the microphone streaming
    private func stopMicrophone() {
        webSocketManager.stopMicrophoneStreaming()
        isMicrophoneStreaming = false
    }
}

#Preview {
    ContentView()
}
