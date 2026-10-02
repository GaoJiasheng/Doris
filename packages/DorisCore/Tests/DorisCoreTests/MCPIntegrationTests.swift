#if os(macOS)
import XCTest
@testable import DorisCore

/// Config surgery only — pure functions and temp files. Nothing here touches
/// the real ~/.claude.json or ~/.codex.
final class MCPIntegrationTests: XCTestCase {
    private let block = [CodexMCPIntegration.tableHeader, #"command = "/Users/me/.doris/bin/doris""#, #"args = ["mcp"]"#]

    func testCodexTableIsAddedReplacedAndRemovedCleanly() {
        let original = """
        model = "gpt-5.5"

        [mcp_servers.other]
        command = "x"
        """
        let added = CodexMCPIntegration.upserting(block, in: original)
        XCTAssertEqual(CodexMCPIntegration.command(in: added), "/Users/me/.doris/bin/doris")
        XCTAssertTrue(added.hasPrefix(original), "everything else is left as it was")

        // Re-registering replaces in place, sub-tables included.
        let withEnv = added + "\n[mcp_servers.doris.env]\nFOO = \"1\"\n\n[profiles.x]\nmodel = \"y\"\n"
        let replaced = CodexMCPIntegration.upserting([CodexMCPIntegration.tableHeader, #"command = "/new""#, #"args = ["mcp"]"#], in: withEnv)
        XCTAssertEqual(CodexMCPIntegration.command(in: replaced), "/new")
        XCTAssertFalse(replaced.contains("[mcp_servers.doris.env]"))
        XCTAssertEqual(replaced.components(separatedBy: CodexMCPIntegration.tableHeader).count, 2)
        XCTAssertTrue(replaced.contains("[profiles.x]"))

        let removed = CodexMCPIntegration.removing(from: replaced)
        XCTAssertNil(CodexMCPIntegration.command(in: removed))
        XCTAssertTrue(removed.contains("[mcp_servers.other]"))
        XCTAssertTrue(removed.contains("[profiles.x]"))
        XCTAssertFalse(removed.contains("\n\n\n"))
    }

    func testCodexTableInAnEmptyFile() {
        let text = CodexMCPIntegration.upserting(block, in: "")
        XCTAssertEqual(text, block.joined(separator: "\n") + "\n")
    }

    func testHintSectionKeepsTheUsersOwnText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("doris-hint-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("AGENTS.md")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mine = "# My rules\n\nBe brief.\n"
        try mine.write(to: url, atomically: true, encoding: .utf8)
        try AgentHintFile.install(at: url)
        try AgentHintFile.install(at: url)   // idempotent
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix(mine))
        XCTAssertEqual(text.components(separatedBy: AgentHintFile.begin).count, 2)

        try AgentHintFile.remove(at: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), mine)

        // A file that only ever held our section goes away entirely.
        let other = dir.appendingPathComponent("CLAUDE.md")
        try AgentHintFile.install(at: other)
        try AgentHintFile.remove(at: other)
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.path))
    }
}
#endif
