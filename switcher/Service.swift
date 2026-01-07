//
//  Service.swift
//  switcher
//
//  Created by Tony Do on 7/16/25.
//

import AVFoundation
import CoreAudio
import os.log

struct Device: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let transport: String
    let isOutput: Bool
    let isInput: Bool
}

@MainActor
@Observable
final class AudioDeviceService {
    private(set) var outputDevices: [Device] = []
    private(set) var inputDevices: [Device] = []
    private(set) var currentOutputDevice: Device.ID?
    private(set) var currentInputDevice: Device.ID?
    private(set) var inputLevel: Float32 = 0

    private let listener: AudioHardwareListener
    private var inputMonitor: InputLevelMonitor?
    private var isMonitoringInput = false

    private func deviceInfo(for id: AudioDeviceID) -> Device? {
        func string(_ selector: AudioObjectPropertySelector) -> String {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            if selector == kAudioDevicePropertyDeviceNameCFString {
                var unmanaged: Unmanaged<CFString>?
                var size = UInt32(MemoryLayout.size(ofValue: unmanaged))
                let result = withUnsafeMutablePointer(
                    to: &unmanaged
                ) { ptr -> OSStatus in
                    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
                }
                guard result == noErr, let str =
                        unmanaged?.takeRetainedValue() else { return "Unknown" }
                return str as String
            }

            var type: UInt32 = 0
            var size = UInt32(MemoryLayout.size(ofValue: type))

            guard AudioObjectGetPropertyData(
                id, &addr, 0, nil, &size, &type
            ) == noErr else { return "-" }

            switch type {
            case kAudioDeviceTransportTypeBuiltIn:
                return "Built-in"
            case kAudioDeviceTransportTypeDisplayPort:
                return "DisplayPort"
            case kAudioDeviceTransportTypeHDMI:
                return "HDMI"
            case kAudioDeviceTransportTypeUSB:
                return "USB"
            case kAudioDeviceTransportTypeBluetooth:
                return "Bluetooth"
            case kAudioDeviceTransportTypeVirtual:
                return "Virtual"
            case kAudioDeviceTransportTypeAggregate:
                return "Aggregate"
            default:
                return "-"
            }
        }

        // Filter out aggregate devices (e.g., CADefaultDeviceAggregate created by AVAudioEngine)
        let transport = string(kAudioDevicePropertyTransportType)
        if transport == "Aggregate" { return nil }

        let hasOutput = hasStream(id, scope: kAudioDevicePropertyScopeOutput)
        let hasInput = hasStream(id, scope: kAudioDevicePropertyScopeInput)
        guard hasInput || hasOutput else { return nil }

        return Device(
            id: id,
            name: string(kAudioDevicePropertyDeviceNameCFString),
            transport: transport,
            isOutput: hasOutput,
            isInput: hasInput
        )
    }
    
