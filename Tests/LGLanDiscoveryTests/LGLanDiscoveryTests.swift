//
//  LGLanDiscoveryTests.swift
//  LGLanDiscoveryTests
//

import Foundation
import Testing
@testable import LGLanDiscovery

// MARK: - Pure parts

@Suite("SSDP messages")
struct SSDPMessageTests {

    @Test("an M-SEARCH is a well-formed HTTPU request for the target")
    func search() {
        let text = String(decoding: SSDPMessage.search(target: "urn:schemas-sony-com:service:IRCC:1"), as: UTF8.self)
        #expect(text.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        #expect(text.contains("HOST: 239.255.255.250:1900\r\n"))
        #expect(text.contains("MAN: \"ssdp:discover\"\r\n"))
        #expect(text.contains("MX: 2\r\n"))
        #expect(text.contains("ST: urn:schemas-sony-com:service:IRCC:1\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    @Test("a 200 response parses into lowercased headers")
    func response() {
        let data = Data("""
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        EXT:\r
        LOCATION: http://192.168.1.24:52323/dmr.xml\r
        SERVER: Linux/3.10 UPnP/1.0 Sony-BDP/2.0\r
        ST: urn:schemas-sony-com:service:IRCC:1\r
        USN: uuid:00000000-0000-1010-8000-a483e7000001::urn:schemas-sony-com:service:IRCC:1\r
        \r

        """.utf8)
        let headers = SSDPMessage.parse(data)
        #expect(headers?["location"] == "http://192.168.1.24:52323/dmr.xml")
        #expect(headers?["st"] == "urn:schemas-sony-com:service:IRCC:1")
        #expect(headers?["usn"]?.hasPrefix("uuid:") == true)
        #expect(headers?["ext"] == "")
        #expect(SSDPMessage.target(of: headers!) == "urn:schemas-sony-com:service:IRCC:1")
        #expect(SSDPMessage.matches(headers!, targets: ["urn:schemas-sony-com:service:IRCC:1"]))
        #expect(SSDPMessage.matches(headers!, targets: ["ssdp:all"]))
        #expect(!SSDPMessage.matches(headers!, targets: ["urn:lge-com:service:webos-second-screen:1"]))
    }

    @Test("advertisements use NT and byebye is ignored; our own search is not a message")
    func notify() {
        let alive = Data("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nNT: urn:lge-com:service:webos-second-screen:1\r\nNTS: ssdp:alive\r\nLOCATION: http://192.168.1.30:1234/desc.xml\r\n\r\n".utf8)
        let headers = SSDPMessage.parse(alive)!
        #expect(SSDPMessage.target(of: headers) == "urn:lge-com:service:webos-second-screen:1")
        #expect(SSDPMessage.matches(headers, targets: ["urn:lge-com:service:webos-second-screen:1"]))

        let bye = Data("NOTIFY * HTTP/1.1\r\nNT: urn:lge-com:service:webos-second-screen:1\r\nNTS: ssdp:byebye\r\n\r\n".utf8)
        #expect(!SSDPMessage.matches(SSDPMessage.parse(bye)!, targets: ["ssdp:all"]))

        #expect(SSDPMessage.parse(SSDPMessage.search(target: "ssdp:all")) == nil)
        #expect(SSDPMessage.parse(Data("HTTP/1.1 404 Not Found\r\n\r\n".utf8)) == nil)
        #expect(SSDPMessage.parse(Data([0xff, 0xfe])) == nil)
    }

    @Test("a UPnP description yields the device fields, root device first, Sony extension included")
    func description() {
        let xml = Data("""
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:av="urn:schemas-sony-com:av">
          <specVersion><major>1</major><minor>0</minor></specVersion>
          <device>
            <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
            <friendlyName>BRAVIA salon</friendlyName>
            <manufacturer>Sony Corporation</manufacturer>
            <modelName>KD-55XH9005</modelName>
            <UDN>uuid:00000000-0000-1010-8000-a483e7000001</UDN>
            <av:X_ScalarWebAPI_DeviceInfo>
              <av:X_ScalarWebAPI_BaseURL>http://192.168.1.24/sony</av:X_ScalarWebAPI_BaseURL>
            </av:X_ScalarWebAPI_DeviceInfo>
            <deviceList><device><friendlyName>embedded</friendlyName></device></deviceList>
          </device>
        </root>
        """.utf8)
        let fields = UPnPDescription.parse(xml)
        #expect(fields["friendlyname"] == "BRAVIA salon")
        #expect(fields["manufacturer"] == "Sony Corporation")
        #expect(fields["modelname"] == "KD-55XH9005")
        #expect(fields["udn"] == "uuid:00000000-0000-1010-8000-a483e7000001")
        #expect(fields["x_scalarwebapi_baseurl"] == "http://192.168.1.24/sony")
        #expect(fields["devicetype"] == nil)
        #expect(UPnPDescription.parse(Data("not xml".utf8)).isEmpty)
    }
}

@Suite("Services")
struct LanServiceTests {

