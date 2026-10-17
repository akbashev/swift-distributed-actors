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

/// An actor is resolved and called only as its own type, or through a protocol it conforms to:
/// any other type would run that type's methods on it.
final class ResolveTypeTests: ClusteredActorSystemsXCTestCase {
    func test_resolve_localActorAsAnotherType_throws() async throws {
        let system = await setUpNode("local")
        let speaker = Speaker(actorSystem: system)

        let error = try shouldThrow {
            _ = try Counter.resolve(id: speaker.id, using: system)
        }
        guard let error = error as? ResolveError, "\(error)".contains("typeMismatch") else {
            throw TestError("Expected a ResolveError for the type mismatch, got \(error)")
        }
    }

    func test_resolve_localActorThroughItsProtocol_reachesIt() async throws {
        let system = await setUpNode("local")
        let speaker = Speaker(actorSystem: system)

        let speaking = try $Speaking.resolve(id: speaker.id, using: system)
        let said = try await speaking.say()
        said.shouldEqual("hello")
    }

    func test_remoteCall_throughAnotherType_failsRightAway() async throws {
        let local = await setUpNode("local")
        let remote = await setUpNode("remote")
        local.cluster.join(endpoint: remote.cluster.endpoint)
        try await self.ensureNodes(.up, nodes: local.cluster.node, remote.cluster.node)

        let speaker = Speaker(actorSystem: local)
        let wrong = try Counter.resolve(id: speaker.id, using: remote)

        let started = ContinuousClock.now
        let error = try await shouldThrow {
            _ = try await wrong.count()
        }
        guard !(error is RemoteCallError) else {
            throw TestError("Expected the recipient to refuse the call, not a timeout: \(error)")
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2))
    }

    func test_remoteCall_throughItsProtocol_reachesIt() async throws {
        let local = await setUpNode("local")
        let remote = await setUpNode("remote")
        local.cluster.join(endpoint: remote.cluster.endpoint)
        try await self.ensureNodes(.up, nodes: local.cluster.node, remote.cluster.node)

        let speaker = Speaker(actorSystem: local)
        let speaking = try $Speaking.resolve(id: speaker.id, using: remote)
        let said = try await speaking.say()
        said.shouldEqual("hello")
    }

    /// A node that doesn't send what a call was made through yet still reaches newer nodes.
    func test_invocation_withoutRecipient_decodes() async throws {
        let system = await setUpNode("local")
        let made = InvocationMessage(
            callID: UUID(),
            targetIdentifier: "target",
            recipient: .protocolStub,
            genericSubstitutions: [],
            arguments: []
        )
        let manifest = try system.serialization.serialize(made).manifest
        let json = #"{"callID":"\#(made.callID.uuidString)","targetIdentifier":"target","genericSubstitutions":[],"arguments":[]}"#

        let decoded = try system.serialization.deserialize(
            as: InvocationMessage.self,
            from: Serialization.Serialized(manifest: manifest, buffer: .data(Data(json.utf8)))
        )
        decoded.callID.shouldEqual(made.callID)
        decoded.recipient.shouldBeNil()
    }

    /// A call forwarded through an interceptor runs only on an actor of the type of the reference
    /// it was made on, as a call made any other way does.
    func test_forwardedCall_toAnotherType_throws() async throws {
        let system = await setUpNode("local")
        let speaker = Speaker(actorSystem: system)
        let wrong: Counter = try system.interceptCalls(
            to: Counter.self,
            metadata: ActorMetadata(),
            interceptor: Forwarding(target: speaker.id)
        )

        let error = try await shouldThrow {
            _ = try await wrong.count()
        }
        guard let error = error as? ResolveError, "\(error)".contains("typeMismatch") else {
            throw TestError("Expected a ResolveError for the type mismatch, got \(error)")
        }
    }
}

/// Forwards every call to the actor with `target`'s ID, as a virtual actor's reference does.
private struct Forwarding: RemoteCallInterceptor {
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

@Resolvable
protocol Speaking: DistributedActor where ActorSystem == ClusterSystem {
    distributed func say() -> String
}

private distributed actor Speaker: Speaking {
    typealias ActorSystem = ClusterSystem

    distributed func say() -> String {
        "hello"
    }
}

private distributed actor Counter {
    typealias ActorSystem = ClusterSystem

    distributed func count() -> Int {
        1
    }
}
