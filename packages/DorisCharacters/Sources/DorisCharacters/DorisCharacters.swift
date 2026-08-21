import Foundation

/// Access point for the character artwork bundle.
///
/// Callers used to reach these files through DorisUI's own `Bundle.module`.
/// They now live in a separate, macOS-only package (see Package.swift for
/// why), so the lookup goes through this instead — the on-disk layout under
/// the bundle is unchanged: `Characters/<id>/…` and `HeroAnim/<mood>/…`.
public enum DorisCharacters {
    public static var bundle: Bundle { .module }
}