    @Test("attributes are lowercased, the id combines source, type and endpoint")
    func identity() {
        let service = LanService(name: "TV", type: "_googlecast._tcp", host: "192.168.1.24", port: 8009,
                                 attributes: ["MD": "BRAVIA 4K", "fn": "TV"], source: .bonjour)
        #expect(service.attributes == ["md": "BRAVIA 4K", "fn": "TV"])
        #expect(service.id == "bonjour|_googlecast._tcp|192.168.1.24:8009")
    }

    @Test("the vendor is recognised from the type, the description or the name")
    func vendor() {
        #expect(LanService(name: "x", type: "urn:schemas-sony-com:service:IRCC:1", host: "h", port: 1, source: .ssdp).vendor == .sony)
        #expect(LanService(name: "x", type: "_googlecast._tcp", host: "h", port: 1, attributes: ["md": "BRAVIA 4K VH2"], source: .bonjour).vendor == .sony)
        #expect(LanService(name: "x", type: "urn:lge-com:service:webos-second-screen:1", host: "h", port: 1, source: .ssdp).vendor == .lg)
        #expect(LanService(name: "[LG] webOS TV OLED55C1", type: "_airplay._tcp", host: "h", port: 7000, source: .bonjour).vendor == .lg)
        #expect(LanService(name: "x", type: "urn:dial-multiscreen-org:service:dial:1", host: "h", port: 1, attributes: ["manufacturer": "LG Electronics"], source: .ssdp).vendor == .lg)
        #expect(LanService(name: "Freebox", type: "ssdp:all", host: "h", port: 1, attributes: ["manufacturer": "Freebox SA"], source: .ssdp).vendor == .unknown)
    }

    @Test("the presets are populated and the error messages read well")
    func presets() {
        #expect(LanDiscoveryConfiguration.televisions.bonjourServiceTypes.contains("_googlecast._tcp"))
        #expect(LanDiscoveryConfiguration.televisions.ssdpSearchTargets.contains("urn:schemas-sony-com:service:IRCC:1"))
        #expect(LanDiscoveryConfiguration.televisions.ssdpSearchTargets.contains("urn:lge-com:service:webos-second-screen:1"))
        #expect(LanDiscoveryConfiguration.everything.ssdpSearchTargets == ["ssdp:all"])
        #expect(LanDiscoveryConfiguration().duration == .seconds(5))
        #expect(LanDiscoveryError.browsingNotAllowed(type: "_x._tcp").localizedDescription.contains("NSBonjourServices"))
        #expect(LanDiscoveryError.multicastNotAllowed.localizedDescription.isEmpty == false)
    }
}

// MARK: - Façade

/// Replays a script; `.pause` waits so a test can `stop()` mid-way.
final class ScriptedEngine: LanDiscoveryEngine, Sendable {
    enum Step: Sendable { case event(LanDiscoveryEvent), pause, fail(LanDiscoveryError) }
    let script: [Step]
    init(_ script: [Step]) { self.script = script }

    func discover(_ configuration: LanDiscoveryConfiguration) -> AsyncThrowingStream<LanDiscoveryEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LanDiscoveryEvent.self)
        let script = script
        let task = Task {
            for step in script {
                switch step {
                case .event(let event): continuation.yield(event)
                case .pause: try? await Task.sleep(for: .seconds(10))
                case .fail(let error): continuation.finish(throwing: error); return
                }
                if Task.isCancelled { return }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}

private let bravia = LanService(name: "BRAVIA salon", type: "urn:schemas-sony-com:service:IRCC:1", host: "192.168.1.24", port: 52323, source: .ssdp)
private let braviaCast = LanService(name: "BRAVIA salon", type: "_googlecast._tcp", host: "192.168.1.24", port: 8009, attributes: ["md": "BRAVIA"], source: .bonjour)
private let webos = LanService(name: "[LG] webOS TV", type: "_airplay._tcp", host: "192.168.1.30", port: 7000, source: .bonjour)
private let printer = LanService(name: "Printer", type: "ssdp:all", host: "192.168.1.40", port: 80, source: .ssdp)

@MainActor
private func settle() async {
    for _ in 0..<50 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(80))
}

@MainActor
@Suite("LGLanDiscovery façade")
struct LGLanDiscoveryTests {

