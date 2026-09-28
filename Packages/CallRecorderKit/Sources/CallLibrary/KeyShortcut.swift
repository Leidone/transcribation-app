import Foundation
import Localization

/// A key combination the person picked, stored by physical key code so it keeps working in any keyboard layout.
public struct KeyShortcut: Codable, Equatable, Hashable, Sendable {
    public enum Modifier: String, Codable, CaseIterable, Sendable {
        // Declared in the order macOS prints them: ⌃⌥⇧⌘.
        case control
        case option
        case shift
        case command

        public var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    /// The hardware key code (the same on every layout), e.g. 15 for the R key.
    public let keyCode: UInt32
    public let modifiers: Set<Modifier>
    /// What is printed on the key in a Latin layout: "R", "F5", "Space".
    public let keyName: String

    public init(keyCode: UInt32, modifiers: Set<Modifier>, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    /// ⌃⌥⌘R, the shortcut the app starts with.
    public static let defaultRecordToggle = KeyShortcut(keyCode: 15, modifiers: [.control, .option, .command], keyName: "R")

    /// ⌃⌥⌘M, the shortcut that marks an important moment of a call.
    public static let defaultMarkImportant = KeyShortcut(keyCode: 46, modifiers: [.control, .option, .command], keyName: "M")

    /// "⌥R", "⌃⇧F5".
    public var display: String {
        Modifier.allCases.filter(modifiers.contains).map(\.symbol).joined() + keyName
    }

    public var isFunctionKey: Bool {
        keyName.count >= 2 && keyName.count <= 3 && keyName.first == "F" && Int(keyName.dropFirst()) != nil
    }

    /// Why this combination would get in the way if it were grabbed system-wide, or `nil` when it is fine.
    public var problem: String? {
        let strong = modifiers.intersection([.control, .option, .command])
        if strong.isEmpty, !isFunctionKey {
            return tr(
                "Добавьте ⌃, ⌥ или ⌘: без них эта клавиша перестанет работать в других программах.",
                "Add ⌃, ⌥ or ⌘: without them this key would stop working in other apps."
            )
        }
        if strong == [.command], !isFunctionKey {
            return tr(
                "Сочетания ⌘ с одной клавишей (⌘C, ⌘V, ⌘Q…) заняты во всех программах. Добавьте ⌥ или ⌃, или возьмите ⌥ либо ⌃ вместо ⌘.",
                "⌘ with a single key (⌘C, ⌘V, ⌘Q…) is taken in every app. Add ⌥ or ⌃, or use ⌥ or ⌃ instead of ⌘."
            )
        }
        return nil
    }
}
