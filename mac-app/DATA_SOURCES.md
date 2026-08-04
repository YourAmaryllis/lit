# Where lit's data comes from

Every number shown in lit traces back to one of four mechanisms. This doc
catalogs each metric, the exact API/key used, whether that API is **public**
(documented, stable, in an Apple header) or **private** (undocumented,
reverse-engineered by observing `ioreg` output, could change on any macOS
update), and how it was verified.

Nothing here is fabricated or guessed at runtime — anything we can't
measure is either omitted or explicitly labeled as an estimate in the UI
itself, not just in this doc.

## 1. Battery charge state — `IOKit/ps` (public, documented)

**Source file:** `BatteryMonitor.refreshPowerSource()`
**API:** `IOPSCopyPowerSourcesInfo()` / `IOPSCopyPowerSourcesList()` /
`IOPSGetPowerSourceDescription()` — Apple's public `IOPowerSources.h`
API, the same one System Settings' Battery pane and `pmset` use.

| Shown as | Dictionary key | Type |
|---|---|---|
| Battery % | `kIOPSCurrentCapacityKey` | public |
| Plugged in | `kIOPSPowerSourceStateKey == kIOPSACPowerValue` | public |
| Charging | `kIOPSIsChargingKey` | public |
| Time to empty | `kIOPSTimeToEmptyKey` | public |
| Time to full | `kIOPSTimeToFullChargeKey` | public |

Refreshed every 2 seconds. Verified against `pmset -g batt` output directly
throughout development (percentage, charging state, and time estimates all
matched).

## 2. Battery health & capacity — `AppleSmartBattery` IOKit service (private keys, public access mechanism)

**Source file:** `BatteryMonitor.refreshHealthSnapshot()`, `refreshElectrical()`
**API:** `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))`
then `IORegistryEntryCreateCFProperty(service, key, ...)` per key.

The *function calls* are public IOKit API. The *dictionary keys* below are
**not** documented by Apple anywhere — they were found by running
`ioreg -r -c AppleSmartBattery -l` and reading the raw output, the same way
every other battery-info tool (coconutBattery, iStat Menus, AirBuddy) does
it. They could change or disappear on a future macOS release.

| Shown as | Key | Notes |
|---|---|---|
| Cycle count | `CycleCount` | |
| Design capacity (mAh) | `DesignCapacity` | Factory spec, fixed. |
| Full/current-max capacity (mAh) | `AppleRawMaxCapacity` (fallback: `MaxCapacity`) | **Real bug fixed during development**: on Apple Silicon, top-level `MaxCapacity` is already a 0–100 *percentage*, not mAh comparable to `DesignCapacity`. Using it directly for health % gave a nonsense ~2% instead of the real ~96%. `AppleRawMaxCapacity` is the correct mAh-comparable field; older Intel Macs only expose `MaxCapacity` in mAh, hence the fallback. |
| Remaining capacity (mAh) | `AppleRawCurrentCapacity` | |
| Temperature | `Temperature` | Raw value is centi-Celsius (÷100 = °C). Fahrenheit is computed (`×9/5+32`), not a separate reading. |
| Voltage | `Voltage` | Raw value is millivolts (÷1000 = V). |
| Current | `InstantAmperage` (fallback: `Amperage`) | mA, signed (negative = discharging). |
| Adapter rated wattage | `AdapterDetails["Watts"]` | This is the **negotiated USB-PD contract ceiling**, not a live power-draw reading — confirmed by polling it repeatedly and observing it doesn't change with system load, only when the physical adapter/cable changes. |
| Fully charged | `FullyCharged` | |

Health % = `AppleRawMaxCapacity / DesignCapacity × 100`. Condition badge
(Good/Fair/Poor) is our own threshold, not an Apple-defined one, chosen to
mirror Apple's own ≥80%-original-capacity guidance for AppleCare battery
service eligibility: ≥80 Good, 50–79 Fair, <50 Poor.

"Within normal range" temperature badge uses 0–35°C, Apple's documented
operating-temperature spec for these devices (not derived from any runtime
API — it's a constant from Apple's own published spec).

