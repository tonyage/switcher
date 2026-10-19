//
//  SleepGuardTests.swift
//  switcherTests
//
//  Created by tonyage on 10/18/26.
//

import Foundation
import IOKit.pwr_mgt
@testable import switcher
import Testing

@Suite(.serialized)
@MainActor
struct SleepGuardTests {
    /// Whether this process currently holds a prevent-idle-sleep assertion.
    private func holdsAssertion() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return false }
        let mine = byProcess[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []
        return mine.contains {
            $0[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleSystemSleep
        }
    }

    @Test("Enabling holds a sleep assertion and disabling releases it")
    func toggle() {
        SleepGuard.setEnabled(true)
        #expect(SleepGuard.isActive)
        #expect(holdsAssertion())

        // Enabling twice doesn't stack a second assertion.
        SleepGuard.setEnabled(true)
        SleepGuard.setEnabled(false)
        #expect(!SleepGuard.isActive)
        #expect(!holdsAssertion())
    }

    @Test("Restores the saved setting")
    func restore() {
        let name = "switcher.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: preventSleepKey)
        SleepGuard.restore(from: defaults)
        #expect(SleepGuard.isActive)

        defaults.set(false, forKey: preventSleepKey)
        SleepGuard.restore(from: defaults)
        #expect(!SleepGuard.isActive)
    }
}
