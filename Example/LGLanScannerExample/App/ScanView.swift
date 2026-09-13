//
//  ScanView.swift
//  LGLanScannerExample
//

import SwiftUI
import LGLanScanner

struct ScanView: View {
    /// `LGLanScanner` is `@Observable`: the view re-renders as progress and devices change.
    @State private var scanner = LGLanScanner()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProgressView(value: scanner.progress) {
                        Text(statusText)
                    }
                    if let error = scanner.error {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    Button(scanner.isScanning ? "Stop" : "Start scan") {
                        if scanner.isScanning {
                            scanner.stop()
                        } else {
                            scanner.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(scanner.isScanning ? .red : .accentColor)
                }

                Section("Devices (\(scanner.devices.count))") {
                    if scanner.devices.isEmpty {
                        Text(scanner.isScanning ? "Looking…" : "Nothing found yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(scanner.devices) { device in
                        DeviceRow(device: device, isLatest: device == scanner.currentDevice)
                    }
                }
            }
            .navigationTitle("LGLanScanner")
        }
    }

    private var statusText: String {
        switch scanner.state {
        case .idle: "Idle"
        case .scanning: "Scanning… \(Int(scanner.progress * 100)) %"
        case .finished: "Done — \(scanner.devices.count) device(s)"
        case .failed: "Failed"
        }
    }
}

private struct DeviceRow: View {
    let device: LanDevice
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(device.name.isEmpty ? device.ipAddress : device.name)
                    .font(.headline)
                if device.isGateway {
                    Image(systemName: "wifi.router").foregroundStyle(.secondary)
                }
                if isLatest {
                    Text("latest").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
            Text(device.brand.isEmpty ? device.ipAddress : "\(device.ipAddress) · \(device.brand)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !device.mac.isEmpty {
                Text(device.mac)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
