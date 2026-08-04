# lit

A free, open-source (MIT) rebuild of [getjuicy.app](https://getjuicy.app) (Juicy) — a native macOS menu bar app for battery alerts and health monitoring — plus feature ideas beyond the original.

Repo: https://github.com/YourAmaryllis/lit

## Structure

- `mac-app/` — Swift Package (SwiftUI `MenuBarExtra`) menu bar app.
  - **`swift run` no longer works standalone** — `UNUserNotificationCenter` crashes hard (`bundleProxyForCurrentProcess is nil`) without a real app bundle, now that alerts exist.
  - Build + package: `./Scripts/build-app.sh [debug|release]` → produces `.build/Lit.app`, ad-hoc codesigned.
- `site/` — Next.js 16 marketing/landing site. Run with `npm run dev` from inside `site/`.

## Architecture: menu bar glance + local web dashboard

Same pattern as CloudMount and similar local-admin-page tools: the app itself
stays a minimal menu bar dropdown (percentage, status, an "Open Dashboard"
button, Quit), and all the detailed stats/settings live in a full dashboard
served over HTTP from **127.0.0.1:7091 only** (not reachable from the LAN —
verified) and opened in your default browser. `DashboardServer.swift` is a
small hand-rolled HTTP/1.1 server on `Network.framework`; `Resources/dashboard.html`
is a single self-contained page (inline CSS/JS, no build step) that polls
`GET /api/status` every 2 seconds and posts to `/api/thresholds/add|remove`
and `/api/icon-style` for the two pieces of writable state.

## Status

**mac-app v0.4** — installed and running on this laptop:
- Installed at `/Applications/Lit.app` (release build, ad-hoc signed)
- Auto-launches at login via `~/Library/LaunchAgents/app.lit.mac.plist` (`RunAtLoad`, no `KeepAlive` — quitting the app doesn't cause launchd to resurrect it)
- Verified: dock icon correctly hidden (`LSUIElement`), stable over the verification window, no crashes
- Dashboard verified end-to-end: real data confirmed consistent (100% / fully charged / 96% health / 123 cycles / 30.7°C / 65W adapter, all internally consistent and matching `ioreg`/`system_profiler`), all three POST endpoints tested via curl and real browser clicks, loopback-only binding confirmed (unreachable from the LAN IP)
- **First launch shows a macOS system prompt asking to allow notifications for "lit" — you need to click Allow yourself**, I can't do that part
- To restart after rebuilding: `launchctl kickstart -k gui/$(id -u)/app.lit.mac`. To fully remove: `launchctl bootout gui/$(id -u)/app.lit.mac`, then delete `/Applications/Lit.app` and `~/Library/LaunchAgents/app.lit.mac.plist`

Shipped features (dashboard unless noted):
- **Hero gauge**: percentage, status, time to full/time remaining
- **Battery Information**: health % with Good/Fair/Poor badge (≥80/50–79/<50, mirroring Apple's own 80% service-eligibility threshold), cycle count, temperature in both °C and °F, "within normal operating range" badge (0–35°C, Apple's documented spec)
- **Power & Electrical**: live voltage, current (mA), computed wattage, connected adapter wattage, and an animated flow diagram between adapter/battery/Mac. **Honesty note**: the diagram only shows what's actually measurable — live battery charge/discharge power (real, computed from V×I) and the adapter's rated wattage (real, from `AdapterDetails`). It does **not** fabricate a "power to Mac vs power to battery" split while charging, because there's no public API giving true live total system power draw — showing that would mean making up a number.
- **Capacity Details**: remaining / full / design capacity in mAh, as a comparison bar
- **Devices**: Bluetooth/HID peripheral battery (AirPods, Beats, Magic Mouse/Keyboard/Trackpad, anything else exposing standard HID battery), still unverified against real hardware — no accessory has been paired on this Mac during testing
- **Apps Using Significant Energy**: ranked by CPU usage via `top`, normalized by core count. Explicitly labeled as a CPU-based estimate, not true Energy Impact — `powermetrics` would give the real number but refuses to run without root, and the private `IOReport` framework (which Activity Monitor/iStat Menus use to get this without root) wasn't implemented here — see roadmap.
- **Alert Thresholds**: add/remove, persisted, live-editable from the dashboard
- **Menu Bar Icon**: icon+%, %-only, icon-only, selectable from the dashboard
- Menu bar itself (native SwiftUI, not dashboard): live percentage, color-coded SF Symbols battery glyph, custom alert thresholds firing real notifications when crossed on battery power, lifecycle alerts (plugged in / unplugged / crossed 80% while charging)
- Health/capacity/temperature refresh every 2 minutes (matches Juicy's own cadence); percentage/power/electrical refresh every 2 seconds

**Not yet built** (harder, system-level pieces — tracked on the site's "On the roadmap" section too):
- Charge limiting / "healthy band" (Sailing Mode / Automatic Discharge) — requires a privileged helper (SMJobBless or similar) since writing SMC charge-control keys needs elevated permissions beyond the sandboxed app
- True per-app Energy Impact (not the current CPU-based proxy) — needs the private `IOReport` framework
- iPhone/iPad plug-in battery health — needs the private MobileDevice framework
- Predictive alerts (Calendar integration), smart charging schedule, long-term health trend export
- Native-style notification "pill" UI (currently uses stock macOS notification banners, not a custom overlay)
- Auto-dismissing macOS's own low-battery pop-up — no known public mechanism for this; may not be feasible without private/Accessibility-API hacks

**site v0.2** (working, verified in-browser): hero, problem statement, shipped-features grid, an honest "on the roadmap" section for what's not built yet, use-case scenarios, open-source/GitHub section, and a genuine FAQ. No fake testimonials — the original's testimonials section was deliberately dropped rather than fabricated.

## Feature reference

Full parity + enhancement list was worked out against the original product's homepage and `/#features` page; see conversation history for the complete breakdown.
