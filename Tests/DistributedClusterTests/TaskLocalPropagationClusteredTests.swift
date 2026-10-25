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
import Foundation
import XCTest

@testable import DistributedCluster

private enum Traveling {
    @TaskLocal static var request: String?
    @TaskLocal static var undeclared: String?
}

distributed actor TaskLocalReader {
    typealias ActorSystem = ClusterSystem

    /// The task-locals this call runs with.
    distributed func read() -> [String?] {
        [Traveling.request, Traveling.undeclared]
    }

    /// What `other` reads, called from here.
    distributed func read(through other: TaskLocalReader) async throws -> [String?] {
        try await other.read()
    }
}

final class TaskLocalPropagationClusteredTests: ClusteredActorSystemsXCTestCase {
    private func declaring(_ settings: inout ClusterSystemSettings) {
        settings.propagateTaskLocal(Traveling.$request, as: "test.request")
    }

    func test_remoteCall_runsWithTheDeclaredTaskLocalsItWasMadeWith() async throws {
        let (first, second) = await self.setUpPair(self.declaring)
        try await self.joinNodes(node: first, with: second)
        let reader = TaskLocalReader(actorSystem: second)
        let remote = try TaskLocalReader.resolve(id: reader.id, using: first)

        let seen = try await Traveling.$request.withValue("ann") {
            try await Traveling.$undeclared.withValue("bob") {
                try await remote.read()
            }
        }

        XCTAssertEqual(seen, ["ann", nil])
    }

    func test_remoteCall_madeFromARemoteCall_carriesTheTaskLocalsOn() async throws {
        let (first, second) = await self.setUpPair(self.declaring)
        try await self.joinNodes(node: first, with: second)
        let onFirst = TaskLocalReader(actorSystem: first)
        let reader = TaskLocalReader(actorSystem: second)
        let onSecond = try TaskLocalReader.resolve(id: reader.id, using: first)

        // first → second → first
        let seen = try await Traveling.$request.withValue("ann") {
            try await onSecond.read(through: onFirst)
        }

        XCTAssertEqual(seen, ["ann", nil])
    }

    func test_remoteCall_withNoTaskLocalSet_runsWithNone() async throws {
        let (first, second) = await self.setUpPair(self.declaring)
        try await self.joinNodes(node: first, with: second)
        let reader = TaskLocalReader(actorSystem: second)
        let remote = try TaskLocalReader.resolve(id: reader.id, using: first)

        let seen = try await remote.read()

        XCTAssertEqual(seen, [nil, nil])
    }

    func test_remoteCall_toANodeNotDeclaringTheTaskLocal_runsWithout() async throws {
        let first = await self.setUpNode("first", self.declaring)
        let second = await self.setUpNode("second")
        try await self.joinNodes(node: first, with: second)
        let reader = TaskLocalReader(actorSystem: second)
        let remote = try TaskLocalReader.resolve(id: reader.id, using: first)

        let seen = try await Traveling.$request.withValue("ann") {
            try await remote.read()
        }

        XCTAssertEqual(seen, [nil, nil])
    }

    func test_localCall_runsWithAllTheCallersTaskLocals() async throws {
        let system = await self.setUpNode("local", self.declaring)
        let reader = TaskLocalReader(actorSystem: system)

        let seen = try await Traveling.$request.withValue("ann") {
            try await Traveling.$undeclared.withValue("bob") {
                try await reader.read()
            }
        }

        XCTAssertEqual(seen, ["ann", "bob"])
    }

    func test_invocationMessage_fromANodeNotSendingTaskLocals_decodesWithNone() throws {
        let message = InvocationMessage(
            callID: UUID(),
            targetIdentifier: "target",
            genericSubstitutions: [],
            arguments: [],
            taskLocals: ["test.request": Data()]
        )
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        fields["taskLocals"] = nil

        let decoded = try JSONDecoder().decode(InvocationMessage.self, from: JSONSerialization.data(withJSONObject: fields))

        XCTAssertEqual(decoded.taskLocals, [:])
        XCTAssertEqual(decoded.targetIdentifier, "target")
    }
}
