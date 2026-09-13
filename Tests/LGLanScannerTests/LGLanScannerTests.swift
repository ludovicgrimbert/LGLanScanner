//
//  LGLanScannerTests.swift
//  LGLanScannerTests
//
//  The observable façade, driven by a scripted engine.
//

import Foundation
import Testing
@testable import LGLanScanner

/// Replays a script of events; can be told to fail, or to wait so a test can `stop()` mid-way.
final class ScriptedEngine: LanScanEngine, @unchecked Sendable {
    enum Step: Sendable { case event(LanScanEvent), pause, fail(LanScanError) }
    let script: [Step]
    private let lock = NSLock()
    private var _terminated = false
    var terminated: Bool { lock.withLock { _terminated } }

    init(_ script: [Step]) { self.script = script }

    func scan(_ configuration: LanScanConfiguration) -> AsyncThrowingStream<LanScanEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LanScanEvent.self)
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
        continuation.onTermination = { [lock] _ in
            task.cancel()
            lock.withLock { self._terminated = true }
        }
        return stream
    }
}

private let tv = LanDevice(name: "bravia", ipAddress: "192.168.1.20", mac: "a4:83:e7:00:00:01", brand: "Sony")
private let router = LanDevice(ipAddress: "192.168.1.1", isGateway: true)

@MainActor
private func settle() async {
    for _ in 0..<50 where true { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(50))
}

@MainActor
@Suite("LGLanScanner façade")
struct LGLanScannerTests {

    @Test("a complete scan goes idle → scanning → finished with the devices in order")
    func completeScan() async {
        let engine = ScriptedEngine([
            .event(.progress(0)), .event(.device(router)), .event(.progress(0.5)),
            .event(.device(tv)), .event(.progress(1)),
        ])
        let scanner = LGLanScanner(engine: engine)
        #expect(scanner.state == .idle)
        #expect(!scanner.isScanning && !scanner.isFinished)

        scanner.start()
        #expect(scanner.state == .scanning)
        #expect(scanner.isScanning)
        await settle()

        #expect(scanner.state == .finished)
        #expect(scanner.isFinished && !scanner.isScanning)
        #expect(scanner.progress == 1)
        #expect(scanner.devices == [router, tv])
        #expect(scanner.currentDevice == tv)
        #expect(scanner.error == nil)
    }

    @Test("progress never goes backwards and is clamped to 1")
    func monotonicProgress() async {
        let engine = ScriptedEngine([.event(.progress(0.6)), .event(.progress(0.2)), .event(.progress(1.7)), .pause])
        let scanner = LGLanScanner(engine: engine)
        scanner.start()
        await settle()
        #expect(scanner.progress == 1)
        scanner.stop()

        let engine2 = ScriptedEngine([.event(.progress(0.6)), .event(.progress(0.2)), .pause])
        let scanner2 = LGLanScanner(engine: engine2)
        scanner2.start()
        await settle()
        #expect(scanner2.progress == 0.6)
        scanner2.stop()
    }

    @Test("a device reported twice is listed once")
    func dedupe() async {
        let engine = ScriptedEngine([.event(.device(tv)), .event(.device(tv)), .event(.device(router))])
        let scanner = LGLanScanner(engine: engine)
        scanner.start()
        await settle()
        #expect(scanner.devices == [tv, router])
    }

    @Test("stop() finishes the scan, keeps the devices and cancels the engine")
    func stop() async {
        let engine = ScriptedEngine([.event(.device(tv)), .event(.progress(0.3)), .pause, .event(.device(router))])
        let scanner = LGLanScanner(engine: engine)
        scanner.start()
        await settle()
        #expect(scanner.state == .scanning)

        scanner.stop()
        #expect(scanner.state == .finished)
        #expect(scanner.devices == [tv])
        #expect(scanner.progress == 0.3)
        await settle()
        #expect(engine.terminated)
        #expect(scanner.devices == [tv])   // nothing leaked in after the stop
    }

    @Test("an engine failure lands in .failed with the error exposed")
    func failure() async {
        let engine = ScriptedEngine([.event(.progress(0)), .fail(.noLocalNetwork(interface: "en0"))])
        let scanner = LGLanScanner(engine: engine)
        scanner.start()
        await settle()
        #expect(scanner.state == .failed(.noLocalNetwork(interface: "en0")))
        #expect(scanner.error == .noLocalNetwork(interface: "en0"))
        #expect(scanner.isFinished && !scanner.isScanning)
        #expect(scanner.error?.localizedDescription.contains("Wi-Fi") == true)
    }

    @Test("start() again resets the previous scan")
    func restart() async {
        let engine = ScriptedEngine([.event(.device(tv)), .event(.progress(0.4)), .pause])
        let scanner = LGLanScanner(engine: engine)
        scanner.start()
        await settle()
        #expect(scanner.devices == [tv])

        scanner.start()
        #expect(scanner.devices.isEmpty)
        #expect(scanner.progress == 0)
        #expect(scanner.currentDevice == nil)
        #expect(scanner.state == .scanning)
        scanner.stop()
    }

    @Test("stop() on an idle scanner does nothing")
    func idleStop() {
        let scanner = LGLanScanner(engine: ScriptedEngine([]))
        scanner.stop()
        #expect(scanner.state == .idle)
    }
}
