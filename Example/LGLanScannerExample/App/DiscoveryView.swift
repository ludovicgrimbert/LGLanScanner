//
//  DiscoveryView.swift
//  LGLanScannerExample
//

import SwiftUI
import LGLanDiscovery

struct DiscoveryView: View {
    /// Bonjour + SSDP, looking for televisions by default.
    @State private var discovery = LGLanDiscovery()
    @State private var everything = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Everything (not just TVs)", isOn: $everything)
                        .onChange(of: everything) { _, all in
                            discovery.configuration = all ? .everything : .televisions
                        }
                    HStack {
                        Text(statusText)
                        if discovery.isDiscovering { Spacer(); ProgressView() }
                    }
                    ForEach(discovery.errors, id: \.self) { error in
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    Button(discovery.isDiscovering ? "Stop" : "Discover") {
                        discovery.isDiscovering ? discovery.stop() : discovery.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(discovery.isDiscovering ? .red : .accentColor)
                }

                if !discovery.televisions.isEmpty {
                    Section("Televisions") {
                        ForEach(discovery.televisions) { service in
                            HStack {
                                Image(systemName: "tv")
                                VStack(alignment: .leading) {
                                    Text(service.name).font(.headline)
                                    Text("\(service.host) · \(service.vendor.rawValue.uppercased())")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Services (\(discovery.services.count))") {
                    if discovery.services.isEmpty {
                        Text(discovery.isDiscovering ? "Listening…" : "Nothing found yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(discovery.services) { service in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name).font(.headline)
                            Text("\(service.host):\(service.port) · \(service.source.rawValue)")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(service.type).font(.caption.monospaced()).foregroundStyle(.tertiary)
                            if let model = service.attributes["modelname"] ?? service.attributes["md"] ?? service.attributes["model"] {
                                Text(model).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("LGLanDiscovery")
        }
    }

    private var statusText: String {
        switch discovery.state {
        case .idle: "Idle"
        case .discovering: "Discovering… (\(Int(discovery.configuration.duration / .seconds(1))) s window)"
        case .finished: "Done — \(discovery.televisions.count) TV(s), \(discovery.services.count) service(s)"
        case .failed: "Failed"
        }
    }
}
