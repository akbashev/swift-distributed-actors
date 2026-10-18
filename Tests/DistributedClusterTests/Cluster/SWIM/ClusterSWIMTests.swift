//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import ClusterMembership
import DistributedActorsTestKit
import SWIM
import SWIMDistributed
import XCTest

@testable import DistributedCluster

/// Tests how the cluster hosts its SWIM failure detector.
///
/// SWIM itself is tested in swift-cluster-membership.
final class ClusterSWIMTests: ClusteredActorSystemsXCTestCase {
    override func configureLogCapture(settings: inout LogCapture.Settings) {
        settings.filterActorPaths = ["/user/swim"]
    }

    func test_SWIM_shouldMonitorJoinedClusterMembers() async throws {
        let localNode = await self.setUpNode("local")
        let remoteNode = await self.setUpNode("remote")

        localNode.cluster.join(endpoint: remoteNode.cluster.endpoint)
        try assertAssociated(localNode, withExactly: remoteNode.cluster.node)

        try await self.awaitAlive(remoteNode.cluster.node, onSWIMOf: localNode)
        try await self.awaitAlive(localNode.cluster.node, onSWIMOf: remoteNode)
    }

    private func awaitAlive(_ node: Cluster.Node, onSWIMOf system: ClusterSystem) async throws {
        guard let swim = system._cluster?._swimShell else {
            throw testKit(system).fail("SWIM of [\(system)] should not be nil")
        }

        let testKit = self.testKit(system)
        try await testKit.eventually(within: .seconds(3)) {
            let members = await swim.whenLocal { $0.members } ?? []
            let status = members.first(where: { $0.node == node.asSWIMNode })?.status
            guard status?.isAlive == true else {
                throw testKit.error("Expected [\(node)] to be alive on SWIM of [\(system)], was: \(String(describing: status))")
            }
        }
    }
}
