//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import Foundation
import Testing

@testable import DistributedCluster

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private let NANOS = 1_000_000_000

struct TimeSpecTests {
    let nanosDuration: Duration = .nanoseconds(100)
    let secondsDuration: Duration = .seconds(2)
    var totalDuration: Duration {
        self.secondsDuration + self.nanosDuration
    }

    var nanos: TimeSpec {
        .from(duration: self.nanosDuration)
    }

    var seconds: TimeSpec {
        .from(duration: self.secondsDuration)
    }

    var total: TimeSpec {
        .from(duration: self.totalDuration)
    }

    @Test
    func test_timeSpecShouldBeCreatedProperlyFromDuration() {
        self.total.toNanos().shouldEqual(Int64(self.totalDuration.nanoseconds))
        self.total.tv_sec.shouldEqual(Int(self.totalDuration.nanoseconds) / NANOS)
        self.total.tv_nsec.shouldEqual(Int(self.totalDuration.nanoseconds) % NANOS)
    }

    @Test
    func test_timeSpecAdd() {
        let sum = self.nanos + self.seconds

        sum.shouldEqual(self.total)
    }

    @Test
    func test_lessThan() {
        #expect(self.nanos < self.seconds)
    }

    @Test
    func test_greaterThan() {
        #expect(self.seconds > self.nanos)
    }

    @Test
    func test_equals() {
        #expect(self.nanos == self.nanos)
        #expect(self.seconds == self.seconds)
        #expect(self.total == self.total)
    }
}

extension TimeSpec: @retroactive Comparable {
    public static func < (lhs: TimeSpec, rhs: TimeSpec) -> Bool {
        lhs.tv_sec < rhs.tv_sec || (lhs.tv_sec == rhs.tv_sec && lhs.tv_nsec < rhs.tv_nsec)
    }

    public static func == (lhs: TimeSpec, rhs: TimeSpec) -> Bool {
        lhs.tv_sec == rhs.tv_sec && lhs.tv_nsec == lhs.tv_nsec
    }
}
