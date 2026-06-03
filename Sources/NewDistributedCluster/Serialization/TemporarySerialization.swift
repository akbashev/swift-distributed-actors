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

// FIXME: Fix with proper serialisation
public struct TemporarySerialization: Sendable {

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    func updateKeys(using clusterSystem: ClusterSystem) {
        self.encoder.userInfo[.actorSystemKey] = clusterSystem
        self.decoder.userInfo[.actorSystemKey] = clusterSystem
    }

    public func serialize<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public func deserialize<T: Decodable>(as: T.Type, from data: Data) throws -> T {
        try decoder.decode(T.self, from: data)
    }
}
