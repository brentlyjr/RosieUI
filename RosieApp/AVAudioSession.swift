//
//  AVAudioSession.swift
//  RosieApp
//
//  Created by Brent Cromley on 1/14/25.
//

// To ensure that the microphone and speaker do not conflict, the recommendation is to use a shared
// AVAudioSession with the same settings. This class is used by both MicrophoneStreamer and
// AudioPlayer

import AVFoundation

class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private init() { }
    
    func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set the audio category to allow simultaneous playback and recording
            try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            
            // Use the voiceChat mode to enable AEC and other voice optimizations
            try audioSession.setMode(.voiceChat)
            
            // Manual set the audio route to the speaker, I added this when it wouldn't
            // produce audio on the phone
            // try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)

            // Activate the audio session
            try audioSession.setActive(true)
            
            print("Audio session configured successfully.")
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}
