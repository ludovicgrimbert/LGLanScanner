//
//  SSDPDiscoveryEngine.swift
//  LGLanDiscovery
//

import Foundation

/// SSDP messages: the `M-SEARCH` request and the parsing of responses and `NOTIFY`s.
enum SSDPMessage {
    static let multicastHost = "239.255.255.250"
    static let multicastPort: UInt16 = 1900

    /// The search request for one target. `MX` is the seconds a device may wait before answering.
    static func search(target: String, mx: Int = 2) -> Data {
        let lines = [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(multicastHost):\(multicastPort)",
            "MAN: \"ssdp:discover\"",
            "MX: \(mx)",
            "ST: \(target)",
            "USER-AGENT: iOS UPnP/1.1 LGLanDiscovery/1.0",
            "", "",
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    /// Headers of a response (`HTTP/1.1 200 OK`) or an advertisement (`NOTIFY * HTTP/1.1`),
    /// keys lowercased. Nil for anything else, including our own `M-SEARCH` echoed back.
    static func parse(_ data: Data) -> [String: String]? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        if lines.count == 1 { lines = text.components(separatedBy: "\n") }
        guard let status = lines.first?.uppercased(),
              status.hasPrefix("HTTP/1.1 200") || status.hasPrefix("NOTIFY") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { headers[key] = value }
        }
        return headers
    }

    /// The target a message speaks for: `ST` in a response, `NT` in an advertisement.
    static func target(of headers: [String: String]) -> String? {
        headers["st"] ?? headers["nt"]
    }

    /// Whether the message matches one of the requested targets.
    static func matches(_ headers: [String: String], targets: [String]) -> Bool {
        guard let target = target(of: headers) else { return false }
        if headers["nts"]?.lowercased() == "ssdp:byebye" { return false }
        return targets.contains("ssdp:all") || targets.contains(target)
    }
}

/// The `<device>` block of a UPnP description document.
enum UPnPDescription {
    /// Fields that describe a device, from the description at `LOCATION`. Sony adds
    /// `x_scalarwebapi_baseurl`, the root of its JSON API.
    static let deviceFields: Set<String> = [
        "friendlyname", "manufacturer", "manufacturerurl", "modelname", "modeldescription",
        "modelnumber", "serialnumber", "udn", "x_scalarwebapi_baseurl",
    ]

    /// Lowercased element name → text, for the elements of ``deviceFields`` found anywhere
    /// in the document (the first occurrence wins, which is the root device's).
    static func parse(_ data: Data) -> [String: String] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.fields
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var fields: [String: String] = [:]
        private var current: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            let name = (elementName.split(separator: ":").last.map(String.init) ?? elementName).lowercased()
            if deviceFields.contains(name) {
                current = name
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if current != nil { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            guard let name = current else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if fields[name] == nil, !value.isEmpty { fields[name] = value }
            current = nil
        }
    }
}

/// One UDP socket for the search: multicasts the requests, then collects the unicast
/// answers. Blocking; used from one serial queue. (`NWConnectionGroup` joins the group but
/// never delivered the unicast replies, so this is plain BSD.)
final class SSDPSocket: @unchecked Sendable {
    struct Datagram {
        let data: Data
        let sender: String
    }

    private let fd: Int32
    private(set) var lastSendErrno: Int32 = 0

    init() throws(LanDiscoveryError) {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw .networkFailure("Could not open a UDP socket (errno \(errno)).") }
        var ttl: Int32 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    deinit { close(fd) }

    /// Multicasts one `M-SEARCH`. False (with `lastSendErrno`) when the kernel refused it.
    func search(_ target: String) -> Bool {
        let packet = SSDPMessage.search(target: target)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = SSDPMessage.multicastPort.bigEndian
        address.sin_addr.s_addr = inet_addr(SSDPMessage.multicastHost)
        let sent = packet.withUnsafeBytes { raw in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 { lastSendErrno = errno }
        return sent == packet.count
    }

    /// Everything that arrives within `window`.
    func receive(for window: Duration) -> [Datagram] {
        var datagrams: [Datagram] = []
        let deadline = ContinuousClock.now + window
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let remaining = deadline - .now
            guard remaining > .zero else { break }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, max(Int32(remaining / .milliseconds(1)), 1))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { break }

            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &from) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, raw.baseAddress, raw.count, 0, sa, &fromLength)
                    }
                }
            }
            guard count > 0 else { continue }
            datagrams.append(Datagram(data: Data(buffer[0..<Int(count)]), sender: String(cString: inet_ntoa(from.sin_addr))))
        }
        return datagrams
    }
}

