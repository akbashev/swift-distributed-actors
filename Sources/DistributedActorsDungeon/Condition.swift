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
////
////  Condition.swift
////  Atomics
////
////  Created by Dario Rexin on 6/11/18.
////
//
//#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
//import Darwin
//#else
//import Glibc
//#endif
//
//public final class Condition {
//  private var condition: pthread_cond_t = pthread_cond_t()
//
//  public init() {
//    let error = pthread_cond_init(&condition, nil)
//
//    switch error {
//    case 0:
//      return
//    default:
//      fatalError("Condition could not be created: \(error)")
//    }
//  }
//
//  deinit {
//    pthread_cond_destroy(&condition)
//  }
//
//  public func wait(_ mutex: Mutex) -> Void {
//    let error = pthread_cond_wait(&condition, &mutex.mutex)
//
//    switch error {
//    case 0:
//      return
//    case EPERM:
//      fatalError("Wait failed, mutex is not owned by this thread")
//    case EINVAL:
//      fatalError("Wait failed, condition is not valid")
//    default:
//      fatalError("Wait failed with unspecified error: \(error)")
//    }
//  }
//
//  public func signal() -> Void {
//    let error = pthread_cond_signal(&condition)
//
//    switch error {
//    case 0:
//      return
//    case EINVAL:
//      fatalError("Signal failed, condition is not valid")
//    default:
//      fatalError("Signal failed with unspecified error: \(error)")
//    }
//  }
//}