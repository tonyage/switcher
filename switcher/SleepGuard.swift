//
//  SleepGuard.swift
//  switcher
//
//  Created by tonyage on 10/18/26.
//

import Foundation
import IOKit.pwr_mgt
import os.log

private let powerLog = Logger(subsystem: "com.tonyage.switcher", category: "power")

/// Settings key for keeping the Mac awake.
let preventSleepKey = "preventSleep"

/// Keeps the Mac from idle sleeping (like `caffeinate -i`) by holding a power
/// assertion. The display may still sleep, and closing the lid or choosing Sleep
/// still works. macOS drops the assertion automatically if switcher quits.
@MainActor
enum SleepGuard {
    private static var assertionID: IOPMAssertionID?

    static var isActive: Bool { assertionID != nil }

    /// Applies the saved setting; call once at launch.
    static func restore(from defaults: UserDefaults = .standard) {
        setEnabled(defaults.bool(forKey: preventSleepKey))
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            guard assertionID == nil else { return }
            var id = IOPMAssertionID(0)
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "switcher: Prevent sleep is turned on in Settings" as CFString,
                &id
            )
            if status == kIOReturnSuccess {
                assertionID = id
            } else {
                powerLog.error("Couldn't prevent sleep (\(status))")
            }
        } else if let id = assertionID {
            IOPMAssertionRelease(id)
            assertionID = nil
        }
    }
}
