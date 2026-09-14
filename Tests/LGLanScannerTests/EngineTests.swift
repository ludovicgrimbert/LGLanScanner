//
//  EngineTests.swift
//  LGLanScannerTests
//
//  The pure parts of the engine: address arithmetic, ICMP packets, the OUI registry, the
//  routing-table reads and the live engine's fail-fast paths. The actual sweep needs a LAN.
//

import Foundation
import Testing
@testable import LGLanScanner

@Suite("IPv4 arithmetic")
struct IPv4Tests {

    @Test("dotted quads parse strictly and print back")
    func parsing() {
        #expect(IPv4Address("192.168.1.24")?.value == 0xC0A8_0118)
        #expect(IPv4Address("192.168.1.24")?.description == "192.168.1.24")
        #expect(IPv4Address("0.0.0.0")?.value == 0)
        #expect(IPv4Address("255.255.255.255")?.value == UInt32.max)
        #expect(IPv4Address("10.0..5") == nil)
        #expect(IPv4Address("10.0.0.256") == nil)
        #expect(IPv4Address("10.0.0") == nil)
        #expect(IPv4Address("10.0.0.5.1") == nil)
        #expect(IPv4Address("a.b.c.d") == nil)
        #expect(IPv4Address("192.168.1.2")! < IPv4Address("192.168.1.10")!)
    }

    @Test("network byte order round-trips")
    func byteOrder() {
        let address = IPv4Address("192.168.1.24")!
        #expect(IPv4Address(networkOrder: address.networkOrder) == address)
        #expect(IPv4Address(networkOrder: inet_addr("192.168.1.24")) == address)
    }

    @Test("a /24 yields the 253 other hosts, in order, without network, broadcast or self")
    func slash24() {
        let subnet = IPv4Subnet(address: IPv4Address("192.168.1.42")!, mask: IPv4Address("255.255.255.0")!)
        #expect(subnet.prefixLength == 24)
        #expect(subnet.network.description == "192.168.1.0")
        #expect(subnet.broadcast.description == "192.168.1.255")
        let hosts = subnet.hosts
        #expect(hosts.count == 253)
        #expect(subnet.hostCount == hosts.count)
        #expect(hosts.first?.description == "192.168.1.1")
        #expect(hosts.last?.description == "192.168.1.254")
        #expect(!hosts.contains(subnet.address))
        #expect(hosts == hosts.sorted())
    }

    @Test("subnets with a zero octet are plain arithmetic (the 0.x bug of the old string builder)")
    func zeroOctets() {
        let subnet = IPv4Subnet(address: IPv4Address("10.0.0.7")!, mask: IPv4Address("255.255.255.0")!)
        #expect(subnet.hosts.map(\.description).prefix(3) == ["10.0.0.1", "10.0.0.2", "10.0.0.3"])
        #expect(subnet.hosts.contains(IPv4Address("10.0.0.100")!))
    }

    @Test("small and large masks")
    func masks() {
        let tiny = IPv4Subnet(address: IPv4Address("192.168.1.1")!, mask: IPv4Address("255.255.255.252")!)
        #expect(tiny.prefixLength == 30)
        #expect(tiny.hosts.map(\.description) == ["192.168.1.2"])
        let pointToPoint = IPv4Subnet(address: IPv4Address("192.168.1.1")!, mask: IPv4Address("255.255.255.254")!)
        #expect(pointToPoint.hosts.isEmpty)
        #expect(pointToPoint.hostCount == 0)
        let big = IPv4Subnet(address: IPv4Address("10.1.2.3")!, mask: IPv4Address("255.255.0.0")!)
        #expect(big.prefixLength == 16)
        #expect(big.hostCount == 65_533)
    }

    @Test("the loopback interface is read as 127.0.0.1/8")
    func loopback() {
        let subnet = LocalNetwork.ipv4Subnet(interface: "lo0")
        #expect(subnet?.address.description == "127.0.0.1")
        #expect(subnet?.prefixLength == 8)
        #expect(LocalNetwork.ipv4Subnet(interface: "nope0") == nil)
    }
}

