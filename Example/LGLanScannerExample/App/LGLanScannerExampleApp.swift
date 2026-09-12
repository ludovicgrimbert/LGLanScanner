//
//  LGLanScannerExampleApp.swift
//  LGLanScannerExample
//
//  Scans the local network with LGLanScanner and lists what it finds. The simulator shares
//  the Mac's network, so it works there too.
//

import SwiftUI

@main
struct LGLanScannerExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ScanView()
        }
    }
}
