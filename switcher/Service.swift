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
final class AudioDeviceService: ObservableObject {
    @Published private(set) var outputDevices: [Device] = []
    @Published private(set) var inputDevices: [Device] = []
    
    private let listener: AudioHardwareListener
    private var cancellable: AnyCancellable?

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
    
    private func hasStream(
        _ id: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Bool {
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

    private func poll() {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioClassID(kAudioObjectSystemObject),
            &listener.address,
            0,
            nil,
            &size
        ) == noErr else { return }
        
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        
        guard AudioObjectGetPropertyData(
            AudioClassID(kAudioObjectSystemObject),
            &listener.address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else { return }
        
        let devices = deviceIDs.compactMap { id -> Device? in
            guard let device = deviceInfo(for: id) else { return nil }
            return device
        }
        outputDevices = devices.filter {
            $0.isOutput && !$0.isInput
        }
        inputDevices = devices.filter(\.isInput)
    }
    
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

    func set(to id: AudioDeviceID, selector: AudioObjectPropertySelector) {
        var id = id
        let size = UInt32(MemoryLayout.size(ofValue: id))
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        _ = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            size,
            &id
        )
    }
    
    init(listener: AudioHardwareListener = .init()) {
        self.listener = listener
        poll()
        cancellable = listener.publisher.receive(on: RunLoop.main).sink {
            [weak self] in self?.poll()
        }
    }
    
    deinit { cancellable?.cancel() }
}

// OUTPUT DEVICE FUNCTIONS
extension AudioDeviceService {
    func setMasterVolume(_ volume: Double, on id: AudioDeviceID) {
        var volume = Float32(max(0, min(1, volume)))
        let size = UInt32(MemoryLayout.size(ofValue: volume))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &volume)
    }
    
    func masterVolume() -> Double? {
        guard let id = getDevice(source: .Output) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: volume))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let res = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &volume)
        return res == noErr ? Double(volume) : nil
    }
    
    func isDeviceMuted(id: AudioDeviceID) -> Bool? {
        var muted: UInt32 = 0
        let size = UInt32(MemoryLayout.size(ofValue: muted))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectSetPropertyData(
            id, &addr, 0, nil, size, &muted
        ) == noErr ? (muted != 0) : nil
    }
    
    func muteDevice(_ flag: Bool, on id: AudioDeviceID) {
        var muted: UInt32 = flag ? 1 : 0
        let size = UInt32(MemoryLayout.size(ofValue: muted))
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &muted)
    }
}
