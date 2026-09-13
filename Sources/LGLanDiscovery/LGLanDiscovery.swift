//
//  LGLanDiscovery.swift
//  LGLanDiscovery
//
//  Asks the network which devices offer a given service, instead of pinging every address.
//

import Foundation
import Observation

/// Runs the discovery engines together and exposes what they find, on the main actor.
/// `@Observable`: read `services`, `state` and `errors` straight from a SwiftUI view.
///
/// ```swift
/// @State private var discovery = LGLanDiscovery()          // Bonjour + SSDP, .televisions
/// …
/// ForEach(discovery.services) { service in Text("\(service.name) — \(service.host)") }
/// Button("Find TVs") { discovery.start() }
/// ```
///
/// The app must declare `NSLocalNetworkUsageDescription` and list the Bonjour types in
/// `NSBonjourServices`. SSDP additionally needs the multicast entitlement on a device; when
/// one engine cannot run its error lands in `errors` and the others carry on. `state` is
/// `.failed` only when every engine failed.
@Observable
@MainActor
public final class LGLanDiscovery {

    public enum State: Sendable, Hashable {
        case idle
        case discovering
        /// The listening window is over, or `stop()` was called.
        case finished
        /// Every engine failed.
        case failed
    }

    public private(set) var state: State = .idle
    /// Services currently announced, in discovery order, one per (source, type, host, port).
    public private(set) var services: [LanService] = []
    /// Engines that could not run during the current discovery.
    public private(set) var errors: [LanDiscoveryError] = []

    public var isDiscovering: Bool { state == .discovering }
    /// The services whose vendor could be recognised, one per host.
    public var televisions: [LanService] {
        var seen: Set<String> = []
        return services.filter { $0.vendor != .unknown && seen.insert($0.host).inserted }
    }

    /// Applied to the next `start()`.
    public var configuration: LanDiscoveryConfiguration

    private let engines: [any LanDiscoveryEngine]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var failed = 0

    /// - Parameters:
    ///   - engines: run concurrently; Bonjour and SSDP by default.
    ///   - configuration: what to look for and for how long; `.televisions` by default.
    public init(
        engines: [any LanDiscoveryEngine] = [BonjourDiscoveryEngine(), SSDPDiscoveryEngine()],
        configuration: LanDiscoveryConfiguration = .televisions
    ) {
        self.engines = engines
        self.configuration = configuration
    }

    /// Starts a discovery, discarding the results of the previous one.
    public func start() {
        cancelTasks()
        generation += 1
        state = .discovering
        services = []
        errors = []
        pending = engines.count
        failed = 0
        guard pending > 0 else {
            state = .finished
            return
        }

        let generation = generation
        // One task per engine, all on the main actor (inherited), so `apply` and the
        // bookkeeping below never race. A stale generation means `stop()` or a restart.
        for engine in engines {
            let stream = engine.discover(configuration)
            tasks.append(Task { [weak self] in
                var failure: LanDiscoveryError?
                do {
                    for try await event in stream {
                        guard let self, self.generation == generation else { return }
                        self.apply(event)
                    }
                } catch {
                    failure = error as? LanDiscoveryError ?? .networkFailure(error.localizedDescription)
                }
                guard let self, self.generation == generation else { return }
                if let failure {
                    self.errors.append(failure)
                    self.failed += 1
                }
                self.pending -= 1
                if self.pending == 0 {
                    self.state = self.failed == self.engines.count ? .failed : .finished
                }
            })
        }
    }

    /// Ends the current discovery; what was found stays in `services`.
    public func stop() {
        cancelTasks()
        generation += 1
        if state == .discovering { state = .finished }
    }

    private func cancelTasks() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func apply(_ event: LanDiscoveryEvent) {
        switch event {
        case .found(let service):
            if let index = services.firstIndex(where: { $0.id == service.id }) {
                services[index] = service
            } else {
                services.append(service)
            }
        case .lost(let service):
            services.removeAll { $0.id == service.id }
        }
    }
}
