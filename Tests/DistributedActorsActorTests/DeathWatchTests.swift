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

import Foundation
import XCTest
@testable import Swift Distributed ActorsActor
import Swift Distributed ActorsActorTestkit

class DeathWatchTests: XCTestCase {

    let system = ActorSystem("ActorSystemTests")
    lazy var testKit: ActorTestKit = ActorTestKit(system: system)

    // MARK: Termination watcher

    enum TerminationWatcherMessages {
        case watch(who: ActorRef<String>, notifyOnDeath: ActorRef<String>) // TODO: abstracting over this needs type erasure?
    }

    override func tearDown() {
        // Await.on(system.terminate()) // FIXME termination that actually does so
    }

    // MARK: stopping actors

    private func stopOnAnyMessage(probe: ActorRef<String>?) -> Behavior<StoppableRefMessage> {
        return .receive { (context, message) in
            switch message {
            case .stop:
                probe?.tell("I (\(context.path)) will now stop")
                return .stopped
            }
        }
    }

    func test_watch_shouldTriggerTerminatedWhenWatchedActorStops() throws {
        let p: ActorTestProbe<String> = ActorTestProbe(named: "px", on: system)
        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(stopOnAnyMessage(probe: p.ref), named: "stopMePlz0")

        p.watch(stoppableRef)

        stoppableRef.tell(.stop)

        // the order of these messages is also guaranteed:
        // 1) first the dying actor has last chance to signal a message,
        try p.expectMessage("I (/user/stopMePlz0) will now stop")
        // 2) and then terminated messages are sent:
        // try p.expectMessage("/user/terminationWatcher received .terminated for: /user/stopMePlz")
        try p.expectTerminated(stoppableRef)
    }

    func test_watch_fromMultipleActors_shouldTriggerTerminatedWhenWatchedActorStops() throws {
        let p: ActorTestProbe<String> = ActorTestProbe(named: "p", on: system)
        let p1: ActorTestProbe<String> = ActorTestProbe(named: "p1", on: system)
        let p2: ActorTestProbe<String> = ActorTestProbe(named: "p2", on: system)

        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(stopOnAnyMessage(probe: p.ref), named: "stopMePlz1")

        p1.watch(stoppableRef)
        p2.watch(stoppableRef)

        stoppableRef.tell(.stop)
        stoppableRef.tell(.stop) // should result in dead letter
        stoppableRef.tell(.stop) // should result in dead letter
        stoppableRef.tell(.stop) // should result in dead letter

        try p.expectMessage("I (/user/stopMePlz1) will now stop")
        // since the first message results in the actor becoming .stopped
        // it should not be able to forward any new messages after the first one:
        try p.expectNoMessage(for: .milliseconds(100))

//    try p1.expectTerminated(stoppableRef)
//    try p2.expectTerminated(stoppableRef)
        Thread.sleep(.milliseconds(1000))
    }

    func test_watch_fromMultipleActors_shouldNotifyOfTerminationOnlyCurrentWatchers() throws {
        let p: ActorTestProbe<String> = ActorTestProbe(named: "p", on: system)
        let p1: ActorTestProbe<String> = ActorTestProbe(named: "p1", on: system)
        let p2: ActorTestProbe<String> = ActorTestProbe(named: "p2", on: system)

        // p3 will not watch by itself, but serve as our observer for what our in-line defined watcher observes
        let p3_partnerOfNotActuallyWatching: ActorTestProbe<String> = ActorTestProbe(named: "p3-not-really", on: system)

        let stoppableRef: ActorRef<StoppableRefMessage> = try system.spawn(stopOnAnyMessage(probe: p.ref), named: "stopMePlz2")

        p1.watch(stoppableRef)
        p2.watch(stoppableRef)
        let notActuallyWatching: ActorRef<String> = try system.spawn(.setup { context in
            context.watch(stoppableRef) // watching...
            context.unwatch(stoppableRef) // ... not *actually* watching!
            return Behavior<String>.receiveMessage { message in
                    switch message {
                    case "ping":
                        p3_partnerOfNotActuallyWatching.tell("pong")
                        return .same
                    default:
                        fatalError("no other message is expected")
                    }
                }
                .receiveSignal { (context, signal) in
                    p3_partnerOfNotActuallyWatching.tell("whoops: actually DID receive terminated!")
                    return .same
                }
        }, named: "notActuallyWatching")

        // we need to perform this ping/pong dance since watch/unwatch are async, so we only know they have been sent
        // once we get a reply for a message from this actor (i.e. it has completed its setup).
        notActuallyWatching.tell("ping")
        try p3_partnerOfNotActuallyWatching.expectMessage("pong")

        stoppableRef.tell(.stop)

        try p.expectMessage("I (/user/stopMePlz2) will now stop")

        try p1.expectTerminated(stoppableRef)
        try p2.expectTerminated(stoppableRef)
        try p3_partnerOfNotActuallyWatching.expectNoMessage(for: .milliseconds(1000)) // make su
    }

