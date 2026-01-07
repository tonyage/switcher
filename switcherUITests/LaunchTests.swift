//
//  LaunchTests.swift
//  switcherUITests
//
//  Created by Tony Do on 1/6/26.
//

import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        // Menu bar apps run in background state, not foreground
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
