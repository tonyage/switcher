//
//  DeviceTests.swift
//  switcherTests
//
//  Created by tonyage on 1/6/26.
//

@testable import switcher
import Testing

@Suite
struct DeviceTests {
    @Test("Device types are correctly identified")
    func outputAndInput() {
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

    @Test("Device is Hashable and Identifiable")
    func hashableAndIdentifiable() {
        let device1 = Device(id: 100, name: "Speaker", transport: "USB", isOutput: true, isInput: false)
        let device2 = Device(id: 100, name: "Speaker", transport: "USB", isOutput: true, isInput: false)
        let device3 = Device(id: 200, name: "Speaker", transport: "USB", isOutput: true, isInput: false)

        #expect(device1 == device2)
        #expect(device1 != device3)
        #expect(device1.id == 100)
    }

    @Test("Devices sort by type, then name, with unknown types last")
    func sortedByType() {
        let devices = [
            Device(id: 1, name: "Studio Display", transport: "USB", isOutput: true, isInput: false),
            Device(id: 2, name: "Mystery Box", transport: "-", isOutput: true, isInput: false),
            Device(id: 3, name: "MacBook Speakers", transport: "Built-in", isOutput: true, isInput: false),
            Device(id: 4, name: "AirPods", transport: "Bluetooth", isOutput: true, isInput: false),
            Device(id: 5, name: "Kanto ORA", transport: "USB", isOutput: true, isInput: false),
        ]

        #expect(devices.sortedByType().map(\.id) == [4, 3, 5, 1, 2])
    }
}
