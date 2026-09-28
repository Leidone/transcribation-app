import Foundation
import Testing
@testable import CodexClient

struct CodexLockdownTests {
    @Test("command execution and browsing are switched off")
    func dangerousToolsAreDisabled() {
        #expect(CodexLockdown.disabledFeatures.contains("shell_tool"))
        #expect(CodexLockdown.disabledFeatures.contains("unified_exec"))
        #expect(CodexLockdown.disabledFeatures.contains("browser_use"))
        #expect(CodexLockdown.disabledFeatures.contains("computer_use"))
    }

    @Test("every feature becomes a --disable pair")
    func flagsArePairs() {
        let flags = CodexLockdown.flags

        #expect(flags.count == CodexLockdown.disabledFeatures.count * 2)
        for index in stride(from: 0, to: flags.count, by: 2) {
            #expect(flags[index] == "--disable")
        }
        #expect(Set(stride(from: 1, to: flags.count, by: 2).map { flags[$0] }) == Set(CodexLockdown.disabledFeatures))
    }

    @Test("the app-server starts with its subcommand followed by the flags")
    func appServerArguments() {
        let arguments = CodexLockdown.appServerArguments

        #expect(arguments.first == "app-server")
        #expect(Array(arguments.dropFirst()) == CodexLockdown.flags)
    }

    @Test("no feature is listed twice")
    func noDuplicates() {
        #expect(Set(CodexLockdown.disabledFeatures).count == CodexLockdown.disabledFeatures.count)
    }
}
