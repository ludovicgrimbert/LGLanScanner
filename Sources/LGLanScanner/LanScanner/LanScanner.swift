//
//  File.swift
//  
//
//  Created by Matheus Gois on 22/10/21.
//

import LanScanInternal
import CoreGraphics

/*
public struct LanDevice {
    public var name: String
    public var ipAddress: String
    public var mac: String
    public var brand: String
}

public protocol LanScannerDelegate: AnyObject {
    func lanScanHasUpdatedProgress(_ progress: CGFloat, address: String)
    func lanScanDidFindNewDevice(_ device: LanDevice)
    func lanScanDidFinishScanning()
}

public class LanScanner: NSObject {

    // MARK: - Properties

    public var scanner: LanScan?
    public weak var delegate: LanScannerDelegate?

    // MARK: - Init

    public init(delegate: LanScannerDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Methods

    public func stop() {
        scanner?.stop()
    }

    public func start() {
        scanner?.stop()
        scanner = LanScan(delegate: self)
        scanner?.start()
    }

    public func getCurrentWifiSSID() -> String? {
        nil // scanner?.getCurrentWifiSSID()
    }
}

extension LanScanner: LANScanDelegate {
    public func lanScanHasUpdatedProgress(_ counter: Int, address: String!) {
        let progress = CGFloat(counter) / CGFloat(MAX_IP_RANGE)
        delegate?.lanScanHasUpdatedProgress(progress, address: address)
    }

    public func lanScanDidFindNewDevice(_ device: [AnyHashable : Any]!) {
        guard let device = device as? [AnyHashable: String] else { return }
        delegate?.lanScanDidFindNewDevice(
            .init(
                name: device[DEVICE_NAME] ?? "",
                ipAddress: device[DEVICE_IP_ADDRESS] ?? "",
                mac: device[DEVICE_MAC] ?? "",
                brand: device[DEVICE_BRAND] ?? ""
            )
        )
    }

    public func lanScanDidFinishScanning() {
        delegate?.lanScanDidFinishScanning()
    }
}
*/

//**************************************
//
//@MainActor
//private enum DeviceScannerKey: @preconcurrency DependencyKey {
//    static let liveValue: DeviceScanner = DeviceScanner()
//}
//
//extension DeviceScannerKey: @preconcurrency TestDependencyKey {
//    static let testValue: DeviceScanner = DeviceScanner() //TODO: mock ?
//}
//
//extension DependencyValues {
//    var scanner: DeviceScanner {
//        get { self[DeviceScannerKey.self] }
//        set { self[DeviceScannerKey.self] = newValue }
//    }
//}
//
//@MainActor
//final class DeviceScanner {
//    //    actor DeviceScanner {
//    
//    nonisolated(unsafe) var connectedDevices = [LanDevice]()
//    nonisolated(unsafe) var progress: CGFloat = .zero
//    nonisolated(unsafe) var isFinished = false
//    
//    nonisolated(unsafe) private lazy var scanner = LanScanner(delegate: self)
//    
//    nonisolated(unsafe) func start() {
//        connectedDevices.removeAll()
//        scanner.start()
//    }
//    
//    nonisolated(unsafe) func stop() {
//        scanner.stop()
//    }
//}
//
//extension DeviceScanner: @preconcurrency LanScannerDelegate {
//    func lanScanHasUpdatedProgress(_ progress: CGFloat, address: String) {
//        self.progress = progress
//    }
//    
//    func lanScanDidFindNewDevice(_ device: LanDevice) {
//        connectedDevices.append(device)
//    }
//    
//    func lanScanDidFinishScanning() {
//        isFinished = true
//    }
//}
//
//extension LanDevice: @retroactive Identifiable { //TODO: tester retroactive !!!
//    public var id: UUID { .init() }
//}
//

//import Foundation
//import CoreGraphics

public struct LanDevice: Sendable {
    public let name: String
    public let ipAddress: String
    public let mac: String
    public let brand: String
}

// Structure pour combiner device et progression
public struct LanScanEvent: Sendable {
    public let progress: CGFloat
    public let device: LanDevice?
}

public class LanScanner: NSObject {
    private var scanner: LanScan?
    private var isCancelled = false
    
    private var onDeviceFound: ((LanDevice) -> Void)?
    private var onProgress: ((CGFloat) -> Void)?
    private var onFinish: (() -> Void)?
    
    // MARK: - Annuler un scan en cours
    public func cancel() {
        isCancelled = true
        scanner?.stop()
    }
    
//    // MARK: - Version simple : tout à la fin
//    public func scan() async -> [LanDevice] {
//        await withCheckedContinuation { continuation in
//            var foundDevices: [LanDevice] = []
//            
//            startScan(
//                progressHandler: { _ in },
//                deviceHandler: { [weak self] device in
//                    guard self?.isCancelled == false else { return }
//                    foundDevices.append(device)
//                },
//                finishHandler: { [weak self] in
//                    guard self?.isCancelled == false else {
//                        continuation.resume(returning: [])
//                        return
//                    }
//                    continuation.resume(returning: foundDevices)
//                }
//            )
//        }
//    }
    
    // MARK: - Version streaming : progression + device
    public func scanStream() -> AsyncStream<LanScanEvent> {
        AsyncStream { continuation in
            startScan(
                progressHandler: { [weak self] progress in
                    guard self?.isCancelled == false else { return }
                    Task { @MainActor in
                        continuation.yield(LanScanEvent(progress: progress, device: nil))
                    }
                },
                deviceHandler: { [weak self] device in
                    guard self?.isCancelled == false else { return }
                    Task { @MainActor in
                        continuation.yield(LanScanEvent(progress: 1.0, device: device))
                    }
                },
                finishHandler: { [weak self] in
                    guard self?.isCancelled == false else {
                        Task { @MainActor in
                            continuation.finish()
                        }
                        return
                    }
                    Task { @MainActor in
                        continuation.finish()
                    }
                }
            )
        }
    }
    
    // MARK: - Démarrage interne du scan
    private func startScan(progressHandler: @escaping (CGFloat) -> Void,
                           deviceHandler: @escaping (LanDevice) -> Void,
                           finishHandler: @escaping () -> Void) {
        isCancelled = false
        scanner?.stop()
        scanner = LanScan(delegate: self)
        self.onProgress = progressHandler
        self.onDeviceFound = deviceHandler
        self.onFinish = finishHandler
        scanner?.start()
    }
}

// MARK: - LANScanDelegate
extension LanScanner: LANScanDelegate {
    public func lanScanHasUpdatedProgress(_ counter: Int, address: String!) {
        let progress = CGFloat(counter) / CGFloat(MAX_IP_RANGE)
        onProgress?(progress)
    }
    
    public func lanScanDidFindNewDevice(_ device: [AnyHashable : Any]!) {
        guard let device = device as? [AnyHashable: String] else { return }
        let found = LanDevice(
            name: device[DEVICE_NAME] ?? "",
            ipAddress: device[DEVICE_IP_ADDRESS] ?? "",
            mac: device[DEVICE_MAC] ?? "",
            brand: device[DEVICE_BRAND] ?? ""
        )
        onDeviceFound?(found)
    }
    
    public func lanScanDidFinishScanning() {
        onFinish?()
    }
}


