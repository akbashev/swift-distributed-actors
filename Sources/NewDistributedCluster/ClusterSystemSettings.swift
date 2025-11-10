//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIO

import class Foundation.ProcessInfo

/// Settings used to configure a `ClusterSystem`.
public struct ClusterSystemSettings: Sendable {
    public enum Default {
        public static let name: String = "ClusterSystem"
        public static let bindHost: String = "127.0.0.1"
        public static let bindPort: Int = 7337
    }

    public static var `default`: ClusterSystemSettings {
        let defaultEndpoint = Cluster.Endpoint(systemName: Default.name, host: Default.bindHost, port: Default.bindPort)
        return ClusterSystemSettings(endpoint: defaultEndpoint)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Connection establishment, protocol settings

    /// Hostname used to accept incoming connections from other nodes.
    public var bindHost: String {
        set {
            self.endpoint.host = newValue
        }
        get {
            self.endpoint.host
        }
    }

    /// Port used to accept incoming connections from other nodes.
    public var bindPort: Int {
        set {
            self.endpoint.port = newValue
        }
        get {
            self.endpoint.port
        }
    }

    /// Node representing this node in the cluster.
    /// Note that most of the time `uniqueBindNode` is more appropriate, as it includes this node's unique id.
    public var endpoint: Cluster.Endpoint

    /// `Cluster.Node.ID` to be used when exposing `Cluster.Node` for node configured by using these settings.
    public var nid: Cluster.Node.ID

    public var node: Cluster.Node {
        Cluster.Node(endpoint: self.endpoint, nid: self.nid)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Logging

    /// If enabled, logs membership changes (including the entire membership table from the perspective of the current node).
    public var logMembershipChanges: Logger.Level? = .debug

    /// When enabled traces _all_ incoming and outgoing cluster (e.g. handshake) protocol communication (remote messages).
    /// All logs will be prefixed using `[tracelog:cluster]`, for easier grepping.
    #if SACT_TRACE_CLUSTER
    public var traceLogLevel: Logger.Level? = .warning
    #else
    public var traceLogLevel: Logger.Level?
    #endif

    public var logging: LoggingSettings = .default

    public init(name: String, host: String = Default.bindHost, port: Int = Default.bindPort) {
        self.init(endpoint: Cluster.Endpoint(systemName: name, host: host, port: port))
    }

    public init(endpoint: Cluster.Endpoint) {
        self.endpoint = endpoint
        self.nid = Cluster.Node.ID.random()
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Logging Settings

/// Settings which allow customizing logging behavior by various sub-systems of the cluster system.
///
public struct LoggingSettings: Sendable {
    public static var `default`: LoggingSettings {
        .init()
    }

    /// Customize the default log level of the `system.log` (and `context.log`) loggers.
    ///
    /// This this modifies the current "base" logger which is `LoggingSettings.logger`,
    /// it is also possible to change the logger itself, e.g. if you care about reusing a specific logger
    /// or need to pass metadata through all loggers in the actor system.
    public var logLevel: Logger.Level {
        get {
            self._logger.logLevel
        }
        set {
            self._logger.logLevel = newValue
        }
    }

    /// "Base" logger that will be used as template for all loggers created by the system.
    ///
    /// Do not use this logger directly, but rather use `system.log` or  `Logger(actor:)`,
    /// as they have more useful metadata configured on them which is obtained during cluster
    /// initialization.
    ///
    /// This may be used to configure specific systems to log to specific files,
    /// or to carry system-wide metadata throughout all loggers the actor system will use.
    public var baseLogger: Logger {
        get {
            self._logger
        }
        set {
            self.customizedLogger = true
            self._logger = newValue
        }
    }

    internal var customizedLogger: Bool = false
    internal var _logger = Logger(label: "ClusterSystem-initializing")  // replaced by specific system name during startup

    internal var useBuiltInFormatter: Bool = true

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Verbose logging of sub-systems (again, would not be needed with configurable appenders)

    /// Log all detailed timer start/cancel events
    internal var verboseTimers = false

    /// Log all actor creation events (`assignID`, `actorReady`)
    internal var verboseSpawning = false

    internal var verboseResolve = false
}
