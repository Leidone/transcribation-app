#if os(macOS)
import Foundation

/// Codex is an agent: by default it can run shell commands, browse the web and open apps. A call transcript holds
/// other people's words, so a participant could try to talk the agent into reading local files. Every tool is
/// switched off; the model can only work with the text it is given.
///
/// Verified with codex 0.155.1: with default settings the agent ran `cat` on a file and returned its contents,
/// with these flags it answered that it has no tools.
public enum CodexLockdown {
    public static let disabledFeatures = [
        "shell_tool", "unified_exec", "apps", "browser_use", "browser_use_external", "computer_use",
        "multi_agent", "multi_agent_v2", "skill_search", "image_generation", "sleep_tool", "tool_suggest", "hooks",
    ]

    /// `--disable <feature>` for every switched-off feature.
    public static var flags: [String] {
        disabledFeatures.flatMap { ["--disable", $0] }
    }

    public static var appServerArguments: [String] {
        ["app-server"] + flags
    }
}
#endif
