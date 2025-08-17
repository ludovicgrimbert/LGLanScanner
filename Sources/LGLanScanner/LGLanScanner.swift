//// The Swift Programming Language
//// https://docs.swift.org/swift-book
///
import Foundation
import ComposableArchitecture
import LanScanInternal


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
    
    let scanner = LanScanner()
    private var scanTask: Task<Void, Never>?
    
    public func start() {
        connectedDevices.removeAll()
        scanTask = Task {
            
            for await event in scanner.scanStream() {
                progress = event.progress
                if let device = event.device {
                    print("📡 Appareil trouvé : \(device.name) - \(device.ipAddress)")
                    connectedDevices.append(device)
                }
            }
            print("✅ Scan terminé")
            isFinished = true
        }
    }
    
    public func stop() {
        scanner.cancel()
        scanTask?.cancel()
        scanTask = nil
    }
}
