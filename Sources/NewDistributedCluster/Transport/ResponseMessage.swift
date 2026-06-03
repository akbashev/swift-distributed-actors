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
import NIOCore

public enum ResponseMessage: Codable, Sendable {
    case reply(ReplyEnvelope)
    case joined
    case connectionClosed
}

public enum ReplyEnvelope: Codable, Sendable {
    case value(Data)
    case error(String)
    case done
}

final class ByteToResponseMessage: ByteToMessageDecoder, MessageToByteEncoder {
    typealias InboundOut = ResponseMessage
    typealias OutboundIn = ResponseMessage

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        // Attempt to read full payload
        if let jsonBytes = buffer.readBytes(length: buffer.readableBytes) {
            let data = Data(jsonBytes)
            let req = try JSONDecoder().decode(ResponseMessage.self, from: data)
            context.fireChannelRead(self.wrapInboundOut(req))
            return .continue
        }
        return .needMoreData
    }

    func encode(data: ResponseMessage, out: inout ByteBuffer) throws {
        let encoded = try JSONEncoder().encode(data)
        out.writeBytes(encoded)
    }
}
