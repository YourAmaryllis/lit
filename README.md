# lit

A free, open-source (MIT) rebuild of [getjuicy.app](https://getjuicy.app) (Juicy) — a native macOS menu bar app for battery alerts and health monitoring — plus feature ideas beyond the original.

## Structure

- `mac-app/` — Swift Package (SwiftUI `MenuBarExtra`) menu bar app.
  - **`swift run` no longer works standalone** — `UNUserNotificationCenter` crashes hard (`bundleProxyForCurrentProcess is nil`) without a real app bundle, now that alerts exist.
  - Build + package: `./Scripts/build-app.sh [debug|release]` → produces `.build/Lit.app`, ad-hoc codesigned.
- `site/` — Next.js 16 marketing/landing site. Run with `npm run dev` from inside `site/`.

## Status

**mac-app v0.2** — installed and running on this laptop:
- Installed at `/Applications/Lit.app` (release build, ad-hoc signed)
- Auto-launches at login via `~/Library/LaunchAgents/app.lit.mac.plist` (`RunAtLoad`, no `KeepAlive` — quitting the app doesn't cause launchd to resurrect it)
- Verified: dock icon correctly hidden (`LSUIElement`), ~0% CPU / 0.4% mem at idle, no crashes over the verification window
- **First launch will show a macOS system prompt asking to allow notifications for "lit" — you need to click Allow yourself**, I can't do that part
- To restart after rebuilding: `launchctl kickstart -k gui/$(id -u)/app.lit.mac`. To fully remove: `launchctl bootout gui/$(id -u)/app.lit.mac`, then delete `/Applications/Lit.app` and `~/Library/LaunchAgents/app.lit.mac.plist`

Features:
- Menu bar icon showing live battery percentage + charging state
- Battery health %, cycle count, temperature (via IOKit `AppleSmartBattery`) — **verified against `ioreg`/`pmset` ground truth on this machine** (89% / charging / 123 cycles / 96% health / 30.5°C, all matching). This caught a real bug: on Apple Silicon, top-level `MaxCapacity` is already a 0–100 percentage, not mAh — the code was computing health from the wrong field until fixed (`AppleRawMaxCapacity` is the correct mAh-comparable value)
- Time remaining / time to full
- Custom alert thresholds with add/remove UI, persisted in `UserDefaults`, firing real local notifications (`UNUserNotificationCenter`) when the battery drops to/below a threshold on battery power, re-arming once plugged in
- Bluetooth/HID peripheral battery levels (AirPods, Magic Mouse/Keyboard/Trackpad, or anything else exposing the standard HID battery property), read via `AppleDeviceManagementHIDEventService` — **code builds and runs cleanly, but is unverified against real hardware** since no Bluetooth accessory was paired on this Mac when this was built. Test with a real device before trusting it.

**Not yet built** (needs more design work):
- Charge limiting / "healthy band" — requires a privileged helper (SMJobBless or similar) since writing SMC charge-control keys needs elevated permissions beyond the sandboxed app
- Per-app energy consumption tracking — no clean public API; likely needs the private `IOReport` framework
- Predictive alerts (Calendar integration), smart charging schedule, long-term health trend export
- Native-style notification "pill" UI (currently uses stock macOS notification banners, not a custom overlay)

**site v0.1** (working): hero, feature grid, "new in lit" section, open-source/GitHub section (replaces the original's paid pricing tiers) — content only, `GITHUB_URL` in `page.tsx` is a placeholder until the repo is published.

## Feature reference

Full parity + enhancement list was worked out against the original product; see conversation history for the complete breakdown (alerts, health tracking, device monitoring, charging protection, energy insights, plus new ideas like predictive alerts, smart charging schedules, generic BLE support, long-term health trend export, companion iOS widget).
