//
//  AudioStreamManager.swift
//  RosieAI
//
//  Created by Brent Cromley on 2/27/25.
//  Manages the microphone and speaker audio streaming
//

import Foundation
import AVFoundation

class AudioStreamManager: NSObject {
    // MARK: - Properties
    
    // Shared audio engine for both streaming and playback
    private var audioEngine: AVAudioEngine!
    
    // Audio player node for playback
    private var audioPlayerNode: AVAudioPlayerNode!
    private var playbackFormat: AVAudioFormat!
    private var isPlaying: Bool = false
    
    // Microphone streaming properties
    private var inputFormat: AVAudioFormat!
    private var micOutputFormat: AVAudioFormat!
    private var audioConverter: AVAudioConverter?
    private let streamingBufferSize: AVAudioFrameCount = 2048 // frames per chunk
    private let minimumAudioDataSize = 1024 // Minimum size for valid audio data
    private var isMicrophoneStreaming: Bool = false
    
    // A property to keep track of the number of pending playback buffers.
    private var pendingPlaybackBuffers: Int = 0

    // Callback for processed microphone data (as Int16)
    var onAudioChunkReady: ((Data) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        // Configure the shared audio session
        configureAudioSession()
        
        // Initialize the audio engine
        audioEngine = AVAudioEngine()
        
        // Set up the playback components
        audioPlayerNode = AVAudioPlayerNode()
        audioEngine.attach(audioPlayerNode)
        
        // Define playback format: PCM Float32, 16kHz, mono, interleaved
        playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )
        
        // Connect the player node to the engine's main mixer
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        
        // Set up the microphone streaming components
        let inputNode = audioEngine.inputNode
        inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Desired microphone output format: PCM Float32, 16kHz, mono, non-interleaved
        micOutputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
        
        // Create an audio converter (kept for future use if needed)
        audioConverter = AVAudioConverter(from: inputFormat, to: micOutputFormat)
        if audioConverter == nil {
            print("Failed to initialize audio converter for microphone streaming.")
        }
        
        // Start the audio engine once everything is attached and connected
        do {
            try audioEngine.start()
            print("Audio engine started successfully.")
        } catch {
            print("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Allow simultaneous playback and recording with Bluetooth and mixing options
            try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])

            // Use voiceChat mode for voice-optimized processing (like AEC)
            try audioSession.setMode(.voiceChat)

            // Activate the session
            try audioSession.setActive(true)

            // Explicitly override output to speaker
            try audioSession.overrideOutputAudioPort(.speaker)

            // Set preferred sample rate and I/O buffer duration
            try audioSession.setPreferredSampleRate(16000)
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer for lower latency
            
            // Log the hardware sample rate
            let hardwareSampleRate = audioSession.sampleRate
            print("Hardware sample rate: \(hardwareSampleRate)")
            if hardwareSampleRate != 16000 {
                print("Warning: Hardware sample rate differs from preferred rate")
            }

            print("Audio session configured successfully.")
            print("Current sample rate: \(audioSession.sampleRate)")
            print("Current I/O buffer duration: \(audioSession.ioBufferDuration)")
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Microphone Streaming Methods
    
    func startMicrophoneStreaming() {
        guard !isMicrophoneStreaming else {
            print("Microphone tap is already installed.")
            return
        }

        let inputNode = audioEngine.inputNode
        // Use the hardware's native input format instead of our predefined format
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        print("Using hardware input format: \(hardwareFormat)")
        
        inputNode.installTap(onBus: 0, bufferSize: streamingBufferSize, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            if let processedData = self.processAudioBufferInt16_new(buffer) {
                self.onAudioChunkReady?(processedData)
            }
        }
        isMicrophoneStreaming = true
        print("Microphone streaming started.")
    }
    
    func stopMicrophoneStreaming() {
        guard isMicrophoneStreaming else {
            print("Microphone streaming is not active; no tap to remove.")
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        isMicrophoneStreaming = false
        print("Microphone streaming stopped.")
    }
    

    // This is the newer version of processAudioBufferInt16 that uses the iOS
    // AVAudioConverter native libraries
    private func processAudioBufferInt16_new(_ buffer: AVAudioPCMBuffer) -> Data? {
        // Create an output format: 16 kHz, mono, PCM Int16.
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16000,
                                               channels: 1,
                                               interleaved: true) else {
            print("Failed to create output format.")
            return nil
        }
        
//        print("Input buffer format: \(buffer.format)")
//        print("Target output format: \(outputFormat)")
//        print("Input buffer frame length: \(buffer.frameLength)")
        
        // Create an AVAudioConverter to convert from the buffer's format to our desired output.
        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            print("Failed to create AVAudioConverter.")
            return nil
        }
        
        // Create an output buffer with a reasonable frame capacity.
        // Here, we use the same capacity as our streamingBufferSize.
        let frameCapacity: AVAudioFrameCount = streamingBufferSize
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            print("Failed to create output buffer.")
            return nil
        }
        
        // The input block provides the converter with the microphone buffer.
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("AVAudioConverter error: \(error.localizedDescription)")
            return nil
        }
        
