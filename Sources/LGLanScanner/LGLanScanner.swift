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

/// Drives one network scan at a time. Read `progress`, `currentDevice` and `isFinished`
/// from the main actor while a scan runs; call `stop()` to cancel it.
///
/// ```swift
/// let scanner = LGLanScanner()
/// scanner.start()
/// // observe scanner.progress / scanner.currentDevice until scanner.isFinished
/// ```
@MainActor
public final class LGLanScanner {

    /// 0...1 progress of the current scan.
    public private(set) var progress: CGFloat = .zero
    /// `true` once the current scan has gone through the whole IP range (or was stopped).
    public private(set) var isFinished = false
    /// The last device found by the current scan.
    public private(set) var currentDevice = LanDevice()

    let scanner = LanScanner()
    private var scanTask: Task<Void, Never>?

    public init() {}

    /// Starts a scan, resetting the state left by a previous one.
    public func start() {
        scanTask?.cancel()
        progress = .zero
        isFinished = false
        currentDevice = LanDevice()
        scanTask = Task {
            for await event in scanner.scanStream() {
                progress = event.progress
                if let device = event.device {
                    currentDevice = device
                }
            }
            isFinished = true
        }
    }

    /// Cancels the current scan. `isFinished` becomes `true` once the stream has wound down.
    public func stop() {
        scanner.cancel()
        scanTask?.cancel()
        scanTask = nil
    }
}
