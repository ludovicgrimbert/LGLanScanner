# Changelog

All notable changes to this package. [Keep a Changelog](https://keepachangelog.com) format,
[SemVer](https://semver.org) — on `0.x`, minor versions may break source compatibility.

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
