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

/// Dead letter errors may be transported back to remote callers, to indicate the recipient they tried to contact is no longer alive.
public struct DeadLetterError: DistributedActorSystemError, CustomStringConvertible, Hashable, Codable {
    public let recipient: ClusterSystem.ActorID

    internal let file: String?
    internal let line: UInt

    init(recipient: ClusterSystem.ActorID, file: String = #fileID, line: UInt = #line) {
        self.recipient = recipient
        self.file = file
        self.line = line
    }

    public func hash(into hasher: inout Hasher) {
        self.recipient.hash(into: &hasher)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.recipient == rhs.recipient
    }

    enum CodingKeys: CodingKey {
        case recipient
        case file
        case line
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.recipient = try container.decode(ClusterSystem.ActorID.self, forKey: .recipient)
        self.file = nil
        self.line = 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.recipient, forKey: .recipient)
        // We do NOT serialize source location, on purpose.
    }

    public var description: String {
        if let file {
            return "\(Self.self)(recipient: \(self.recipient), location: \(file):\(self.line))"
        }

        return "\(Self.self)(\(self.recipient))"
    }
}