/// Sends SSDP `M-SEARCH` requests to the UPnP multicast group and reports every device
/// that answers for one of the configured targets, enriched with its UPnP description
/// (`friendlyName`, `manufacturer`, `modelName`, Sony's `X_ScalarWebAPI_BaseURL`…).
///
/// Multicast on a device requires the `com.apple.developer.networking.multicast`
/// entitlement, which Apple grants on request; without it the engine fails with
/// ``LanDiscoveryError/multicastNotAllowed``. The simulator is not restricted.
public final class SSDPDiscoveryEngine: LanDiscoveryEngine, Sendable {

    private let queue = DispatchQueue(label: "LGLanDiscovery.ssdp", qos: .userInitiated)

    public init() {}

    public func discover(_ configuration: LanDiscoveryConfiguration) -> AsyncThrowingStream<LanDiscoveryEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LanDiscoveryEvent.self)
        guard !configuration.ssdpSearchTargets.isEmpty else {
            continuation.finish()
            return stream
        }
        let queue = queue
        let task = Task {
            do {
                try await Self.run(configuration, queue: queue) { continuation.yield($0) }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private static func run(
        _ configuration: LanDiscoveryConfiguration,
        queue: DispatchQueue,
        emit: @escaping @Sendable (LanDiscoveryEvent) -> Void
    ) async throws {
        let socket = try SSDPSocket()
        let targets = configuration.ssdpSearchTargets

        @Sendable func searchAll() throws {
            let sent = targets.map { socket.search($0) }
            guard sent.contains(true) else {
                switch socket.lastSendErrno {
                case EPERM, EACCES, ENETUNREACH, EADDRNOTAVAIL, EHOSTUNREACH:
                    throw LanDiscoveryError.multicastNotAllowed
                default:
                    throw LanDiscoveryError.networkFailure("Could not send the SSDP search (errno \(socket.lastSendErrno)).")
                }
            }
        }

        try await blocking(on: queue) { try searchAll() }
        let deadline = ContinuousClock.now + configuration.duration
        var repeated = false
        var reported: Set<String> = []

        try await withThrowingTaskGroup(of: Void.self) { group in
            while true {
                try Task.checkCancellation()
                let remaining = deadline - .now
                guard remaining > .zero else { break }
                let datagrams = try await blocking(on: queue) { socket.receive(for: min(remaining, .milliseconds(250))) }

                for datagram in datagrams {
                    guard let headers = SSDPMessage.parse(datagram.data),
                          SSDPMessage.matches(headers, targets: targets),
                          let target = SSDPMessage.target(of: headers),
                          let location = headers["location"], let url = URL(string: location)
                    else { continue }
                    let key = (headers["usn"] ?? location) + "|" + target
                    guard reported.insert(key).inserted else { continue }
                    let host = url.host ?? datagram.sender
                    let timeout = configuration.resolveTimeout
                    group.addTask {
                        var attributes = headers
                        if let description = await description(at: url, timeout: timeout) {
                            attributes.merge(description) { _, fetched in fetched }
                        }
                        try Task.checkCancellation()
                        emit(.found(LanService(
                            name: attributes["friendlyname"] ?? host,
                            type: target,
                            host: host,
                            port: url.port ?? 80,
                            attributes: attributes,
                            source: .ssdp
                        )))
                    }
                }

                // Devices answer within MX seconds; a second request catches the ones that
                // missed the first (UDP) without waiting the whole window.
                if !repeated, configuration.duration - remaining >= .seconds(1) {
                    repeated = true
                    try await blocking(on: queue) { try searchAll() }
                }
            }
            try await group.waitForAll()
        }
    }

    private static func description(at url: URL, timeout: Duration) async -> [String: String]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout / .seconds(1)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { return nil }
        let fields = UPnPDescription.parse(data)
        return fields.isEmpty ? nil : fields
    }

    private static func blocking<T: Sendable>(on queue: DispatchQueue, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }
}
