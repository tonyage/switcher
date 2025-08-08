//
//  switcherTests.swift
//  switcherTests
//
//  Created by Tony Do on 7/14/25.
//

@testable import switcher
import Combine
import CoreAudio
import Testing

#if TESTING
@_cdecl("AudioObjectSetPropertyData")
func AudioObjectSetPropertyData(
    _ objectID: AudioObjectID,
    _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ inDataSize: UInt32,
    _ inData: UnsafeRawPointer?
) -> OSStatus { OSStatus(0) }
#endif

@Suite
struct DeviceTypeTests {
    @Test("Device types are correctly identified")
    func outputAndInput() async throws {
        let outputDevice = Device(
            id: 0,
            name: "USB AMP",
            transport: "USB",
            isOutput: true,
            isInput: false
        )
        
        let inputDevice = Device(
            id: 1,
            name: "USB Microphone",
            transport: "USB",
            isOutput: true,
            isInput: true
        )
        
        #expect(outputDevice.isOutput)
        #expect(!outputDevice.isInput)
        #expect(inputDevice.isOutput)
        #expect(inputDevice.isInput)
    }
}

@Suite
struct AudioHardwareListenerPlumbingTests {
    @Test("poll() is called when HAL event fires")
    func polling() async throws {
        let service = await AudioDeviceService(
            listener: AudioHardwareListener()
        )
        
        let devices = await service.outputDevices.count
        #expect(devices >= 1)
    }
}

@Suite
struct OutputTests {
    @Test("set master volume of first output device")
    func setMasterVolume() async throws {
        let service = await AudioDeviceService(
            listener: AudioHardwareListener()
        )
        
        let id = await service.getDevice(source: .Output)
        let currentVolume = await service.masterVolume()
        await service.setMasterVolume(1.0, on: id.unsafelyUnwrapped)
        let newVolume = await service.masterVolume()
        
        #expect(currentVolume.unsafelyUnwrapped == newVolume.unsafelyUnwrapped)
    }
    
    @Test("check that first output device is not muted")
    func isMuted() async throws {
        let service = await AudioDeviceService(
            listener: AudioHardwareListener()
        )
        
        let id = await service.getDevice(source: .Output)
        let isMuted = await service.isDeviceMuted(id: id.unsafelyUnwrapped)
        #expect(!isMuted.unsafelyUnwrapped)
    }
}
