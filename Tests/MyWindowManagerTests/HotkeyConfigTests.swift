import Testing
import Carbon.HIToolbox
@testable import MyWindowManager

@Test func hyperkeyUsesSparkleSymbol() {
    let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    let hotkey = HotkeyConfig(keyCode: 0, modifiers: modifiers)

    #expect(hotkey.displayString == "✦A")
}

@Test func regularModifiersKeepExistingSymbols() {
    let modifiers = UInt32(controlKey | optionKey)
    let hotkey = HotkeyConfig(keyCode: 0, modifiers: modifiers)

    #expect(hotkey.displayString == "⌃⌥A")
}

@Test func hyperkeyWithAdditionalFlagKeepsExistingSymbols() {
    let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey | alphaLock)
    let hotkey = HotkeyConfig(keyCode: 0, modifiers: modifiers)

    #expect(hotkey.displayString == "⌃⌥⇧⌘A")
}
