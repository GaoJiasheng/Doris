#if os(macOS)
import XCTest
@testable import DorisCore

/// Launch-time self-repair decides whether a hook needs rewriting by reading
/// back the CLI path it bakes in. These pin that reader to the writers, so a
/// change to how a hook is generated can't silently break detection.
final class HookCLIPathTests: XCTestCase {
    func testClaudeHookRoundTrips() {
        for path in ["/Users/me/.doris/bin/doris",
                     "/Applications/Doris.app/Contents/Resources/doris",
                     "/Users/me/My Apps/Doris.app/Contents/Resources/doris"] {
            let command = ClaudeCodeIntegration.hookCommand(cliPath: path)
            XCTAssertEqual(ClaudeCodeIntegration.cliPath(inHookCommand: command), path, command)
        }
    }

    func testClaudeFindsOnlyTheMarkedHook() {
        let ours = ClaudeCodeIntegration.hookCommand(cliPath: "/x/doris")
        let root: [String: Any] = ["hooks": ["Stop": [
            ["hooks": [["type": "command", "command": "say done"]]],
            ["hooks": [["type": "command", "command": ours]]],
        ]]]
        XCTAssertEqual(ClaudeCodeIntegration.dorisHookCommand(in: root), ours)
        XCTAssertNil(ClaudeCodeIntegration.dorisHookCommand(in: ["hooks": ["Stop": [
            ["hooks": [["type": "command", "command": "say done"]]]]]]))
    }

    /// Pre-1.8.3 dispatchers were scripts; launch repair has to read the
    /// path out of them to decide what to do. Excerpt of a real one.
    func testReadsLegacyCodexDispatcherScript() {
        let legacy = """
        #!/bin/bash
        # >>> doris-codex-notify-dispatch >>>
        DORIS_CLI="/Applications/Doris.app/Contents/Resources/doris"

        if [ -x "$DORIS_CLI" ]; then
            "$DORIS_CLI" notify \\
                --title 'Codex 任务完成' \\
                --source codex >/dev/null 2>&1 &
        fi
        exit 0
        """
        XCTAssertEqual(CodexIntegration.cliPath(inDispatcher: legacy),
                       "/Applications/Doris.app/Contents/Resources/doris")
        XCTAssertNil(CodexIntegration.cliPath(inDispatcher: "#!/bin/bash\nexit 0\n"))
    }

    func testStableLinkIsWhatNewHooksBake() {
        XCTAssertTrue(DorisCLILink.path.hasSuffix("/.doris/bin/doris"))
        XCTAssertFalse(DorisCLILink.path.contains("/Library/Containers/"),
                       "must be the real home, not the sandbox container")
    }
}
#endif
