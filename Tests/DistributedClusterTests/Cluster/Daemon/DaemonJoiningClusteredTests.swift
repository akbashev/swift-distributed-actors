//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the Swift Distributed Actors project authors
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
import Testing

@testable import DistributedCluster

@Suite(.timeLimit(.minutes(1)), .serialized)
struct DaemonJoiningClusteredTests {
    let testCase: ClusteredActorSystemsTestCase
    var daemon: ClusterDaemon?

    init() throws {
        let testCase = try ClusteredActorSystemsTestCase()
        testCase.configureLogCapture = { settings in
            settings.excludeActorPaths = [
                "/system/cluster/swim",
                "/system/cluster/gossip",
                "/system/replicator",
                "/system/cluster",
                "/system/clusterEvents",
                "/system/cluster/leadership",
                "/system/nodeDeathWatcher",

                "/dead/system/receptionist-ref",  // FIXME(distributed): it should simply be quiet
            ]
            settings.excludeGrep = [
                "timer"
            ]
        }
        self.testCase = testCase
    }

    @Test
    mutating func test_shouldPerformLikeASeedNode() async throws {
        self.daemon = await ClusterSystem.startClusterDaemon()
        let first = await self.testCase.setUpNode("first") { settings in
            settings.discovery = .clusterd
        }
        let second = await self.testCase.setUpNode("second") { settings in
            settings.discovery = .clusterd
        }
        try await self.testCase.ensureNodes(atLeast: .up, nodes: [first.cluster.node, second.cluster.node])

        // Manual tear down since we need to shut down the daemon:
        try await self.daemon?.shutdown().wait()
    }
}
