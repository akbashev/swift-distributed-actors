import Foundation
import NIOCore

public enum RequestMessage: Codable, Sendable {
    case call(RemoteCallEnvelope)
    case join(Cluster.Endpoint)
    case connectionClosed
}

public struct RemoteCallEnvelope: Codable, Sendable {
    let recipient: ClusterSystem.ActorID
    let invocationTarget: String
    let genericSubs: [String]
    let args: [Data]
}

final class ByteToRequestMessage: ByteToMessageDecoder, MessageToByteEncoder {
    typealias InboundOut = RequestMessage
    typealias OutboundIn = RequestMessage

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        // Attempt to read full payload
        if let jsonBytes = buffer.readBytes(length: buffer.readableBytes) {
            let data = Data(jsonBytes)
            let req = try JSONDecoder().decode(RequestMessage.self, from: data)
            context.fireChannelRead(self.wrapInboundOut(req))
            return .continue
        }
        return .needMoreData
    }

    func encode(data: RequestMessage, out: inout ByteBuffer) throws {
        let encoded = try JSONEncoder().encode(data)
        out.writeBytes(encoded)
    }
}