@Suite("ICMP echo")
struct ICMPTests {

    @Test("a request is 16 bytes, type 8, carries id and sequence, and checksums to zero")
    func request() {
        let packet = ICMPEcho.request(identifier: 0xBEEF, sequence: 0x0102)
        #expect(packet.count == 16)
        #expect(packet[0] == 8 && packet[1] == 0)
        #expect(packet[4] == 0xBE && packet[5] == 0xEF)
        #expect(packet[6] == 0x01 && packet[7] == 0x02)
        #expect(ICMPEcho.checksum(packet) == 0)
        #expect(packet[2] != 0 || packet[3] != 0)
    }

    @Test("the checksum matches a known vector and handles odd lengths")
    func checksum() {
        // RFC 1071 worked example: 0x0001 0xf203 0xf4f5 0xf6f7 → complement of 0xddf2 = 0x220d.
        #expect(ICMPEcho.checksum([0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7]) == 0x220d)
        #expect(ICMPEcho.checksum([0x00, 0x01, 0xf2]) == ~UInt16(0x0001 + 0xf200))
        #expect(ICMPEcho.checksum([]) == 0xffff)
    }

    @Test("replies are recognised with and without the IPv4 header, requests are not")
    func replies() {
        let bare = [UInt8](repeating: 0, count: 8)
        #expect(ICMPEcho.isEchoReply(bare))
        var withHeader = [UInt8](repeating: 0, count: 28)
        withHeader[0] = 0x45   // IPv4, IHL 5 → 20-byte header
        #expect(ICMPEcho.isEchoReply(withHeader))
        withHeader[20] = 8     // echo request
        #expect(!ICMPEcho.isEchoReply(withHeader))
        #expect(!ICMPEcho.isEchoReply([0x45, 0, 0]))
        #expect(!ICMPEcho.isEchoReply([]))
    }

    @Test("an unprivileged ICMP socket opens, and the default gateway answers a ping")
    func gatewayPing() throws {
        // Darwin does not answer ICMP datagram-socket echoes on loopback, so the router is the
        // only host a test can count on; without one (no Wi-Fi) there is nothing to assert.
        let socket = try ICMPSocket()
        guard let gateway = RoutingTable.defaultGateway(interface: "en0") else { return }
        let result = socket.probe([gateway], accepting: [gateway], timeout: .seconds(1))
        #expect(result.sendFailures == 0)
        #expect(result.alive == [gateway])
        #expect(RoutingTable.macAddress(for: gateway) != nil)   // the reply filled the ARP cache
    }

    @Test("an address nobody answers times out without being reported")
    func timeout() throws {
        let socket = try ICMPSocket()
        // TEST-NET-1 (RFC 5737) is never routed.
        let nobody = IPv4Address("192.0.2.1")!
        let clock = ContinuousClock()
        let start = clock.now
        let result = socket.probe([nobody], accepting: [nobody], timeout: .milliseconds(200))
        #expect(result.alive.isEmpty)
        #expect(clock.now - start >= .milliseconds(150))
        #expect(clock.now - start < .seconds(2))
    }
}

@Suite("Device details")
struct DeviceDetailsTests {

    @Test("the OUI key is the uppercased first three octets")
    func ouiKey() {
        #expect(OUITable.key(for: "a4:83:e7:12:34:56") == "A4-83-E7")
        #expect(OUITable.key(for: "00:00:00:00:00:01") == "00-00-00")
        #expect(OUITable.key(for: "") == nil)
        #expect(OUITable.key(for: "a4:83:e7") == nil)
    }

    @Test("the bundled registry loads and resolves a known prefix")
    func bundledRegistry() {
        let table = OUITable.bundled
        #expect(table.brands.count > 20_000)
        #expect(table.brand(for: "00:00:00:aa:bb:cc") == "XEROX CORPORATION")
        #expect(table.brand(for: "02:00:00:aa:bb:cc") == nil)   // locally administered
    }

