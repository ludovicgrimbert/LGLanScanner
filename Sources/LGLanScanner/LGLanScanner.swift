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
    
    //     private lazy var scanner: LanScanner = {
    //        LanScanner(delegate: self)
    //    }()
    //
    //    public func start() {
    //        connectedDevices.removeAll()
    //        scanner.start()
    //    }
    //
    //    public func stop() {
    //        scanner.stop()
    //    }
    
    let scanner = LanScanner()
    private var scanTask: Task<Void, Never>?

    public func start() async throws {
        connectedDevices.removeAll()
        
        scanTask = Task {
            for await device in scanner.scanStream() {
                connectedDevices.append(device)
                print("Appareil trouvé : \(device.name)")
            }
            isFinished = true
        }
        
    }
    
    public func stop() async throws {
        scanner.cancel()
        scanTask?.cancel()
    }
    
}
    
    
    

//
//extension LGLanScanner: @preconcurrency LanScannerDelegate {
//    public func lanScanHasUpdatedProgress(_ progress: CGFloat, address: String) {
//        self.progress = progress
//    }
//    
//    public func lanScanDidFindNewDevice(_ device: LanDevice) {
//        connectedDevices.append(device)
//    }
//    
//    public func lanScanDidFinishScanning() {
//        isFinished = true
//    }
//}
//
//extension LanDevice: Identifiable { //TODO: tester retroactive !!!
//    public var id: UUID { .init() }
//}


/*
let scanner = LanScanner()

// Lancer un scan
let task = Task {
    for await device in scanner.scanStream() {
        print("Appareil trouvé : \(device.name)")
    }
}

// Annuler après 3 secondes
DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    print("⛔️ Annulation du scan")
    scanner.cancel()
    task.cancel()
}
*/
