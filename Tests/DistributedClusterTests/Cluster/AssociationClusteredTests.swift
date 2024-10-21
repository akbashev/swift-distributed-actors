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
@testable import DistributedCluster
import NIO
import Testing

@Suite(.timeLimit(.minutes(1)), .serialized)
struct ClusterAssociationTests {
    
    let testCase: ClusteredActorSystemsTestCase
    
    init() throws {
        self.testCase = try ClusteredActorSystemsTestCase()
        self.self.testCase.configureLogCapture = { settings in
            settings.excludeActorPaths = [
                "/system/replicator",
                "/system/cluster/swim",
            ]
        }
    }
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Happy path, accept association
    @Test
    func test_boundServer_shouldAcceptAssociate() async throws {
        let (first, second) = await self.testCase.setUpPair()
        
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        try self.testCase.assertAssociated(second, withExactly: first.cluster.node)
    }

    @Test
    func test_boundServer_shouldAcceptAssociate_raceFromBothNodes() async throws {
        let (first, second) = await self.testCase.setUpPair()
        let n3 = await self.testCase.setUpNode("node-3")
        let n4 = await self.testCase.setUpNode("node-4")
        let n5 = await self.testCase.setUpNode("node-5")
        let n6 = await self.testCase.setUpNode("node-6")
        
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        second.cluster.join(endpoint: first.cluster.node.endpoint)
        
        n3.cluster.join(endpoint: first.cluster.node.endpoint)
        first.cluster.join(endpoint: n3.cluster.node.endpoint)
        
        n4.cluster.join(endpoint: first.cluster.node.endpoint)
        first.cluster.join(endpoint: n4.cluster.node.endpoint)
        
        n5.cluster.join(endpoint: first.cluster.node.endpoint)
        first.cluster.join(endpoint: n5.cluster.node.endpoint)
        
        n6.cluster.join(endpoint: first.cluster.node.endpoint)
        first.cluster.join(endpoint: n6.cluster.node.endpoint)
        
        try self.testCase.assertAssociated(first, withAtLeast: second.cluster.node)
        try self.testCase.assertAssociated(second, withAtLeast: first.cluster.node)
    }

    @Test
    func test_handshake_shouldNotifyOnSuccess() async throws {
        let (first, second) = await self.testCase.setUpPair()
        
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        try self.testCase.assertAssociated(second, withExactly: first.cluster.node)
    }

    @Test
    func test_handshake_shouldNotifySuccessWhenAlreadyConnected() async throws {
        let (first, second) = await self.testCase.setUpPair()
        
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        try self.testCase.assertAssociated(second, withExactly: first.cluster.node)
        
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        try self.testCase.assertAssociated(second, withExactly: first.cluster.node)
    }

