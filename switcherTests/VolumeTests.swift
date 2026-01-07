//
//  VolumeTests.swift
//  switcherTests
//
//  Created by Tony Do on 1/6/26.
//

@testable import switcher
import Testing

@Suite
struct VolumeTests {
    @Test("Volume is within valid range 0-1")
    func volumeRange() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        let currentVolume = await service.volume()

        if let volume = currentVolume {
            #expect(volume >= 0.0)
            #expect(volume <= 1.0)
        }
    }
}

@Suite(.serialized)
struct MuteTests {
    @Test("Mute state can be toggled")
    func muteToggle() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        guard let deviceId = await service.getDevice(source: .Output) else {
            return
        }

        let originalMuted = await service.isDeviceMuted(id: deviceId)

        // Toggle mute
        await service.muteDevice(!originalMuted, on: deviceId)
        let newMuted = await service.isDeviceMuted(id: deviceId)
        #expect(newMuted == !originalMuted)

        // Restore original state
        await service.muteDevice(originalMuted, on: deviceId)
    }
}
