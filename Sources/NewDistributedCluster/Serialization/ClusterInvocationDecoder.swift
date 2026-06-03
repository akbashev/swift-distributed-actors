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

import struct Foundation.Data

public struct ClusterInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = any Codable

    public struct Message: Sendable, Codable, CustomStringConvertible {
        let targetIdentifier: String
        let genericSubstitutions: [String]
        let arguments: [Data]

        var target: RemoteCallTarget {
            RemoteCallTarget(targetIdentifier)
        }

        public var description: String {
            "Message(target: \(target), genericSubstitutions: \(genericSubstitutions), arguments: \(arguments.count))"
        }
    }

    let system: ClusterSystem
    let message: Message

    var argumentIdx = 0

    public init(system: ClusterSystem, message: Message) {
        self.system = system
        self.message = message
    }

    public mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
        let genericSubstitutions = message.genericSubstitutions
        return try genericSubstitutions.map {
            guard let type = _typeByName($0) else {
                throw SerializationError(.notAbleToDeserialize(hint: $0))
            }
            return type
        }
    }

    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument {
        let argumentData: Data
        guard self.argumentIdx < message.arguments.count else {
            throw SerializationError(.notEnoughArgumentsEncoded(expected: self.argumentIdx + 1, have: message.arguments.count))
        }

        argumentData = message.arguments[self.argumentIdx]
        self.argumentIdx += 1
        let argument = try system.serialization.deserialize(as: Argument.self, from: argumentData)
        return argument
    }

    public mutating func decodeErrorType() throws -> Any.Type? {
        nil  // TODO(distributed): might need this
    }

    public mutating func decodeReturnType() throws -> Any.Type? {
        nil  // TODO(distributed): might need this
    }
}
