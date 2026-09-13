//
//  LanDevice.swift
//  LGLanScanner
//

import Foundation

/// A device that answered on the local network. Identified by its IP address.
public struct LanDevice: Sendable, Hashable, Identifiable {
    /// Reverse-DNS or mDNS name, empty when the device has none.
    public let name: String
    /// Dotted IPv4 address, e.g. `192.168.1.24`.
    public let ipAddress: String
    /// Hardware address, lowercase `aa:bb:cc:dd:ee:ff`; empty when the ARP cache had none.
    public let mac: String
    /// Manufacturer from the bundled OUI registry, empty when unknown.
    public let brand: String
    /// `true` for the default gateway (the router).
    public let isGateway: Bool

    public var id: String { ipAddress }

    public init(name: String = "", ipAddress: String, mac: String = "", brand: String = "", isGateway: Bool = false) {
        self.name = name
        self.ipAddress = ipAddress
        self.mac = mac
        self.brand = brand
        self.isGateway = isGateway
    }
}

/// What a scan emits, in order: progress steps interleaved with the devices found.
public enum LanScanEvent: Sendable, Hashable {
    /// 0...1, monotonic.
    case progress(Double)
    case device(LanDevice)
}

/// Why a scan could not run or complete.
public enum LanScanError: Error, Hashable, LocalizedError {
    /// The interface has no IPv4 address: no Wi-Fi, or the device is on cellular only.
    case noLocalNetwork(interface: String)
    /// The subnet has more hosts than ``LanScanConfiguration/maxHosts`` allows.
    case subnetTooLarge(hosts: Int, limit: Int)
    /// The ICMP socket could not be created (`errno`).
    case socketUnavailable(errno: Int32)
    /// Every probe failed to send. On iOS this is what a denied local-network permission
    /// looks like; the app can point the user to Settings.
    case localNetworkDenied
    /// An engine failed with an error that is not a `LanScanError`.
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .noLocalNetwork(let interface):
            "No IPv4 network on \(interface). Connect to Wi-Fi and try again."
        case .subnetTooLarge(let hosts, let limit):
            "The network has \(hosts) addresses, more than the \(limit) this scan allows."
        case .socketUnavailable(let errno):
            "Could not open a ping socket (errno \(errno))."
        case .localNetworkDenied:
            "Local network access is not allowed. Enable it for this app in Settings."
        case .unexpected(let description):
            description
        }
    }
}

/// Knobs of a scan. The defaults sweep a /24 in two to three seconds.
public struct LanScanConfiguration: Sendable, Hashable {
    /// The interface whose IPv4 subnet is scanned. `en0` is Wi-Fi on every iPhone and iPad.
    public var interface: String
    /// How long a batch of probes waits for answers. LAN round trips are a few milliseconds;
    /// sleepy devices can take longer.
    public var pingTimeout: Duration
    /// How many hosts are probed at once.
    public var batchSize: Int
    /// Refuse subnets with more usable hosts than this (a /22 has 1022).
    public var maxHosts: Int
    /// Ask the network for each device's name (reverse DNS / mDNS).
    public var resolvesHostNames: Bool
    /// How long a name lookup may take before the device is reported without one.
    public var hostNameTimeout: Duration

    public init(
        interface: String = "en0",
        pingTimeout: Duration = .milliseconds(300),
        batchSize: Int = 32,
        maxHosts: Int = 1024,
        resolvesHostNames: Bool = true,
        hostNameTimeout: Duration = .seconds(1)
    ) {
        self.interface = interface
        self.pingTimeout = pingTimeout
        self.batchSize = max(1, batchSize)
        self.maxHosts = max(1, maxHosts)
        self.resolvesHostNames = resolvesHostNames
        self.hostNameTimeout = hostNameTimeout
    }
}
