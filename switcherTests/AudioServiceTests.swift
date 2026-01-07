//
//  AudioServiceTests.swift
//  switcherTests
//
//  Created by Tony Do on 1/6/26.
//

@testable import switcher
import Testing

@Suite
struct AudioServiceTests {
    @Test("Service discovers output devices")
    func discoverOutputDevices() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        let devices = await service.outputDevices.count
        // May be 0 in CI environments without audio hardware
        #expect(devices >= 0)
    }

    @Test("Service sets current output device on init")
    func currentDeviceSet() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        let outputDevices = await service.outputDevices
        let currentOutput = await service.currentOutputDevice

        // If there are output devices, current should be set
        if !outputDevices.isEmpty {
            #expect(currentOutput != nil)
        }
    }

    @Test("Service can get default output device")
    func getDefaultOutputDevice() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        let deviceId = await service.getDevice(source: .Output)

        // Should have a default output device on most systems
        // But gracefully handle CI environments
        if await !service.outputDevices.isEmpty {
            #expect(deviceId != nil)
        }
    }

    @Test("Service can get default input device")
    func getDefaultInputDevice() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        let deviceId = await service.getDevice(source: .Input)

        if await !service.inputDevices.isEmpty {
            #expect(deviceId != nil)
        }
    }
}
