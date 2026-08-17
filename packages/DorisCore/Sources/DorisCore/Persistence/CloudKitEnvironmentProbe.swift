import Foundation
import DorisIPC
#if os(macOS)
import Security
#endif

/// Which CloudKit database the running binary actually talks to.
public enum CloudKitEnvironment: String, Sendable {
    case production
    case development
    /// Entitlements weren't readable (simulator, unsigned build). We say so
    /// rather than guessing — a wrong "Production" here is worse than "?".
    case unknown

    public var displayName: String {
        switch self {
        case .production:  return "Production"
        case .development: return "Development"
        case .unknown:     return "?"
        }
    }
}

/// Reports the CloudKit container + environment of the **running** binary by
/// reading its signed entitlements.
///
/// Why read the signature instead of a compile-time flag: the environment is
/// decided at *signing* time, not build time. A Debug build signed one way
/// reaches Production; signed another way it silently reaches Development,
/// where mirroring still reports success and `ZNEEDSUPLOAD` still drains to
/// 0 — the records simply land in a database no other device reads. One Mac
/// diverged for three months that way. Surfacing this in Settings is the
/// cheapest possible guard against a repeat.
///
/// Precedence matches CloudKit's own: an explicit
/// `com.apple.developer.icloud-container-environment` wins; otherwise the
/// environment follows `aps-environment`.
public enum CloudKitEnvironmentProbe {

    public static var containerIdentifier: String {
        DorisIdentifiers.cloudKitContainer
    }

    public static var current: CloudKitEnvironment { probe() }

    /// "iCloud.com.gavin.doris · Production" — one line for Settings.
    public static var summary: String {
        "\(containerIdentifier) · \(current.displayName)"
    }

    // MARK: - Platform probes

    private static func probe() -> CloudKitEnvironment {
        guard let ents = entitlements() else { return .unknown }
        // Explicit pin wins. Apple spells the values capitalised here.
        if let explicit = ents["com.apple.developer.icloud-container-environment"] as? String {
            switch explicit.lowercased() {
            case "production":  return .production
            case "development": return .development
            default:            return .unknown
            }
        }
        // Fall back to the push environment, which is what CloudKit uses when
        // the explicit key is absent. macOS and iOS spell the key differently.
        let aps = (ents["com.apple.developer.aps-environment"] as? String)
            ?? (ents["aps-environment"] as? String)
        switch aps?.lowercased() {
        case "production":  return .production
        case "development": return .development
        default:            return .unknown
        }
    }

    #if os(macOS)
    /// Read the entitlements the running bundle was actually signed with.
    /// Same approach as `CodeSigningCheck` — inspect the on-disk bundle
    /// rather than trusting the checked-in .entitlements file, which Xcode
    /// rewrites during automatic signing.
    private static func entitlements() -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
    }
    #else
    /// iOS has no SecCode API for self-inspection. The embedded provisioning
    /// profile carries the same `aps-environment` the signature was granted;
    /// it's a CMS blob, but the payload plist sits in it as plain XML, so we
    /// slice it out rather than pulling in a CMS decoder. Absent on the
    /// simulator — hence `.unknown` instead of a guess.
    private static func entitlements() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data[start.lowerBound..<end.upperBound]
        guard let profile = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil) as? [String: Any]
        else { return nil }
        return profile["Entitlements"] as? [String: Any]
    }
    #endif
}
