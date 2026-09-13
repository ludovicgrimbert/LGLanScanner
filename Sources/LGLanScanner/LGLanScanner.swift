//
//  LGLanScanner.swift
//  LGLanScanner
//
//  Scans the local network and exposes the progress and the devices found, on the main actor.
//

import Foundation
import Observation

/// Drives one network scan at a time. `@Observable`: read `state`, `progress`, `devices`
/// and `currentDevice` straight from a SwiftUI view, no polling.
///
/// ```swift
/// @State private var scanner = LGLanScanner()
/// …
/// ProgressView(value: scanner.progress)
/// ForEach(scanner.devices) { device in Text(device.ipAddress) }
/// Button(scanner.isScanning ? "Stop" : "Scan") { scanner.isScanning ? scanner.stop() : scanner.start() }
/// if let error = scanner.error { Text(error.localizedDescription) }
/// ```
///
/// The app must declare `NSLocalNetworkUsageDescription`; iOS asks the user on the first scan.
@Observable
@MainActor
public final class LGLanScanner {

    public enum State: Sendable, Hashable {
        case idle
        case scanning
        /// The whole range was swept, or `stop()` was called.
        case finished
        case failed(LanScanError)
    }

    public private(set) var state: State = .idle
    /// 0...1, never goes backwards during a scan.
    public private(set) var progress: Double = 0
    /// Every device found by the current scan, in discovery order, one per IP address.
    public private(set) var devices: [LanDevice] = []
    /// The last device found by the current scan.
    public private(set) var currentDevice: LanDevice?

    public var isScanning: Bool { state == .scanning }
    /// `true` once the scan is over, whether it completed, was stopped or failed.
    public var isFinished: Bool {
        switch state {
        case .finished, .failed: true
        case .idle, .scanning: false
        }
    }
    public var error: LanScanError? {
        if case .failed(let error) = state { error } else { nil }
    }

    /// Applied to the next `start()`.
    public var configuration: LanScanConfiguration

    private let engine: any LanScanEngine
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// - Parameters:
    ///   - engine: what performs the scan; the live ping sweep by default.
    ///   - configuration: interface, timeouts and batch size.
    public init(engine: any LanScanEngine = LiveLanScanEngine(), configuration: LanScanConfiguration = LanScanConfiguration()) {
        self.engine = engine
        self.configuration = configuration
    }

    /// Starts a scan, discarding the state of a previous one.
    public func start() {
        scanTask?.cancel()
        state = .scanning
        progress = 0
        devices = []
        currentDevice = nil

        let stream = engine.scan(configuration)
        scanTask = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self, !Task.isCancelled else { return }
                    apply(event)
                }
                guard let self, !Task.isCancelled else { return }
                progress = 1
                state = .finished
            } catch {
                guard let self, !Task.isCancelled else { return }
                state = .failed(error as? LanScanError ?? .unexpected(error.localizedDescription))
            }
        }
    }

    /// Ends the current scan; what was found stays in `devices`.
    public func stop() {
        scanTask?.cancel()
        scanTask = nil
        if state == .scanning { state = .finished }
    }

    private func apply(_ event: LanScanEvent) {
        switch event {
        case .progress(let value):
            progress = max(progress, min(value, 1))
        case .device(let device):
            currentDevice = device
            if !devices.contains(where: { $0.ipAddress == device.ipAddress }) {
                devices.append(device)
            }
        }
    }
}
