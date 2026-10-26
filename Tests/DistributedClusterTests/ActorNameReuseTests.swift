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
import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

distributed actor NamedGreeter {
    typealias ActorSystem = ClusterSystem

    distributed func greet() -> String {
        "Hello"
    }
}

final class ActorNameReuseTests: SingleClusterSystemXCTestCase {
    private func named(_ name: String) -> _Props {
        var props = _Props()
        props._knownActorName = name
        return props
    }

    func test_actorWithAName_endedNow_leavesTheNameFree() async throws {
        for index in 0..<20 {
            var ended: NamedGreeter? = _Props.$forSpawn.withValue(self.named("greeter-\(index)")) {
                NamedGreeter(actorSystem: self.system)
            }
            try await ended!.greet().shouldEqual("Hello")
            ended = nil

            // Its name is free as soon as it has ended, not once it has finished stopping.
            let next: _ActorRef<String> = try self.system._spawn(
                .unique("greeter-\(index)"),
                _Behavior.receiveMessage { _ in .same }
            )
            next.id.path.name.shouldEqual("greeter-\(index)")
        }
    }
}
