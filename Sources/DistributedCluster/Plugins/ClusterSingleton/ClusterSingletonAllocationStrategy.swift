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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Protocol for singleton allocation strategy

/// Strategy for choosing a `Cluster.Node` to allocate singleton.
public protocol ClusterSingletonAllocationStrategy {
    /// Receives and handles the `Cluster.Event`.
    ///
    /// - Returns: The current `node` after processing `clusterEvent`.
    func onClusterEvent(_ clusterEvent: Cluster.Event) async -> Cluster.Node?

    /// The currently allocated `node` for the singleton.
    var node: Cluster.Node? { get async }

    /// Receives the nodes that host the singleton, meaning they called
    /// `ClusterSystem.singleton.host(type:name:settings:makeInstance:)` for it.
    ///
    /// Nodes that only proxy the singleton, or don't run the plugin at all, such as a
    /// cluster daemon, can't run it. Strategies can use this to avoid choosing them.
    ///
    /// - Returns: The current `node` after taking `hosts` into account.
    func onHostsChange(_ hosts: Set<Cluster.Node>) async -> Cluster.Node?
}

extension ClusterSingletonAllocationStrategy {
    /// Ignores the hosting nodes, keeping the current `node`.
    public func onHostsChange(_ hosts: Set<Cluster.Node>) async -> Cluster.Node? {
        await self.node
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ClusterSingletonAllocationStrategy implementations

/// An `AllocationStrategy` in which selection is based on cluster leadership.
///
/// The singleton runs on the cluster leader when the leader hosts it. When it doesn't,
/// for example because the leader is a cluster daemon or only proxies the singleton,
/// the singleton runs on the lowest-address node that hosts it instead, so it always
/// has somewhere to run.
public final class ClusterSingletonAllocationByLeadership: ClusterSingletonAllocationStrategy {
    var leader: Cluster.Node?
    /// Nodes known to host the singleton; empty until they're discovered.
    var hosts: Set<Cluster.Node> = []

    public init(settings: ClusterSingletonSettings, actorSystem: ClusterSystem) {
        // not used...
    }

    public func onClusterEvent(_ clusterEvent: Cluster.Event) async -> Cluster.Node? {
        switch clusterEvent {
        case .leadershipChange(let change):
            self.leader = change.newLeader?.node
        case .snapshot(let membership):
            self.leader = membership.leader?.node
        default:
            ()  // ignore other events
        }
        return self.allocatedNode
    }

    public func onHostsChange(_ hosts: Set<Cluster.Node>) async -> Cluster.Node? {
        self.hosts = hosts
        return self.allocatedNode
    }

    public var node: Cluster.Node? {
        get async {
            self.allocatedNode
        }
    }

    /// The leader, unless hosting nodes are known and the leader isn't one of them.
    private var allocatedNode: Cluster.Node? {
        guard let leader else { return nil }
        guard !self.hosts.isEmpty, !self.hosts.contains(leader) else { return leader }
        return self.hosts.min()
    }
}

// TODO: "oldest node"

// TODO: "race to become the host", all nodes race and try CAS-like to set themselves as leader -- this we could do with cas-paxos perhaps or similar; it is less predictable which node wins, which can be good or bad