//        print("Conversion status: \(status)")
//        print("Output buffer frame length: \(outputBuffer.frameLength)")
        
        // Extract raw audio data from the converted output buffer.
        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else {
            print("No audio data available in output buffer.")
            return nil
        }
        
        let data = Data(bytes: mData, count: Int(audioBuffer.mDataByteSize))
//        print("Processed audio data size: \(data.count) bytes")
        
        // Check if we have enough audio data
        if data.count < minimumAudioDataSize {
            print("Warning: Audio data size below minimum threshold")
            return nil
        }
        
        // Log the first few samples to check for potential issues
        if data.count >= 4 {
            let samples = data.prefix(4).map { Int16(bitPattern: UInt16($0)) }
//            print("First 4 samples: \(samples)")
            
            // Check if the audio data is all zeros or contains invalid values
            let allZeros = samples.allSatisfy { $0 == 0 }
            let hasInvalidValues = samples.contains { abs($0) > 32767 }
            
            if allZeros {
                print("Warning: Audio data contains all zeros")
                return nil
            }
            
            if hasInvalidValues {
                print("Warning: Audio data contains invalid values")
                return nil
            }
        }
        
        return data
    }

    // MARK: - Audio Playback Methods
    
    // Plays a Base64-encoded PCM16 audio chunk.
    func playBase64EncodedAudioChunk(_ base64String: String) {
        // Disable microphone input
        if isMicrophoneStreaming {
            stopMicrophoneStreaming()
        }

        // Decode the Base64 string to raw PCM16 data.
        guard let audioData = Data(base64Encoded: base64String) else {
            print("Failed to decode Base64 string")
            // Optionally re-enable the microphone here if decoding fails.
            if pendingPlaybackBuffers == 0 {
                startMicrophoneStreaming()
            }
            return
        }
        
        // Resample PCM16 data (assumed 24000 Hz) to PCM Float32 at 16kHz.
        guard let resampledData = resamplePCM16ToPCMFloat32(
            pcm16Data: audioData,
            inputSampleRate: 24000,
            outputSampleRate: 16000,
            channels: 1
        ) else {
            print("Failed to resample audio")
            if pendingPlaybackBuffers == 0 {
                startMicrophoneStreaming()
            }
            return
        }
        
        // Create an AVAudioPCMBuffer from the resampled data.
        guard let buffer = createPCMBuffer(from: resampledData) else {
            print("Failed to create PCM buffer")
            if pendingPlaybackBuffers == 0 {
                startMicrophoneStreaming()
            }
            return
        }
        
        // Increment the pending buffer count.
        pendingPlaybackBuffers += 1

        // Schedule the buffer for playback with a completion handler.
        // The completion handler will re-enable the microphone once playback is finished.
        audioPlayerNode.scheduleBuffer(buffer, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingPlaybackBuffers -= 1
                // If no more buffers are pending, re-enable the microphone.
                if self.pendingPlaybackBuffers == 0 {
                    self.startMicrophoneStreaming()
                }
            }
        })

        // Start playback if not already running.
        if !isPlaying {
            audioPlayerNode.play()
            isPlaying = true
        }
    }
    
    // Create an AVAudioPCMBuffer from raw PCM Float32 data.
    private func createPCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameLength = UInt32(data.count) / 4 // 4 bytes per Float32 frame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameLength) else {
            return nil
        }
        
        buffer.frameLength = frameLength
        
        data.withUnsafeBytes { (audioBytes: UnsafeRawBufferPointer) in
            guard let audioPtr = audioBytes.baseAddress else { return }
            memcpy(buffer.floatChannelData![0], audioPtr, data.count)
        }
        
        return buffer
    }
    
    // Converts raw PCM16 (24kHz, mono) data to PCM Float32 (16kHz, mono).
    func resamplePCM16ToPCMFloat32(
        pcm16Data: Data,
        inputSampleRate: Double,
        outputSampleRate: Double,
        channels: Int = 1
    ) -> Data? {
        let resampleRatio = outputSampleRate / inputSampleRate
        
        // Convert PCM16 data to an array of Int16 values.
        let sampleCount = pcm16Data.count / MemoryLayout<Int16>.size
        let inputSamples = pcm16Data.withUnsafeBytes { buffer in
            Array(UnsafeBufferPointer<Int16>(start: buffer.baseAddress!.assumingMemoryBound(to: Int16.self), count: sampleCount))
        }
        
        // Determine the number of output samples.
        let outputSampleCount = Int(Double(inputSamples.count) * resampleRatio)
        var outputSamples = [Float](repeating: 0, count: outputSampleCount)
        
        // Perform linear interpolation to resample.
        for i in 0..<outputSampleCount {
            let srcIndex = Double(i) / resampleRatio
            let lowerIndex = Int(floor(srcIndex))
            let upperIndex = min(lowerIndex + 1, inputSamples.count - 1)
            let weight = Float(srcIndex - Double(lowerIndex))
            
            let sample = (1.0 - weight) * Float(inputSamples[lowerIndex]) + weight * Float(inputSamples[upperIndex])
            outputSamples[i] = sample / Float(Int16.max) // Normalize to [-1.0, 1.0]
        }
        
        let outputData = outputSamples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        return outputData
    }
    
    // Stops audio playback.
    func stopPlayback() {
        audioPlayerNode.stop()
        isPlaying = false
    }
}
