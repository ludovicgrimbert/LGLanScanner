//
//  LGLanScanner.swift
//  LGLanScanner
//
//  Scans the local network and exposes the progress and the devices found, on the main actor.
//  Source of the underlying scanner: https://github.com/MaatheusGois/lan-scanner
//  (add a macOS Info.plist if you want a Mac app).
//

import Foundation
import LanScanInternal
import Observation

/// Drives one network scan at a time. `@Observable`: read `progress`, `devices`,
/// `currentDevice`, `isScanning` and `isFinished` straight from a SwiftUI view, no polling.
///
/// ```swift
/// @State private var scanner = LGLanScanner()
/// …
/// ProgressView(value: scanner.progress)
/// ForEach(scanner.devices) { device in Text(device.ipAddress) }
/// Button(scanner.isScanning ? "Stop" : "Scan") { scanner.isScanning ? scanner.stop() : scanner.start() }
/// ```
@Observable
@MainActor
public final class LGLanScanner {

    /// 0...1 progress of the current scan.
    public private(set) var progress: CGFloat = .zero
    /// `true` while a scan runs.
    public private(set) var isScanning = false
    /// `true` once the current scan has gone through the whole IP range (or was stopped).
    public private(set) var isFinished = false
    /// The last device found by the current scan.
    public private(set) var currentDevice = LanDevice()
    /// Every device found by the current scan, in discovery order, one entry per IP address.
    public private(set) var devices: [LanDevice] = []

    private let scanner = LanScanner()
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    public init() {}

    /// Starts a scan, resetting the state left by a previous one.
    public func start() {
        scanTask?.cancel()
        progress = .zero
        isScanning = true
        isFinished = false
        currentDevice = LanDevice()
        devices = []
        scanTask = Task {
            for await event in scanner.scanStream() {
                progress = event.progress
                if let device = event.device {
                    currentDevice = device
                    if !devices.contains(where: { $0.ipAddress == device.ipAddress }) {
                        devices.append(device)
                    }
                }
            }
            isScanning = false
            isFinished = true
        }
    }

    /// Cancels the current scan.
    public func stop() {
        scanner.cancel()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        isFinished = true
    }
}