    private func hasStream(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            id, &addr, 0, nil, &size
        ) == noErr else { return false }
        return size > 0
    }
    
    private func channelCount(id: AudioObjectID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }
        
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufferList)
        var channels: UInt32 = 0
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffers {
            channels += buffer.mNumberChannels
        }
        return channels
    }
    
    /// Returns the left and right channel indices (1-based) for stereo balance control.
    /// First tries to find labeled L/R channels from the device's channel layout,
    /// then falls back to channels 1 and 2 for simple stereo devices.
    private func stereoChannels(id: AudioObjectID) -> (left: UInt32, right: UInt32)? {
        let count = channelCount(id: id)
        guard count >= 2 else { return nil }

        // Try to get channel layout and find labeled left/right channels
        if let layout = channelLayout(id: id) {
            var left: UInt32?
            var right: UInt32?

            for (i, description) in layout.channelDescriptions().enumerated() {
                switch description.mChannelLabel {
                case kAudioChannelLabel_Left:
                    left = UInt32(i + 1)
                case kAudioChannelLabel_Right:
                    right = UInt32(i + 1)
                default:
                    break
                }
            }

            if let l = left, let r = right {
                return (l, r)
            }
        }

        // Fallback: assume channels 1 and 2 are left and right
        return (1, 2)
    }

    private func channelLayout(id: AudioObjectID) -> AudioChannelLayout? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelLayout,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else {
            return nil
        }

        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioChannelLayout>.alignment
        )
        defer { ptr.deallocate() }

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr) == noErr else {
            return nil
        }
        return ptr.assumingMemoryBound(to: AudioChannelLayout.self).pointee
    }

    private func channelVolume(id: AudioObjectID, channel: UInt32) -> Float32? {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: volume))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &volume) == noErr else {
            return nil
        }
        return volume
    }

    private func setChannelVolume(_ volume: Float32, on id: AudioDeviceID, for channel: UInt32) {
        var volume = volume
        let size = UInt32(MemoryLayout.size(ofValue: volume))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        AudioObjectSetPropertyData(id, &addr, 0, nil, size, &volume)
    }

    private func poll() {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectGetPropertyDataSize(
            AudioClassID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else { return }
        
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        
        guard AudioObjectGetPropertyData(
            AudioClassID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else { return }
        
        let devices = deviceIDs.compactMap { deviceInfo(for: $0) }
        outputDevices = devices.filter { $0.isOutput && !$0.isInput }
        inputDevices = devices.filter(\.isInput)
    }
    
    private func currentDevices() {
        currentOutputDevice = getDevice(source: .Output)
        currentInputDevice = getDevice(source: .Input)
    }
    
    private func registerListeners() {
        listener.onDevicesChanged = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.poll()
                self.currentDevices()
            }
        }
        listener.onDeviceChanged = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let previousInput = self.currentInputDevice
                self.currentDevices()
                if self.currentInputDevice != previousInput {
                    self.restartInputMonitoringIfNeeded()
                }
            }
        }
        listener.start()
    }
    
    private func start() {
        poll()
        currentDevices()
        registerListeners()
    }

    init(listener: AudioHardwareListener) {
        self.listener = listener
        start()
    }
}

private let audioLog = Logger(subsystem: "com.tonyage.switcher", category: "audio")

final class InputLevelMonitor: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let levelCallback: (Float32) -> Void

    init(onLevel: @escaping (Float32) -> Void) {
        self.levelCallback = onLevel
    }

    func start() {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            audioLog.error("Invalid input format: \(format.sampleRate)Hz, \(format.channelCount)ch")
            return
        }

        audioLog.info("Input format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            audioLog.info("Input monitoring started successfully")
        } catch {
            audioLog.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var maxRMS: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = samples[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameLength))
            maxRMS = max(maxRMS, rms)
        }

        let scaledLevel = min(maxRMS * 3.0, 1.0)
        levelCallback(scaledLevel)
    }
}

