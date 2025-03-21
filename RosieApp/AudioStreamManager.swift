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
    private let streamingBufferSize: AVAudioFrameCount = 2400  // Match input frame size
    private let minimumAudioDataSize = 1024 // Minimum size for valid audio data
    private var isMicrophoneStreaming: Bool = false
    
    // A property to keep track of the number of pending playback buffers.
    private var pendingPlaybackBuffers: Int = 0

    // Callback for processed microphone data (as Int16)
    var onAudioChunkReady: ((Data) -> Void)?
    
    // Add these properties at the top with other properties
    private var audioFileWriter: AVAudioFile?
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var recordingURL: URL?

    // 3. Add property to store previous chunk end for overlap handling
    private var previousChunkEnd: [Int16]?

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

        // Add this method after init()
        setupAudioFileWriter()
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Allow simultaneous playback and recording with Bluetooth and mixing options
            try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])

            // Use voiceChat mode for voice-optimized processing (like AEC)
            try audioSession.setMode(.voiceChat)
            
            // Match the hardware sample rate
            try audioSession.setPreferredSampleRate(24000)
            
            // Increase buffer duration slightly
            try audioSession.setPreferredIOBufferDuration(0.010)  // 10ms buffer
            
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
            
            print("""
            Audio Session Configuration:
            Sample Rate: \(audioSession.sampleRate)
            IO Buffer Duration: \(audioSession.ioBufferDuration)
            Input Latency: \(audioSession.inputLatency)
            Output Latency: \(audioSession.outputLatency)
            """)
        } catch {
            print("Failed to configure audio session: \(error)")
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
        finalizeRecording()
        print("Microphone streaming stopped and recording finalized.")
    }
    

    // 2. Modify processAudioBufferInt16_new to handle the full buffer
    private func processAudioBufferInt16_new(_ buffer: AVAudioPCMBuffer) -> Data? {
        // Log input buffer details
        // print("Input buffer: format=\(buffer.format), frames=\(buffer.frameLength), capacity=\(buffer.frameCapacity)")
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,  // Match input sample rate
            channels: AVAudioChannelCount(1),
            interleaved: true
        ) else {
            print("Failed to create output format.")
            return nil
        }
        
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
        
        // Log conversion details
        // print("Conversion: status=\(status), outputFrames=\(outputBuffer.frameLength), error=\(error?.localizedDescription ?? "none")")
        
        if let error = error {
            print("AVAudioConverter error: \(error.localizedDescription)")
            return nil
        }
        
        // Extract raw audio data from the converted output buffer.
        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else {
            print("No audio data available in output buffer.")
            return nil
        }
        
        let data = Data(bytes: mData, count: Int(audioBuffer.mDataByteSize))
        
        // Log data size
        // print("Audio chunk size: \(data.count) bytes")
        
        // Check if we have enough audio data
        if data.count < minimumAudioDataSize {
            print("Warning: Audio data size below minimum threshold")
            return nil
        }
        
        // Before returning the data, write it to our file
        writeAudioChunkToFile(data)
        
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
        
        audioPlayerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.pendingPlaybackBuffers -= 1
                if self?.pendingPlaybackBuffers == 0 {
                    self?.startMicrophoneStreaming()
                }
            }
        }

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
        // Use AVAudioConverter instead of manual resampling
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: inputSampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ),
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ) else {
            return nil
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        
        // Create input buffer
        let frameCount = UInt32(pcm16Data.count) / 2 // 2 bytes per Int16
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            return nil
        }
        inputBuffer.frameLength = frameCount
        
        // Copy input data
        pcm16Data.withUnsafeBytes { ptr in
            if let addr = ptr.baseAddress {
                memcpy(inputBuffer.int16ChannelData?[0], addr, Int(frameCount) * 2)
            }
        }
        
        // Create output buffer
        let outputFrameCapacity = AVAudioFrameCount(Double(frameCount) * outputSampleRate / inputSampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        guard status != .error, error == nil else {
            return nil
        }
        
        // Convert to Data
        let channelData = outputBuffer.floatChannelData!
        return Data(bytes: channelData[0], count: Int(outputBuffer.frameLength) * 4)
    }
    
    // Stops audio playback.
    func stopPlayback() {
        audioPlayerNode.stop()
        isPlaying = false
    }

    // Add this method after init()
    private func setupAudioFileWriter() {
        let timestamp = Int(Date().timeIntervalSince1970)
        recordingURL = documentsPath.appendingPathComponent("audio_recording_\(timestamp).wav")
        
        guard let url = recordingURL else {
            print("Failed to create recording URL")
            return
        }
        
        // Create an audio file with the same format as our PCM16 input
        let fileFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: AVAudioChannelCount(1),
            interleaved: true
        )
        
        do {
            audioFileWriter = try AVAudioFile(
                forWriting: url,
                settings: fileFormat?.settings ?? [:],
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            print("Audio file writer created successfully at: \(url.path)")
        } catch {
            print("Failed to create audio file writer: \(error)")
        }
    }

    // Add this method to write chunks
    private func writeAudioChunkToFile(_ audioData: Data) {
        guard let audioFile = audioFileWriter else {
            print("Audio file writer not initialized")
            return
        }
        
        // Convert Data to AVAudioPCMBuffer
        let frameCount = UInt32(audioData.count) / 2 // 2 bytes per Int16 sample
        guard let tempFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: AVAudioChannelCount(1),
            interleaved: true
        ),
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: tempFormat, frameCapacity: frameCount) else {
            print("Failed to create temporary PCM buffer")
            return
        }
        
        pcmBuffer.frameLength = frameCount
        
        // Copy audio data into the buffer
        audioData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            if let addr = ptr.baseAddress {
                memcpy(pcmBuffer.int16ChannelData?[0], addr, Int(frameCount) * 2)
            }
        }
        
        // Write the buffer to file
        do {
            try audioFile.write(from: pcmBuffer)
            // print("Wrote \(frameCount) frames to WAV file")
        } catch {
            print("Failed to write audio chunk to file: \(error)")
        }
    }

    // Add method to get the recording URL
    func getRecordingURL() -> URL? {
        return recordingURL
    }

    // Add method to close the audio file
    func finalizeRecording() {
        audioFileWriter = nil
        if let url = recordingURL {
            print("Recording saved at: \(url.path)")
        }
    }

    // Add this method to list all recordings
    func listRecordings() -> [URL] {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL,
                                                             includingPropertiesForKeys: nil,
                                                             options: .skipsHiddenFiles)
            return fileURLs.filter { $0.pathExtension == "wav" }
        } catch {
            print("Failed to list recordings: \(error)")
            return []
        }
    }
}
