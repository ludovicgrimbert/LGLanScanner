//
//  File.swift
//  
//
//  Created by Matheus Gois on 22/10/21.
//

import LanScanInternal
import CoreGraphics

public struct LanDevice: Sendable {
    public let name: String
    public let ipAddress: String
    public let mac: String
    public let brand: String
}

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
                        continuation.yield(LanScanEvent(progress: 0.0, device: device))
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


