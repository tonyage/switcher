//
//  BalanceTests.swift
//  switcherTests
//
//  Created by Tony Do on 1/6/26.
//

@testable import switcher
import Testing

@Suite(.serialized)
struct BalanceTests {
    @Test("Balance is within valid range -1 to 1")
    func balanceRange() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        guard let deviceId = await service.getDevice(source: .Output) else {
            return // Skip if no output device
        }

        let balance = await service.getBalance(on: deviceId)
        #expect(balance >= -1.0)
        #expect(balance <= 1.0)
    }

    @Test("Setting balance to center (0) results in balanced output")
    func setCenterBalance() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        guard let deviceId = await service.getDevice(source: .Output) else {
            return
        }

        await service.setBalance(0, on: deviceId)
        let balance = await service.getBalance(on: deviceId)

        #expect(abs(balance) < 0.01)
    }

    @Test("Setting balance to full left (-1)")
    func setLeftBalance() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        guard let deviceId = await service.getDevice(source: .Output) else {
            return
        }

        let originalBalance = await service.getBalance(on: deviceId)

        await service.setBalance(-1, on: deviceId)
        let balance = await service.getBalance(on: deviceId)
        #expect(balance < -0.9)

        await service.setBalance(originalBalance, on: deviceId)
    }

    @Test("Setting balance to full right (+1)")
    func setRightBalance() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        guard let deviceId = await service.getDevice(source: .Output) else {
            return
        }

        let originalBalance = await service.getBalance(on: deviceId)

        await service.setBalance(1, on: deviceId)
        let balance = await service.getBalance(on: deviceId)
        #expect(balance > 0.9)

        await service.setBalance(originalBalance, on: deviceId)
    }

    @Test("Balance values are clamped to valid range")
    func balanceClamping() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        guard let deviceId = await service.getDevice(source: .Output) else {
            return
        }

        let originalBalance = await service.getBalance(on: deviceId)

        // Try setting out-of-range values
        await service.setBalance(-5, on: deviceId)
        var balance = await service.getBalance(on: deviceId)
        #expect(balance >= -1.0)

        await service.setBalance(5, on: deviceId)
        balance = await service.getBalance(on: deviceId)
        #expect(balance <= 1.0)

        await service.setBalance(originalBalance, on: deviceId)
    }

    @Test("Balance round-trip preserves value")
    func balanceRoundTrip() async throws {
        let service = await AudioDeviceService(listener: AudioHardwareListener())
        guard let deviceId = await service.getDevice(source: .Output) else {
            return
        }

        let originalBalance = await service.getBalance(on: deviceId)

        let testValues: [Float32] = [-0.5, -0.25, 0, 0.25, 0.5]
        for testValue in testValues {
            await service.setBalance(testValue, on: deviceId)
            let readBack = await service.getBalance(on: deviceId)
            #expect(abs(readBack - testValue) < 0.05, "Balance \(testValue) round-trip failed, got \(readBack)")
        }

        await service.setBalance(originalBalance, on: deviceId)
    }
}