    @Test("two engines are merged, televisions are deduplicated per host, then finished")
    func merge() async {
        let discovery = LGLanDiscovery(engines: [
            ScriptedEngine([.event(.found(bravia)), .event(.found(printer))]),
            ScriptedEngine([.event(.found(braviaCast)), .event(.found(webos))]),
        ])
        #expect(discovery.state == .idle)
        discovery.start()
        #expect(discovery.isDiscovering)
        await settle()
        #expect(discovery.state == .finished)
        #expect(Set(discovery.services.map(\.id)) == Set([bravia, printer, braviaCast, webos].map(\.id)))
        #expect(discovery.televisions.map(\.host).sorted() == ["192.168.1.24", "192.168.1.30"])
        #expect(discovery.errors.isEmpty)
    }

    @Test("a lost service disappears, a re-found one is updated in place")
    func lost() async {
        let renamed = LanService(name: "Salon", type: webos.type, host: webos.host, port: webos.port, source: .bonjour)
        let engine = ScriptedEngine([.event(.found(webos)), .event(.found(bravia)), .event(.lost(webos)), .event(.found(bravia)), .event(.found(renamed))])
        let discovery = LGLanDiscovery(engines: [engine])
        discovery.start()
        await settle()
        #expect(discovery.services.map(\.name) == ["BRAVIA salon", "Salon"])
    }

    @Test("one failing engine is reported while the other's results stand")
    func partialFailure() async {
        let discovery = LGLanDiscovery(engines: [
            ScriptedEngine([.fail(.multicastNotAllowed)]),
            ScriptedEngine([.event(.found(braviaCast))]),
        ])
        discovery.start()
        await settle()
        #expect(discovery.state == .finished)
        #expect(discovery.errors == [.multicastNotAllowed])
        #expect(discovery.services == [braviaCast])
    }

    @Test("every engine failing is a failed discovery")
    func totalFailure() async {
        let discovery = LGLanDiscovery(engines: [
            ScriptedEngine([.fail(.multicastNotAllowed)]),
            ScriptedEngine([.fail(.browsingNotAllowed(type: "_airplay._tcp"))]),
        ])
        discovery.start()
        await settle()
        #expect(discovery.state == .failed)
        #expect(discovery.errors.count == 2)
    }

    @Test("stop() keeps what was found and restarting clears it")
    func stopAndRestart() async {
        let discovery = LGLanDiscovery(engines: [ScriptedEngine([.event(.found(bravia)), .pause, .event(.found(webos))])])
        discovery.start()
        await settle()
        #expect(discovery.state == .discovering)
        discovery.stop()
        #expect(discovery.state == .finished)
        #expect(discovery.services == [bravia])
        await settle()
        #expect(discovery.services == [bravia])

        discovery.start()
        #expect(discovery.services.isEmpty && discovery.state == .discovering)
        discovery.stop()
    }

    @Test("no engines finishes immediately")
    func noEngines() async {
        let discovery = LGLanDiscovery(engines: [])
        discovery.start()
        await settle()
        #expect(discovery.state == .finished)
    }
}

// MARK: - Live engines (network-dependent, tolerant)

@Suite("Live engines")
struct LiveEngineTests {

    @Test("engines with nothing to look for finish at once")
    func empty() async throws {
        var count = 0
        for try await _ in BonjourDiscoveryEngine().discover(LanDiscoveryConfiguration()) { count += 1 }
        for try await _ in SSDPDiscoveryEngine().discover(LanDiscoveryConfiguration()) { count += 1 }
        #expect(count == 0)
    }

    @Test("an SSDP search for everything runs for its duration and never throws on the simulator")
    func ssdp() async throws {
        let configuration = LanDiscoveryConfiguration(ssdpSearchTargets: ["ssdp:all"], duration: .seconds(2))
        let clock = ContinuousClock()
        let start = clock.now
        var found: [LanService] = []
        for try await event in SSDPDiscoveryEngine().discover(configuration) {
            if case .found(let service) = event { found.append(service)}
        }
        #expect(clock.now - start >= .seconds(2))
        #expect(clock.now - start < .seconds(8))
        for service in found {
            #expect(!service.host.isEmpty && service.port > 0 && service.source == .ssdp)
        }
    }

    @Test("a Bonjour browse runs for its duration, or is refused by policy")
    func bonjour() async {
        let configuration = LanDiscoveryConfiguration(bonjourServiceTypes: ["_airplay._tcp", "_googlecast._tcp"], duration: .seconds(2))
        do {
            for try await event in BonjourDiscoveryEngine().discover(configuration) {
                if case .found(let service) = event {
                    #expect(!service.host.isEmpty && service.port > 0 && service.source == .bonjour)
                }
            }
        } catch let error as LanDiscoveryError {
            // A test bundle has no NSBonjourServices; a refusal is a legitimate outcome.
            if case .browsingNotAllowed = error {} else { Issue.record("unexpected \(error)") }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}