**Refresh cadence:** health/capacity/temperature refresh every 2 minutes
(matches Juicy's own observed cadence, and avoids UI jitter for values that
don't change fast anyway); voltage/current/adapter refresh every 2 seconds.

**Verified:** cross-checked every field against `ioreg -r -c AppleSmartBattery -l`
and `system_profiler SPPowerDataType` directly, multiple times, including
while actively charging and while idle at 100%.

**Known driver limitation (not a bug):** the `AppleSmartBattery` kernel
driver itself only updates these registry values on its own internal
cadence — empirically confirmed to be slower than 2 seconds (polling faster,
via raw `ioreg` in a tight loop, returns identical cached values). Polling
lit more frequently would not produce fresher numbers.

## 3. Estimated Mac power draw while charging — derived, not measured

**Source file:** `BatteryMonitor.estimatedSystemWattageWhileCharging`

```
estimate = adapterWattage − batteryWattage   (batteryWattage = Voltage × InstantAmperage)
```

There is no public (or found private) API for true live total system power
draw on Apple Silicon. This estimate is only accurate when the Mac is
pulling the adapter's full rated capacity — true for small/low-wattage
adapters under load, **false** for a high-wattage adapter at light load
(it will overstate Mac draw by the unused headroom). It's labeled
"estimated" everywhere it's shown, not presented as an independent
measurement. Verified against a real 15W adapter while charging, giving
results matching Juicy's own displayed split closely.

We deliberately did **not** fabricate this number for the non-charging
states (idle/full, or discharging) — those already have a real, directly
measured single number (battery V×I), so no estimate is needed there.

## 4. Bluetooth/HID peripheral battery — `AppleDeviceManagementHIDEventService` (private)

**Source file:** `PeripheralsMonitor.scanHIDBatteryDevices()`
**API:** `IOServiceMatching("AppleDeviceManagementHIDEventService")` +
`IOServiceGetMatchingServices` to enumerate, then per-entry
`IORegistryEntryCreateCFProperty` for `BatteryPercent`, `Product`,
`Built-In`, `SerialNumber`.

This is the same IOKit service macOS itself uses to drive the Bluetooth
menu's battery icons for AirPods, Beats, and Magic Mouse/Keyboard/Trackpad
— no `IOBluetooth` pairing/authorization dance required. Entries with
`Built-In == true` (the internal keyboard/trackpad) are excluded.

**Status:** code is correct by inspection and matches the known pattern
other open-source tools use, but is **unverified against real hardware** —
no Bluetooth accessory has been connected on the development machine while
testing this.

## 5. iPhone/iPad battery — `libimobiledevice` (external LGPL-2.1 tool, invoked as a subprocess)

**Source file:** `PeripheralsMonitor.scanIDevices()`
**Tool:** [`libimobiledevice`](https://libimobiledevice.org) — `idevice_id`
(list attached device UDIDs) and `ideviceinfo -u <udid> -q com.apple.mobile.battery`
(query `BatteryCurrentCapacity`/`BatteryIsCharging`, plus `-k DeviceName` and
`-k DeviceClass` for the display name and iPad/iPhone icon), invoked as
external subprocesses via `Process()`. Not installed/bundled by default —
requires `brew install libimobiledevice`; if the binaries aren't found,
this silently contributes nothing to the device list (no error, no crash).
Cycle count / health % is **not** exposed for connected iOS devices via this
mechanism (confirmed — not present in the full key dump) — only percentage
and charging state are real, available data here.

**Researched before implementing:** there is **no reliable Bluetooth-only
API** for this. The real mechanism is USB-pair-once, then Wi-Fi sync over
the same private `lockdownd`/MobileDevice protocol used for cable
connections (`idevice_id -n` lists network-reachable UDIDs once a device
has been USB-trusted at least once). A pure-Bluetooth fallback exists in
principle (public `CoreBluetooth`, reading the standard GATT Battery
Service 0x180F / characteristic 0x2A19), but is unreliable and limited to
cellular-capable iPhone/iPad.

**Why a subprocess:** `libimobiledevice` is **LGPL-2.1**, which is fine to
invoke as an external subprocess without any license obligation on this
MIT-licensed codebase — the same pattern as an app invoking `ffmpeg`. This
was written from scratch against `libimobiledevice`'s own CLI (`--help`
output) and the `ideviceinfo`/`libplist` source on GitHub for the exact
`Key: Value` output format.

**Status: verified against real hardware.** Tested end-to-end with a real
iPad connected via USB: `idevice_id -l` initially showed nothing even
though the cable was plugged in — turned out to be Apple's **USB Restricted
Mode** (no data access until the device is unlocked with a passcode/Face ID
within the last hour; simply waking the screen doesn't count). After
unlocking and replugging, `idevice_id -l` returned a real UDID, and
`ideviceinfo -u <udid> -q com.apple.mobile.battery` returned real data
(`BatteryCurrentCapacity: 90`, `BatteryIsCharging: true`, plus
`ExternalChargeCapable`/`ExternalConnected`/`FullyCharged`/`HasBattery`).
Confirmed the app itself picked it up correctly on its next 30s refresh —
`{"name":"Elia's iPad","batteryPercent":94,"symbolOverride":"ipad","isCharging":true}`
via the dashboard API, matching the raw tool output, with the percentage
independently increasing across two checks (94% vs. an earlier 90%/91%),
confirming it's genuinely live and not a cached/stale read. Rendered
correctly in the web dashboard too (📱 icon + name + charging bolt + bar).
The "no device"/"tool not installed" paths were already verified separately
and remain correct.

If this stops working for you specifically: the most common cause by far is
**USB Restricted Mode** — fully unlock the device (not just wake it) and
replug the cable. Second most common: a charge-only cable with no data
lines.

## 6. Apps Using Significant Energy — `proc_pid_rusage` (public API, undocumented semantics)

**Source file:** `EnergyMonitor.energyNanojoules(forPid:)`
**API:** `proc_pid_rusage(pid, RUSAGE_INFO_V6, &buf)`, reading
`ri_energy_nj` off the returned `rusage_info_v6` struct.

This is genuinely public API — declared in `<libproc.h>`, part of the SDK,
callable from plain Swift with `import Darwin` and no bridging header, no
`dlopen`/private framework, no root needed for processes owned by the
current user (root only required to read *other users'* processes).

`ri_energy_nj` is a cumulative nanojoule counter the kernel bills to each
process — the same underlying number Activity Monitor's Energy tab and
`powermetrics --samplers tasks` are built on. Since it's cumulative, usage
is computed as a **power reading** (watts) from the delta between two
samples 8 seconds apart, then displayed as each app's % share of the total
across every running app — which is why the shown top-N legitimately sums
to less than 100% when more apps are running than shown.

Only processes present in `NSWorkspace.shared.runningApplications` are
included, so daemons/CLI tools (`kernel_task`, `node`, `python3.11`, etc.)
never show up — only real, launched applications. Filtered to ≥10% for
display (smaller entries are still counted in the total, just not listed).

**Why not `IOReport`** (the private framework other tools use for
system-wide power)? Researched before implementing: `IOReport`'s power
channels are hardware/subsystem-scoped (`CPU Energy`, `GPU Energy`, `ANE`,
`DRAM`) with **no per-process attribution at all** — it cannot answer
"app X used Y joules." `proc_pid_rusage` was the right tool for this,
`IOReport` would have been the wrong one.

**Verified:** confirmed real, varying, non-zero deltas across 100+ running
apps after fixing an initial bug (see below); compared against `top`/`ps`
output for plausibility.

## 7. System Temperature (CPU/GPU) — SMC (private, undocumented) + `ProcessInfo.thermalState` (public)

**Source files:** `SMCReader.swift`, `SystemTemperatureMonitor.swift`

**Mechanism:** the same undocumented SMC (System Management Controller)
technique smcFanControl/TG Pro/iStat Menus and the open-source
`exelban/stats` (MIT) use — `IOServiceOpen("AppleSMC")`, then
`IOConnectCallStructMethod` with an undocumented `SMCKeyData_t`-equivalent
struct to read individual 4-character sensor keys. **Researched and ported
from real, current source before writing anything** — the struct layout,
selector values, and decode logic were pulled verbatim from `stats`'
`SMC/smc.swift`, not reconstructed from memory, since a wrong memory layout
here risks a hang/crash on the raw IOKit call, not just wrong data.

**Apple Silicon key list is model-specific and only verified for this
machine** (MacBook Air, Mac16,12, base M4):

```
CPU efficiency cores: Te05, Te0S, Te09, Te0H
CPU performance cores: Tp01, Tp05, Tp09, Tp0D, Tp0V, Tp0Y, Tp0b, Tp0e
GPU: Tg0G, Tg0H
```

Sourced from `exelban/stats`' `Modules/Sensors/values.swift` (itself sourced
from `acidanthera/VirtualSMC`'s `SMCSensorKeys.txt`). Other chip generations
(M1/M2/M3, Pro/Max/Ultra variants, Intel) will simply get no CPU/GPU
temperature — `SMCReader` returns nil for keys that don't exist on that
hardware, never crashes or shows wrong data for it. `ProcessInfo.thermalState`
(public API, `.nominal`/`.fair`/`.serious`/`.critical`) is shown regardless
of chip generation as a zero-risk qualitative complement.

**Why not `IOReport` for this?** Researched first (see §6 below) — on
Apple Silicon, `IOReport`'s "Energy Model" channels give aggregate CPU/GPU
**power** (Watts), not temperature. SMC was the right tool for °C; IOReport
would have been the wrong one here too.

**A real, genuinely tricky bug was found and fixed here — worth documenting
in detail since it cost significant time and the symptoms were actively
misleading:**

Initial testing (standalone test harness, then direct binary execution)
produced real, plausible temperatures immediately. But once deployed as
the actual LaunchAgent-managed app, temperature was reliably `nil`. This
looked exactly like a connection/permissions problem — added logging,
confirmed the SMC connection opened successfully every time, no TCC/entitlement
denials anywhere in the system log. Eventually added per-key logging and
found the real cause: individual key reads were **succeeding** and
returning a "flt " (float) data type correctly, but decoding to
nonsensical values — denormalized near-zero garbage on some runs
(`~1e-43`), wildly random huge/negative numbers on others. That
run-to-run *inconsistency for identical code* was the tell: this wasn't a
logic bug (which would be wrong the same way every time), it was
**undefined behavior**. The `.flt` decode case used
`[bytes...].withUnsafeBytes { $0.load(as: UInt32.self) }` — `load(as:)`
requires the pointer be correctly aligned for the loaded type (4 bytes for
`UInt32`), and a `[UInt8]` array's backing buffer has no such guarantee.
Fixed by building the `UInt32` via manual bit-shifting instead (matching
the style already used for every other data-type case here), which has no
alignment requirement at all. Verified with 3 consecutive fresh
LaunchAgent-managed launches after the fix, all producing correct,
consistent, physically plausible readings (~43-49°C CPU, ~37-41°C GPU)
immediately.

**Lesson for anyone touching this file:** if temperature (or any SMC value)
ever looks wrong again, check whether the *dataType* logged for that key is
still `sp78`/`flt `/`fpe2`/etc. as expected before assuming the struct
layout or key codes are wrong — an alignment or decode bug produces
symptoms (nil, or wrong-looking numbers) that are easy to misattribute to
connection/permission/timing issues, exactly as happened here.

## 8. Alerts & notifications — `UserNotifications` (public)

**Source file:** `AlertsManager.swift`, `PeripheralsMonitor.notify()`
**API:** `UNUserNotificationCenter` — standard public framework. Requires
running from a real `.app` bundle (a bare `swift run` binary crashes here
with `bundleProxyForCurrentProcess is nil`).

Thresholds and lifecycle events (plugged in / unplugged / crossed 80% while
charging) are evaluated locally from the data above — no additional data
source, just state-transition logic over what `BatteryMonitor` already
tracks.

## 9. Menu bar icon — SF Symbols (public)

**Source file:** `BatteryIcon.swift`
Battery glyphs (`battery.0` … `battery.100`) are standard SF Symbols,
bucketed from the real percentage above. No separate data source.

---

## Corrections made during development (for the record)

- **Battery health**: was reading `MaxCapacity` (already-a-percentage on
  Apple Silicon) instead of `AppleRawMaxCapacity` (mAh) — computed ~2%
  health instead of the real ~96% until fixed. Caught by cross-checking
  against `ioreg` directly.
- **Apps Using Significant Energy**: originally implemented as a CPU-time
  proxy via `top -l 1`, which reports 0.0% for every process because `top`
  needs two samples to compute a delta — confirmed by comparing raw
  `top -l 1` vs `top -l 2` output side by side. Replaced entirely with the
  real per-process energy approach in §5 above.
- **Background timers stalling**: all three monitors used
  `Timer.scheduledTimer`, which only fires in the default run loop mode and
  silently pauses during event-tracking mode (dropdown open, mouse
  interaction). Fixed by scheduling in `.common` mode instead; verified by
  adding temporary debug logging and watching the real `.app` bundle's
  output.