    @Test
    func test_clusterControl_joined_shouldCauseJoiningAttempt() async throws {
        let (first, second) = await self.testCase.setUpPair()
        
        try await first.cluster.joined(endpoint: second.cluster.endpoint, within: .seconds(3))
        try await second.cluster.joined(endpoint: first.cluster.endpoint, within: .seconds(3))
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        try await self.testCase.assertMemberStatus(on: first, node: second.cluster.node, atLeast: .up, within: .seconds(3))
        
        try self.testCase.assertAssociated(second, withExactly: first.cluster.node)
        try await self.testCase.assertMemberStatus(on: second, node: first.cluster.node, atLeast: .up, within: .seconds(3))
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Joining into existing cluster
    @Test
    func test_association_sameAddressNodeJoin_shouldOverrideExistingNode() async throws {
        let (first, second) = await self.testCase.setUpPair()
        
        let secondName = second.cluster.node.endpoint.systemName
        let secondPort = second.cluster.node.port
        
        let firstEventsProbe = self.testCase.testKit(first).makeTestProbe(expecting: Cluster.Event.self)
        let secondEventsProbe = self.testCase.testKit(second).makeTestProbe(expecting: Cluster.Event.self)
        await first.cluster.events._subscribe(firstEventsProbe.ref)
        await second.cluster.events._subscribe(secondEventsProbe.ref)
        
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        try self.testCase.assertAssociated(second, withExactly: first.cluster.node)
        
        let oldSecond = second
        let shutdown = try oldSecond.shutdown() // kill second node
        try shutdown.wait(atMost: .seconds(3))
        
        let secondReplacement = await self.testCase.setUpNode(secondName + "-REPLACEMENT") { settings in
            settings.bindPort = secondPort
        }
        let secondReplacementEventsProbe = self.testCase.testKit(secondReplacement).makeTestProbe(expecting: Cluster.Event.self)
        await secondReplacement.cluster.events._subscribe(secondReplacementEventsProbe.ref)
        await second.cluster.events._subscribe(secondReplacementEventsProbe.ref)
        
        // the new replacement node is now going to initiate a handshake with 'first' which knew about the previous
        // instance (oldSecond) on the same node; It should accept this new handshake, and ban the previous node.
        secondReplacement.cluster.join(endpoint: first.cluster.node.endpoint)
        
        // verify we are associated ONLY with the appropriate nodes now;
        try self.testCase.assertAssociated(first, withExactly: [secondReplacement.cluster.node])
        try self.testCase.assertAssociated(secondReplacement, withExactly: [first.cluster.node])
    }

    @Test
    func test_association_shouldAllowSendingToSecondReference() async throws {
        let (first, second) = await self.testCase.setUpPair()
        
        let probeOnSecond = self.testCase.testKit(second).makeTestProbe(expecting: String.self)
        let refOnSecondSystem: _ActorRef<String> = try second._spawn(
            "secondAcquaintance",
            .receiveMessage { message in
                probeOnSecond.tell("forwarded:\(message)")
                return .same
            }
        )
        
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        
        try self.testCase.assertAssociated(first, withExactly: second.settings.bindNode)
        
        // first we manually construct the "right second path"; Don't do this in normal production code
        let uniqueSecondAddress = ActorID(local: second.cluster.node, path: refOnSecondSystem.path, incarnation: refOnSecondSystem.id.incarnation)
        // to then obtain a second ref ON the `system`, meaning that the node within uniqueSecondAddress is a second one
        let resolvedRef = self.testCase.resolveRef(first, type: String.self, id: uniqueSecondAddress, on: second)
        // the resolved ref is a first resource on the `system` and points via the right association to the second actor
        // inside system `second`. Sending messages to a ref constructed like this will make the messages go over remoting.
        resolvedRef.tell("HELLO")
        
        try probeOnSecond.expectMessage("forwarded:HELLO")
    }

    @Test
    func test_ignore_attemptToSelfJoinANode() async throws {
        let alone = await self.testCase.setUpNode("alone")
        
        alone.cluster.join(endpoint: alone.cluster.node.endpoint) // "self join", should simply be ignored
        
        let testKit = self.testCase.testKit(alone)
        try await testKit.eventually(within: .seconds(3)) {
            let snapshot: Cluster.Membership = await alone.cluster.membershipSnapshot
            if snapshot.count != 1 {
                throw TestError("Expected membership to include self node, was: \(snapshot)")
            }
        }
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Concurrently initiated handshakes to same node should both get completed
    @Test
    func test_association_shouldEstablishSingleAssociationForConcurrentlyInitiatedHandshakes_incoming_outgoing() async throws {
        let (first, second) = await self.testCase.setUpPair()
        
        // here we attempt to make a race where the nodes race to join each other
        // again, only one association should be created.
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        second.cluster.ref.tell(.command(.handshakeWith(first.cluster.node.endpoint)))
        
        try self.testCase.assertAssociated(first, withExactly: second.settings.bindNode)
        try self.testCase.assertAssociated(second, withExactly: first.settings.bindNode)
    }

    func test_association_shouldEstablishSingleAssociationForConcurrentlyInitiatedHandshakes_outgoing_outgoing() async throws {
        let (first, second) = await self.testCase.setUpPair()
        
        // we issue two handshakes quickly after each other, both should succeed but there should only be one association established (!)
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        
        try self.testCase.assertAssociated(first, withExactly: second.settings.bindNode)
        try self.testCase.assertAssociated(second, withExactly: first.settings.bindNode)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Retry handshakes
    @Test
    func test_handshake_shouldKeepTryingUntilOtherNodeBindsPort() async throws {
        let first = await self.testCase.setUpNode("first")
        
        let secondPort = first.cluster.node.endpoint.port + 10
        // second is NOT started, but we already ask first to handshake with the second one (which will fail, though the node should keep trying)
        let secondEndpoint = Cluster.Endpoint(systemName: "second", host: "127.0.0.1", port: secondPort)
        
        first.cluster.join(endpoint: secondEndpoint)
        try await Task.sleep(for: .seconds(3)) // we give it some time to keep failing to connect, so the second node is not yet started
        
        let second = await self.testCase.setUpNode("second") { settings in
            settings.bindPort = secondPort
        }
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        try self.testCase.assertAssociated(second, withExactly: first.cluster.node)
    }

    @Test
    func test_handshake_shouldStopTryingWhenMaxAttemptsExceeded() async throws {
        let first = await self.testCase.setUpNode("first") { settings in
            settings.handshakeReconnectBackoff = Backoff.exponential(
                initialInterval: .milliseconds(100),
                maxAttempts: 2
            )
        }
        
        let secondPort = first.cluster.node.endpoint.port + 10
        // second is NOT started, but we already ask first to handshake with the second one (which will fail, though the node should keep trying)
        let secondEndpoint = Cluster.Endpoint(systemName: "second", host: "127.0.0.1", port: secondPort)
        
        first.cluster.join(endpoint: secondEndpoint)
        try await Task.sleep(for: .seconds(1)) // we give it some time to keep failing to connect (and exhaust the retries)
        
        let logs = self.testCase.capturedLogs(of: first)
        try logs.awaitLogContaining(self.testCase.testKit(first), text: "Giving up on handshake with node [sact://second@127.0.0.1:9011]")
    }

    @Test
    func test_handshake_shouldNotAssociateWhenRejected() async throws {
        let first = await self.testCase.setUpNode("first") { settings in
            settings._protocolVersion.major += 1 // handshake will be rejected on major version difference
        }
        let second = await self.testCase.setUpNode("second")
        
        first.cluster.join(endpoint: second.cluster.node.endpoint)
        
        try self.testCase.assertNotAssociated(system: first, node: second.cluster.node)
        try self.testCase.assertNotAssociated(system: second, node: first.cluster.node)
    }

    @Test
    func test_handshake_shouldNotifyOnRejection() async throws {
        let first = await self.testCase.setUpNode("first") { settings in
            settings._protocolVersion.major += 1 // handshake will be rejected on major version difference
        }
        let second = await self.testCase.setUpNode("second")
        
        first.cluster.ref.tell(.command(.handshakeWith(second.cluster.node.endpoint)))
        
        try self.testCase.assertNotAssociated(system: first, node: second.cluster.node)
        try self.testCase.assertNotAssociated(system: second, node: first.cluster.node)
        
        try self.testCase.capturedLogs(of: first)
            .awaitLogContaining(
                self.testCase.testKit(first),
                text: "Handshake rejected by [sact://second@127.0.0.1:9002], reason: incompatibleProtocolVersion"
            )
    }

    // ==== ----------------------------------------------------------------------------------------------------------------
    // MARK: Leaving/down rejecting handshakes
    @Test
    func test_handshake_shouldRejectIfNodeIsLeavingOrDown() async throws {
        let first = await self.testCase.setUpNode("first") { settings in
            settings.onDownAction = .none // don't shutdown this node (keep process alive)
        }
        let second = await self.testCase.setUpNode("second")
        
        first.cluster.down(endpoint: first.cluster.node.endpoint)
        
        let testKit = self.testCase.testKit(first)
        try await testKit.eventually(within: .seconds(3)) {
            let snapshot: Cluster.Membership = await first.cluster.membershipSnapshot
            if let selfMember = snapshot.member(first.cluster.node) {
                if selfMember.status == .down {
                    () // good
                } else {
                    throw testKit.error("Expecting \(first.cluster.node) to become [.down] but was \(selfMember.status). Membership: \(pretty: snapshot)")
                }
            } else {
                throw testKit.error("No self member for \(first.cluster.node)! Membership: \(pretty: snapshot)")
            }
        }
        
        // now we try to join the "already down" node; it should reject any such attempts
        second.cluster.ref.tell(.command(.handshakeWith(first.cluster.node.endpoint)))
        
        try self.testCase.assertNotAssociated(system: first, node: second.cluster.node)
        try self.testCase.assertNotAssociated(system: second, node: first.cluster.node)
        
        try self.testCase.capturedLogs(of: second)
            .awaitLogContaining(
                self.testCase.testKit(second),
                text: "Handshake rejected by [sact://first@127.0.0.1:9001], reason: Node already leaving cluster."
            )
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: second control caching
    @Test
    func test_cachedSecondControlsWithSameNodeID_shouldNotOverwriteEachOther() async throws {
        let (first, second) = await self.testCase.setUpPair()
        second.cluster.join(endpoint: first.cluster.node.endpoint)
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        
        let thirdSystem = await self.testCase.setUpNode("third") { settings in
            settings.nid = second.settings.nid
            settings.endpoint.port = 9119
        }
        
        thirdSystem.cluster.join(endpoint: first.cluster.node.endpoint)
        try self.testCase.assertAssociated(first, withExactly: [second.cluster.node, thirdSystem.settings.bindNode])
        
        first._cluster?._testingOnly_associations.count.shouldEqual(2)
    }

    @Test
    func test_sendingMessageToNotYetAssociatedNode_mustCauseAssociationAttempt() async throws {
        let first = await self.testCase.setUpNode("first")
        let second = await self.testCase.setUpNode("second")
        
        // actor on `second` node
        let p2 = self.testCase.testKit(second).makeTestProbe(expecting: String.self)
        let secondOne: _ActorRef<String> = try second._spawn("second-1", .receive { _, message in
            p2.tell("Got:\(message)")
            return .same
        })
        let secondFullAddress = ActorID(remote: second.cluster.node, path: secondOne.path, incarnation: secondOne.id.incarnation)
        
        // we somehow obtained a ref to secondOne (on second node) without associating second yet
        // e.g. another node sent us that ref; This must cause buffering of sends to second and an association to be created.
        
        let resolveContext = _ResolveContext<String>(id: secondFullAddress, system: first)
        let ref = first._resolve(context: resolveContext)
        
        try self.testCase.assertNotAssociated(system: first, node: second.cluster.node)
        try self.testCase.assertNotAssociated(system: second, node: first.cluster.node)
        
        // will be buffered until associated, and then delivered:
        ref.tell("Hello 1")
        ref.tell("Hello 2")
        ref.tell("Hello 3")
        
        try p2.expectMessage("Got:Hello 1")
        try p2.expectMessage("Got:Hello 2")
        try p2.expectMessage("Got:Hello 3")
        
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        try self.testCase.assertAssociated(second, withExactly: first.cluster.node)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Change membership on Down detected
    @Test
    func test_down_self_shouldChangeMembershipSelfToBeDown() async throws {
        let (first, second) = await self.testCase.setUpPair { settings in
            settings.onDownAction = .none // as otherwise we can't inspect if we really changed the status to .down, as we might shutdown too quickly :-)
        }
        
        second.cluster.join(endpoint: first.cluster.node.endpoint)
        try self.testCase.assertAssociated(first, withExactly: second.cluster.node)
        
        // down myself
        first.cluster.down(endpoint: first.cluster.node.endpoint)
        
        let firstProbe = self.testCase.testKit(first).makeTestProbe(expecting: Cluster.Membership.self)
        let secondProbe = self.testCase.testKit(second).makeTestProbe(expecting: Cluster.Membership.self)
        
        // we we down first on first, it should become down there:
        try self.testCase.testKit(first).eventually(within: .seconds(3)) {
            first.cluster.ref.tell(.query(.currentMembership(firstProbe.ref)))
            let firstMembership = try firstProbe.expectMessage()
            
            guard let selfMember = firstMembership.member(first.cluster.node) else {
                throw self.testCase.testKit(second).error("No self member in membership! Wanted: \(first.cluster.node)", line: #line - 1)
            }
            guard selfMember.status == .down else {
                throw self.testCase.testKit(first).error("Wanted self member to be DOWN, but was: \(selfMember)", line: #line - 1)
            }
        }
        try await self.testCase.assertMemberStatus(on: first, node: first.cluster.node, is: .down, within: .seconds(3))
        
        // and the second node should also notice
        try self.testCase.testKit(second).eventually(within: .seconds(3)) {
            second.cluster.ref.tell(.query(.currentMembership(secondProbe.ref)))
            let secondMembership = try secondProbe.expectMessage()
            
            // and the first node should also propagate the Down information to the second node
            // although this may be a best effort since the first can just shut down if it wanted to,
            // this scenario assumes a graceful leave though:
            
            guard let firstMemberObservedOnSecond = secondMembership.member(first.cluster.node) else {
                throw self.testCase.testKit(second).error("\(second) does not know about the \(first.cluster.node) at all...!", line: #line - 1)
            }
            
            guard firstMemberObservedOnSecond.status == .down else {
                throw self.testCase.testKit(second).error("Wanted to see \(first.cluster.node) as DOWN on \(second), but was still: \(firstMemberObservedOnSecond)", line: #line - 1)
            }
        }
    }
}
