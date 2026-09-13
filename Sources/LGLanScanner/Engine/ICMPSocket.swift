//
//  ICMPSocket.swift
//  LGLanScanner
//

import Foundation

/// ICMPv4 echo packets: building requests and recognising replies.
enum ICMPEcho {
    static let headerLength = 8
    static let echoRequest: UInt8 = 8
    static let echoReply: UInt8 = 0

    /// An echo request with an 8-byte payload and a valid checksum.
    static func request(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: headerLength + 8)
        packet[0] = echoRequest
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xff)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xff)
        for index in 0..<8 { packet[headerLength + index] = UInt8(0x61 + index) }   // "abcdefgh"
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xff)
        return packet
    }

    /// RFC 1071 one's-complement sum. Over a packet whose checksum field is filled it is 0.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    /// Whether a received datagram is an echo reply. Darwin hands ICMPv4 datagrams over
    /// with their IP header; a bare ICMP header (starting with type 0) is accepted too.
    static func isEchoReply(_ datagram: [UInt8]) -> Bool {
        guard datagram.count >= headerLength else { return false }
        var offset = 0
        if datagram[0] >> 4 == 4 { offset = Int(datagram[0] & 0x0f) * 4 }
        guard datagram.count >= offset + headerLength else { return false }
        return datagram[offset] == echoReply && datagram[offset + 1] == 0
    }
}

/// One unprivileged ICMP datagram socket. Sends a batch of echo requests, then collects
/// replies until the deadline. Blocking: use it from one serial queue.
final class ICMPSocket: @unchecked Sendable {
    struct ProbeResult {
        var alive: Set<IPv4Address>
        var sendFailures: Int
    }

    private let fd: Int32
    private let identifier = UInt16.random(in: 1...UInt16.max)
    private var sequence: UInt16 = 0

    init() throws(LanScanError) {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { throw .socketUnavailable(errno: errno) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    deinit { close(fd) }

    /// Probes `hosts` and returns those that answered before `timeout`. Replies from any
    /// address in `accepting` count, so a slow answer to an earlier batch is not lost.
    func probe(_ hosts: [IPv4Address], accepting: Set<IPv4Address>, timeout: Duration) -> ProbeResult {
        var result = ProbeResult(alive: [], sendFailures: 0)
        for host in hosts where !send(to: host) {
            result.sendFailures += 1
        }

        let batch = Set(hosts)
        let deadline = ContinuousClock.now + timeout
        var buffer = [UInt8](repeating: 0, count: 1024)
        while !batch.isSubset(of: result.alive) {
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
            let sender = IPv4Address(networkOrder: from.sin_addr.s_addr)
            if accepting.contains(sender), ICMPEcho.isEchoReply(Array(buffer[0..<Int(count)])) {
                result.alive.insert(sender)
            }
        }
        return result
    }

    private func send(to host: IPv4Address) -> Bool {
        sequence &+= 1
        let packet = ICMPEcho.request(identifier: identifier, sequence: sequence)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = host.networkOrder
        let sent = packet.withUnsafeBytes { raw in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == packet.count
    }
}
