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
private distributed actor Waiter {
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

/// Forwards every call to the actor with `target`'s ID, as a virtual actor's reference does.
private struct ForwardingInterceptor: RemoteCallInterceptor {
    let target: ClusterSystem.ActorID

    func interceptRemoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout ClusterSystem.InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: Codable {
        try await (actor.actorSystem as! ClusterSystem).forwardCall(
            to: self.target,
            as: Act.self,
            target: target,
            invocation: &invocation,
            throwing: throwing,
            returning: returning
        )
    }

    func interceptRemoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout ClusterSystem.InvocationEncoder,
        throwing: Err.Type
    ) async throws where Act: DistributedActor, Act.ID == ActorID, Err: Error {
        try await (actor.actorSystem as! ClusterSystem).forwardCallVoid(
            to: self.target,
            as: Act.self,
            target: target,
            invocation: &invocation,
            throwing: throwing
        )
    }
}

final class LocalCallCancellationTests: SingleClusterSystemXCTestCase {
    /// A call forwarded to an actor on the same node is a local call: its caller's cancellation
    /// reaches it, as it reaches any call the caller awaits.
    func test_localCall_cancelledCaller_cancelsTheCall() async throws {
        let waiter = Waiter(actorSystem: system)
        let forwarded: Waiter = try system.interceptCalls(
            to: Waiter.self,
            metadata: ActorMetadata(),
            interceptor: ForwardingInterceptor(target: waiter.id)
        )

        let started = ContinuousClock.now
        let call = Task { await (try? forwarded.waitFor(seconds: 60)) ?? false }
        try await Task.sleep(for: .milliseconds(200))
        call.cancel()

        let cancelled = await call.value
        cancelled.shouldBeTrue()
        (ContinuousClock.now - started < .seconds(10)).shouldBeTrue()
    }

    /// The same for a call that returns nothing.
    func test_localCallVoid_cancelledCaller_cancelsTheCall() async throws {
        let waiter = Waiter(actorSystem: system)
        let forwarded: Waiter = try system.interceptCalls(
            to: Waiter.self,
            metadata: ActorMetadata(),
            interceptor: ForwardingInterceptor(target: waiter.id)
        )

        let started = ContinuousClock.now
        let call = Task { try? await forwarded.wait(seconds: 60) }
        try await Task.sleep(for: .milliseconds(200))
        call.cancel()
        await call.value

        (ContinuousClock.now - started < .seconds(10)).shouldBeTrue()
        try await waiter.wasCancelled.shouldBeTrue()
    }
}
