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

@_exported import Distributed
import Foundation  // ProcessInfo.processInfo.activeProcessorCount
import Logging
import NIO
import Synchronization

import struct Foundation.Data
import struct Foundation.UUID

public typealias Serialization = TemporarySerialization

/// A `ClusterSystem` is a confined space which runs and manages Actors.
///
/// Most applications need _no-more-than_ a single `ClusterSystem`.
/// Rather, the system should be configured to host the kinds of dispatchers that the application needs.
///
/// A `ClusterSystem` and all of the actors contained within remain alive until the `terminate` call is made.
public final class ClusterSystem: DistributedActorSystem, Sendable {

    public typealias InvocationDecoder = ClusterInvocationDecoder
    public typealias InvocationEncoder = ClusterInvocationEncoder
    public typealias SerializationRequirement = any Codable
    public typealias ResultHandler = ClusterInvocationResultHandler

    private let settings: ClusterSystemSettings
    public var endpoint: Cluster.Endpoint { self.settings.endpoint }

    internal let serialization: TemporarySerialization = TemporarySerialization()

    private let connectionManager: ConnectionManager
    internal let managedDistributedActors: Mutex<WeakAnyDistributedActorDictionary> = Mutex(.init())

    // ==== ----------------------------------------------------------------------------------------------------------------
    // MARK: Logging

    /// Root logger of this actor system, as configured in `LoggingSettings`.
    public let log: Logger = Logger(label: "ClusterSystem")

    public init(settings: ClusterSystemSettings = .default) async throws {
        self.settings = settings
        self.connectionManager = try await ConnectionManager(
            endpoint: settings.endpoint
        )
        self.serialization.updateKeys(using: self)
        await self.connectionManager.run(on: self)
    }

    public func join(_ endpoint: Cluster.Endpoint) async throws {
        guard self.endpoint != endpoint else { return }
        let response = try? await self.connectionManager
            .execute(
                endpoint: endpoint,
                request: .join(self.endpoint)
            )
        if response != nil {
            print("joined node", endpoint)
        } else {
            print("Shouldn't be called...")
        }
    }

    public func shutdown() async {
        await self.connectionManager.close()
    }
}

extension ClusterSystem {
    public func remoteCall<Act: DistributedActor, Err: Error, Res: Codable>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Act.ID == ActorID {
        let envelope = RemoteCallEnvelope(
            recipient: actor.id,
            invocationTarget: target.identifier,
            genericSubs: invocation.genericSubstitutions,
            args: invocation.arguments
        )

        let response: ResponseMessage? = try await self.connectionManager
            .execute(
                endpoint: actor.id.node.endpoint,
                request: .call(envelope)
            )

        guard let response, case .reply(let envelope) = response else {
            // FIXME: Proper error
            fatalError()
        }

        switch envelope {
        case .value(let data):
            return try self.serialization.deserialize(as: Res.self, from: data)
        case .error(let error):
            // FIXME: Proper error casting
            throw SerializationError(.notAbleToDeserialize(hint: error))
        case .done:
            // FIXME: Proper error casting
            throw SerializationError(.notAbleToDeserialize(hint: ""))
        }
    }

    public func remoteCallVoid<Act: DistributedActor, Err: Error>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws where Act.ID == ActorID {
        let envelope = RemoteCallEnvelope(
            recipient: actor.id,
            invocationTarget: target.identifier,
            genericSubs: invocation.genericSubstitutions,
            args: invocation.arguments
        )
        _ = try await self.connectionManager
            .execute(
                endpoint: actor.id.node.endpoint,
                request: .call(envelope)
            )
        print("done")
    }
}

extension ClusterSystem {
    public func resolve<Act: DistributedActor>(
        id: ActorID,
        as actorType: Act.Type
    ) throws -> Act? where Act.ID == ActorID {
        // If the actor is not located on this node, immediately resolve as "remote"
        guard self.settings.node == id.node else {
            return nil
        }

        // Resolve using the usual id lookup method
        let managed = self.managedDistributedActors.withLock { $0.get(identifiedBy: id) }

        guard let managed = managed else {
            // TRICK: for _resolveStub which we may be resolving an ID which may be dead, but we always want to get the stub anyway
            if Act.self is StubDistributedActor.Type {
                return nil
            }

            throw DeadLetterError(recipient: id)
        }

        guard let resolved = managed as? Act else {
            self.log.trace(
                "Resolved actor identity, however did not match expected type: \(Act.self)",
                metadata: [
                    "actor/id": "\(id)",
                    "actor/type": "\(type(of: managed))",
                    "expected/type": "\(Act.self)",
                ]
            )
            return nil
        }

        self.log.trace(
            "Resolved as local instance",
            metadata: [
                "actor/id": "\(id)",
                "actor": "\(resolved)",
            ]
        )
        return resolved
    }

    public func assignID<Act: DistributedActor>(
        _ actorType: Act.Type
    ) -> ActorID where Act.ID == ActorID {
        ActorID(node: settings.node, id: UUID().uuidString)
    }

    public func actorReady<Act: DistributedActor>(_ actor: Act) where Act.ID == ActorID {
        self.managedDistributedActors.withLock { $0.insert(actor: actor) }
    }

    public func resignID(_ id: ActorID) {
        self.managedDistributedActors.withLock { _ = $0.removeActor(identifiedBy: id) }
    }

    public func makeInvocationEncoder() -> ClusterInvocationEncoder {
        InvocationEncoder(system: self)
    }
}

