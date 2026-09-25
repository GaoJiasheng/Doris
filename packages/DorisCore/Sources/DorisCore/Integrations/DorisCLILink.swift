#if os(macOS)

import Foundation
import DorisIPC

/// A fixed place for hooks to find the `doris` CLI: `~/.doris/bin/doris`,
/// a symlink the app re-points at its own bundled CLI on every launch.
///
/// Hooks used to bake the bundle path itself
/// (`/Applications/Doris.app/Contents/Resources/doris`). When the app went
/// missing from `/Applications`, every Claude Code and Codex notification
/// failed for seven weeks without a word: the Claude hook exited non-zero,
/// the Codex dispatcher skipped, and Settings still said "Registered". A
/// link the app owns follows the app wherever it's installed or run from.
///
/// A symlink rather than a copy: a copied binary written by the sandboxed
/// app would pick up the quarantine attribute, and exec'ing a quarantined
/// binary from a hook can be refused. The link's target is inside the
/// signed app bundle, which is not quarantined.
public enum DorisCLILink {
    public static var url: URL {
        integrationsRealHome()
            .appendingPathComponent(".doris/bin", isDirectory: true)
            .appendingPathComponent("doris")
    }

    public static var path: String { url.path }

    /// This process's bundled CLI, when there is one.
    public static var bundledCLI: URL? {
        let u = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/doris")
        return FileManager.default.isExecutableFile(atPath: u.path) ? u : nil
    }

    /// The link exists and resolves to an executable (`isExecutableFile`
    /// follows the symlink).
    public static var isHealthy: Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// Point the link at `target`. Returns whether the link is healthy
    /// afterwards; without a target it only reports the current state.
    @discardableResult
    public static func refresh(target: URL? = bundledCLI) -> Bool {
        guard let target else { return isHealthy }
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: path)) == target.path {
            return isHealthy
        }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            // Stale link (or anything else squatting on the name). Removing
            // a symlink removes the link, never its target.
            if (try? fm.attributesOfItem(atPath: path)) != nil
                || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil {
                try fm.removeItem(atPath: path)
            }
            try fm.createSymbolicLink(atPath: path, withDestinationPath: target.path)
        } catch {
            IntegrationSelfRepair.log("could not link \(path) → \(target.path): \(error)")
            return false
        }
        return isHealthy
    }
}

/// An integration that bakes an absolute CLI path into someone else's
/// config (a hook command, a dispatcher script).
protocol CLIPathBakingIntegration: IntegrationProvider {
    /// The CLI path the installed hook actually calls, or nil when the
    /// hook isn't installed.
    func bakedCLIPath() -> String?

    /// Whether the installed hook should be rewritten. Default: it calls
    /// anything other than the stable link.
    func hookNeedsRepair() -> Bool
}

extension CLIPathBakingIntegration {
    func hookNeedsRepair() -> Bool {
        guard let baked = bakedCLIPath() else { return false }
        return baked != DorisCLILink.path
    }
}

/// Launch-time check that keeps registered hooks pointed at a CLI that
/// exists.
///
/// Only touches integrations that are already registered — a user who
/// never turned one on won't find it switched on. Re-registering is the
/// providers' own idempotent upsert, so this is the same write the
/// Settings "Register" button performs.
public enum IntegrationSelfRepair {
    /// Refresh the stable CLI link, then rewrite every registered hook
    /// that `hookNeedsRepair()`. Returns the ids of the integrations that
    /// were rewritten.
    @discardableResult
    public static func run(providers: [any IntegrationProvider] = dorisDefaultIntegrationProviders) async -> [String] {
        guard DorisCLILink.refresh() else {
            log("stable CLI link unavailable; leaving hooks as they are")
            return []
        }
        var repaired: [String] = []
        for case let provider as any CLIPathBakingIntegration in providers {
            guard provider.hookNeedsRepair() else { continue }
            let before = provider.bakedCLIPath() ?? "?"
            do {
                try await provider.register()
                repaired.append(provider.id)
                log("\(provider.id): hook called \(before), now \(DorisCLILink.path)")
            } catch {
                log("\(provider.id): could not rewrite hook (calls \(before)): \(error)")
            }
        }
        return repaired
    }

    static func log(_ message: String) {
        DorisLog.app.info("integration self-repair: \(message, privacy: .public)")
    }
}

#endif // os(macOS)
