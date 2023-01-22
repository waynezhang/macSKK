// SPDX-FileCopyrightText: 2023 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

@testable import macSKK

final class StateTests: XCTestCase {
    func testComposingStateAppendText() throws {
        var state = ComposingState(
            isShift: true, text: [Romaji.table["a"]!, Romaji.table["i"]!], okuri: nil, romaji: "", cursor: nil)
        state = state.appendText(Romaji.table["u"]!)
        XCTAssertEqual(state.string(for: .hiragana), "あいう")
        state = state.moveCursorLeft()
        XCTAssertEqual(state.cursor, 2)
        state = state.appendText(Romaji.table["e"]!)
        XCTAssertEqual(state.string(for: .hiragana), "あいえう")
        XCTAssertEqual(state.cursor, 3)
        state = state.moveCursorRight()
        XCTAssertNil(state.cursor, "末尾まで移動したらカーソルはnilになる")
    }

    func testComposingStateDropLast() {
        let state = ComposingState(
            isShift: true, text: [Romaji.table["a"]!, Romaji.table["i"]!], okuri: nil, romaji: "", cursor: nil)
        XCTAssertEqual(state.dropLast()?.text, [Romaji.table["a"]!])
    }

    func testComposingStateDropLastEmpty() {
        let state = ComposingState(isShift: true, text: [], okuri: nil, romaji: "", cursor: nil)
        XCTAssertNil(state.dropLast())
    }

    func testComposingStateDropLastTextAndRomaji() {
        let state = ComposingState(isShift: true, text: [Romaji.table["a"]!], okuri: nil, romaji: "k", cursor: nil)
        let state2 = state.dropLast()
        XCTAssertEqual(state2?.romaji, "")
    }

    func testComposingStateDropLastTextAndOkuri() {
        let state = ComposingState(isShift: true, text: [Romaji.table["a"]!], okuri: [], romaji: "", cursor: nil)
        let state2 = state.dropLast()
        XCTAssertNil(state2?.okuri)
    }

    func testComposingStateDropLastCursor() {
        let state = ComposingState(
            isShift: true, text: [Romaji.table["a"]!, Romaji.table["i"]!], okuri: nil, romaji: "", cursor: 1)
        XCTAssertEqual(state.dropLast()?.text, [Romaji.table["i"]!])
    }

    func testComposingStateSubText() {
        var state = ComposingState(
            isShift: true, text: [Romaji.table["a"]!, Romaji.table["i"]!], okuri: nil, romaji: "", cursor: 1)
        XCTAssertEqual(state.subText(), [Romaji.table["a"]!])
        state.cursor = nil
        XCTAssertEqual(state.subText(), [Romaji.table["a"]!, Romaji.table["i"]!])
    }

    func testSelectingStateFixedText() throws {
        let selectingState = SelectingState(
            prev: SelectingState.PrevState(
                mode: .hiragana,
                composing: ComposingState(isShift: true, text: [Romaji.table["a"]!], romaji: "")),
            yomi: "あ",
            candidates: [Word("亜")],
            candidateIndex: 0,
            cursorPosition: .zero
        )
        XCTAssertEqual(selectingState.fixedText(), "亜")
    }

    func testSelectingStateFixedTextOkuriari() throws {
        let selectingState = SelectingState(
            prev: SelectingState.PrevState(
                mode: .hiragana,
                composing: ComposingState(
                    isShift: true,
                    text: [Romaji.table["a"]!],
                    okuri: [Romaji.table["ru"]!],
                    romaji: ""
                )
            ),
            yomi: "あ",
            candidates: [Word("有")],
            candidateIndex: 0,
            cursorPosition: .zero
        )
        XCTAssertEqual(selectingState.fixedText(), "有る")
    }

    func testRegisterStateAppendText() throws {
        var state = RegisterState(
            prev: (.hiragana, ComposingState(isShift: true, text: [Romaji.table["a"]!], okuri: nil, romaji: "")),
            yomi: "あ", text: "")
        state = state.appendText("あ")
        XCTAssertEqual(state.appendText("い").text, "あい")
        state = state.moveCursorLeft()
        XCTAssertEqual(state.cursor, 0)
        state = state.appendText("い")
        XCTAssertEqual(state.text, "いあ")
        XCTAssertEqual(state.cursor, 1)
    }

    func testRegisterStateDropLast() throws {
        var state = RegisterState(
            prev: (.hiragana, ComposingState(isShift: true, text: [Romaji.table["a"]!], okuri: nil, romaji: "")),
            yomi: "あ", text: "あいう", cursor: nil)
        state = state.dropLast()
        XCTAssertEqual(state.text, "あい")
        state = state.moveCursorLeft().dropLast()
        XCTAssertEqual(state.text, "い")
        XCTAssertEqual(state.cursor, 0)
    }

    func testUnregisterState() throws {
        let prevSelectingState = SelectingState(
            prev: SelectingState.PrevState(
                mode: .hiragana,
                composing: ComposingState(
                    isShift: true,
                    text: [Romaji.table["a"]!],
                    okuri: [Romaji.table["ru"]!],
                    romaji: ""
                )
            ),
            yomi: "あ",
            candidates: [Word("有")],
            candidateIndex: 0,
            cursorPosition: .zero
        )
        var state = UnregisterState(prev: (.hiragana, prevSelectingState), text: "")
        state = state.appendText("y")
        XCTAssertEqual(state.text, "y")
        state = state.appendText("e").moveCursorLeft().dropLast()
        XCTAssertEqual(state.text, "y")
    }
}