// TODO: Check if needed? 🤔
internal distributed actor StubDistributedActor {
    typealias ID = ClusterSystem.ActorID
    typealias ActorSystem = ClusterSystem
}

actor ConnectionManager {
    private var runnerTask: Task<Void, any Error>?
    private let endpoint: Cluster.Endpoint
    private var connections: [Cluster.Endpoint: Channel] = [:]

    let eventLoopGroup: EventLoopGroup
    let runner: NIOAsyncChannel<NIOAsyncChannel<RequestMessage, ResponseMessage>, Never>

    init(
        endpoint: Cluster.Endpoint,
        eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(
            numberOfThreads: ProcessInfo.processInfo.activeProcessorCount
        )
    ) async throws {
        self.eventLoopGroup = eventLoopGroup
        self.runner = try await ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(host: endpoint.host, port: endpoint.port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        ByteToMessageHandler(ByteToRequestMessage())
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        MessageToByteHandler(ByteToResponseMessage())
                    )
                    return try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: NIOAsyncChannel.Configuration(
                            inboundType: RequestMessage.self,
                            outboundType: ResponseMessage.self
                        )
                    )
                }
            }
        self.endpoint = endpoint
    }

    func run(on clusterSystem: ClusterSystem) {
        self.runnerTask = Task {
            try await self.run(on: clusterSystem)
        }
    }

    // TODO: Remove clusterSystem dependency?
    private func run(on clusterSystem: ClusterSystem) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            try await self.runner.executeThenClose { clients in
                for try await client in clients {
                    group.addTask {
                        do {
                            try await self.handleClient(client, on: clusterSystem)
                        } catch {
                            // TODO: Handle errors
                        }
                    }
                }
            }
        }
    }

    func handleClient(
        _ client: NIOAsyncChannel<RequestMessage, ResponseMessage>,
        on clusterSystem: ClusterSystem
    ) async throws {
        try await client.executeThenClose { inbound, outbound in
            for try await message in inbound {
                switch message {
                case .call(let value):
                    let actor = clusterSystem.managedDistributedActors.withLock {
                        $0.get(identifiedBy: value.recipient)
                    }
                    // FIXME: error
                    guard let actor else { continue }
                    let handler = ClusterSystem.ResultHandler(
                        system: clusterSystem,
                        channel: outbound
                    )
                    var decoder = ClusterSystem.InvocationDecoder(
                        system: clusterSystem,
                        message: .init(
                            targetIdentifier: value.invocationTarget,
                            genericSubstitutions: value.genericSubs,
                            arguments: value.args
                        )
                    )
                    try await clusterSystem.executeDistributedTarget(
                        on: actor,
                        target: RemoteCallTarget(value.invocationTarget),
                        invocationDecoder: &decoder,
                        handler: handler
                    )
                case .connectionClosed:
                    return  // finish loop
                case .join(let endpoint):
                    if self.connections[endpoint] == nil {
                        try await clusterSystem.join(endpoint)
                    }
                    try await outbound.write(.joined)
                }
            }
        }
    }

    func close() {
        self.runnerTask?.cancel()
        self.runnerTask = nil
    }

    func execute(
        endpoint: Cluster.Endpoint,
        request: RequestMessage
    ) async throws -> ResponseMessage {
        if self.connections[endpoint] != nil {
            return try await self.connections[endpoint]!.sendRequest(request)
        }
        let client = try await ClientBootstrap(group: eventLoopGroup)
            .connect(host: endpoint.host, port: endpoint.port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        ByteToMessageHandler(ByteToResponseMessage())
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        MessageToByteHandler(ByteToRequestMessage())
                    )
                    return try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: NIOAsyncChannel.Configuration(
                            inboundType: ResponseMessage.self,
                            outboundType: RequestMessage.self
                        )
                    )
                }
            }
        let channel = Channel(channel: client)
        self.connections[endpoint] = channel
        return try await channel.sendRequest(request)
    }

    deinit {
        self.runnerTask?.cancel()
        self.runnerTask = nil
    }
}

enum Connection {

    static func execute<Result>(
        endpoint: Cluster.Endpoint,
        eventLoopGroup: EventLoopGroup,
        work: @escaping @Sendable (NIOAsyncChannelInboundStream<ResponseMessage>, NIOAsyncChannelOutboundWriter<RequestMessage>) async throws -> (Result)
    ) async throws -> Result {
        try await ClientBootstrap(group: eventLoopGroup)
            .connect(host: endpoint.host, port: endpoint.port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        ByteToMessageHandler(ByteToResponseMessage())
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        MessageToByteHandler(ByteToRequestMessage())
                    )
                    return try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: NIOAsyncChannel.Configuration(
                            inboundType: ResponseMessage.self,
                            outboundType: RequestMessage.self
                        )
                    )
                }
            }
            .executeThenClose(work)
    }
}

final class Channel: @unchecked Sendable {
    private let channel: NIOAsyncChannel<ResponseMessage, RequestMessage>
    private var inboundIterator: NIOAsyncChannelInboundStream<ResponseMessage>.AsyncIterator

    init(channel: NIOAsyncChannel<ResponseMessage, RequestMessage>) {
        self.channel = channel
        self.inboundIterator = channel.inbound.makeAsyncIterator()
    }

    func sendRequest(_ request: RequestMessage) async throws -> ResponseMessage {
        try await channel.outbound.write(request)
        guard let response = try await inboundIterator.next() else {
            return .connectionClosed
        }
        return response
    }

    func close() async throws {
        try await channel.channel.close()
    }
}
