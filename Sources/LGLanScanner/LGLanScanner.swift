//// The Swift Programming Language
//// https://docs.swift.org/swift-book
////
////  DeviceScanner.swift
////  RemoteTV
////
////  Created by Ludovic Grimbert on 16/05/2024.
////
//
//import Foundation
////import LanScanner
//import ComposableArchitecture
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
