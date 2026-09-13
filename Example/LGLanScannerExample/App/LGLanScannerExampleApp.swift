//
//  LGLanScannerExampleApp.swift
//  LGLanScannerExample
//
//  Two tabs: the ping sweep (LGLanScanner) and the service discovery (LGLanDiscovery).
//  The simulator shares the Mac's network, so both work there too.
//

import SwiftUI

@main
struct LGLanScannerExampleApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ScanView()
                    .tabItem { Label("Scan", systemImage: "dot.radiowaves.left.and.right") }
                DiscoveryView()
                    .tabItem { Label("Discovery", systemImage: "tv.badge.wifi") }
            }
        }
    }
}
