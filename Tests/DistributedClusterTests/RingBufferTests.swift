//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import Testing

@testable import DistributedCluster

struct RingBufferTests {
    let capacity: Int = 10

    @Test
    func test_isEmpty_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        buffer.isEmpty.shouldEqual(true)
    }

    @Test
    func test_isEmpty_non_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        _ = buffer.offer(element: 1)

        buffer.isEmpty.shouldEqual(false)
    }

    @Test
    func test_isEmpty_after_wrap() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        for i in 1...self.capacity {
            if buffer.offer(element: i) {
                _ = buffer.take()
            }
        }

        buffer.isEmpty.shouldEqual(true)
    }

    @Test
    func test_isFull_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        buffer.isFull.shouldEqual(false)
    }

    @Test
    func test_isFull_non_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        _ = buffer.offer(element: 1)

        buffer.isFull.shouldEqual(false)
    }

    @Test
    func test_isFull_full() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        for i in 1...self.capacity {
            _ = buffer.offer(element: i)
        }

        buffer.isFull.shouldEqual(true)
    }

    @Test
    func test_offer_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        for i in 1...self.capacity {
            buffer.offer(element: i).shouldEqual(true)
        }
    }

    @Test
    func test_offer_full() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        for i in 1...self.capacity {
            buffer.offer(element: i).shouldEqual(true)
        }

        buffer.offer(element: 1).shouldEqual(false)
    }

    @Test
    func test_take_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        buffer.take().shouldBeNil()
    }

    @Test
    func test_take_non_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        _ = buffer.offer(element: 1)

        buffer.take().shouldEqual(1)
    }

    @Test
    func test_peek_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        buffer.peek().shouldBeNil()
    }

    @Test
    func test_peek_non_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        _ = buffer.offer(element: 1)

        buffer.peek().shouldEqual(1)
    }

    @Test
    func test_peek_non_empty_multiple_calls() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        _ = buffer.offer(element: 1)

        for _ in 1...10 {
            buffer.peek().shouldEqual(1)
        }

        buffer.count.shouldEqual(1)
    }

    @Test
    func test_writeIndex_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        buffer.writeIndex.shouldEqual(0)
    }

    @Test
    func test_writeIndex_full() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        for i in 1...self.capacity {
            _ = buffer.offer(element: i)
        }

        buffer.writeIndex.shouldBeNil()
    }

    @Test
    func test_writeIndex_empty_after_wrap() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        for i in 1...self.capacity {
            _ = buffer.offer(element: i)
            _ = buffer.take()
        }

        buffer.writeIndex.shouldEqual(0)
    }

    @Test
    func test_readIndex_empty() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        buffer.readIndex.shouldBeNil()
    }

    @Test
    func test_readIndex_non_empty_first() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)

        _ = buffer.offer(element: 1)
        buffer.readIndex.shouldEqual(0)
    }

    @Test
    func test_readIndex_non_empty_middle() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        let middleIndex = (capacity / 2)

        for i in 1...middleIndex {
            _ = buffer.offer(element: i)
            _ = buffer.take()
        }
        _ = buffer.offer(element: 1)

        buffer.readIndex.shouldEqual(middleIndex)
    }

    @Test
    func test_readIndex_empty_after_wrap() {
        let buffer: RingBuffer<Int> = RingBuffer(capacity: capacity)
        for i in 1...self.capacity {
            _ = buffer.offer(element: i)
            _ = buffer.take()
        }

        buffer.readIndex.shouldBeNil()
    }
}