    func test_minimized_deathPact_shouldTriggerForWatchedActor() throws {
        let probe = ActorTestProbe<String>(named: "pp", on: system)

        let juliet = try system.spawn(Behavior<String>.receiveMessage { msg in
            return .same
        }, named: "juliet")

        let romeo = try system.spawn(Behavior<String>.setup { context in
            context.watch(juliet)

            return .receiveMessage { msg in
                probe.ref.tell("reply:\(msg)")
                return .same
            }
        }, named: "romeo")

        probe.watch(juliet)
        probe.watch(romeo)

        romeo ! "hi"
        try probe.expectMessage("reply:hi")

        // internal hacks
        let fakeTerminated: SystemMessage = .terminated(ref: juliet.internal_boxAnyAddressableActorRef(), existenceConfirmed: true)
        romeo.internal_boxAnyReceivesSignals().sendSystemMessage(fakeTerminated)

        try probe.expectTerminated(romeo)
    }

    func test_minimized_deathPact_shouldNotTriggerForActorThatWasWatchedButIsNotAnymoreWhenTerminatedArrives() throws {
        // Tests a very specific situation where romeo watches juliet, juliet terminates and sends .terminated
        // yet during that time, romeo unwatches her. This means that the .terminated message could arrive at
        // romeo AFTER the unwatch has been triggered. In this situation we DO NOT want to trigger the death pact,
        // since romeo by that time "does not care" about juliet anymore and should not die because of the .terminated.
        //
        // The .terminated message should also NOT be delivered to the .receiveSignal handler, it should be as if the watcher
        // never watched juliet to begin with. (This also is important so Swift Distributed Actors semantics are the same as what users would manually be able to to)

        let probe = ActorTestProbe<String>(named: "pp", on: system)

        let juliet = try system.spawn(Behavior<String>.receiveMessage { msg in
            return .same
        }, named: "juliet")

        let romeo = try system.spawn(Behavior<String>.receive { context, message in
            switch message {
            case "watch":
                context.watch(juliet)
                probe.tell("reply:watch")
            case "unwatch":
                context.unwatch(juliet)
                probe.tell("reply:unwatch")
            default:
                fatalError("should not happen")
            }
            return .same
        }.receiveSignal { context, signal in
            if case let .terminated(ref) = signal {
                probe.tell("Unexpected terminated received!!! \(ref)")
            }
            return .same
        }, named: "romeo")

        probe.watch(juliet)
        probe.watch(romeo)

        romeo ! "watch"
        try probe.expectMessage("reply:watch")
        romeo ! "unwatch"
        try probe.expectMessage("reply:unwatch")

        // internal hacks; we simulate that Juliet has terminated, and enqueued the .terminated before the unwatch managed to reach her
        let fakeTerminated: SystemMessage = .terminated(ref: juliet.internal_boxAnyAddressableActorRef(), existenceConfirmed: true)
        romeo.internal_boxAnyReceivesSignals().sendSystemMessage(fakeTerminated)

        // should NOT trigger the receiveSignal handler (which notifies the probe)
        try probe.expectNoMessage(for: .milliseconds(100))
    }

    func test_watch_anAlreadyStoppedActorRefShouldReplyWithTerminated() throws {
        let p: ActorTestProbe<String> = ActorTestProbe(named: "alreadyDeadWatcherProbe", on: system)

        let alreadyDead: ActorRef<String> = try system.spawn(.stopped, named: "alreadyDead")

        p.watch(alreadyDead)
        try p.expectTerminated(alreadyDead)

        // even if a new actor comes in and performs the watch, it also should notice that `alreadyDead` is dead
        let p2: ActorTestProbe<String> = ActorTestProbe(named: "alreadyDeadWatcherProbe2", on: system)
        p2.watch(alreadyDead)
        try p2.expectTerminated(alreadyDead)

        // `p` though should not accidentally get another .terminated when p2 installed the watch.
        try p.expectNoTerminationSignal(for: .milliseconds(200))
    }

    // MARK: Death pact

    func test_deathPact_shouldMakeWatcherKillItselfWhenWatcheeDies() throws {
        let romeo = try system.spawn(Behavior<RomeoMessage>.receive { (context, message) in
            switch message {
            case let .pleaseWatch(juliet, probe):
                context.watch(juliet)
                probe.tell(.done)
                return .same
            }
        }/* NOT handling signal on purpose, we are in a Death Pact */, named: "romeo")

        let juliet = try system.spawn(Behavior<JulietMessage>.receiveMessage { message in
            switch message {
            case .takePoison:
                return .stopped // "kill myself" // TODO: throw
            }
        }, named: "juliet")

        let p = ActorTestProbe<Done>(named: "p", on: system)

        p.watch(juliet)
        p.watch(romeo)

        romeo.tell(.pleaseWatch(juliet: juliet, probe: p.ref))
        try p.expectMessage(.done)

        juliet.tell(.takePoison)

        try p.expectTerminated(juliet) // TODO: not actually guaranteed in the order here
        try p.expectTerminated(romeo) // TODO: not actually guaranteed in the order here
    }

    // MARK: Watching dead letters ref

//    // FIXME: Make deadLetters a real thing, currently it is too hacky (i.e. this will crash):
//    func test_deadLetters_canBeWatchedAndAlwaysImmediatelyRepliesWithTerminated() throws {
//      let p: ActorTestProbe<Never> = .init(named: "deadLetter-probe", on: system)
//
//        p.watch(system.deadLetters)
//        try p.expectTerminated(system.deadLetters)
//    }
}

private enum Done {
    case done
}

private enum RomeoMessage {
    case pleaseWatch(juliet: ActorRef<JulietMessage>, probe: ActorRef<Done>)
}

private enum JulietMessage {
    case takePoison
}

private enum StoppableRefMessage {
    case stop
}
