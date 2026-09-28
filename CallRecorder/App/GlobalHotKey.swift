import AppKit
import Carbon.HIToolbox
import CallLibrary
import os

private let hotKeyLog = Logger(subsystem: "app.callrecorder.dev", category: "hotkey")

/// The person's key combination, from any app. Carbon's hot keys are the system mechanism that needs no
/// Accessibility permission: the app is told only about this one combination, it never sees other keystrokes.
@MainActor
final class GlobalHotKey {
    private let action: @MainActor () -> Void
    /// Tells this combination's presses apart from those of the app's other hot keys: every handler sees them all.
    private let id: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private static let signature = OSType(0x5452_4E53) // "TRNS"
    private static var lastID: UInt32 = 0

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        Self.lastID += 1
        id = Self.lastID
    }

    /// Grabs `shortcut` (releasing the one held before). Returns `false` when the system refuses it, usually because
    /// another app holds the same combination.
    @discardableResult
    func register(_ shortcut: KeyShortcut) -> Bool {
        unregister()
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &pressedID
            )
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            return MainActor.assumeIsolated { () -> OSStatus in
                // Another of the app's combinations: pass it on to the handler that owns it.
                guard pressedID.signature == GlobalHotKey.signature, pressedID.id == hotKey.id else {
                    return OSStatus(eventNotHandledErr)
                }
                hotKey.action()
                return noErr
            }
        }, 1, &pressed, context, &handler)
        guard installed == noErr else {
            hotKeyLog.error("cannot install the hot key handler: \(installed)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode, Self.carbonModifiers(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKey
        )
        guard status == noErr else {
            hotKeyLog.error("the hot key \(shortcut.display, privacy: .public) is taken or refused: \(status)")
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    private static func carbonModifiers(_ modifiers: Set<KeyShortcut.Modifier>) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}

extension KeyShortcut {
    /// The combination of a key press, or `nil` for anything that is not a key press.
    @MainActor
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<Modifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyName: Self.name(ofKey: event.keyCode))
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// What is printed on a key in a Latin layout, so a Russian layout still shows "R" rather than "К".
    private static func name(ofKey keyCode: UInt16) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "#\(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
