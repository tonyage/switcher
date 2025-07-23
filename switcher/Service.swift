//
//  Service.swift
//  switcher
//
//  Created by Tony Do on 7/16/25.
//

import Combine
import CoreAudio

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
        func string(_ selector: AudioObjectPropertySelector) -> String? {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            if selector != kAudioDevicePropertyTransportType {
                var unmanaged: Unmanaged<CFString>?
                var size = UInt32(MemoryLayout.size(ofValue: unmanaged))
                let result = withUnsafeMutablePointer(
                    to: &unmanaged
                ) { ptr -> OSStatus in
                    AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
                }
                guard result == noErr, let str =
                        unmanaged?.takeRetainedValue() else { return nil }
                return str as String
            }

            var type: UInt32 = 0
            var size = UInt32(MemoryLayout.size(ofValue: type))
            
            guard AudioObjectGetPropertyData(
                id, &address, 0, nil, &size, &type
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
        
        let name = string(kAudioDevicePropertyDeviceNameCFString) ?? "Unknown"
        let transport = string(kAudioDevicePropertyTransportType) ?? "-"
        
        return Device(
            id: id,
            name: name,
            transport: transport,
            isOutput: hasOutput,
            isInput: hasInput
        )
    }
    
    private func hasStream(
        _ id: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            id, &address, 0, nil, &size
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

    init(listener: AudioHardwareListener = .init()) {
        self.listener = listener
        poll()
        cancellable = listener.publisher.receive(on: RunLoop.main).sink {
            [weak self] in self?.poll()
        }
    }
    
    deinit { cancellable?.cancel() }
}

extension AudioDeviceService {
    func set(to id: AudioDeviceID, selector: AudioObjectPropertySelector) {
        var id = id
        let size = UInt32(MemoryLayout.size(ofValue: id))
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &id
        )
    }
}
