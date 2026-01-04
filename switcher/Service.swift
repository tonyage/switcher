//
//  Service.swift
//  switcher
//
//  Created by Tony Do on 7/16/25.
//

@preconcurrency import Combine
import CoreAudio
import CoreAudio.AudioHardware

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
    
    private let listener: AudioHardwareListener

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
            default:
                return "-"
            }
        }
        
        let hasOutput = hasStream(id, scope: kAudioDevicePropertyScopeOutput)
        let hasInput = hasStream(id, scope: kAudioDevicePropertyScopeInput)
        guard hasInput || hasOutput else { return nil }
        
        return Device(
            id: id,
            name: string(kAudioDevicePropertyDeviceNameCFString),
            transport: string(kAudioDevicePropertyTransportType),
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
    
    /// TODO: might cull this entirely and ignore handling for devices that support
    /// surround sound.
    private func channelLayout(id: AudioObjectID) -> AudioChannelLayout? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelLayout,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            id,
            &address,
            0,
            nil,
            &size
        ) == noErr else { return nil }
        
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioChannelLayout>.alignment
        )
        
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(
            id,
            &address,
            0,
            nil,
            &size,
            ptr
        ) == noErr else { return nil }
        return ptr.assumingMemoryBound(to: AudioChannelLayout.self).pointee
    }
    
    private func frontChannels(layout: AudioChannelLayout) -> (left: UInt32?, right: UInt32?)? {
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
        return (left, right)
    }
    
    private func channelVolumes(id: AudioObjectID) -> [UInt32: Float32] {
        var volumes: [UInt32: Float32] = [:]
        
        let channelCount = channelCount(id: id)
        for channel in 1...channelCount {
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout.size(ofValue: volume))
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            let res = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &volume)
            
            if res == noErr { volumes[channel] = volume }
        }
        return volumes
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
        
        let devices = deviceIDs.compactMap { id -> Device? in
            guard let device = deviceInfo(for: id) else { return nil }
            return device
        }
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
                self.currentDevices()
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
    
    func setBalance(_ balance: Float32, on id: AudioObjectID) {
        guard
            let layout = channelLayout(id: id),
            let frontChannels = frontChannels(layout: layout),
            let leftChannel = frontChannels.left,
            let rightChannel = frontChannels.right
        else { return }
        
        let volumes = channelVolumes(id: id)
        
        guard
            let leftBase = volumes[leftChannel],
            let rightBase = volumes[rightChannel]
        else { return }
        
        let clamped = max(-1, min(balance, 1))
        let leftVol: Float32
        let rightVol: Float32
        
        if clamped < 0 {
            leftVol = leftBase
            rightVol = rightBase * (1 + clamped)
        } else {
            leftVol = leftBase * (1 - clamped)
            rightVol = rightBase
        }
        
        setChannelVolume(leftVol, on: id, for: leftChannel)
        setChannelVolume(rightVol, on: id, for: rightChannel)
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
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout.size(ofValue: volume))
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            let res = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &volume)
            
            if res == noErr { totalVolume += volume }
        }
        return totalVolume / Float32(channels)
    }
    
    func isDeviceMuted(id: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        let size = UInt32(MemoryLayout.size(ofValue: muted))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectSetPropertyData(
            id, &addr, 0, nil, size, &muted
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
    
    func rms(from buffer: UnsafePointer<Float32>, count: Int) -> Float32 {
        var sum: Float32 = 0
        for i in 0..<count {
            sum += buffer[i] * buffer[i]
        }
        return sqrt(sum / Float(count))
    }
    
    func inputGain(deviceID: AudioDeviceID) -> Float32? {
        var gain: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        return AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &gain
        ) == noErr ? gain : nil
    }
}
