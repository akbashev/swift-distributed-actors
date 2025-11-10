//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2025 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NewDistributedCluster
import Testing

struct FirstTest {

    distributed actor Demo {
        var value = 0

        distributed func recieve(from another: Demo) async throws -> Int {
            try await another.getCurrent()
        }

        distributed func testVoid() {
            ()
        }

        distributed func getCurrent() -> Int {
            defer { self.value += 1 }
            return self.value
        }
    }

    @Test
    func remote() async throws {
        let nodeA = Cluster.Endpoint(host: "127.0.0.1", port: 2550)
        let nodeB = Cluster.Endpoint(host: "127.0.0.1", port: 2551)
        let clusterA = try await ClusterSystem(
            settings: .init(endpoint: nodeA)
        )
        let clusterB = try await ClusterSystem(
            settings: .init(endpoint: nodeB)
        )

        try await clusterA.join(clusterB.endpoint)
        try await Task.sleep(for: .seconds(1.0))

        let demo1 = Demo(actorSystem: clusterA)
        let demo2 = Demo(actorSystem: clusterB)

        #expect(!__isRemoteActor(demo1))
        #expect(!__isRemoteActor(demo2))

        let demo1Remote = try Demo.resolve(id: demo1.id, using: clusterB)
        let demo2Remote = try Demo.resolve(id: demo2.id, using: clusterA)

        // Should be remote
        #expect(__isRemoteActor(demo1Remote))
        #expect(__isRemoteActor(demo2Remote))

        try await demo1Remote.testVoid()
        try await demo2Remote.testVoid()

        // 0
        var value1 = try await demo1Remote.recieve(from: demo2Remote)
        #expect(value1 == 0)
        var value2 = try await demo2Remote.recieve(from: demo1Remote)
        #expect(value2 == 0)
        // 1
        value1 = try await demo1Remote.recieve(from: demo2Remote)
        #expect(value1 == 1)
        value2 = try await demo2Remote.recieve(from: demo1Remote)
        #expect(value2 == 1)
    }
}