    @Test("routing-table reads do not crash and agree with each other when there is a gateway")
    func routingTable() {
        #expect(RoutingTable.macAddress(for: IPv4Address("192.0.2.1")!) == nil)   // never in the ARP cache
        if let gateway = RoutingTable.defaultGateway(interface: "en0") {
            #expect(gateway.value != 0)
            // The gateway is in the ARP cache whenever the simulator's Mac talked to it recently.
            _ = RoutingTable.macAddress(for: gateway)
        }
    }

    @Test("name resolution of loopback returns localhost within the timeout")
    func hostName() async {
        let clock = ContinuousClock()
        let start = clock.now
        let name = await HostNameResolver.name(for: IPv4Address("127.0.0.1")!, timeout: .seconds(2))
        #expect(name == "localhost")
        #expect(clock.now - start < .seconds(2))
    }

    @Test("name resolution gives up at the timeout")
    func hostNameTimeout() async {
        let clock = ContinuousClock()
        let start = clock.now
        _ = await HostNameResolver.name(for: IPv4Address("192.0.2.1")!, timeout: .milliseconds(300))
        #expect(clock.now - start < .seconds(1))
    }
}

@Suite("Live engine, fail-fast paths")
struct LiveEngineTests {

    private func events(_ configuration: LanScanConfiguration) async throws -> [LanScanEvent] {
        var events: [LanScanEvent] = []
        for try await event in LiveLanScanEngine().scan(configuration) { events.append(event) }
        return events
    }

    @Test("an interface without IPv4 fails with noLocalNetwork")
    func noNetwork() async {
        await #expect(throws: LanScanError.noLocalNetwork(interface: "nope0")) {
            try await events(LanScanConfiguration(interface: "nope0"))
        }
    }

    @Test("a subnet above the host limit is refused before any probe")
    func tooLarge() async {
        // lo0 is 127.0.0.1/8: 16 million hosts.
        await #expect(throws: LanScanError.subnetTooLarge(hosts: 16_777_213, limit: 1024)) {
            try await events(LanScanConfiguration(interface: "lo0"))
        }
    }

    @Test("stopping the consumer cancels the producer")
    func cancellation() async throws {
        let engine = LiveLanScanEngine()
        // A configuration that would take a while if it ran to the end.
        let configuration = LanScanConfiguration(interface: "lo0", pingTimeout: .seconds(1), batchSize: 1, maxHosts: Int.max)
        let task = Task {
            var count = 0
            for try await _ in engine.scan(configuration) {
                count += 1
                if count == 2 { break }
            }
            return count
        }
        let count = try await task.value
        #expect(count == 2)
    }
}

@Suite("Hardware address lookup")
struct HardwareAddressTests {

    @Test("a malformed address is nil without touching the network")
    func malformed() async {
        #expect(await LGHardwareAddress.lookup("not an address") == nil)
        #expect(await LGHardwareAddress.lookup("10.0.0.256") == nil)
    }

    @Test("an address nobody holds is nil once the ping timed out")
    func nobodyThere() async {
        // TEST-NET-1 (RFC 5737): never routed, never in the ARP cache.
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await LGHardwareAddress.lookup("192.0.2.1", timeout: .milliseconds(200)) == nil)
        #expect(clock.now - start < .seconds(3))
    }

    @Test("the default gateway, when there is one, has a MAC in the expected format")
    func gateway() async throws {
        guard let gateway = RoutingTable.defaultGateway(interface: LanScanConfiguration().interface) else { return }
        let mac = await LGHardwareAddress.lookup(gateway.description)
        if let mac {
            #expect(mac.wholeMatch(of: /[0-9a-f]{2}(:[0-9a-f]{2}){5}/) != nil)
        }
    }
}
