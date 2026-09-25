import XCTest
@testable import DorisUI

/// iOS and the app extensions can't read `pack.json` (it ships only in the
/// macOS-only character-art bundle), so the default pack's theme is also
/// compiled into DorisUI. This keeps the two copies from drifting apart.
final class DefaultPackThemeTests: XCTestCase {
    func testCompiledInThemeMatchesCatManifest() throws {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // DorisUITests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // DorisUI
            .deletingLastPathComponent()          // packages
            .appendingPathComponent("DorisCharacters/Sources/DorisCharacters/Characters")
            .appendingPathComponent(CharacterPack.defaultPackID)
            .appendingPathComponent("pack.json")
        let pack = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any]
        let fromManifest = try XCTUnwrap(pack?["theme"] as? NSDictionary)
        let compiledIn = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(CharacterTheme.defaultPackThemeJSON.utf8)) as? NSDictionary)
        XCTAssertEqual(compiledIn, fromManifest,
                       "CharacterTheme.defaultPackThemeJSON must mirror the theme in \(manifest.path)")
    }
}
