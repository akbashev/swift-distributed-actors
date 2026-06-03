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

import Logging
import NIOCore

import struct Foundation.Data

public struct ClusterInvocationResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = any Codable

    let system: ClusterSystem
    let channel: NIOAsyncChannelOutboundWriter<ResponseMessage>

    init(system: ClusterSystem, channel: NIOAsyncChannelOutboundWriter<ResponseMessage>) {
        self.system = system
        self.channel = channel
    }

    public func onReturn<Success: Codable & Sendable>(value: Success) async throws {
        system.log.trace(
            "Result handler, onReturn",
            metadata: [
                "type": "\(Success.self)"
            ]
        )
        try await channel.write(
            ResponseMessage.reply(.value(system.serialization.encoder.encode(value)))
        )
    }

    public func onReturnVoid() async throws {
        system.log.debug(
            "Result handler, onReturnVoid"
        )
        try await channel.write(ResponseMessage.reply(.done))
    }

    public func onThrow<Err: Error>(error: Err) async throws {
        system.log.debug("Result handler, onThrow: \(error)")
        try await channel.write(ResponseMessage.reply(.error(error.localizedDescription)))
    }
}
