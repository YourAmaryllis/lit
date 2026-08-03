# lit

A free, open-source (MIT) rebuild of [getjuicy.app](https://getjuicy.app) (Juicy) — a native macOS menu bar app for battery alerts and health monitoring — plus feature ideas beyond the original.

Repo: https://github.com/YourAmaryllis/lit

## Structure

- `mac-app/` — Swift Package (SwiftUI `MenuBarExtra`) menu bar app.
  - **`swift run` no longer works standalone** — `UNUserNotificationCenter` crashes hard (`bundleProxyForCurrentProcess is nil`) without a real app bundle, now that alerts exist.
  - Build + package: `./Scripts/build-app.sh [debug|release]` → produces `.build/Lit.app`, ad-hoc codesigned.
- `site/` — Next.js 16 marketing/landing site. Run with `npm run dev` from inside `site/`.

## Status

**mac-app v0.3** — installed and running on this laptop:
- Installed at `/Applications/Lit.app` (release build, ad-hoc signed)
- Auto-launches at login via `~/Library/LaunchAgents/app.lit.mac.plist` (`RunAtLoad`, no `KeepAlive` — quitting the app doesn't cause launchd to resurrect it)
- Verified: dock icon correctly hidden (`LSUIElement`), ~0% CPU / 0.4% mem at idle, no crashes over the verification window
- **First launch shows a macOS system prompt asking to allow notifications for "lit" — you need to click Allow yourself**, I can't do that part
- To restart after rebuilding: `launchctl kickstart -k gui/$(id -u)/app.lit.mac`. To fully remove: `launchctl bootout gui/$(id -u)/app.lit.mac`, then delete `/Applications/Lit.app` and `~/Library/LaunchAgents/app.lit.mac.plist`

Shipped features:
- Menu bar icon: themeable (icon+%, % only, icon only), color-coded battery glyph (SF Symbols `battery.0`–`battery.100`), red/orange under 20%/10%, green while charging
- Battery health %, cycle count, temperature (via IOKit `AppleSmartBattery`) — **verified against `ioreg`/`pmset` ground truth on this machine** (89% / charging / 123 cycles / 96% health / 30.5°C, all matching). This caught a real bug: on Apple Silicon, top-level `MaxCapacity` is already a 0–100 percentage, not mAh — the code was computing health from the wrong field until fixed (`AppleRawMaxCapacity` is the correct mAh-comparable value)
- Time remaining / time to full
- Custom alert thresholds with add/remove UI, persisted in `UserDefaults`, firing real local notifications when the battery drops to/below a threshold on battery power, re-arming once plugged in
- Lifecycle alerts: plugged in, unplugged, and crossing 80% while charging (the cue to unplug for battery health)
- Bluetooth/HID peripheral battery levels (AirPods, Beats, Magic Mouse/Keyboard/Trackpad, or anything else exposing the standard HID battery property), read via `AppleDeviceManagementHIDEventService`, with per-device low-battery/fully-charged alerts — **code builds and runs cleanly, but is still unverified against real hardware**: no Bluetooth accessory has been connected on this Mac while testing. Pair a device and check the menu before trusting it.

**Not yet built** (harder, system-level pieces — tracked on the site's "On the roadmap" section too):
- Charge limiting / "healthy band" (Sailing Mode / Automatic Discharge) — requires a privileged helper (SMJobBless or similar) since writing SMC charge-control keys needs elevated permissions beyond the sandboxed app
- Per-app energy consumption tracking — no clean public API; likely needs the private `IOReport` framework
- iPhone/iPad plug-in battery health — needs the private MobileDevice framework
- Predictive alerts (Calendar integration), smart charging schedule, long-term health trend export
- Native-style notification "pill" UI (currently uses stock macOS notification banners, not a custom overlay)
- Auto-dismissing macOS's own low-battery pop-up — no known public mechanism for this; may not be feasible without private/Accessibility-API hacks

**site v0.2** (working, verified in-browser): hero, problem statement, shipped-features grid, an honest "on the roadmap" section for what's not built yet, use-case scenarios, open-source/GitHub section, and a genuine FAQ. No fake testimonials — the original's testimonials section was deliberately dropped rather than fabricated.

## Feature reference

Full parity + enhancement list was worked out against the original product's homepage and `/#features` page; see conversation history for the complete breakdown.
