//
//  DeviceTests.swift
//  switcherTests
//
//  Created by Tony Do on 1/6/26.
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
}
