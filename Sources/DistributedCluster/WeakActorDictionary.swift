//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Distributed

/// A dictionary which only weakly retains the
public struct WeakActorDictionary<Act: DistributedActor>: ExpressibleByDictionaryLiteral
    where Act.ID == ClusterSystem.ActorID
{
    var underlying: [ClusterSystem.ActorID: DistributedActorRef.Weak<Act>]

    /// Initialize an empty dictionary.
    public init() {
        self.underlying = [:]
    }

    public init(dictionaryLiteral elements: (Act.ID, Act)...) {
        self.underlying = [:]
        self.underlying.reserveCapacity(elements.count)
        for (id, actor) in elements {
            self.underlying[id] = .init(actor)
        }
    }

    /// Insert the passed in actor into the dictionary.
    ///
    /// Note that the dictionary only holds the actor weakly,
    /// so if no other strong references to the actor remain this dictionary
    /// will not contain the actor anymore.
    ///
    /// - Parameter actor:
    public mutating func insert(_ actor: Act) {
        self.underlying[actor.id] = DistributedActorRef.Weak(actor)
    }

    public mutating func getActor(identifiedBy id: ClusterSystem.ActorID) -> Act? {
        guard let reference = underlying[id] else {
            // unknown id
            return nil
        }

        guard let knownActor = reference.actor else {
            // the actor was released -- let's remove the reference while we're here
            _ = self.removeActor(identifiedBy: id)
            return nil
        }

        return knownActor
    }

    public mutating func removeActor(identifiedBy id: ClusterSystem.ActorID) -> Act? {
        return self.underlying.removeValue(forKey: id)?.actor
    }
}

/// A type erased dictionary which only weakly retains the
public struct WeakAnyDistributedActorDictionary {
    
    var underlying: [ClusterSystem.ActorID: DistributedActorRef.WeakAny]

    public init() {
        self.underlying = [:]
    }

    mutating func removeActor(identifiedBy id: ClusterSystem.ActorID) -> Bool {
        return self.underlying.removeValue(forKey: id) != nil
    }

    mutating func insert<Act: DistributedActor>(actor: Act) where Act.ID == ClusterSystem.ActorID {
        self.underlying[actor.id] = .init(actor)
    }

    mutating func get(identifiedBy id: ClusterSystem.ActorID) -> (any DistributedActor)? {
        guard let reference = underlying[id] else {
            // unknown id
            return nil
        }

        guard let knownActor = reference.actor else {
            // the actor was released -- let's remove the reference while we're here
            _ = self.removeActor(identifiedBy: id)
            return nil
        }

        return knownActor
    }
}

public enum DistributedActorRef {
    
    /// Wrapper class for weak `distributed actor` references.
    ///
    /// Allows for weak storage of distributed actor references inside collections,
    /// although those collections need to be manually cleared from dead references.
    ///
    public final class Weak<Act: DistributedActor>: CustomStringConvertible {
        public weak var actor: Act?

        public init(_ actor: Act) {
            self.actor = actor
        }
        
        public var description: String {
            "DistributedActorRef.Weak(\(self.actor, orElse: "nil"))"
        }
    }
    
    /// Type erased wrapper class for weak `distributed actor` references.
    ///
    /// Allows for weak storage of distributed actor references inside collections,
    /// although those collections need to be manually cleared from dead references.
    ///
    public final class WeakAny: CustomStringConvertible {
        public weak var actor: (any DistributedActor)?

        public init(_ actor: any DistributedActor) {
            self.actor = actor
        }
        
        public var description: String {
            "DistributedActorRef.WeakAny(\(self.actor, orElse: "nil")))"
        }
    }
    
    /// Wrapper class for weak `distributed actor` references.
    ///
    /// Allows for weak storage of distributed actor references inside collections,
    /// although those collections need to be manually cleared from dead references.
    ///
    public final class WeakWhenLocal<Act: DistributedActor>: CustomStringConvertible {
        private weak var weakLocalRef: Act?
        private let remoteRef: Act?
        
        public init(_ actor: Act) {
            if __isRemoteActor(actor) {
                self.remoteRef = actor
                self.weakLocalRef = nil
            } else {
                self.remoteRef = nil
                self.weakLocalRef = actor
            }
            
            assert((self.remoteRef == nil && self.weakLocalRef != nil) ||
                   (self.remoteRef != nil && self.weakLocalRef == nil),
                   "Only a single var may hold the actor: remote: \(self.remoteRef, orElse: "nil"), \(self.weakLocalRef, orElse: "nil")")
        }
        
        public var actor: Act? {
            remoteRef ?? weakLocalRef
        }
        
        public var description: String {
            "DistributedActorRef.WeakWhenLocal(\(self.actor, orElse: "nil"), isLocal: \(self.remoteRef == nil))"
        }
    }
}
