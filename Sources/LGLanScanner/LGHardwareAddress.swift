//
//  LGHardwareAddress.swift
//  LGLanScanner
//

import Foundation

/// The hardware (MAC) address of one host, without sweeping the network.
///
/// A MAC is the stable identity of a device on the LAN: when a television's DHCP lease
/// hands it a new IP address, its MAC does not change. An app that stores it can find the
/// device again.
public enum LGHardwareAddress {
    /// The MAC of `ipAddress`, lowercase `aa:bb:cc:dd:ee:ff`, or nil when the host did not
    /// answer and the ARP cache does not know it.
    ///
    /// The kernel's ARP cache only holds devices that recently exchanged packets with this
    /// one, so the host is pinged first (unprivileged ICMP, `timeout` at most) and the cache
    /// read afterwards. Off the main thread: the ping blocks for up to `timeout`.
    public static func lookup(_ ipAddress: String, timeout: Duration = .seconds(1)) async -> String? {
        guard let address = IPv4Address(ipAddress) else { return nil }
        let answered = await Task.detached(priority: .utility) { () -> Bool in
            guard let socket = try? ICMPSocket() else { return false }
            return socket.probe([address], accepting: [address], timeout: timeout).alive.contains(address)
        }.value
        // Even without an answer the cache may still hold the entry (a recent exchange over
        // TCP counts): read it either way.
        _ = answered
        return RoutingTable.macAddress(for: address)
    }
}
