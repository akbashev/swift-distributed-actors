//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

final class ClusterSingletonPluginTests: SingleClusterSystemXCTestCase {
    func test_singletonPlugin_clusterDisabled() async throws {
        // Singleton should work just fine without clustering
        let test = await setUpNode("test") { settings in
            settings.enabled = false
            settings += ClusterSingletonPlugin()
        }

        let name = "the-one"

        // singleton.host
        let ref = try await test.singleton.host(name: name) { actorSystem in
            TheSingleton(greeting: "Hello", actorSystem: actorSystem)
        }
        let reply = try await ref.greet(name: "Charlie")
        reply.shouldStartWith(prefix: "Hello Charlie!")

        // singleton.ref (proxy-only)
        let proxyRef = try await test.singleton.proxy(TheSingleton.self, name: name)
        let proxyReply = try await proxyRef.greet(name: "Charlene")
        proxyReply.shouldStartWith(prefix: "Hello Charlene!")
    }

    /// Plugins start while the system starts, and some host a singleton then, as virtual actors
    /// host their router.
    func test_singleton_hostedWhilePluginsStart() async throws {
        let hosting = SingletonHostingPlugin()
        let system = await setUpNode("test") { settings in
            // Clustered, as hosting reaches the receptionist only then, and alone, so it leads.
            settings.enabled = true
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: 1)
            settings += ClusterSingletonPlugin()
            settings += hosting
        }
        system.cluster.join(endpoint: system.cluster.endpoint)
        try await system.cluster.joined(within: .seconds(10))

        let singleton = try XCTUnwrap(hosting.singleton)
        let reply = try await singleton.greet(name: "Charlie")
        reply.shouldStartWith(prefix: "Hello Charlie!")
    }

    func test_singleton_nestedSingleton() async throws {
        let system = await setUpNode("test") { settings in
            settings += ClusterSingletonPlugin()
        }

        let singleton = try await system.singleton.host(name: "test-singleton") { actorSystem in
            SingletonWhichCreatesDistributedActorDuringInit(actorSystem: actorSystem)
        }

        let singletonID = singleton.id
        let greeterID = try await singleton.getGreeter().id

        pinfo("singleton proxy    id: \(singletonID)")
        pinfo("singleton actual   id: \(try await singleton.actualID())")
        pinfo("singleton(greeter) id: \(greeterID)")

        try await singleton.actualID().detailedDescription.shouldContain("test-singleton")
        // if this were true we would have crashed by a duplicate name already, but let's make sure:
        singletonID.shouldNotEqual(greeterID)
    }

    func test_plugin_hooks() async throws {
        let actorID = "actorHookID"
        let hookFulfillment = self.expectation(description: "actor-hook")
        let plugin = TestActorLifecyclePlugin { actor in
            /// There are multiple internal actors fired, we only checking for `ActorWithId`
            guard let actor = actor as? ActorWithID else { return }
            Task {
                let id = try? await actor.getID()
                XCTAssertEqual(id, actorID, "Expected \(actorID) as an ID")
                hookFulfillment.fulfill()
            }
        }
        let testNode = await setUpNode("test-hook") { settings in
            settings.enabled = false
            settings += plugin
        }

        let id = ActorWithID(actorSystem: testNode, customID: actorID)
        await fulfillment(of: [hookFulfillment], timeout: 3.0)
    }

    /// Hosts a singleton when it starts.
    final class SingletonHostingPlugin: Plugin, @unchecked Sendable {
        var key: Key { "$testSingletonHosting" }

        private let lock: _Mutex = .init()
        private var _singleton: TheSingleton?

        var singleton: TheSingleton? {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self._singleton
        }

        func start(_ system: ClusterSystem) async throws {
            let singleton = try await system.singleton.host(name: "the-one") { actorSystem in
                TheSingleton(greeting: "Hello", actorSystem: actorSystem)
            }
            self.lock.lock()
            self._singleton = singleton
            self.lock.unlock()
        }

        func stop(_ system: ClusterSystem) async {}
    }

    final class TestActorLifecyclePlugin: ActorLifecyclePlugin {
        var key: Key { "$testClusterHook" }

        let onActorReady: (any DistributedActor) -> Void
        let _lock: _Mutex = .init()

        init(
            onActorReady: @escaping (any DistributedActor) -> Void
        ) {
            self.onActorReady = onActorReady
        }

        func onActorReady<Act: DistributedActor>(_ actor: Act) where Act.ID == ClusterSystem.ActorID {
            self._lock.lock()
            self.onActorReady(actor)
            self._lock.unlock()
        }

        func onResignID(_ id: ClusterSystem.ActorID) {}
        func start(_ system: ClusterSystem) async throws {}
        func stop(_ system: ClusterSystem) async {}
    }

    distributed actor SingletonWhichCreatesDistributedActorDuringInit: ClusterSingleton {
        typealias ActorSystem = ClusterSystem

        private let greeter: Greeter

        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
            self.greeter = Greeter(actorSystem: actorSystem)
        }

        distributed func actualID() -> ActorSystem.ActorID {
            self.id
        }

        distributed func getGreeter() -> Greeter {
            self.greeter
        }
    }

    distributed actor Greeter {
        typealias ActorSystem = ClusterSystem
        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }

        distributed func greet() {
            print("Hello!")
        }
    }

    distributed actor ActorWithID {
        let customID: String

        init(
            actorSystem: ActorSystem,
            customID: String
        ) {
            self.actorSystem = actorSystem
            self.customID = customID
        }

        distributed func getID() -> String {
            self.customID
        }
    }
}
