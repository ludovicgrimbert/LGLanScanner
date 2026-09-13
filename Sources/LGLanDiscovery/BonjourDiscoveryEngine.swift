//
//  BonjourDiscoveryEngine.swift
//  LGLanDiscovery
//

import Foundation
import Network

/// Browses Bonjour (mDNS) for the configured service types with `NWBrowser`, then resolves
/// each service to an IPv4 address and port by opening (and immediately closing) a TCP
/// connection to it — the supported way to learn a Bonjour endpoint's address.
///
/// The app must list every type in `NSBonjourServices` and declare
/// `NSLocalNetworkUsageDescription`; no entitlement is needed.
public final class BonjourDiscoveryEngine: LanDiscoveryEngine, Sendable {

    public init() {}

    public func discover(_ configuration: LanDiscoveryConfiguration) -> AsyncThrowingStream<LanDiscoveryEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LanDiscoveryEvent.self)
        guard !configuration.bonjourServiceTypes.isEmpty else {
            continuation.finish()
            return stream
        }
        let session = BonjourSession(configuration: configuration, continuation: continuation)
        session.start()
        let timer = Task {
            try? await Task.sleep(for: configuration.duration)
            guard !Task.isCancelled else { return }
            session.stop()
            continuation.finish()
        }
        continuation.onTermination = { _ in
            timer.cancel()
            session.stop()
        }
        return stream
    }
}

/// One browse: a browser per type, resolutions in flight, and what was already reported.
/// Every member is touched on `queue` only.
private final class BonjourSession: @unchecked Sendable {
    private let configuration: LanDiscoveryConfiguration
    private let continuation: AsyncThrowingStream<LanDiscoveryEvent, any Error>.Continuation
    private let queue = DispatchQueue(label: "LGLanDiscovery.bonjour")
    private var browsers: [NWBrowser] = []
    private var failures: [String: NWError] = [:]
    private var resolving: [NWEndpoint: NWConnection] = [:]
    private var known: [NWEndpoint: LanService] = [:]
    private var stopped = false

    init(configuration: LanDiscoveryConfiguration, continuation: AsyncThrowingStream<LanDiscoveryEvent, any Error>.Continuation) {
        self.configuration = configuration
        self.continuation = continuation
    }

    func start() {
        queue.async { [self] in
            for type in configuration.bonjourServiceTypes {
                let parameters = NWParameters()
                parameters.includePeerToPeer = false
                // `bonjourWithTXTRecord` is what fills `result.metadata`; plain `.bonjour` leaves it empty.
                let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: parameters)
                browser.stateUpdateHandler = { [weak self] state in self?.browser(type: type, changed: state) }
                browser.browseResultsChangedHandler = { [weak self] _, changes in self?.apply(changes, type: type) }
                browsers.append(browser)
                browser.start(queue: queue)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            browsers.forEach { $0.cancel() }
            resolving.values.forEach { $0.cancel() }
            browsers = []
            resolving = [:]
        }
    }

    private func browser(type: String, changed state: NWBrowser.State) {
        guard !stopped else { return }
        switch state {
        case .failed(let error), .waiting(let error):
            failures[type] = error
            // One refused type is a configuration slip; all of them refused is a real failure.
            if failures.count == configuration.bonjourServiceTypes.count {
                stopped = true
                browsers.forEach { $0.cancel() }
                continuation.finish(throwing: Self.map(error, type: type))
            }
        default:
            break
        }
    }

    private static func map(_ error: NWError, type: String) -> LanDiscoveryError {
        switch error {
        case .dns(let code) where code == -65570 /* kDNSServiceErr_PolicyDenied */:
            .browsingNotAllowed(type: type)
        case .posix(let code) where code == .EPERM || code == .EACCES:
            .browsingNotAllowed(type: type)
        default:
            .networkFailure(error.localizedDescription)
        }
    }

    private func apply(_ changes: Set<NWBrowser.Result.Change>, type: String) {
        guard !stopped else { return }
        for change in changes {
            switch change {
            case .added(let result):
                resolve(result, type: type)
            case .removed(let result):
                resolving[result.endpoint]?.cancel()
                resolving[result.endpoint] = nil
                if let service = known.removeValue(forKey: result.endpoint) {
                    continuation.yield(.lost(service))
                }
            case .changed(_, let new, _):
                if known[new.endpoint] == nil { resolve(new, type: type) }
            default:
                break
            }
        }
    }

    private func resolve(_ result: NWBrowser.Result, type: String) {
        guard case .service(let name, _, _, _) = result.endpoint, resolving[result.endpoint] == nil else { return }
        let attributes: [String: String]
        if case .bonjour(let record) = result.metadata { attributes = record.dictionary } else { attributes = [:] }

        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: result.endpoint, using: parameters)
        resolving[result.endpoint] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                    let service = LanService(name: name, type: type, host: Self.literal(host), port: Int(port.rawValue),
                                             attributes: attributes, source: .bonjour)
                    known[result.endpoint] = service
                    if !stopped { continuation.yield(.found(service)) }
                }
                finish(connection, for: result.endpoint)
            case .failed, .cancelled:
                finish(connection, for: result.endpoint)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + .nanoseconds(Int(configuration.resolveTimeout / .nanoseconds(1)))) { [weak self] in
            guard let self, resolving[result.endpoint] === connection else { return }
            finish(connection, for: result.endpoint)
        }
    }

    private func finish(_ connection: NWConnection, for endpoint: NWEndpoint) {
        connection.cancel()
        if resolving[endpoint] === connection { resolving[endpoint] = nil }
    }

    /// `192.168.1.24`, without the `%en0` interface scope Network appends to link-local addresses.
    private static func literal(_ host: NWEndpoint.Host) -> String {
        let text: String
        switch host {
        case .ipv4(let address): text = "\(address)"
        case .ipv6(let address): text = "\(address)"
        case .name(let name, _): text = name
        @unknown default: text = "\(host)"
        }
        return text.split(separator: "%").first.map(String.init) ?? text
    }
}
