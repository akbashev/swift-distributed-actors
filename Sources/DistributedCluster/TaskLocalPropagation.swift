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

import Foundation  // for Data
import Logging

/// The task-local values that travel with remote calls: only those declared with
/// ``ClusterSystemSettings/propagateTaskLocal(_:as:)``.
///
/// A local call runs in its caller's task, so the target sees the caller's task-local values. A
/// remote call carries the declared ones, and its target runs with them, as it would locally.
internal struct TaskLocalPropagation: Sendable {
    /// Runs an operation with a task-local set to a value.
    typealias Setting = (() async throws -> Void) async throws -> Void

    /// One declared task-local: how its value is read where a call is made, and set where the call runs.
    struct Declared: Sendable {
        let name: String
        let read: @Sendable (Serialization) throws -> Data?
        let decode: @Sendable (Data, Serialization) throws -> Setting
    }

    private(set) var declared: [Declared] = []

    mutating func declare<Value: Codable & Sendable>(_ taskLocal: TaskLocal<Value?>, as name: String) {
        precondition(!self.declared.contains { $0.name == name }, "A task-local is already propagated as \(name)")
        self.declared.append(
            Declared(
                name: name,
                read: { serialization in
                    guard let value = taskLocal.get() else { return nil }
                    return try serialization.serialize(value).buffer.readData()
                },
                decode: { data, serialization in
                    let value = try serialization.deserialize(
                        as: Value.self,
                        from: .data(data),
                        using: serialization.outboundManifest(Value.self)
                    )
                    return { operation in try await taskLocal.withValue(value, operation: operation) }
                }
            )
        )
    }

    /// The values the current task has set, of the declared task-locals, by name.
    func values(using serialization: Serialization) throws -> [String: Data] {
        var values: [String: Data] = [:]
        for declared in self.declared {
            if let data = try declared.read(serialization) {
                values[declared.name] = data
            }
        }
        return values
    }

    /// Runs `operation` with the declared task-locals set to `values`. A value that isn't
    /// declared here, or doesn't decode, is left unset.
    func running(
        with values: [String: Data],
        using serialization: Serialization,
        log: Logger,
        _ operation: () async throws -> Void
    ) async throws {
        try await self.running(self.declared[...], with: values, using: serialization, log: log, operation)
    }

    private func running(
        _ declared: ArraySlice<Declared>,
        with values: [String: Data],
        using serialization: Serialization,
        log: Logger,
        _ operation: () async throws -> Void
    ) async throws {
        guard let first = declared.first else { return try await operation() }
        let rest = declared.dropFirst()
        guard let data = values[first.name] else {
            return try await self.running(rest, with: values, using: serialization, log: log, operation)
        }
        let setting: Setting
        do {
            setting = try first.decode(data, serialization)
        } catch {
            // The value didn't decode: the call runs without it.
            log.warning("Could not decode propagated task-local \(first.name): \(error)")
            return try await self.running(rest, with: values, using: serialization, log: log, operation)
        }
        try await setting {
            try await self.running(rest, with: values, using: serialization, log: log, operation)
        }
    }
}

extension ClusterSystemSettings {
    /// Makes the value of `taskLocal`, where it's set, travel with remote calls under `name`, for
    /// their targets to run with, as they would in a local call.
    ///
    /// Only declared task-locals travel, and only while set. Every node that should receive the
    /// value declares it too, under the same name.
    public mutating func propagateTaskLocal<Value: Codable & Sendable>(_ taskLocal: TaskLocal<Value?>, as name: String) {
        self.taskLocalPropagation.declare(taskLocal, as: name)
    }
}
