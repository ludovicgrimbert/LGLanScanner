# Changelog

All notable changes to this package. [Keep a Changelog](https://keepachangelog.com) format,
[SemVer](https://semver.org).

## [1.0.0] - 2026-09-13

First stable release: the Objective-C core is gone, replaced by a Swift Concurrency engine.
The façade keeps its shape (`progress`, `devices`, `isScanning`, `start()`, `stop()`).

### Changed
- The sweep runs off the main thread, in batches of concurrent pings (32 hosts, 300 ms per
  batch by default): a /24 takes two to three seconds instead of 25, and the UI no longer
  lives in nested run loops for the duration.
- Hosts are enumerated from the interface's address and mask as integers. The old string
  builder produced invalid addresses on `10.0.0.x` networks (`10.0..5`), which found nothing.
- `progress` is a `Double` and is monotonic; it used to fall back to 0 on every device found.
- `currentDevice` is optional; `state` (`idle / scanning / finished / failed`) replaces the
  `isScanning` + `isFinished` pair, which stay as derived properties. `error` exposes the failure.
- Engines: `LanScanEngine` protocol + `LiveLanScanEngine`; `LanScanEvent` is an enum.
- `LanDevice` gains `isGateway`; the router's name no longer gets " (router)" appended.
- The MAC and default gateway come from a 120-line C file over the kernel routing socket,
  instead of 950 lines of vendored kernel headers.

### Added
- `LanScanError`: `noLocalNetwork` (no Wi-Fi: the 0.x scan stayed "scanning" forever),
  `localNetworkDenied` (permission refused), `subnetTooLarge`, `socketUnavailable`.
- `LanScanConfiguration`: interface, ping timeout, batch size, host limit, name resolution.
- Host-name lookup with a hard timeout (the old `CFHost` call was synchronous, deprecated,
  leaked, and returned error text as the device name).
- Swift Testing target (26 tests), LICENSE with third-party notices.

### Removed
- The call to `api.macvendors.com` for unknown MAC prefixes: it ran synchronously on the main
  thread, sent the MAC addresses of the user's devices to a third party, and cached error
  bodies as brands in `Documents/vendors.out`. The bundled registry is the only source now.
- `NSLog` on every failed ping in Release, `CaptiveNetwork`, dead code.

## [0.3.1] - 2026-09-12

Release tag on main after merging fix_lazy_scanner / remove_tca / example_app. Same content as 0.3.0.

## [0.3.0] - 2026-09-12

### Added
- `LGLanScanner` is `@Observable`: SwiftUI views update as `progress`, `devices`,
  `currentDevice`, `isScanning` and `isFinished` change — no more polling `currentDevice`
  (which could miss a device found between two reads).
- `devices: [LanDevice]` — every device of the current scan, one per IP, in discovery order.
- `isScanning`.
- `LanDevice` is `Hashable` and `Identifiable` (by IP address).
- `LGLanScanner.xcworkspace` and `Example/LGLanScannerExample` (xcodegen), README.

## [0.2.0] - 2026-09-12

### Removed
- The Composable Architecture dependency: the `LGLanScannerKey` / `DependencyValues.scanner`
  glue is gone; `LGLanScanner.init()` is public.

### Changed
- Stored properties are ordinary `@MainActor` properties (`private(set)`) instead of
  `nonisolated(unsafe)`; `start()` resets the state of the previous scan.

## [0.1.2]

Last release before this changelog. Note: the `scanStream()` / `currentDevice` API that
RemoteTV uses only existed on the `fix_lazy_scanner` branch until 0.2.0.
