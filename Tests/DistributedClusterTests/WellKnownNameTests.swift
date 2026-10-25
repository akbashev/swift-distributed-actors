//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Distributed
import DistributedActorsConcurrencyHelpers
import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

distributed actor WellKnownNamed {
    typealias ActorSystem = ClusterSystem

    distributed func greet() -> String {
        "Hello"
    }
}

final class WellKnownNameTests: SingleClusterSystemXCTestCase {
    private func wellKnown(_ name: String) -> _Props {
        var props = _Props()
        props._knownActorName = name
        props._wellKnownName = name
        return props
    }

    /// How many ids are reserved under each of `names`.
    private func reserved(_ names: [String]) -> [Int] {
        self.system.namingLock.withLock {
            names.map { name in self.system._reservedNames.filter { $0.path.name == name }.count }
        }
    }

    func test_wellKnownActor_startedAgainAfterItEnded_keepsNamesApart() async throws {
        let names = (0..<50).map { "named-\($0)" }
        var first: [WellKnownNamed]? = names.map { name in
            _Props.$forSpawn.withValue(self.wellKnown(name)) { WellKnownNamed(actorSystem: self.system) }
        }
        for actor in first! { self.system.releaseWellKnownActorID(actor.id) }
        first = nil
        // An actor that ended holds its name no longer.
        self.reserved(names).shouldEqual(Array(repeating: 0, count: names.count))

        let second = names.map { name in
            _Props.$forSpawn.withValue(self.wellKnown(name)) { WellKnownNamed(actorSystem: self.system) }
        }
        self.reserved(names).shouldEqual(Array(repeating: 1, count: names.count))
        let greeting = try await second[0].greet()
        greeting.shouldEqual("Hello")
    }
}
