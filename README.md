# LGLanScanner

Two ways to find the devices on the local Wi-Fi network, iOS 17+, Swift 6, no dependencies:

- **LGLanScanner** — a ping sweep of the subnet, then the MAC (ARP cache), manufacturer
  (bundled IEEE OUI registry) and name (reverse DNS / mDNS) of each device that answered.
  Swift Concurrency, off the main thread, nothing leaves the LAN.
- **LGLanDiscovery** — asks the network who offers a service (Bonjour and SSDP/UPnP): faster,
  and it returns only the devices you care about, televisions by default, with their names.

```swift
.package(url: "https://github.com/ludovicgrimbert/LGLanScanner", from: "1.1.0")
// products: "LGLanScanner", "LGLanDiscovery"
```

## Usage

```swift
import LGLanScanner

@State private var scanner = LGLanScanner()          // @Observable, @MainActor

ProgressView(value: scanner.progress)                // 0...1, monotonic
ForEach(scanner.devices) { device in                 // one per IP, discovery order
    Text("\(device.name) — \(device.ipAddress) — \(device.mac) — \(device.brand)")
}
Button(scanner.isScanning ? "Stop" : "Scan") {
    scanner.isScanning ? scanner.stop() : scanner.start()   // start() resets the previous scan
}
if let error = scanner.error { Text(error.localizedDescription) }
```

`state` is `idle`, `scanning`, `finished` (swept, or stopped) or `failed(LanScanError)`;
`isScanning`, `isFinished` and `error` are views on it. `currentDevice` is the last device
found. `LanDevice.isGateway` flags the router.

The app must declare `NSLocalNetworkUsageDescription`. iOS asks the user on the first scan;
a refusal surfaces as `LanScanError.localNetworkDenied`, no Wi-Fi as `.noLocalNetwork`.

### Configuration

```swift
LGLanScanner(configuration: LanScanConfiguration(
    interface: "en0",                  // Wi-Fi on iPhone and iPad
    pingTimeout: .milliseconds(300),   // per batch; raise for sleepy devices
    batchSize: 32,                     // hosts probed at once
    maxHosts: 1024,                    // refuse anything wider than a /22
    resolvesHostNames: true,
    hostNameTimeout: .seconds(1)
))
```

A /24 takes two to three seconds with the defaults: 254 hosts, 32 at a time, 300 ms per
batch. Name resolution runs in parallel for the devices found and never holds the scan
longer than its timeout.

### Own engine

`LGLanScanner` consumes a `LanScanEngine`: anything that turns a configuration into an
`AsyncThrowingStream<LanScanEvent, Error>` of `.progress(Double)` and `.device(LanDevice)`.
`LiveLanScanEngine` is the real one; a scripted engine makes view-model tests trivial (see
`Tests/LGLanScannerTests/LGLanScannerTests.swift`).

## How it works

1. `LocalNetwork` reads the interface's IPv4 address and mask (`getifaddrs`); `IPv4Subnet`
   enumerates the hosts between network and broadcast, minus the device itself.
2. `ICMPSocket` sends echo requests from one unprivileged `SOCK_DGRAM` ICMP socket, a batch
   at a time, and collects the replies until the batch deadline, on a private queue.
3. For each answer, `RoutingTable` reads the ARP cache and the default gateway through the
   kernel routing socket (the only C in the package, `LanScanInternal`), `OUITable` maps the
   MAC prefix to a manufacturer, `HostNameResolver` asks for a name with a hard timeout.

## Migrating from 0.x

| 0.x | 1.0 |
|---|---|
| `progress: CGFloat` | `progress: Double` |
| `isScanning`, `isFinished` | still there, derived from `state` |
| `currentDevice: LanDevice` (empty sentinel) | `currentDevice: LanDevice?` |
| no error | `state == .failed(error)`, `scanner.error` |
| `LanScanner` class + `scanStream()` | `LanScanEngine` protocol, `LiveLanScanEngine` |
| `LanScanEvent(progress:device:)` struct | `enum LanScanEvent { progress, device }` |
| `LanDevice(name:ipAddress:mac:brand:)` | same, plus `isGateway`; the router no longer gets " (router)" appended to its name |
| brand fetched from api.macvendors.com when unknown | bundled registry only; unknown stays empty |

## LGLanDiscovery

```swift
import LGLanDiscovery

@State private var discovery = LGLanDiscovery()   // Bonjour + SSDP, .televisions, 5 s window

Button("Find TVs") { discovery.start() }
ForEach(discovery.televisions) { tv in            // vendor recognised, one per host
    Text("\(tv.name) — \(tv.host) — \(tv.vendor.rawValue)")
}
ForEach(discovery.services) { service in          // everything announced
    Text("\(service.type) at \(service.host):\(service.port)")
}
ForEach(discovery.errors, id: \.self) { Text($0.localizedDescription) }
```

`LanService.attributes` holds the Bonjour TXT record, or the SSDP headers plus the UPnP
description fields (`friendlyname`, `manufacturer`, `modelname`, `udn`, Sony's
`x_scalarwebapi_baseurl`). `vendor` is a heuristic over all of that: `.sony`, `.lg`, `.unknown`.

`.televisions` looks for `_googlecast._tcp`, `_androidtvremote2._tcp`, `_airplay._tcp`
(Bonjour) and IRCC, Scalar Web API, webOS second screen, DIAL (SSDP). `.everything` browses the
common Bonjour types and `ssdp:all`. Build your own `LanDiscoveryConfiguration` for anything else.

What the app must declare:

| | Info.plist | Entitlement |
|---|---|---|
| Ping sweep | `NSLocalNetworkUsageDescription` | — |
| Bonjour | + every type in `NSBonjourServices` | — |
| SSDP | `NSLocalNetworkUsageDescription` | `com.apple.developer.networking.multicast` (request it from Apple; without it the engine fails with `multicastNotAllowed` and the others carry on) |

The simulator enforces none of the entitlements. Engines run together: one failing lands in
`errors`, `state` is `.failed` only when all of them fail.

## Example app

Open `LGLanScanner.xcworkspace`: the package next to `Example/LGLanScannerExample`, two tabs
(the sweep: start/stop, progress, error, device list; the discovery: televisions and every
service, with the engines' errors) built against the working tree. Generated with
[xcodegen](https://github.com/yonaskolb/XcodeGen) from `Example/project.yml`
(`cd Example && xcodegen generate` after adding files). The simulator shares the Mac's network.

## Development

```sh
xcodebuild test -workspace LGLanScanner.xcworkspace -scheme LGLanScanner -destination 'platform=iOS Simulator,name=iPhone 17'
```

The tests cover the address arithmetic, the ICMP packets (including a real ping of the
gateway when there is one), the OUI registry, the routing-table reads, the engines' fail-fast
paths, the SSDP/UPnP parsing, the vendor heuristics and both façades' state machines with
scripted engines. Sweeping or discovering on a real LAN is exercised by the example app.
