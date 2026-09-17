//
//  VolumeBalanceTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Guards that a volume write on a device without a master element keeps
//  the user's L/R balance instead of flattening both channels.
//

import XCTest
@testable import boringNotch

final class VolumeBalanceTests: XCTestCase {

    func testPreservesChannelRatio() {
        let levels = VolumeManager.balancedLevels(target: 0.8, current: [0.5, 1.0])
        XCTAssertEqual(levels[0], 0.4, accuracy: 0.0001)
        XCTAssertEqual(levels[1], 0.8, accuracy: 0.0001)
    }

    func testSilentDeviceFallsBackToUniform() {
        XCTAssertEqual(VolumeManager.balancedLevels(target: 0.6, current: [0, 0]), [0.6, 0.6])
    }

    func testClampsToUnitRange() {
        let levels = VolumeManager.balancedLevels(target: 2, current: [0.25, 0.5])
        XCTAssertEqual(levels, [1, 1])
    }
}
