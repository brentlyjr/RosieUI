//
//  AudioPlayer.swift
//  RosieApp
//
//  Created by Brent Cromley on 12/6/24.
//

import Foundation
import AVFoundation

class AudioPlayer {
    private var audioEngine: AVAudioEngine!
    private var audioPlayerNode: AVAudioPlayerNode!
    private var audioFormat: AVAudioFormat!
    private var isPlaying = false // To manage playback state
    
    init(sampleRate: Double = 16000, channels: UInt32 = 1) {
        // Use the shared audio session manager to configure the session
        AudioSessionManager.shared.configureAudioSession()

        // Initialize the audio engine and player node
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        
        // Define the audio format (PCM16, mono, 16kHz)
        audioFormat = AVAudioFormat(
            commonFormat: AVAudioCommonFormat.pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )
        
        // Attach and connect the player node to the audio engine
        audioEngine.attach(audioPlayerNode)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        
        // Start the audio engine
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    /// Play Base64-encoded PCM16 audio chunk
    func playBase64EncodedAudioChunk(_ base64String: String) {
        // Decode Base64 string into raw audio data
        guard let audioData = Data(base64Encoded: base64String) else {
            print("Failed to decode Base64 string")
            return
        }
        
        // Resample PCM16 data to PCM Float32
        guard let resampledData = resamplePCM16ToPCMFloat32(
            pcm16Data: audioData,
            inputSampleRate: 24000,
            outputSampleRate: 16000,
            channels: 1
        ) else {
            print("Failed to resample audio")
            return
        }
        
        // Create an AVAudioPCMBuffer from the resampled data
        guard let buffer = createPCMBuffer(from: resampledData) else {
            print("Failed to create PCM buffer")
            return
        }
        
        // Schedule the buffer for playback
        audioPlayerNode.scheduleBuffer(buffer)
        
        // Start playback if not already playing
        if !isPlaying {
            audioPlayerNode.play()
            isPlaying = true
        }
    }
    
    /// Convert raw PCM Float32 data to an AVAudioPCMBuffer
    private func createPCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameLength = UInt32(data.count) / 4 // Each PCM Float32 frame is 4 bytes
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameLength) else {
            return nil
        }
        
        buffer.frameLength = frameLength
        
        // Copy raw PCM Float32 data into the buffer
        data.withUnsafeBytes { (audioBytes: UnsafeRawBufferPointer) in
            guard let audioPtr = audioBytes.baseAddress else { return }
            memcpy(buffer.floatChannelData![0], audioPtr, data.count)
        }
        
        return buffer
    }
    
    // Stop the audio player
    func stop() {
        audioPlayerNode.stop()
        isPlaying = false
    }

    /// Converts raw PCM16 24kHz mono audio to PCM Float32 16kHz mono audio.
    /// - Parameters:
    ///   - pcm16Data: The input raw PCM16 audio data (little-endian, mono, 24kHz).
    ///   - inputSampleRate: The input sample rate (default is 24kHz).
    ///   - outputSampleRate: The output sample rate (default is 16kHz).
    /// - Returns: A `Data` object containing the converted PCM Float32 audio data.
    func resamplePCM16ToPCMFloat32(
        pcm16Data: Data,
        inputSampleRate: Double,
        outputSampleRate: Double,
        channels: Int = 1
    ) -> Data? {
        // Calculate the resampling ratio
        let resampleRatio = outputSampleRate / inputSampleRate
        
        // Convert input PCM16 data to Int16 array
        let sampleCount = pcm16Data.count / MemoryLayout<Int16>.size
        let inputSamples = pcm16Data.withUnsafeBytes { buffer in
            Array(UnsafeBufferPointer<Int16>(start: buffer.baseAddress!.assumingMemoryBound(to: Int16.self), count: sampleCount))
        }
        
        // Calculate the number of output samples
        let outputSampleCount = Int(Double(inputSamples.count) * resampleRatio)
        var outputSamples = [Float](repeating: 0, count: outputSampleCount)
        
        // Perform linear interpolation for resampling
        for i in 0..<outputSampleCount {
            let srcIndex = Double(i) / resampleRatio
            let lowerIndex = Int(floor(srcIndex))
            let upperIndex = min(lowerIndex + 1, inputSamples.count - 1)
            let weight = Float(srcIndex - Double(lowerIndex))
            
            // Interpolate between the two nearest samples
            let sample = (1.0 - weight) * Float(inputSamples[lowerIndex]) + weight * Float(inputSamples[upperIndex])
            outputSamples[i] = sample / Float(Int16.max) // Normalize to [-1.0, 1.0]
        }
        
        // Convert the resampled Float array back to Data
        let outputData = outputSamples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        return outputData
    }
}
