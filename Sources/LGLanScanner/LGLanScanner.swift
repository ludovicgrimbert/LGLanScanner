//// The Swift Programming Language
//// https://docs.swift.org/swift-book
///
import Foundation
import ComposableArchitecture

@MainActor
public enum LGLanScannerKey: @preconcurrency DependencyKey {
    public static let liveValue: LGLanScanner = LGLanScanner()
}

extension LGLanScannerKey: @preconcurrency TestDependencyKey {
    public static let testValue: LGLanScanner = LGLanScanner() //TODO: mock ?
}

public extension DependencyValues {
    var scanner: LGLanScanner {
        get { self[LGLanScannerKey.self] }
        set { self[LGLanScannerKey.self] = newValue }
    }
}

@MainActor
public final class LGLanScanner {
    
    nonisolated(unsafe) var connectedDevices = [LanDevice]()
    nonisolated(unsafe) var progress: CGFloat = .zero
    nonisolated(unsafe) var isFinished = false
    
    nonisolated(unsafe) private lazy var scanner = LanScanner(delegate: self)
    
    nonisolated(unsafe) func start() {
        connectedDevices.removeAll()
        scanner.start()
    }
    
    nonisolated(unsafe) func stop() {
        scanner.stop()
    }
}

extension LGLanScanner: @preconcurrency LanScannerDelegate {
    public func lanScanHasUpdatedProgress(_ progress: CGFloat, address: String) {
        self.progress = progress
    }
    
    public func lanScanDidFindNewDevice(_ device: LanDevice) {
        connectedDevices.append(device)
    }
    
    public func lanScanDidFinishScanning() {
        isFinished = true
    }
}

extension LanDevice: Identifiable { //TODO: tester retroactive !!!
    public var id: UUID { .init() }
}

