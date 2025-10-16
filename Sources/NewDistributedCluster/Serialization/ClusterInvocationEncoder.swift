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

public struct ClusterInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = any Codable

    var arguments: [Data] = []
    var genericSubstitutions: [String] = []
    var throwing: Bool = false

    let system: ClusterSystem

    init(system: ClusterSystem) {
        self.system = system
    }

    init(system: ClusterSystem, arguments: [Data]) {
        self.system = system
        self.arguments = arguments
        self.throwing = false
    }

    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        let typeName = _mangledTypeName(type) ?? _typeName(type)
        self.genericSubstitutions.append(typeName)
    }

    public mutating func recordArgument<Value: Codable>(_ argument: RemoteCallArgument<Value>) throws {
        let serialized = try self.system.serialization.serialize(argument.value)
        //        let data = serialized.buffer.readData()
        self.arguments.append(serialized)
    }

    public mutating func recordReturnType<Success: Codable>(_ returnType: Success.Type) throws {}

    public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {
        self.throwing = true
    }

    public mutating func doneRecording() throws {
        // noop
    }
}
