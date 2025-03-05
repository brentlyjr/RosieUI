//
//  OpenAIController.swift
//  RosieApp
//
//  Created by Brent Cromley on 12/6/24.
//

import Foundation
import SwiftUI

class OpenAIController: ObservableObject {
    @Published var receivedMessages: [Message] = [] // Published messages for SwiftUI views
    @Published var isConnected: Bool = false        // Connection status for SwiftUI views
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let apiKey:String
    private let openAIURL: URL

    // Audio in and out classes
    private let audioStreamManager: AudioStreamManager

    // These three classes are for external tools needed by OpenAI
    private let phoneCall = PhoneCall()
    private let numberLookup = NumberLookup()
    private let invoker = FunctionInvoker()
    
    init() {
        // Get our OpenAI URL from the config file
        guard let openAIURL = Utilities.loadInfoConfig(forKey: "OPENAI_URL") else {
            fatalError("Failed to load URL from Info.plist: OPENAI_URL")
        }
        // Convert string to a URL for websocket - uses base URL and API endpoint
        guard let url = URL(string: openAIURL) else {
            fatalError("Invalid WebSocket URL.")
        }
        self.openAIURL = url

        // Load the OpenAI Key from the config file
        guard let apiKey = Utilities.loadSecret(forKey: "OPENAI_API_KEY") else {
            fatalError("Failed to load API key: OPENAI_API_KEY")
        }
        self.apiKey = apiKey

        // Add our two external tools so we can call them later
        invoker.addFunction("restaurant_phone_lookup", instance: numberLookup)
        invoker.addFunction("make_phone_call", instance: phoneCall)
        
        // Initialize the microphone streamer
        self.audioStreamManager = AudioStreamManager()
        
        // Set up the callback for audio chunks from our microphone
        self.audioStreamManager.onAudioChunkReady = { [weak self] audioData in
            guard let self = self else { return }

            // Send audio data over the WebSocket
            self.sendAudioChunk(data: audioData)
        }
    }
    
    // Connects to the WebSocket server
    func connect() {
        guard webSocketTask == nil else {
            print("Already connected to the WebSocket.")
            return
        }

        // Create a URLRequest to add headers
        var request = URLRequest(url: openAIURL)

        // Add hardcoded headers required to connect to OpenAI, including our secret key
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        print("Connected to WebSocket: \(openAIURL)")
        
        // Update our session to include an audio transcription
        sendInitialSessionUpdate()
        
        // I had to back out these changes. If I tried to send 3 updates in fast succession, it would blow away
        // the first session update with the later ones. So I would never get the phoneCall registered, just the
        // numberLookup. This may be a bug in API, so will want to revisit this code path.
        // Register our two client tools
        // self.installTool(ofType: phoneCall)
        // self.installTool(ofType: numberLookup)

        // Start listening for messages
        receiveMessages()
    }

    // Disconnects from the WebSocket server
    func disconnect() {
        guard let task = webSocketTask else {
            print("WebSocket is already disconnected.")
            return
        }
        
        task.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("Disconnected from WebSocket.")
    }