/// OUTPUT & INPUT DEVICE FUNCTIONS
extension AudioDeviceService {
    func getDevice(source: SourceType) -> AudioDeviceID? {
        func selectorType(_ source: SourceType) -> AudioObjectPropertySelector {
            if source == .Output {
                return kAudioHardwarePropertyDefaultOutputDevice
            } else {
                return kAudioHardwarePropertyDefaultInputDevice
            }
        }
        
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selectorType(source),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &id
        )
        return status == noErr ? id : nil
    }
    
    /// Gets the current balance for a device as a value from -1 (full left) to +1 (full right).
    /// Returns 0 (center) if the device doesn't support stereo or volumes can't be read.
    func getBalance(on id: AudioObjectID) -> Float32 {
        guard let channels = stereoChannels(id: id),
              let leftVol = channelVolume(id: id, channel: channels.left),
              let rightVol = channelVolume(id: id, channel: channels.right)
        else { return 0 }

        let maxVol = max(leftVol, rightVol)
        guard maxVol > 0 else { return 0 }

        // Calculate balance: -1 = full left, 0 = center, +1 = full right
        // When centered, both volumes are equal
        // When panned left, right volume is reduced
        // When panned right, left volume is reduced
        let leftNorm = leftVol / maxVol
        let rightNorm = rightVol / maxVol

        if leftNorm >= rightNorm {
            // Panned left or center: balance is -(1 - rightNorm)
            return rightNorm - 1
        } else {
            // Panned right: balance is (1 - leftNorm)
            return 1 - leftNorm
        }
    }

    /// Sets the balance for a device. Balance ranges from -1 (full left) to +1 (full right).
    /// This adjusts the relative volume between left and right channels while preserving
    /// the overall volume level.
    func setBalance(_ balance: Float32, on id: AudioObjectID) {
        guard let channels = stereoChannels(id: id),
              let leftVol = channelVolume(id: id, channel: channels.left),
              let rightVol = channelVolume(id: id, channel: channels.right)
        else { return }

        let clamped = max(-1, min(balance, 1))

        // Use the maximum of the two channels as the reference volume
        let maxVol = max(leftVol, rightVol)
        guard maxVol > 0 else { return }

        let newLeftVol: Float32
        let newRightVol: Float32

        if clamped <= 0 {
            // Panning left: left stays at max, right is reduced
            newLeftVol = maxVol
            newRightVol = maxVol * (1 + clamped)
        } else {
            // Panning right: right stays at max, left is reduced
            newLeftVol = maxVol * (1 - clamped)
            newRightVol = maxVol
        }

        setChannelVolume(newLeftVol, on: id, for: channels.left)
        setChannelVolume(newRightVol, on: id, for: channels.right)
    }

    func set(to id: AudioDeviceID, selector: AudioObjectPropertySelector) {
        var id = id
        let size = UInt32(MemoryLayout.size(ofValue: id))
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            size,
            &id
        )
        
        /// Immediately update current device state when change initiated by user
        switch selector {
            case kAudioHardwarePropertyDefaultOutputDevice:
                currentOutputDevice = id
            case kAudioHardwarePropertyDefaultInputDevice:
                currentInputDevice = id
            default:
                break
        }
    }
    
    func setVolume(_ volume: Float32, on id: AudioDeviceID) {
        let channels = channelCount(id: id)
        guard channels > 0 else { return }
        
        for channel in 1...channels {
            setChannelVolume(volume, on: id, for: channel)
        }
    }
    
    func volume() -> Float32? {
        guard let id = getDevice(source: .Output) else { return nil }

        let channels = channelCount(id: id)
        guard channels > 0 else { return nil }

        var totalVolume: Float32 = 0
        for channel in 1...channels {
            if let vol = channelVolume(id: id, channel: channel) {
                totalVolume += vol
            }
        }
        return totalVolume / Float32(channels)
    }
    
    func isDeviceMuted(id: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: muted))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyData(
            id, &addr, 0, nil, &size, &muted
        ) == noErr ? (muted != 0) : false
    }
    
    func muteDevice(_ flag: Bool, on id: AudioDeviceID) {
        var muted: UInt32 = flag ? 1 : 0
        let size = UInt32(MemoryLayout.size(ofValue: muted))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(id, &addr, 0, nil, size, &muted)
    }
    
    func startInputMonitoring() {
        guard !isMonitoringInput else { return }
        isMonitoringInput = true

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            createAndStartMonitor()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    if granted {
                        self?.createAndStartMonitor()
                    } else {
                        self?.isMonitoringInput = false
                        audioLog.warning("Microphone access denied by user")
                    }
                }
            }
        case .denied, .restricted:
            isMonitoringInput = false
            audioLog.warning("Microphone access denied or restricted")
        @unknown default:
            isMonitoringInput = false
        }
    }

    private func createAndStartMonitor() {
        inputMonitor = InputLevelMonitor { [weak self] level in
            Task { @MainActor [weak self] in
                self?.inputLevel = level
            }
        }
        inputMonitor?.start()
    }

    func stopInputMonitoring() {
        guard isMonitoringInput else { return }
        isMonitoringInput = false
        inputMonitor?.stop()
        inputMonitor = nil
        inputLevel = 0
    }

    func restartInputMonitoringIfNeeded() {
        guard isMonitoringInput else { return }
        stopInputMonitoring()
        startInputMonitoring()
    }
}
