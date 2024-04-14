import Distributed

//// Here magic should happen
public actor ClusterJournalPlugin {
    
  public enum Error: Swift.Error {
    case factoryError
  }
  
  private var actorSystem: ClusterSystem!
  private var store: (ClusterSystem) async throws -> (any EventStore)
  private var emitContinuations: [PersistenceID: [CheckedContinuation<Void, Never>]] = [:]
  private var restoringActorTasks: [PersistenceID: Task<Void, Never>] = [:]
  
  public func emit<A: EventSourced>(_ event: A.Event, from actor: A) async throws {
    let store = try await self.store(self.actorSystem)
    try await actor.whenLocal { myself in
      let persistenceId = myself.persistenceId
      /// Checking if actor is in restoring state, if yes—wating until finished
      guard await self.restoringActorTasks[persistenceId] == .none else {
        await withCheckedContinuation { continuation in
          self.emitContinuations[persistenceId, default: []].append(continuation)
        }
        return try await store.persistEvent(event, id: persistenceId)
      }
      try await store.persistEvent(event, id: persistenceId)
    }
  }
  
  public func restoreEventsFor<A: EventSourced>(actor: A) async {
    await actor.whenLocal { [weak self] myself in
      let persistenceId = myself.persistenceId
      guard await self?.restoringActorTasks[persistenceId] == .none else { return }
      defer { Task { [weak self] in await self?.removeTaskFor(id: persistenceId) } }
      /// Checking if actor is already in restoring state
      let task = Task { [weak self] in
        do {
          let store = try await self!.store(self!.actorSystem)
          let events: [A.Event] = try await store.eventsFor(id: persistenceId)
          for event in events {
            try await actor.handleEvent(event)
          }
        } catch {
          // TODO: Add retry mechanism?
          await self?.actorSystem.log.error(
            "Cluster journal haven't been able to restore state of an actor \(persistenceId), reason: \(error)"
          )
        }
      }
      await self?.addTask(task, id: persistenceId)
    }
  }
  
  private func finishContinuationsFor(
    id: PersistenceID
  ) {
    for emit in (self.emitContinuations[id] ?? []) { emit.resume() }
    self.emitContinuations.removeValue(forKey: id)
  }
  
  // TODO: Remove when we can pass inherite isolation
  private func addTask(_ task: Task<Void, Never>, id: PersistenceID) {
    self.restoringActorTasks[id] = task
  }
  
  private func removeTaskFor(id: PersistenceID) {
    self.restoringActorTasks.removeValue(forKey: id)
    self.finishContinuationsFor(id: id)
  }
    
  public init<E: EventStore>(
    factory: @escaping (ClusterSystem) -> E
  ) {
    self.store = {
      try await $0
        .singleton
        .host(name: "\(ClusterJournalPlugin.pluginKey)_store") {
          factory($0)
        }
    }
  }
}

extension ClusterJournalPlugin: _Plugin {
  static let pluginKey: Key = "$clusterJournal"
  
  public nonisolated var key: Key {
    Self.pluginKey
  }
  
  public func start(_ system: ClusterSystem) async throws {
    self.actorSystem = system
  }
  
  public func stop(_ system: ClusterSystem) async {
    self.actorSystem = nil
    for task in self.restoringActorTasks.values { task.cancel() }
  }
}

extension ClusterSystem {
  
  public var journal: ClusterJournalPlugin {
    let key = ClusterJournalPlugin.pluginKey
    guard let journalPlugin = self.settings.plugins[key] else {
      fatalError("No plugin found for key: [\(key)], installed plugins: \(self.settings.plugins)")
    }
    return journalPlugin
  }
}

extension EventSourced where ActorSystem == ClusterSystem {
  public func emit(event: Event) async throws {
    try await self.actorSystem.journal.emit(event, from: self)
  }
}
