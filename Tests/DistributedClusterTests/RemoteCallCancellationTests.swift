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

/// Waits as long as it's asked to, and says whether its wait was cancelled.
private distributed actor RemoteWaiter {
    typealias ActorSystem = ClusterSystem

    private var cancelled = false

    distributed func wait(seconds: Int) async {
        do {
            try await Task.sleep(for: .seconds(seconds))
        } catch {
            cancelled = true
        }
    }

    distributed func waitFor(seconds: Int) async -> Bool {
        await wait(seconds: seconds)
        return cancelled
    }

    distributed var wasCancelled: Bool { cancelled }
}

final class RemoteCallCancellationTests: ClusteredActorSystemsXCTestCase {
    /// A call to an actor on another node: its caller's cancellation is sent to that node, which
    /// cancels the call there, and the caller gets the call's reply, as from a local call.
    func test_remoteCall_cancelledCaller_cancelsTheCallOnItsNode() async throws {
        let local = await setUpNode("local")
        let remote = await setUpNode("remote")
        local.cluster.join(endpoint: remote.cluster.endpoint)
        try await self.ensureNodes(.up, nodes: local.cluster.node, remote.cluster.node)

        let waiter = RemoteWaiter(actorSystem: remote)
        let reached = try RemoteWaiter.resolve(id: waiter.id, using: local)

        let started = ContinuousClock.now
        let call = Task { await (try? reached.waitFor(seconds: 60)) ?? false }
        try await Task.sleep(for: .milliseconds(500))
        call.cancel()

        let cancelled = await call.value
        cancelled.shouldBeTrue()
        (ContinuousClock.now - started < .seconds(10)).shouldBeTrue()
    }

    /// The same for a call that returns nothing.
    func test_remoteCallVoid_cancelledCaller_cancelsTheCallOnItsNode() async throws {
        let local = await setUpNode("local")
        let remote = await setUpNode("remote")
        local.cluster.join(endpoint: remote.cluster.endpoint)
        try await self.ensureNodes(.up, nodes: local.cluster.node, remote.cluster.node)

        let waiter = RemoteWaiter(actorSystem: remote)
        let reached = try RemoteWaiter.resolve(id: waiter.id, using: local)

        let started = ContinuousClock.now
        let call = Task { try? await reached.wait(seconds: 60) }
        try await Task.sleep(for: .milliseconds(500))
        call.cancel()
        await call.value

        (ContinuousClock.now - started < .seconds(10)).shouldBeTrue()
        try await waiter.wasCancelled.shouldBeTrue()
    }
}
