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

@testable import DistributedCluster
import DistributedActorsTestKit
import Foundation
import NIO
import XCTest

final class WeakReferencesTests: SingleClusterSystemXCTestCase {

    func test_weakWhenLocal_notKeepLocalActorAlive_local() throws {
        var greeter: Greeter? = Greeter(actorSystem: system)
        let id = greeter!.id

        let ref = DistributedActorRef.WeakWhenLocal(greeter!)
        "\(ref)".shouldEqual("DistributedActorRef.WeakWhenLocal(Greeter(/user/Greeter-y), isLocal: true)")
        greeter = nil

        try testKit.assertIDAvailable(id)
        ref.actor.shouldBeNil()
    }

    func test_weakWhenLocal_alwaysKeepTheRemoteRef() async throws {
        let second = await setUpNode("second")

        let greeter: Greeter? = Greeter(actorSystem: system)
        let id = greeter!.id

        var remoteRef: Greeter? = try Greeter.resolve(id: id, using: second)

        let ref = DistributedActorRef.WeakWhenLocal(remoteRef!)
        "\(ref)".shouldEqual("DistributedActorRef.WeakWhenLocal(Greeter(/user/Greeter-y), isLocal: false)")
        remoteRef = nil // doesn't do anything, was just a remote reference

        try testKit(system).assertIDAssigned(id)
        try testKit(second).assertIDAvailable(id)
        ref.actor.shouldNotBeNil() // keeps the remote reference, until we notice terminated and reap the `ref`
    }
}

fileprivate distributed actor Greeter: CustomStringConvertible {
    typealias ActorSystem = ClusterSystem

    distributed func greet(name: String) -> String {
        "Hello, \(name)!"
    }

    nonisolated var description: String {
        "\(Self.self)(\(self.id))"
    }
}

extension ActorTestKit {
    /// Assert that a given `ActorID` is not used by this system. E.g. it has been resigned already.
    fileprivate func assertIDAvailable(
            _ id: ClusterSystem.ActorID,
            file: StaticString = #fileID, line: UInt = #line, column: UInt = #column) throws {
        if self.system._isAssigned(id: id) {
            self.fail("ActorID [\(id)] is assigned to some actor in \(self.system)!",
                    file: file, line: line, column: column)
        }
    }

    fileprivate func assertIDAssigned(
            _ id: ClusterSystem.ActorID,
            file: StaticString = #fileID, line: UInt = #line, column: UInt = #column) throws {
        if !self.system._isAssigned(id: id) {
            self.fail("ActorID [\(id)] was not assigned to any actor in \(self.system)!",
                    file: file, line: line, column: column)
        }
    }
}
