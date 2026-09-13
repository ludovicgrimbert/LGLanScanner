//
//  IPv4.swift
//  LGLanScanner
//

import Foundation

/// An IPv4 address as a host-order 32-bit value, so subnet arithmetic is plain integer math.
public struct IPv4Address: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let value: UInt32

    public init(_ value: UInt32) { self.value = value }

    /// Parses a strict dotted quad (`192.168.1.24`); nil otherwise.
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber), let octet = UInt32(part), octet <= 255 else { return nil }
            value = value << 8 | octet
        }
        self.value = value
    }

    /// From an `in_addr.s_addr`, which is in network byte order.
    init(networkOrder: in_addr_t) { value = UInt32(bigEndian: networkOrder) }

    var networkOrder: in_addr_t { value.bigEndian }

    public var description: String {
        "\(value >> 24).\((value >> 16) & 0xff).\((value >> 8) & 0xff).\(value & 0xff)"
    }

    public static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool { lhs.value < rhs.value }
}

/// The IPv4 network an interface sits on.
public struct IPv4Subnet: Hashable, Sendable {
    /// The interface's own address.
    public let address: IPv4Address
    public let mask: IPv4Address

    public init(address: IPv4Address, mask: IPv4Address) {
        self.address = address
        self.mask = mask
    }

    public var network: IPv4Address { IPv4Address(address.value & mask.value) }
    public var broadcast: IPv4Address { IPv4Address(address.value | ~mask.value) }
    public var prefixLength: Int { mask.value.nonzeroBitCount }

    /// How many addresses ``hosts`` would return.
    public var hostCount: Int {
        let all = Int(broadcast.value) - Int(network.value) - 1   // minus network and broadcast
        return max(0, all - 1)                                     // minus ourselves
    }

    /// Every address worth probing: the range between network and broadcast, without the
    /// interface's own address.
    public var hosts: [IPv4Address] {
        guard broadcast.value > network.value + 1 else { return [] }
        var hosts: [IPv4Address] = []
        hosts.reserveCapacity(hostCount)
        for value in network.value + 1..<broadcast.value where value != address.value {
            hosts.append(IPv4Address(value))
        }
        return hosts
    }
}

/// Reads the interfaces of the device.
enum LocalNetwork {
    /// The IPv4 subnet of an interface that is up, or nil.
    static func ipv4Subnet(interface: String) -> IPv4Subnet? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, let netmask = entry.ifa_netmask,
                  addr.pointee.sa_family == sa_family_t(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0,
                  String(cString: entry.ifa_name) == interface else { continue }
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            return IPv4Subnet(address: IPv4Address(networkOrder: address), mask: IPv4Address(networkOrder: mask))
        }
        return nil
    }
}
