//
//  MicrophoneStreamer.swift
//  RosieApp
//
//  Created by Brent Cromley on 12/9/24.
//

import Foundation
import AVFoundation

class MicrophoneStreamer: NSObject {
    private var audioEngine: AVAudioEngine!
    private var inputFormat: AVAudioFormat!
    private var outputFormat: AVAudioFormat!
    private var audioConverter: AVAudioConverter!
    private var streamingBufferSize: AVAudioFrameCount = 1024 // Number of frames per chunk
    
    // Callback to handle processed audio chunks
    var onAudioChunkReady: ((Data) -> Void)?
    
    override init() {
        super.init()
        
        // Use the shared audio session manager to configure the session
        AudioSessionManager.shared.configureAudioSession()
        
        // Set up the audio engine
        audioEngine = AVAudioEngine()

        // Configure input (microphone) format (device default)
        let inputNode = audioEngine.inputNode
        inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Configure desired output format (16kHz, mono, 32-bit float)
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
        
        // Create audio converter for resampling
        audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
        
        if audioConverter == nil {
            print("Failed to initialize audio converter.")
        }
    }
    
    func startStreaming() {
        let inputNode = audioEngine.inputNode
        
        // Install a tap on the input node to capture audio data
        inputNode.installTap(onBus: 0, bufferSize: streamingBufferSize, format: inputFormat) { [weak self] buffer, _ in
            
            guard let self = self else { return }
            
            // Process and convert the buffer
            if let processedData = self.processAudioBufferInt16(buffer) {
                // Pass the processed audio data to the callback
                self.onAudioChunkReady?(processedData)
            }
        }
        
        // Start the audio engine
        do {
            try audioEngine.start()
            print("Microphone streaming started.")
        } catch {
            print("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    func stopStreaming() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        print("Microphone streaming stopped.")
    }
    
    // This will have a 32-bit float buffer at the end, which is not what we need
    private func processAudioBufferFloat32(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let audioConverter = audioConverter else { return nil }
        
        // Create a buffer for the converted data
        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: streamingBufferSize)
        
        // Convert the audio data to the desired format
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        var error: NSError?
        audioConverter.convert(to: convertedBuffer!, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("Audio conversion failed: \(error.localizedDescription)")
            return nil
        }
        
        // Extract audio data from the converted buffer
        guard let channelData = convertedBuffer?.floatChannelData?[0] else { return nil }
        let frameLength = Int(convertedBuffer!.frameLength)
        
        let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
        return data
    }
    
    private func processAudioBufferInt16(_ buffer: AVAudioPCMBuffer) -> Data? {
        // Ensure the input buffer is valid
        guard let inputChannelData = buffer.floatChannelData else {
            print("Input buffer does not contain valid channel data.")
            return nil
        }
        
        let inputFrameLength = Int(buffer.frameLength)
        let inputSampleRate = buffer.format.sampleRate
        let inputChannels = Int(buffer.format.channelCount)
        
        // Print the input buffer details
        // print("Input Buffer Format: \(buffer.format)")
        // print("Input Buffer Sample Rate: \(inputSampleRate)")
        // print("Input Buffer Channels: \(inputChannels)")
        // print("Input Buffer Frame Length: \(inputFrameLength) frames")
        
        // Mix stereo to mono (if input has 2 channels)
        let monoSamples = [Float](unsafeUninitializedCapacity: inputFrameLength) { buffer, count in
            if inputChannels == 2 {
                let leftChannel = inputChannelData[0]
                let rightChannel = inputChannelData[1]
                for i in 0..<inputFrameLength {
                    buffer[i] = (leftChannel[i] + rightChannel[i]) / 2.0 // Average the left and right channels
                }
            } else if inputChannels == 1 {
                // Copy mono data directly
                let channel = inputChannelData[0]
                for i in 0..<inputFrameLength {
                    buffer[i] = channel[i]
                }
            }
            count = inputFrameLength
        }
        
        // Downsample from 44100 Hz to 16000 Hz
        let targetSampleRate: Float = 16000.0
        let downsampleFactor = Float(inputSampleRate) / targetSampleRate
        let downsampledFrameLength = Int(Float(monoSamples.count) / downsampleFactor)
        
        let downsampledSamples = [Float](unsafeUninitializedCapacity: downsampledFrameLength) { buffer, count in
            var outputIndex = 0
            var accumulator: Float = 0.0
            var accumulatorCount: Int = 0
            
            for i in monoSamples.indices {
                let targetIndex = Int(Float(i) / downsampleFactor)
                if targetIndex > outputIndex {
                    // Average the accumulated samples
                    buffer[outputIndex] = accumulator / Float(accumulatorCount)
                    outputIndex += 1
                    accumulator = 0.0
                    accumulatorCount = 0
                }
                accumulator += monoSamples[i]
                accumulatorCount += 1
            }
            
            // Handle any remaining samples
            if accumulatorCount > 0 {
                buffer[outputIndex] = accumulator / Float(accumulatorCount)
                outputIndex += 1
            }
            
            count = outputIndex
        }
        
        // Convert float32 samples to int16
        var int16Data = [Int16](repeating: 0, count: downsampledSamples.count)
        for i in 0..<downsampledSamples.count {
            let sample = downsampledSamples[i]
            int16Data[i] = Int16(max(-32768, min(32767, sample * 32767.0)))
        }
        
        // Create Data directly from the int16 array
        let data = Data(bytes: int16Data, count: int16Data.count * MemoryLayout<Int16>.size)
        
        // Print the final data details
        // print("Output Data: \(data.count) bytes, \(int16Data.count) samples")
        return data
    }
}
