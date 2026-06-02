//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// tag::imports[]

import DistributedCluster
import Logging

// end::imports[]

// tag::singleton-actor[]
distributed actor SampleSingleton: ClusterSingleton {
    typealias ActorSystem = ClusterSystem

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    distributed func greet(name: String) {
        // ...
    }
}
// end::singleton-actor[]

class ActorSingletonDocExamples {
    func example_ref() async throws {
        // tag::configure-system[]
        let system = await ClusterSystem("Sample") { settings in
            settings += ClusterSingletonPlugin()  // <1>
        }
        // end::configure-system[]

        // tag::host-ref[]
        let singletonRef = try await system.singleton.host(name: "SampleSingleton") { actorSystem in
            SampleSingleton(actorSystem: actorSystem)  // <1>
        }
        try await singletonRef.greet(name: "Jane Doe")  // <2>
        // end::host-ref[]

        // tag::proxy-ref[]
        let singletonProxyRef = try await system.singleton.proxy(SampleSingleton.self, name: "SampleSingleton")
        try await singletonProxyRef.greet(name: "Jane Doe")  // <1>
        // end::proxy-ref[]
    }
}
