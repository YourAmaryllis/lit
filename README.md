# lit

A free, open-source (MIT) native macOS menu bar app for battery alerts and
health monitoring — a rebuild of [getjuicy.app](https://getjuicy.app) (Juicy)
plus a few ideas of its own.

No account, no subscription, no telemetry. Everything runs locally.

## Features

- **Menu bar glyph** — live percentage, color-coded SF Symbols battery icon,
  charging indicator
- **Battery health** — health %, cycle count, temperature (°C/°F), condition
  badge
- **Power & Electrical** — live voltage, current, wattage, and an animated
  flow diagram between adapter/battery/Mac (while charging, shown as a real
  branch: one adapter source, two simultaneous destinations)
- **Capacity details** — remaining / full / design capacity in mAh
- **System temperature** — CPU/GPU temperature (Apple Silicon) plus thermal
  pressure state
- **Connected devices** — Bluetooth accessory battery (AirPods, Magic
  Mouse/Keyboard/Trackpad), iPhone/iPad battery percentage, and Android
  battery percentage (requires USB debugging enabled on the phone)
- **Apps using significant energy** — ranked by real per-process energy
  usage, not a CPU-time proxy
- **Custom alert thresholds** — add any percentage, get a real notification
  when you cross it, plus lifecycle alerts (plugged in / unplugged / crossed
  80% while charging)
- **Local web dashboard** — the same stats with more room to breathe, served
  from `127.0.0.1` only, opened from the menu bar's Settings row

Every number is either a real, verified reading or clearly labeled as an
estimate — see [`mac-app/DATA_SOURCES.md`](mac-app/DATA_SOURCES.md) for
exactly which API backs each one, and which are still unverified against
real hardware.

## Install

Download the latest DMG from [Releases](https://github.com/YourAmaryllis/lit/releases),
open it, and drag **lit** into Applications.

Builds are unsigned (no Apple Developer ID) — right-click → Open on first
launch if Gatekeeper warns.

iPhone/iPad battery support requires
[`libimobiledevice`](https://libimobiledevice.org): `brew install libimobiledevice`.

Android battery support requires `adb`: `brew install android-platform-tools`,
plus Developer Options → USB debugging enabled on the phone.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel (universal binary)
- CPU/GPU temperature is currently verified only on Apple Silicon; on other
  chips it's simply omitted, never shown incorrectly

## Building from source

```bash
cd mac-app
swift build                    # or: ./Scripts/build-app.sh [debug|release]
```

`swift run` does not work standalone once notifications are involved —
`UNUserNotificationCenter` requires a real `.app` bundle. Use
`./Scripts/build-app.sh` to produce one at `mac-app/.build/Lit.app`.

## Project structure

- `mac-app/` — the Swift Package (SwiftUI `MenuBarExtra`) menu bar app
- `site/` — Next.js marketing site
- `scripts/` — release build scripts (`build-app.sh` → universal, versioned
  `dist/Lit.app`; `build-dmg.sh` → `dist/lit-<version>.dmg`)
- `.github/workflows/release.yml` — tag-triggered CI release

## Architecture

Stats appear in two places by design:

- The **menu bar dropdown** (`MenuBarView.swift`, pure SwiftUI) is a rich,
  color-coded, collapsible view for a quick glance.
- The **web dashboard** (`DashboardServer.swift`, a small HTTP/1.1 server on
  `Network.framework`; `Resources/dashboard.html`, a single self-contained
  page) shows the same data with more room, served from `127.0.0.1:7091`
  only — not reachable from the LAN.

Alert thresholds and menu bar icon style are dashboard-only, since they're
editable config rather than stats and don't fit a 300px popover.

## Releasing

Version lives in the `VERSION` file. To cut a release:

```bash
git tag v0.0.1 && git push origin v0.0.1
```

This triggers `.github/workflows/release.yml`, which builds a universal DMG
and publishes a GitHub Release. Can also be run manually via
Actions → Release → Run workflow.

## Roadmap

- Charge limiting / healthy charge band (needs a privileged helper — writing
  SMC charge-control keys requires elevated permissions)
- iPhone/iPad full battery health (cycle count, temperature — currently only
  percentage and charging state are shown)
- Predictive, calendar-aware alerts
- Custom notification UI (currently uses stock macOS notification banners)

## License

MIT. See [`LICENSE`](LICENSE).
