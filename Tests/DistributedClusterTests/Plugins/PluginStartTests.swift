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

final class PluginStartTests: ClusteredActorSystemsXCTestCase {
    /// Plugins start once the system is initialized, so they can use it: its receptionist here,
    /// as a plugin hosting a cluster singleton does.
    func test_pluginStart_usesTheSystem() async throws {
        let plugin = ReceptionistUsingPlugin()
        let system = await self.setUpNode("plugins") { settings in
            settings += plugin
        }

        XCTAssertTrue(plugin.started)
        _ = system
    }

    final class ReceptionistUsingPlugin: Plugin, @unchecked Sendable {
        var key: Key { "$testReceptionistUsing" }

        private let lock: _Mutex = .init()
        private var _started = false

        var started: Bool {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self._started
        }

        func start(_ system: ClusterSystem) async throws {
            _ = system.receptionist
            self.lock.lock()
            self._started = true
            self.lock.unlock()
        }

        func stop(_ system: ClusterSystem) async {}
    }
}