    // Helper function to send a WebSocket message
    func sendWebSocketMessage(_ messageDict: [String: Any]) {
        guard let task = webSocketTask else {
            print("Cannot send message. WebSocket is not connected.")
            return
        }

        // Get the type of message we are sending to print out for debugging later
        let messageType = messageDict["type"] as? String
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                task.send(message) { error in
                    if let error = error {
                        print("Error sending message: \(error)")
                    } else {
                        if (messageType != "input_audio_buffer.append") {
                            print("Message sent: \(messageType!)")
                        }
                    }
                }
            }
        } catch {
            print("Failed to encode JSON: \(error.localizedDescription)")
        }
    }

    // Called to setout our chat session and the server settings
    func sendInitialSessionUpdate() {
        let threshold: Decimal = 0.1 // Use Decimal type for better precision control
        let defaultPrompt = "You are a helpful AI assistant. You are trying to help make a restaurant reservation. You will have two tools to use. One will allow you to look up the number of a restaurant, based on its name and city. The second tool will make the phone call for you if you call this tool with the correct parameters."

        // Had to add the tools here in initial session update as adding later in succession caused issues
        let parameters1 = phoneCall.getParameters()
        let parameters2 = numberLookup.getParameters()
        
        let prompt = Utilities.loadPrompt(forKey: "restaurant_reservation") ?? defaultPrompt

        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "instructions" : prompt,
                "input_audio_transcription": [
                    "model": "whisper-1"
                ],
                "turn_detection" :[
                    "prefix_padding_ms" : 300,
                    "silence_duration_ms" : 200,
                    "threshold" : threshold,
                    "type" : "server_vad"
                ],
                "tools": [
                    parameters1,
                    parameters2
                ]
            ]
        ]
        
        sendWebSocketMessage(event)
    }

    // Call this function when you have a tool you would like to install into our OpenAI session
    private func installTool(ofType clientProtocol: ClientToolProtocol) {
        
        // Call our protocol function to get the parameters this functions requires
        let parameters = clientProtocol.getParameters()
        
        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "tools": [
                    parameters
                ]
            ]
        ]
        
        sendWebSocketMessage(event)
    }

    func sendMessage(ofType type: String) {
        let messageDict: [String: String] = [
            "type": type
        ]
        
        sendWebSocketMessage(messageDict)
    }
    
    private func sendFunctionDoneMessage(message: String, callId: String) {
        let messageDict: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": message
            ]
        ]
        
        sendWebSocketMessage(messageDict)
        sendMessage(ofType: "response.create")
    }
    
    func sendTextMessage(text: String) {
        let event: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": text
                    ]
                ]
            ]
        ]
        
        sendWebSocketMessage(event)
        sendMessage(ofType: "response.create")
    }

    // Send a chunk of audio data from the microphone to OpenAI
    private func sendAudioChunk(data: Data) {
        // Base64 encode the audio data
        let base64Chunk = data.base64EncodedString()

        // Create the JSON event payload
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Chunk
        ]
        
        sendWebSocketMessage(event)
    }

    // Starts streaming audio from the microphone
    func startMicrophoneStreaming() {
        guard isConnected else {
            print("Cannot start microphone streaming. WebSocket is not connected.")
            return
        }
        
        audioStreamManager.startMicrophoneStreaming()
    }
    
    // Stops streaming audio from the microphone, and trigger a response
    func stopMicrophoneStreaming() {
        audioStreamManager.stopMicrophoneStreaming()

        // Once we have done streaming to OpenAI, we need to notify that we need a response
        sendMessage(ofType: "input_audio_buffer.commit")
        sendMessage(ofType: "response.create")
    }

    // Listens for messages from the WebSocket server
    private func receiveMessages() {
        guard let task = webSocketTask else {
            print("Cannot receive messages. WebSocket is not connected.")
            return
        }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // Try to parse the JSON text into a dynamic object
                    if let jsonData = text.data(using: .utf8) {
                        do {
                            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                            
                            // Handle the received JSON object (could be a dictionary or array)
                            if let dictionary = jsonObject as? [String: Any] {
                                
                                if let type = dictionary["type"] as? String, let eventId = dictionary["event_id"] as? String {

                                    if (!type.contains("delta")) {
                                        print("Received message type: \(type), event_id: \(eventId)")
                                    }
//                                    if (type.contains("delta")) {
//                                        print("Received message type: \(type), event_id: \(eventId)")
//                                    }

                                    switch type {

                                    case "response.audio.delta":
                                        if let delta = dictionary["delta"] as? String {
                                            // Switched from playing straight to doing it on main thread via DispatchQueue
                                            DispatchQueue.global(qos: .userInitiated).async {
                                                self.audioStreamManager.playBase64EncodedAudioChunk(delta)
                                            }
                                            // Old Code, that was working
                                            // audioPlayer.playBase64EncodedAudioChunk(delta)
                                        } else {
                                            print("The 'delta' key is missing or is not a String.")
                                        }
                                    case "response.audio_transcript.done":
                                        // End of our voice message back from GPT, so ensure we put linebreak in text view
                                        if let transcript = dictionary["transcript"] as? String {
                                            DispatchQueue.main.async {
                                                self.receivedMessages.append(Message(text: transcript, color: .red))
                                            }
                                        }
                                    case "conversation.item.input_audio_transcription.completed":
                                        if let transcript = dictionary["transcript"] as? String {
                                            DispatchQueue.main.async {
                                                self.receivedMessages.append(Message(text: transcript, color: .blue))
                                            }
                                        }
                                    case "session.created":
                                        print("Received JSON dictionary: \(dictionary)")
                                    case "session.updated":
                                        print("Received JSON dictionary: \(dictionary)")
                                    case "response.function_call_arguments.done":
                                        // print("Received JSON dictionary: \(dictionary)")

                                        let callId = dictionary["call_id"] as? String

                                        if let functionName = dictionary["name"] as? String {
                                            if let argumentsString = dictionary["arguments"] as? String,
                                               let argumentsData = argumentsString.data(using: .utf8) {
                                                do {
                                                    // Decode the JSON string into a dictionary
                                                    guard let args = try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
                                                        throw NSError(domain: "InvalidArgumentsError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Arguments are not a valid JSON object."])
                                                    }
                                                    
                                                    Task {
                                                        let result = await self.invoker.invoke(functionName: functionName, parameters: args)
                                                        
                                                        switch result {
                                                        case .success(let message):
                                                            self.sendFunctionDoneMessage(message: message, callId: callId ?? "")
                                                        case .failure(let error):
                                                            self.sendFunctionDoneMessage(message: "Error: \(error.localizedDescription)", callId: callId ?? "")
                                                        }
                                                    }
                                                } catch {
                                                    let errorMessage = "Failed to decode arguments: \(error.localizedDescription)"
                                                    print(errorMessage)
                                                    self.sendFunctionDoneMessage(message: errorMessage, callId: callId ?? "")
                                                }
                                            } else {
                                                let errorMessage = "The 'arguments' field is missing or is not a valid JSON string."
                                                print(errorMessage)
                                                self.sendFunctionDoneMessage(message: errorMessage, callId: callId ?? "")
                                            }
                                        }
                                    case "error":
                                        print("Received JSON dictionary: \(dictionary)")

                                    default:
                                        break
                                        // print("Unknown message type received: \(type)")
                                        // Handle any other cases or unknown types
                                    }
                                } else {
                                    print("The 'type' key is missing or not a string.")
                                }
                            } else {
                                print("Received JSON is not a dictionary.")
                            }
                        } catch {
                            print("Error parsing JSON: \(error.localizedDescription)")
                        }
                    } else {
                        print("Failed to convert text to Data")
                    }
                    
                case .data(let data):
                    print("Received binary data, which should not be expected in your case: \(data.count) bytes")
                    // You can log or handle this case if needed, even though you're not expecting binary.

                @unknown default:
                    print("Unknown message type received.")
                }
                
                // Continue listening for more messages from our GPT
                self.receiveMessages()
                
            case .failure(let error):
                print("Error receiving message: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }
}
