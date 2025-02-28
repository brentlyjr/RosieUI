//
//  AudioStreamManager.swift
//  RosieApp
//
//  Created by Brent Cromley on 2/27/25.
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
    private let streamingBufferSize: AVAudioFrameCount = 1024 // frames per chunk
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
            try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .defaultToSpeaker])
            // Use voiceChat mode for voice-optimized processing (like AEC)
            try audioSession.setMode(.voiceChat)
            // Activate the session
            try audioSession.setActive(true)

            // Explicitly override output to speaker
            try audioSession.overrideOutputAudioPort(.speaker)

            print("Audio session configured successfully.")
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
        inputNode.installTap(onBus: 0, bufferSize: streamingBufferSize, format: inputFormat) { [weak self] buffer, _ in
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
    
    // Convert the input buffer to a mono, downsampled, Int16 data chunk.
    private func processAudioBufferInt16(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let inputChannelData = buffer.floatChannelData else {
            print("Input buffer does not contain valid channel data.")
            return nil
        }
        
        let inputFrameLength = Int(buffer.frameLength)
        let inputSampleRate = buffer.format.sampleRate
        let inputChannels = Int(buffer.format.channelCount)
        
        // Mix stereo to mono (if necessary) or copy mono channel
        let monoSamples = [Float](unsafeUninitializedCapacity: inputFrameLength) { bufferPtr, count in
            if inputChannels == 2 {
                let leftChannel = inputChannelData[0]
                let rightChannel = inputChannelData[1]
                for i in 0..<inputFrameLength {
                    bufferPtr[i] = (leftChannel[i] + rightChannel[i]) / 2.0
                }
            } else if inputChannels == 1 {
                let channel = inputChannelData[0]
                for i in 0..<inputFrameLength {
                    bufferPtr[i] = channel[i]
                }
            }
            count = inputFrameLength
        }
        
        // Downsample from the input sample rate to 16kHz.
        let targetSampleRate: Float = 16000.0
        let downsampleFactor = Float(inputSampleRate) / targetSampleRate
        let downsampledFrameLength = Int(Float(monoSamples.count) / downsampleFactor)
        
        let downsampledSamples = [Float](unsafeUninitializedCapacity: downsampledFrameLength) { bufferPtr, count in
            var outputIndex = 0
            var accumulator: Float = 0.0
            var accumulatorCount: Int = 0
            
            for i in monoSamples.indices {
                let targetIndex = Int(Float(i) / downsampleFactor)
                if targetIndex > outputIndex {
                    bufferPtr[outputIndex] = accumulator / Float(accumulatorCount)
                    outputIndex += 1
                    accumulator = 0.0
                    accumulatorCount = 0
                }
                accumulator += monoSamples[i]
                accumulatorCount += 1
            }
            
            if accumulatorCount > 0 {
                bufferPtr[outputIndex] = accumulator / Float(accumulatorCount)
                outputIndex += 1
            }
            count = outputIndex
        }
        
        // Convert the downsampled Float samples to Int16
        var int16Data = [Int16](repeating: 0, count: downsampledSamples.count)
        for i in 0..<downsampledSamples.count {
            let sample = downsampledSamples[i]
            int16Data[i] = Int16(max(-32768, min(32767, sample * 32767.0)))
        }
        
        let data = Data(bytes: int16Data, count: int16Data.count * MemoryLayout<Int16>.size)
        return data
    }
    
    private func processAudioBufferInt16_new(_ buffer: AVAudioPCMBuffer) -> Data? {
        // Create an output format: 16 kHz, mono, PCM Int16.
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16000,
                                               channels: 1,
                                               interleaved: true) else {
            print("Failed to create output format.")
            return nil
        }
        
        // Create an AVAudioConverter to convert from the buffer’s format to our desired output.
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
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("AVAudioConverter error: \(error.localizedDescription)")
            return nil
        }
        
        // Extract raw audio data from the converted output buffer.
        // Since we requested an interleaved format, we extract the data from the buffer's audioBufferList.
        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else {
            print("No audio data available in output buffer.")
            return nil
        }
        
        let data = Data(bytes: mData, count: Int(audioBuffer.mDataByteSize))
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
