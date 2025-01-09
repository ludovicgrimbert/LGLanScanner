//// The Swift Programming Language
//// https://docs.swift.org/swift-book
///
import Foundation
import ComposableArchitecture

// Source: https://github.com/MaatheusGois/lan-scanner -> add mac os infoplist if you want app mac

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
    
   public nonisolated(unsafe) var connectedDevices = [LanDevice]()
    public nonisolated(unsafe) var progress: CGFloat = .zero
    public nonisolated(unsafe) var isFinished = false
    
    nonisolated(unsafe) private lazy var scanner = LanScanner(delegate: self)
    
    public nonisolated(unsafe) func start() {
        connectedDevices.removeAll()
        scanner.start()
    }
    
    public nonisolated(unsafe) func stop() {
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

