# LGLanScanner

Scans the local network (ping sweep + ARP, from
[MaatheusGois/lan-scanner](https://github.com/MaatheusGois/lan-scanner)) and reports the
devices found, as an `@Observable` main-actor class. iOS 17+, Swift 6, no dependencies.

```swift
.package(url: "https://github.com/ludovicgrimbert/LGLanScanner", exact: "0.3.1")
```

## Usage

```swift
import LGLanScanner

@State private var scanner = LGLanScanner()

ProgressView(value: scanner.progress)                       // 0...1
ForEach(scanner.devices) { device in                        // one per IP, discovery order
    Text("\(device.name) — \(device.ipAddress) — \(device.mac) — \(device.brand)")
}
Button(scanner.isScanning ? "Stop" : "Scan") {
    scanner.isScanning ? scanner.stop() : scanner.start()   // start() resets the previous scan
}
```

`currentDevice` is the last device found; `isFinished` flips once the whole range was swept
(or `stop()` was called). Everything is read on the main actor; no polling needed.

The app must declare `NSLocalNetworkUsageDescription` — iOS prompts for local-network
access on the first scan.

## Example app

Open `LGLanScanner.xcworkspace`: the package next to `Example/LGLanScannerExample`, a one-screen
app (start/stop, progress, device list) built against the working tree. Generated with
[xcodegen](https://github.com/yonaskolb/XcodeGen) from `Example/project.yml`
(`cd Example && xcodegen generate` after adding files). The simulator shares the Mac's network.

## Development

iOS-only; build through a simulator:

```sh
xcodebuild build -workspace LGLanScanner.xcworkspace -scheme LGLanScanner -destination 'generic/platform=iOS Simulator'
```
