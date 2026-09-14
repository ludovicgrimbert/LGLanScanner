//
//  LGWakeOnLAN.swift
//  LGLanScanner
//

import Foundation

/// Wake-on-LAN: the "magic packet" that brings a sleeping device back — a television in deep
/// standby that no longer runs its network API, typically. The packet is 6 × `0xFF` followed
/// by the MAC repeated 16 times, sent over UDP to the broadcast address; the device's network
/// card recognises its own address and powers the device on. Needs the feature enabled on the
/// device (Sony: "Remote start"; most call it "Wake on LAN").
public enum LGWakeOnLAN {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        /// Not six hexadecimal bytes.
        case invalidMAC(String)
        case socketUnavailable(errno: Int32)
        case sendFailed(errno: Int32)

        public var errorDescription: String? {
            switch self {
            case .invalidMAC(let mac): "'\(mac)' is not a MAC address."
            case .socketUnavailable(let errno): "Could not open a UDP socket (errno \(errno))."
            case .sendFailed(let errno): "Could not send the wake-up packet (errno \(errno))."
            }
        }
    }

    /// The six bytes of a MAC written as `aa:bb:cc:dd:ee:ff`, `AA-BB-CC-DD-EE-FF` or `aabbccddeeff`.
    public static func bytes(of mac: String) -> [UInt8]? {
        let hex = mac.filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// The 102-byte magic packet for `mac`, or nil when the MAC is malformed.
    public static func magicPacket(for mac: String) -> Data? {
        guard let bytes = bytes(of: mac) else { return nil }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return Data(packet)
    }

    /// Sends the magic packet `count` times (devices drop packets while waking; three is the
    /// usual number), to the limited broadcast address on the given port. Port 9 (discard)
    /// is the convention; some devices listen on 7 as well.
    public static func wake(mac: String, port: UInt16 = 9, count: Int = 3) async throws(Error) {
        guard let packet = magicPacket(for: mac) else { throw .invalidMAC(mac) }
        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            send(packet, port: port, count: count)
        }.value
        try result.get()
    }

    static func send(_ packet: Data, port: UInt16, count: Int) -> Result<Void, Error> {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return .failure(.socketUnavailable(errno: errno)) }
        defer { close(fd) }
        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_BROADCAST
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        for _ in 0..<max(count, 1) {
            let sent = packet.withUnsafeBytes { raw in
                withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent == packet.count else { return .failure(.sendFailed(errno: errno)) }
        }
        return .success(())
    }
}
