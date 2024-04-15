import Distributed

/**
 This is a starting point to create some Event Sourcing with actors, thus very rudimentary.
 
 References:
 1. https://doc.akka.io/docs/akka/current/typed/persistence.html
 2. https://doc.akka.io/docs/akka/current/persistence.html
 3. https://learn.microsoft.com/en-us/dotnet/orleans/grains/grain-persistence/?pivots=orleans-7-0
 4. https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing
 */

public typealias PersistenceID = String

public protocol EventSourced: DistributedActor {
  associatedtype Event: Codable & Sendable

  distributed var persistenceId: PersistenceID { get }
  distributed func handleEvent(_ event: Event)
}

public protocol EventStore {
  func persistEvent<Event: Codable>(_ event: Event, id: PersistenceID) async throws
  func eventsFor<Event: Codable>(id: PersistenceID) async throws -> [Event]
}
