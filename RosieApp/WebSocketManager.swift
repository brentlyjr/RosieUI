//
//  WebSocketManager.swift
//  RosieApp
//
//  Created by Brent Cromley on 12/6/24.
//

import Foundation

class WebSocketManager: ObservableObject {
    @Published var receivedMessages: String = "" // Published messages for SwiftUI views
    @Published var isConnected: Bool = false       // Connection status for SwiftUI views
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL

    // Audio in and out classes
    private let microphoneStreamer: MicrophoneStreamer
    private let audioPlayer = AudioPlayer()

    // These three classes are for external tools needed by OpenAI
    private let phoneCall = PhoneCall()
    private let numberLookup = NumberLookup()
    private let invoker = FunctionInvoker()
    
    init(urlString: String) {
        guard let url = URL(string: urlString) else {
            fatalError("Invalid WebSocket URL.")
        }
        self.url = url

        // Add our two external tools so we can call them later
        invoker.addFunction("restaurant_phone_lookup", function: numberLookup.lookupPhoneNumber)
        invoker.addFunction("make_phone_call", function: phoneCall.makePhoneCall)
        
        // Initialize the microphone streamer
        self.microphoneStreamer = MicrophoneStreamer()
        
        // Set up the callback for audio chunks from our microphone
        self.microphoneStreamer.onAudioChunkReady = { [weak self] audioData in
            guard let self = self else { return }

            // Send audio data over the WebSocket
            self.sendAudioChunk(data: audioData)
        }
    }
    
    /// Connects to the WebSocket server
    func connect() {
        guard webSocketTask == nil else {
            print("Already connected to the WebSocket.")
            return
        }

        guard let apiKey = Utilities.loadSecret(forKey: "OPENAI_API_KEY") else {
            print("Failed to load API key.")
            return
        }

        // Create a URLRequest to add headers
        var request = URLRequest(url: url)

        // Add hardcoded headers
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        print("Connected to WebSocket: \(url)")
        
        // Update our session to include an audio transcription
        sendInitialSessionUpdate()
        
        // Start listening for messages
        receiveMessages()
    }
    
    /// Disconnects from the WebSocket server
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

