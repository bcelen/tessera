@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowHintsCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseSingleCommandSucc("window-hints show", WindowHintsCmdArgs(rawArgs: []).copy(\.action, .initialized(.show)))
        testParseSingleCommandSucc("window-hints hide", WindowHintsCmdArgs(rawArgs: []).copy(\.action, .initialized(.hide)))
        testParseSingleCommandSucc(
            "window-hints --visible show",
            WindowHintsCmdArgs(rawArgs: []).copy(\.action, .initialized(.show)).copy(\.visibleOnly, true),
        )
        assertEquals(parseCommand("window-hints").errorOrNil, "ERROR: Argument '(show|hide|pick)' is mandatory")
    }

    func testWindowIdIsMandatoryForPick() {
        assertEquals(
            parseCommand("window-hints pick").errorOrNil,
            "--window-id is mandatory for 'pick' and incompatible with the other arguments",
        )
        assertEquals(
            parseCommand("window-hints show --window-id 42").errorOrNil,
            "--window-id is mandatory for 'pick' and incompatible with the other arguments",
        )
        assertEquals(
            parseCommand("window-hints --visible hide").errorOrNil,
            "--visible is only compatible with 'show'",
        )
        testParseSingleCommandSucc(
            "window-hints --window-id 42 pick",
            WindowHintsCmdArgs(rawArgs: []).copy(\.action, .initialized(.pick)).copy(\.windowId, 42),
        )
    }

    /// Hints must be unique and start on the home row
    func testHintAlphabet() {
        let alphabet = "asdfghjklqwertyuiopzxcvbnm".map(String.init)
        assertEquals(alphabet.count, 26)
        assertEquals(Set(alphabet).count, 26)
        assertEquals(alphabet.first, "a")
        // Every hint must be bindable, otherwise the key silently does nothing
        assertTrue(alphabet.allSatisfy { keyNotationToKeyCode[$0] != nil })
        assertTrue(keyNotationToKeyCode["esc"] != nil)
    }
}
