import Foundation
import IOKit

/// Low-level access to the SMC (System Management Controller) — the same
/// undocumented mechanism smcFanControl/TG Pro/iStat Menus and the
/// open-source `exelban/stats` use for CPU/GPU temperature. There is no
/// public API for this; the struct layout below is ported directly from
/// `stats`' `SMC/smc.swift` (MIT licensed) to match the kernel driver's
/// expected memory layout exactly — a wrong layout here risks a hang/crash
/// on the IOKit call, not just wrong data, so this was not reconstructed
/// from memory.
final class SMCReader {
    private enum Selector: UInt8 {
        case kernelIndex = 2
        case readBytes = 5
        case readKeyInfo = 9
    }

    private enum DataType: String {
        case sp78 = "sp78"
        case flt = "flt "
        case fpe2 = "fpe2"
        case ui8 = "ui8 "
        case ui16 = "ui16"
        case ui32 = "ui32"
    }

    private struct KeyData {
        typealias Bytes32 = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )

        struct Vers {
            var major: CUnsignedChar = 0
            var minor: CUnsignedChar = 0
            var build: CUnsignedChar = 0
            var reserved: CUnsignedChar = 0
            var release: CUnsignedShort = 0
        }

        struct LimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }

        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    // Opened lazily and retried on every read rather than once at init, so a
    // transient failure to open isn't cached as permanent for the app's
    // whole lifetime. (In practice, the actual bug that caused persistent
    // nil temperature during development was a decode bug below, not the
    // connection — see the .flt case — but retrying the connection is cheap
    // and still worth keeping as a defensive measure.)
    private var connection: io_connect_t?

    deinit {
        if let connection {
            IOServiceClose(connection)
        }
    }

    private func openConnectionIfNeeded() -> io_connect_t? {
        if let connection { return connection }

        let service: io_object_t = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
        connection = conn
        return conn
    }

    /// Reads a 4-character SMC key (e.g. "Tp01") and returns its value in
    /// whatever unit that key represents — Celsius for the temperature keys
    /// this app uses. Returns nil if the key doesn't exist on this Mac, the
    /// SMC connection failed to open, or the reported value is implausible
    /// (some Apple Silicon generations are known to occasionally return
    /// garbage from certain sensor keys — same defensive bounds-check
    /// `stats` uses, "fix for m2 broken sensors").
    func readTemperature(key: String) -> Double? {
        guard let value = readRaw(key: key) else { return nil }
        guard value >= 10, value <= 120 else { return nil }
        return value
    }

    private func readRaw(key: String) -> Double? {
        guard let connection = openConnectionIfNeeded(), key.utf8.count == 4 else { return nil }

        var input = KeyData()
        input.key = fourCharCode(key)
        input.data8 = Selector.readKeyInfo.rawValue

        var output = KeyData()
        guard call(connection, &input, &output) == kIOReturnSuccess else { return nil }

        let dataSize = output.keyInfo.dataSize
        let dataType = fourCharString(output.keyInfo.dataType)

        input.keyInfo.dataSize = dataSize
        input.data8 = Selector.readBytes.rawValue
        guard call(connection, &input, &output) == kIOReturnSuccess else { return nil }

        return decode(type: dataType, bytes: output.bytes)
    }

    private func call(_ connection: io_connect_t, _ input: inout KeyData, _ output: inout KeyData) -> kern_return_t {
        let inputSize = MemoryLayout<KeyData>.stride
        var outputSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(connection, UInt32(Selector.kernelIndex.rawValue), &input, inputSize, &output, &outputSize)
    }

    private func decode(type: String, bytes: KeyData.Bytes32) -> Double? {
        switch DataType(rawValue: type) {
        case .sp78:
            // Signed fixed-point, 8 fractional bits. Two's-complement negative
            // values aren't handled here (matches the reference implementation)
            // — irrelevant for temperature sensors, which never read negative.
            let raw = Int(bytes.0) * 256 + Int(bytes.1)
            return Double(raw) / 256.0
        case .fpe2:
            let raw = Int(bytes.0) << 8 | Int(bytes.1)
            return Double(raw) / 4.0
        case .flt:
            // Native (little-endian) byte order, unlike the other cases —
            // confirmed by hand-decoding real captured bytes against a known
            // plausible temperature. Built via manual bit-shifting rather
            // than `UnsafeRawBufferPointer.load(as: UInt32.self)` on purpose:
            // that requires 4-byte alignment, which a [UInt8] array's buffer
            // isn't guaranteed to have — undefined behavior that manifested
            // as wildly inconsistent garbage (wrong sign/magnitude, different
            // every run) rather than a clean crash, which is what actually
            // happened here and cost real time to track down.
            let bits = UInt32(bytes.0) | UInt32(bytes.1) << 8 | UInt32(bytes.2) << 16 | UInt32(bytes.3) << 24
            return Double(Float(bitPattern: bits))
        case .ui8:
            return Double(bytes.0)
        case .ui16:
            return Double(Int(bytes.0) << 8 | Int(bytes.1))
        case .ui32:
            return Double(Int(bytes.0) << 24 | Int(bytes.1) << 16 | Int(bytes.2) << 8 | Int(bytes.3))
        case .none:
            return nil
        }
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharString(_ code: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(decoding: chars, as: UTF8.self)
    }
}
