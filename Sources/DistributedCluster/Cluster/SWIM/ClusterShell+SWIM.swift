//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import ClusterMembership
import Distributed
import Logging
import SWIM
import SWIMDistributed

/// The failure detector of the cluster.
///
/// - SeeAlso: `SWIM.Instance` for detailed documentation about the SWIM protocol implementation.
internal typealias ClusterSWIMShell = SWIM.Shell<ClusterSystem>

extension SWIM.Shell where System == ClusterSystem {
    static var props: _Props {
        var ps = _Props()
        ps._knownActorName = ActorPath._swim.name
        ps._wellKnown = true
        return ps.metrics(group: "swim.shell", measure: [.serialization, .deserialization])
    }
}

extension ActorID {
    static func _swim(on node: Cluster.Node) -> ActorID {
        .init(remote: node, path: ActorPath._swim, incarnation: .wellKnown)
    }
}

extension ActorPath {
    static let _swim: ActorPath = try! ActorPath._user.appending("swim")
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Running SWIM in the cluster

extension ClusterShell {
    /// Spawns the well-known `ClusterSWIMShell` of this node and starts running it.
    func startSWIM(settings: ClusterSystemSettings, system: ClusterSystem, clusterRef: ClusterShell.Ref) {
        guard settings.swim.initialContactPoints.isEmpty else {
            fatalError(
                """
                swim.initialContactPoints was not empty! Please use `settings.discovery` settings to discover peers,
                rather than the internal swim instances configuration settings!
                """
            )
        }

        var swimSettings = settings.swim
        swimSettings.metrics.systemName = system.settings.metrics.systemName
        let selfNode = settings.bindNode

        let swim = _Props.$forSpawn.withValue(ClusterSWIMShell.props) {
            ClusterSWIMShell(
                settings: .init(
                    swim: swimSettings,
                    myself: selfNode.asSWIMNode,
                    resolvePeer: { [weak system] node in
                        guard let system, let clusterNode = node.asClusterNode else {
                            return nil
                        }
                        return try? ClusterSWIMShell.resolve(id: ._swim(on: clusterNode), using: system)
                    }
                ),
                actorSystem: system
            )
        }
        precondition(swim.id.incarnation == 0 || swim.id.isWellKnown, "SWIM was not well known!? Was: \(swim.id.detailedDescription)")

        self._swimShell = swim
        self._swimTask = Task {
            await Self.runSWIM(swim, selfNode: selfNode, clusterRef: clusterRef, log: system.log)
        }
    }

    /// Runs `swim` and forwards its reachability changes to the cluster shell, until cancelled.
    private static func runSWIM(_ swim: ClusterSWIMShell, selfNode: Cluster.Node, clusterRef: ClusterShell.Ref, log: Logger) async {
        guard let changes = await swim.whenLocal({ $0.membershipChanges }) else {
            return
        }
        await withDiscardingTaskGroup { group in
            group.addTask {
                await swim.whenLocal { await $0.run() }
            }
            for await change in changes {
                Self.announceMemberReachability(change: change, selfNode: selfNode, clusterRef: clusterRef, log: log)
            }
        }
    }

    private static func announceMemberReachability(
        change: SWIM.MemberStatusChangedEvent,
        selfNode: Cluster.Node,
        clusterRef: ClusterShell.Ref,
        log: Logger
    ) {
        switch change.status {
        case .unreachable:
            log.info(
                """
                Node \(change.member.node) determined [.unreachable]! \
                The node is not yet marked [.down], a downing strategy or other Cluster.Event subscriber may act upon this information.
                """,
                metadata: [
                    "swim/member": "\(change.member)"
                ]
            )
        default:
            log.info(
                "Node \(change.member.node) determined [.\(change.status)] (was \(optional: change.previousStatus)).",
                metadata: [
                    "swim/member": "\(change.member)"
                ]
            )
        }

        if change.status == .dead,
            change.member.node.asClusterNode == selfNode
        {
            return
        }

        let reachability: Cluster.MemberReachability
        switch change.status {
        case .alive, .suspect:
            reachability = .reachable
        case .unreachable, .dead:
            reachability = .unreachable
        }

        guard let node = change.member.node.asClusterNode else {
            log.warning("Unable to emit failureDetectorReachabilityChanged, for event: \(change), since can't represent member as node!")
            return
        }

        clusterRef.tell(.command(.failureDetectorReachabilityChanged(node, reachability)))
    }

    /// Starts monitoring `node` with SWIM.
    func monitorWithSWIM(_ node: Cluster.Node) {
        let swim = self._swimShell!
        Task {
            await swim.whenLocal { await $0.monitor(node: node.asSWIMNode) }
        }
    }

    /// Confirms to SWIM that `node` is dead, so it stops monitoring it.
    func confirmDeadToSWIM(_ node: Cluster.Node) {
        let swim = self._swimShell!
        Task {
            await swim.whenLocal { $0.confirmDead(node: node.asSWIMNode) }
        }
    }
}
