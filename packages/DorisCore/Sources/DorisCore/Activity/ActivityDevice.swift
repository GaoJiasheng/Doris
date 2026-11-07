#if os(macOS)
import Foundation
import CryptoKit
import IOKit
import SystemConfiguration
import DorisIPC

/// The machine identity behind `ActivityDay.deviceKey`.
///
/// Not `DeviceIdentity.current()`: that UUID lives in the App Group's
/// defaults, which Migration Assistant copies to a new Mac — two Macs
/// would then report token snapshots under one key, and the max-merge
/// would hide one of them. The hardware UUID never moves between machines
/// and survives reinstalls, so a reinstalled Mac keeps its key (its token
/// snapshots still merge by max, as they should). Hashed so the raw
/// hardware identifier never leaves the Mac.
public enum ActivityDevice {
    public static let key: String = {
        let raw = platformUUID() ?? DeviceIdentity.current().uuidString
        let digest = SHA256.hash(data: Data(("doris-activity|" + raw).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }()

    /// The Mac's computer name ("Gavin's MacBook Pro"), shown in per-Mac breakdowns.
    public static let name: String = {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? DeviceIdentity.currentName()
    }()

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String
    }
}
#endif