    // Update our session at beginning with our initial settings
    // This is where we have it give us back a transcript of our voice input
    // as well as ask it for our plugins that we want as callbacks
    func sendInitialSessionUpdate() {
        guard let task = webSocketTask else {
            print("Cannot send message. WebSocket is not connected.")
            return
        }

        // Create the JSON payload
        // Update the session to get an audio transcription from our GPT
        // And pass in our two tools we want to enable
        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "input_audio_transcription": [
                    "model": "whisper-1"
                ],
                "tools": [
                    [
                        "type": "function",
                        "name": "restaurant_phone_lookup",
                        "description": "Looks up the phone number of a restaurant based on its name and city.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "name": [
                                    "type": "string",
                                    "description": "Name of Restaurant"
                                ],
                                "city": [
                                    "type": "string",
                                    "description": "City restaurant is in"
                                ]
                            ],
                            "required": ["name", "city"]
                        ]
                    ],
                    [
                        "type": "function",
                        "name": "make_phone_call",
                        "description": "Make a phone call to a business with the provided number.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "name": [
                                    "type": "string",
                                    "description": "Name of Business"
                                ],
                                "phone_number": [
                                    "type": "string",
                                    "description": "Telephone Number for business"
                                ]
                            ],
                            "required": ["name", "phone_number"]
                            ]
                    ]
                ]
            ]
        ]

        // Convert the JSON object to Data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: event, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // Send the JSON string
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                task.send(message) { error in
                    if let error = error {
                        print("Error sending message: \(error.localizedDescription)")
                    } else {
                        print("Message sent: \(jsonString)")
                    }
                }
            }
        } catch {
            print("Failed to encode JSON: \(error.localizedDescription)")
        }
    }

    // Function to send a generic message to the OpenAI API
    // You only need to give the type of message that is sent and it will
    // send that message to the websocket
    func sendMessage(ofType type: String) {
        guard let task = webSocketTask else {
            print("Cannot send message. WebSocket is not connected.")
            return
        }
        
        // Create the dictionary representing the message
        let messageDict: [String: String] = [
            "type": type
        ]
        
        // Convert the dictionary to JSON data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // Send the JSON string as a WebSocket message
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                task.send(message) { error in
                    if let error = error {
                        print("Error sending message: \(error.localizedDescription)")
                    } else {
                        print("Message sent: \(jsonString)")
                    }
                }
            }
        } catch {
            print("Failed to convert message to JSON: \(error.localizedDescription)")
        }
    }
    
    func sendFunctionDoneMessage(message: String, callId: String) {
        guard let task = webSocketTask else {
            print("Cannot send message. WebSocket is not connected.")
            return
        }

        // Create the dictionary representing the message
        let messageDict: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": message
            ]
        ]

        // Convert the dictionary to JSON data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // Send the JSON string as a WebSocket message
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                task.send(message) { error in
                    if let error = error {
                        print("Error sending message: \(error.localizedDescription)")
                    } else {
                        print("Message sent: \(jsonString)")
                    }
                }
            }
        } catch {
            print("Failed to convert message to JSON: \(error.localizedDescription)")
        }

        sendMessage(ofType: "response.create")
    }
    
    
    /// Sends a text message over the WebSocket (very specific type of message)
    /// Essentially sends 2 messages conversation.item.create and response.create
    func send(text: String) {
        guard let task = webSocketTask else {
            print("Cannot send message. WebSocket is not connected.")
            return
        }
        
        // Create the JSON payload
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

        // Convert the JSON object to Data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: event, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // Send the JSON string
                let message = URLSessionWebSocketTask.Message.string(jsonString)
                task.send(message) { error in
                    if let error = error {
                        print("Error sending message: \(error.localizedDescription)")
                    } else {
                        print("Message sent: \(jsonString)")
                    }
                }
            }
        } catch {
            print("Failed to encode JSON: \(error.localizedDescription)")
        }

        sendMessage(ofType: "response.create")
    }
    
    /// Sends binary data over the WebSocket
    func send(data: Data) {
        guard let task = webSocketTask else {
            print("Cannot send data. WebSocket is not connected.")
            return
        }
        
        let message = URLSessionWebSocketTask.Message.data(data)
        task.send(message) { error in
            if let error = error {
                print("Error sending data: \(error.localizedDescription)")
            } else {
                print("Binary data sent.")
            }
        }
    }
    
    // Send a chunk of audio data from the microphone to OpenAI
    func sendAudioChunk(data: Data) {
        guard let task = webSocketTask else {
            print("Cannot send data. WebSocket is not connected.")
            return
        }
        
        // Base64 encode the audio data
        let base64Chunk = data.base64EncodedString()

        // Create the JSON payload
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Chunk
        ]
        
        // Convert the JSON object to Data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: event, options: [])
            
            // Create a string message for the WebSocket
            let messageString = String(data: jsonData, encoding: .utf8) ?? ""
            
            // Send the JSON string over the WebSocket
            let webSocketMessage = URLSessionWebSocketTask.Message.string(messageString)
            task.send(webSocketMessage) { error in
                if let error = error {
                    print("Error sending data: \(error.localizedDescription)")
                }  else {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    // let timestamp = formatter.string(from: Date())
                    // print("[\(timestamp)] Audio chunk sent.")
                }
            }
        } catch {
            print("Error encoding JSON: \(error.localizedDescription)")
        }
    }

    /// Starts streaming audio from the microphone
    func startMicrophoneStreaming() {
        guard isConnected else {
            print("Cannot start microphone streaming. WebSocket is not connected.")
            return
        }
        
        microphoneStreamer.startStreaming()
    }
    
    /// Stops streaming audio from the microphone, and trigger a response
    func stopMicrophoneStreaming() {
        microphoneStreamer.stopStreaming()

        // Once we have done streaming to OpenAI, we need to notify that we need a response
        sendMessage(ofType: "input_audio_buffer.commit")
        sendMessage(ofType: "response.create")
    }

    /// Listens for messages from the WebSocket server
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
                    // print("Received text: \(text)")
                    
                    // Try to parse the JSON text into a dynamic object
                    if let jsonData = text.data(using: .utf8) {
                        do {
                            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                            
                            // Handle the received JSON object (could be a dictionary or array)
                            if let dictionary = jsonObject as? [String: Any] {
                                
                                if let type = dictionary["type"] as? String, let eventId = dictionary["event_id"] as? String {
                                    print("Received message type: \(type), event_id: \(eventId)")

                                    switch type {

                                    case "response.audio.delta":
                                        // print("Handling response audio delta...")
                                        // print("Received JSON dictionary: \(dictionary)")
                                        if let delta = dictionary["delta"] as? String {
                                            // Switched from playing straight to doing it on main thread via DispatchQueue
                                            DispatchQueue.global(qos: .userInitiated).async {
                                                self.audioPlayer.playBase64EncodedAudioChunk(delta)
                                            }
                                            // Old Code, that was working
                                            // audioPlayer.playBase64EncodedAudioChunk(delta)
                                        } else {
                                            print("The 'delta' key is missing or is not a String.")
                                        }
                                    case "response.audio_transcript.delta":
                                        // print("Handling audio transcript delta...")
                                        if let delta = dictionary["delta"] as? String {
                                            // print("Received delta string: \(delta)")
                                            DispatchQueue.main.async {
                                                self.receivedMessages += delta // Appends text directly
                                            }
                                        }
                                    case "response.audio_transcript.done":
                                        // End of our voice message back from GPT, so ensure we put linebreak in text view
                                        DispatchQueue.main.async {
                                            self.receivedMessages += "\n" // Appends text directly
                                        }
                                    case "conversation.item.input_audio_transcription.completed":
                                        print("Received JSON dictionary: \(dictionary)")
                                        if let transcript = dictionary["transcript"] as? String {
                                            DispatchQueue.main.async {
                                                self.receivedMessages += transcript
                                            }
                                        }

                                    case "input_audio_buffer.committed":
                                        print("Received JSON dictionary: \(dictionary)")
                                    case "session.created":
                                        print("Received JSON dictionary: \(dictionary)")
                                    case "session.updated":
                                        print("Received JSON dictionary: \(dictionary)")
                                    case "response.function_call_arguments.done":
                                        print("Received JSON dictionary: \(dictionary)")
                                        // Hard code the function to call
                                        // let strResponse = "The phone number is 415-706-3926."
                                        let callId = dictionary["call_id"] as? String

                                        if let functionName = dictionary["name"] as? String {
                                            
                                            if let argumentsString = dictionary["arguments"] as? String {
                                                do {
                                                    // Decode the JSON string into a dictionary
                                                    if let argumentsData = argumentsString.data(using: .utf8) {
                                                        let args = try JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any]
                                                        
                                                        if let args = args,
                                                           let name = args["name"] as? String,
                                                           let city = args["city"] as? String {
                                                            
                                                            // Call the PhoneLookup function
                                                            // invoker.invoke(functionName: functionName, param1: name, param2: city)

                                                            invoker.invoke(functionName: functionName, param1: name, param2: city) { result in
                                                                // Send the result back to OpenAI
                                                                self.sendFunctionDoneMessage(message: result, callId: callId ?? "")
                                                            }
                                                            // numberLookup.lookupPhoneNumber(name: name, city: city) { result in
                                                                // Send the result back to OpenAI
                                                            //     self.sendFunctionDoneMessage(message: result, callId: callId ?? "")
                                                            // }
                                                        } else {
                                                            // Handle invalid arguments case
                                                            let errorMessage = "Invalid arguments received for restaurant_phone_lookup."
                                                            self.sendFunctionDoneMessage(message: errorMessage, callId: callId ?? "")
                                                        }
                                                    }
                                                } catch {
                                                    print("Failed to decode arguments JSON: \(error.localizedDescription)")
                                                    let errorMessage = "Invalid arguments received for restaurant_phone_lookup."
                                                    self.sendFunctionDoneMessage(message: errorMessage, callId: callId ?? "")
                                                }
                                            } else {
                                                print("The 'arguments' field is missing or is not a string.")
                                                let errorMessage = "Invalid arguments received for restaurant_phone_lookup."
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
                self.isConnected = false
            }
        }
    }
}
