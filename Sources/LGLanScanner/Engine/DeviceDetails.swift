//
//  DeviceDetails.swift
//  LGLanScanner
//

import Foundation
import LanScanInternal
import os

/// Hardware addresses and the default gateway, read from the kernel routing table.
enum RoutingTable {
    /// The MAC the ARP cache holds for the address, lowercase `aa:bb:cc:dd:ee:ff`. The cache
    /// only knows devices that recently answered, so ask right after a successful ping.
    static func macAddress(for address: IPv4Address) -> String? {
        var mac = [UInt8](repeating: 0, count: 6)
        guard LGRoutingTableMACAddress(address.networkOrder, &mac) else { return nil }
        return mac.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    static func defaultGateway(interface: String) -> IPv4Address? {
        var gateway: UInt32 = 0
        guard LGRoutingTableDefaultGateway(interface, &gateway) else { return nil }
        return IPv4Address(networkOrder: gateway)
    }
}

/// The IEEE OUI registry bundled as `oui.plist`: 24-bit prefix (`A4-83-E7`) → manufacturer.
struct OUITable: Sendable {
    let brands: [String: String]

    /// Loaded once, lazily, on first use (a 1.3 MB plist, tens of milliseconds).
    static let bundled: OUITable = {
        guard let url = Bundle.module.url(forResource: "oui", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return OUITable(brands: [:]) }
        return OUITable(brands: plist)
    }()

    /// `aa:bb:cc:dd:ee:ff` → `AA-BB-CC`.
    static func key(for mac: String) -> String? {
        let parts = mac.split(separator: ":")
        guard parts.count == 6 else { return nil }
        return parts.prefix(3).joined(separator: "-").uppercased()
    }

    func brand(for mac: String) -> String? {
        guard let key = Self.key(for: mac) else { return nil }
        return brands[key]
    }
}

/// Reverse lookup of a device's name (DNS or mDNS), with a hard timeout: `getnameinfo` is
/// synchronous and can take seconds on a device that ignores the query.
enum HostNameResolver {
    static func name(for address: IPv4Address, timeout: Duration) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (String?) -> Void = { name in
                let first = resumed.withLock { done in
                    if done { return false }
                    done = true
                    return true
                }
                if first { continuation.resume(returning: name) }
            }
            DispatchQueue.global(qos: .utility).async { finish(lookup(address)) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .nanoseconds(Int(timeout / .nanoseconds(1)))) { finish(nil) }
        }
    }

    private static func lookup(_ address: IPv4Address) -> String? {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = address.networkOrder
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &sin) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD | NI_NOFQDN)
            }
        }
        guard status == 0 else { return nil }
        let name = String(cString: host)
        return name.isEmpty ? nil : name
    }
}
