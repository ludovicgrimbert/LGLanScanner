//
//  LanService.swift
//  LGLanDiscovery
//

import Foundation

/// A service a device announces on the local network, found by Bonjour or SSDP.
public struct LanService: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable, Hashable {
        case bonjour
        case ssdp
    }

    /// Human name: the Bonjour instance name, or UPnP's `friendlyName`.
    public let name: String
    /// What was announced: a Bonjour type (`_googlecast._tcp`) or an SSDP search target
    /// (`urn:schemas-sony-com:service:IRCC:1`).
    public let type: String
    /// Dotted IPv4 address of the device (IPv6 literal when it has no IPv4).
    public let host: String
    /// The service port (Bonjour), or the port of the UPnP description URL (SSDP).
    public let port: Int
    /// Bonjour TXT record, or SSDP response headers plus the `device` fields of the UPnP
    /// description (`friendlyname`, `manufacturer`, `modelname`, `udn`…). Keys are lowercased.
    public let attributes: [String: String]
    public let source: Source

    public var id: String { "\(source.rawValue)|\(type)|\(host):\(port)" }

    public init(name: String, type: String, host: String, port: Int, attributes: [String: String] = [:], source: Source) {
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.attributes = attributes.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
        self.source = source
    }

    /// Best guess of the television vendor, from what the service says about itself.
    public var vendor: LanServiceVendor {
        let haystack = ([name, type] + attributes.values.map { $0 }).joined(separator: " ").lowercased()
        if haystack.contains("sony") || haystack.contains("bravia") { return .sony }
        if haystack.contains("lge-com") || haystack.contains("lg electronics") || haystack.contains("webos") || haystack.contains("[lg]") { return .lg }
        return .unknown
    }
}

/// The television makers RemoteTV knows how to drive.
public enum LanServiceVendor: String, Sendable, Hashable {
    case sony
    case lg
    case unknown
}

/// What a discovery emits. Bonjour also reports services that go away.
public enum LanDiscoveryEvent: Sendable, Hashable {
    case found(LanService)
    case lost(LanService)
}

/// Why a discovery engine could not run.
public enum LanDiscoveryError: Error, Hashable, LocalizedError {
    /// Sending multicast is refused. On a device this is the missing
    /// `com.apple.developer.networking.multicast` entitlement (SSDP) or the local-network
    /// permission; the simulator is not restricted.
    case multicastNotAllowed
    /// Bonjour browsing was refused: the service type is missing from `NSBonjourServices`
    /// in the app's Info.plist, or the local-network permission was denied.
    case browsingNotAllowed(type: String)
    /// Another networking failure, described.
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .multicastNotAllowed:
            "Multicast is not allowed for this app; SSDP discovery cannot run."
        case .browsingNotAllowed(let type):
            "Browsing \(type) is not allowed; declare it in NSBonjourServices and allow local network access."
        case .networkFailure(let description):
            description
        }
    }
}

/// What to look for. `.televisions` covers Sony Bravia and LG webOS.
public struct LanDiscoveryConfiguration: Sendable, Hashable {
    /// Bonjour service types, e.g. `_googlecast._tcp`. Each must be listed in the app's
    /// `NSBonjourServices`.
    public var bonjourServiceTypes: [String]
    /// SSDP search targets (`ST`), e.g. `urn:schemas-sony-com:service:IRCC:1`, or `ssdp:all`.
    public var ssdpSearchTargets: [String]
    /// How long the discovery listens before finishing.
    public var duration: Duration
    /// How long resolving a Bonjour endpoint or fetching a UPnP description may take.
    public var resolveTimeout: Duration

    public init(
        bonjourServiceTypes: [String] = [],
        ssdpSearchTargets: [String] = [],
        duration: Duration = .seconds(5),
        resolveTimeout: Duration = .seconds(3)
    ) {
        self.bonjourServiceTypes = bonjourServiceTypes
        self.ssdpSearchTargets = ssdpSearchTargets
        self.duration = duration
        self.resolveTimeout = resolveTimeout
    }

    /// Sony Bravia (Google TV: Cast and Android TV remote; IRCC and Scalar Web API over UPnP),
    /// LG webOS (second-screen service), and AirPlay/DIAL, which both brands support.
    public static let televisions = LanDiscoveryConfiguration(
        bonjourServiceTypes: ["_googlecast._tcp", "_androidtvremote2._tcp", "_airplay._tcp"],
        ssdpSearchTargets: [
            "urn:schemas-sony-com:service:IRCC:1",
            "urn:schemas-sony-com:service:ScalarWebAPI:1",
            "urn:lge-com:service:webos-second-screen:1",
            "urn:dial-multiscreen-org:service:dial:1",
        ]
    )

    /// Everything that answers `ssdp:all`, plus the common Bonjour types.
    public static let everything = LanDiscoveryConfiguration(
        bonjourServiceTypes: ["_http._tcp", "_airplay._tcp", "_googlecast._tcp", "_hap._tcp", "_printer._tcp", "_ipp._tcp", "_smb._tcp"],
        ssdpSearchTargets: ["ssdp:all"]
    )
}

/// Produces the events of one discovery. ``BonjourDiscoveryEngine`` and
/// ``SSDPDiscoveryEngine`` are the real ones; tests plug scripted engines into ``LGLanDiscovery``.
///
/// The stream ends after the configuration's `duration`, or when the consumer stops
/// iterating; it throws a ``LanDiscoveryError`` when the engine cannot run at all.
public protocol LanDiscoveryEngine: Sendable {
    func discover(_ configuration: LanDiscoveryConfiguration) -> AsyncThrowingStream<LanDiscoveryEvent, any Error>
}
