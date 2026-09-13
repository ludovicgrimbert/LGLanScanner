//
//  LanScanEngine.swift
//  LGLanScanner
//

import Foundation

/// Produces the events of one scan. ``LiveLanScanEngine`` sweeps the real network; apps
/// and tests can plug a fake one into ``LGLanScanner``.
///
/// The stream ends normally when the sweep completes or the consumer stops iterating, and
/// throws a ``LanScanError`` when the scan cannot run.
public protocol LanScanEngine: Sendable {
    func scan(_ configuration: LanScanConfiguration) -> AsyncThrowingStream<LanScanEvent, any Error>
}

/// Pings every address of the interface's subnet in batches, off the main thread, then
/// completes each answering device with its MAC (ARP cache), manufacturer (bundled OUI
/// registry) and name (reverse DNS / mDNS, bounded by a timeout).
///
/// A /24 with the default configuration takes two to three seconds: 254 hosts, 32 at a time,
/// 300 ms per batch. Nothing leaves the local network — no vendor API is queried.
public final class LiveLanScanEngine: LanScanEngine, Sendable {

    private let queue = DispatchQueue(label: "LGLanScanner.icmp", qos: .userInitiated)

    public init() {}

    public func scan(_ configuration: LanScanConfiguration) -> AsyncThrowingStream<LanScanEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LanScanEvent.self)
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
        _ configuration: LanScanConfiguration,
        queue: DispatchQueue,
        emit: @Sendable (LanScanEvent) -> Void
    ) async throws {
        guard let subnet = LocalNetwork.ipv4Subnet(interface: configuration.interface) else {
            throw LanScanError.noLocalNetwork(interface: configuration.interface)
        }
        guard subnet.hostCount <= configuration.maxHosts else {
            throw LanScanError.subnetTooLarge(hosts: subnet.hostCount, limit: configuration.maxHosts)
        }
        let hosts = subnet.hosts
        let gateway = RoutingTable.defaultGateway(interface: configuration.interface)
        let oui = OUITable.bundled
        let socket = try ICMPSocket()

        emit(.progress(0))
        var remaining = Set(hosts)
        var found = Set<IPv4Address>()
        var probed = 0
        var sendFailures = 0

        for start in stride(from: 0, to: hosts.count, by: configuration.batchSize) {
            try Task.checkCancellation()
            let batch = Array(hosts[start..<min(start + configuration.batchSize, hosts.count)])
            let accepting = remaining
            let result = try await blocking(on: queue) {
                socket.probe(batch, accepting: accepting, timeout: configuration.pingTimeout)
            }
            sendFailures += result.sendFailures

            let newAddresses = result.alive.subtracting(found).sorted()
            found.formUnion(newAddresses)
            remaining.subtract(newAddresses)

            let devices = await withTaskGroup(of: LanDevice.self, returning: [LanDevice].self) { group in
                for address in newAddresses {
                    group.addTask { await device(at: address, gateway: gateway, oui: oui, configuration: configuration) }
                }
                var devices: [LanDevice] = []
                for await device in group { devices.append(device) }
                return devices.sorted { IPv4Address($0.ipAddress)!.value < IPv4Address($1.ipAddress)!.value }
            }
            try Task.checkCancellation()
            for device in devices { emit(.device(device)) }

            probed += batch.count
            emit(.progress(Double(probed) / Double(hosts.count)))
        }

        if !hosts.isEmpty && sendFailures == hosts.count {
            throw LanScanError.localNetworkDenied
        }
    }

    private static func device(
        at address: IPv4Address,
        gateway: IPv4Address?,
        oui: OUITable,
        configuration: LanScanConfiguration
    ) async -> LanDevice {
        let mac = RoutingTable.macAddress(for: address) ?? ""
        let brand = oui.brand(for: mac) ?? ""
        let name = configuration.resolvesHostNames
            ? await HostNameResolver.name(for: address, timeout: configuration.hostNameTimeout) ?? ""
            : ""
        return LanDevice(name: name, ipAddress: address.description, mac: mac, brand: brand, isGateway: address == gateway)
    }

    /// Runs blocking socket work on the engine's serial queue, keeping the cooperative pool free.
    private static func blocking<T: Sendable>(on queue: DispatchQueue, _ work: @escaping @Sendable () -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
