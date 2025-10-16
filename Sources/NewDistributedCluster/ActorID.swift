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

import Foundation

// ==== ----------------------------------------------------------------------------------------------------------------
extension ClusterSystem {
    public struct ActorID: Hashable, Sendable {
        /// The unique node on which the actor identified by this identity is located.
        public let node: Cluster.Node
        public let id: String

        public init(
            node: Cluster.Node,
            id: String
        ) {
            self.node = node
            self.id = id
            traceLog_DeathWatch("Made ID: \(self)")
        }
    }
}

// TODO: Needed for actorid now, refactor or remove when adding serialization
extension ClusterSystem.ActorID: Codable {}
