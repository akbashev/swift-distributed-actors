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

// FIXME: Put normal serialization error
public struct SerializationError: Swift.Error {
    let _error: _SerializationError

    internal enum _SerializationError {
        case notAbleToDeserialize(hint: String)
        case notEnoughArgumentsEncoded(expected: Int, have: Int)
    }

    init(_ error: _SerializationError) {
        self._error = error
    }
}
