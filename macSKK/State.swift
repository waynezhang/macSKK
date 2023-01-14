// SPDX-FileCopyrightText: 2022 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum InputMethodState: Equatable {
    /**
     * 直接入力 or 確定入力済で、下線がない状態
     *
     * 単語登録中は "[登録：りんご]apple" のようになり、全体に下線がついている状態であってもnormalになる
     */
    case normal

    /**
     * 未確定入力中の下線が当たっている部分
     *
     * 送り仮名があるときはあら + った + あらt みたいなようにもっておくと良さそう (辞書には "あらt" => "洗" が登録されている
     * カタカナでも変換できるほうがよい
     * ということはMojiの配列で持っておいたほうがよさそうな気がする
     *
     * 例えば "(Shift)ara(Shift)tta" と入力した場合、次のように遷移します
     * (isShift, text, okuri, romaji)
     *
     * 1. (true, "あ", nil, "")
     * 2. (true, "あ", nil, "r")
     * 3. (true, "あら", nil, "")
     * 4. (true, "あら", "", "t") (Shift押して送り仮名モード)
     * 5. (true, "あら", "っ", "t")
     * 6. (true, "あら", "った", "") (ローマ字がなくなった瞬間に変換されて変換 or 辞書登録に遷移する)
     *
     * abbrevモードの例 "/apple" と入力した場合、次のように遷移します
     *
     * 1. (true, "", nil, "")
     * 2. (true, "apple", nil, "")
     *
     **/
    case composing(ComposingState)
    /**
     * 変換候補選択中の状態
     */
    case selecting(SelectingState)
}

protocol CursorProtocol {
    func moveCursorLeft() -> Self
    func moveCursorRight() -> Self
}

/// 入力中の未確定文字列の定義
struct ComposingState: Equatable, CursorProtocol {
    /// (Sticky)Shiftによる未確定入力中かどうか。先頭に▽ついてる状態。
    var isShift: Bool
    /// かな/カナならかなになっている文字列、abbrevなら入力した文字列. (Sticky)Shiftが押されたらそのあとは更新されない
    var text: [Romaji.Moji]
    /// (Sticky)Shiftが押されたあとに入力されてかなになっている文字列。送り仮名モードになってなければnil
    var okuri: [Romaji.Moji]?
    /// ローマ字モードで未確定部分。"k" や "ky" など最低あと1文字でかなに変換できる文字列。
    var romaji: String
    /// カーソル位置。末尾のときはnil。先頭の▽分は含まないので非nilのときは[0, text.count)の範囲を取る。
    var cursor: Int?

    func string(for mode: InputMode) -> String {
        let newText: [Romaji.Moji] = romaji == "n" ? text + [Romaji.n] : text
        return newText.map { $0.string(for: mode) }.joined()
    }

    /// text部に文字を追加する
    func appendText(_ moji: Romaji.Moji) -> ComposingState {
        let newText: [Romaji.Moji]
        let newCursor: Int?
        if let cursor {
            newText = text[0..<cursor] + [moji] + text[cursor...]
            newCursor = cursor + 1
        } else {
            newText = text + [moji]
            newCursor = nil
        }
        return ComposingState(isShift: isShift, text: newText, okuri: okuri, romaji: romaji, cursor: newCursor)
    }

    /// 入力中の文字列をカーソル位置から一文字削除する。0文字で削除できないときはnilを返す
    func dropLast() -> Self? {
        if !romaji.isEmpty {
            return ComposingState(
                isShift: isShift, text: text, okuri: okuri, romaji: String(romaji.dropLast()), cursor: cursor)
        } else if let okuri {
            return ComposingState(
                isShift: isShift, text: text, okuri: okuri.isEmpty ? nil : okuri.dropLast(), romaji: romaji,
                cursor: cursor)
        } else if text.isEmpty {
            return nil
        } else if let cursor = cursor, cursor > 0 {
            var newText = text
            newText.remove(at: cursor - 1)
            return ComposingState(isShift: isShift, text: newText, okuri: okuri, romaji: romaji, cursor: cursor - 1)
        } else {
            return ComposingState(isShift: isShift, text: text.dropLast(), okuri: okuri, romaji: romaji, cursor: cursor)
        }
    }

    func resetRomaji() -> Self {
        return ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: "", cursor: cursor)
    }

    /// カーソルより左のtext部分を返す。
    func subText() -> [Romaji.Moji] {
        if let cursor {
            return Array(text[0..<cursor])
        } else {
            return text
        }
    }

    // MARK: - CursorProtocol
    func moveCursorLeft() -> Self {
        let newCursor: Int
        // 入力済みの非送り仮名部分のみカーソル移動可能
        if text.isEmpty {
            return self
        } else if isShift {
            if let cursor {
                newCursor = max(cursor - 1, 0)
            } else {
                newCursor = max(text.count - 1, 0)
            }
            return ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: romaji, cursor: newCursor)
        } else {
            return self
        }
    }

    func moveCursorRight() -> Self {
        // 入力済みの非送り仮名部分のみカーソル移動可能
        if text.isEmpty {
            return self
        } else if let cursor, isShift {
            if cursor + 1 == text.count {
                return ComposingState(isShift: isShift, text: text, okuri: okuri, romaji: romaji, cursor: nil)
            } else {
                return ComposingState(
                    isShift: isShift, text: text, okuri: okuri, romaji: romaji, cursor: min(cursor + 1, text.count))
            }
        } else {
            return self
        }
    }
}

/// 変換候補選択状態
struct SelectingState: Equatable {
    struct PrevState: Equatable {
        let mode: InputMode
        let composing: ComposingState
    }
    /// 候補選択状態に遷移する前の状態。
    let prev: PrevState
    /// 辞書登録する際の読み。ひらがなのみ、もしくは `ひらがな + アルファベット` もしくは `":" + アルファベット` (abbrev) のパターンがある
    let yomi: String
    /// 変換候補
    let candidates: [Word]
    var candidateIndex: Int = 0
    /// カーソル位置。この位置を基に変換候補パネルを表示する
    let cursorPosition: NSRect

    func addCandidateIndex(diff: Int) -> SelectingState {
        return SelectingState(
            prev: prev, yomi: yomi, candidates: candidates, candidateIndex: candidateIndex + diff,
            cursorPosition: cursorPosition)
    }

    /// 現在選択中の文字列を返す
    func fixedText() -> String {
        let text = candidates[candidateIndex].word
        let okuri = prev.composing.okuri?.map { $0.string(for: prev.mode) }
        if let okuri {
            return text + okuri.joined()
        } else {
            return text
        }
    }
}

/// 辞書登録状態
struct RegisterState: CursorProtocol {
    /// 辞書登録状態に遷移する前の状態。
    let prev: (InputMode, ComposingState)
    /// 辞書登録する際の読み。ひらがなのみ、もしくは `ひらがな + アルファベット` もしくは `":" + アルファベット` (abbrev) のパターンがある
    let yomi: String
    /// 入力中の登録単語。変換中のように未確定の文字列は含まず確定済文字列のみが入る
    var text: String = ""
    /// カーソル位置。nilのときは末尾扱い (composing中の場合を含む) 0のときは "[登録：\(text)]" の直後
    var cursor: Int?

    /// カーソル位置に文字列を追加する。
    func appendText(_ text: String) -> RegisterState {
        if let cursor {
            var newText: String = self.text
            newText.insert(contentsOf: text, at: newText.index(newText.startIndex, offsetBy: cursor))
            return RegisterState(prev: prev, yomi: yomi, text: newText, cursor: cursor + text.count)
        } else {
            return RegisterState(prev: prev, yomi: yomi, text: self.text + text, cursor: cursor)
        }
    }

    /// 入力中の文字列をカーソル位置から一文字削除する。0文字のときは無視する
    func dropLast() -> Self {
        if text.isEmpty {
            return self
        }
        if let cursor = cursor, cursor > 0 {
            var newText: String = text
            newText.remove(at: text.index(text.startIndex, offsetBy: cursor - 1))
            return RegisterState(prev: prev, yomi: yomi, text: newText, cursor: cursor - 1)
        } else {
            return RegisterState(prev: prev, yomi: yomi, text: String(text.dropLast()), cursor: cursor)
        }
    }

    // MARK: - CursorProtocol
    func moveCursorLeft() -> Self {
        if text.isEmpty {
            return self
        }
        let newCursor: Int
        if let cursor {
            newCursor = max(cursor - 1, 0)
        } else {
            newCursor = max(text.count - 1, 0)
        }
        return RegisterState(prev: prev, yomi: yomi, text: text, cursor: newCursor)
    }

    func moveCursorRight() -> Self {
        if let cursor {
            return RegisterState(
                prev: prev, yomi: yomi, text: text, cursor: cursor + 1 == text.count ? nil : cursor + 1)
        } else {
            return self
        }
    }
}

struct MarkedText: Equatable {
    let text: String
    let cursor: Int?
}

struct Candidates: Equatable {
    let words: [Word]
    let selected: Word
    let cursorPosition: NSRect
}

struct IMEState {
    var inputMode: InputMode = .hiragana
    var inputMethod: InputMethodState = .normal
    var registerState: RegisterState?
    var candidates: [Word] = []

    /// "▽\(text)" や "▼(変換候補)" や "[登録：\(text)]" のような、下線が当たっていて表示されている文字列とカーソル位置を返す。
    /// カーソル位置は末尾の場合はnilを返す
    func displayText() -> MarkedText {
        var markedText = ""
        // 単語登録モードのカーソルより後の確定済文字列
        var registerTextSuffix = ""
        var cursor: Int? = nil
        if let registerState {
            let mode = registerState.prev.0
            let composing = registerState.prev.1
            var yomi = composing.text.map { $0.string(for: mode) }.joined()
            if let okuri = composing.okuri {
                yomi += "*" + okuri.map { $0.string(for: mode) }.joined()
            }
            markedText = "[登録：\(yomi)]"
            if let registerCursor = registerState.cursor {
                cursor = markedText.count + registerCursor
                markedText += registerState.text.prefix(registerCursor)
                if registerCursor == 0 {
                    registerTextSuffix = registerState.text
                } else {
                    registerTextSuffix += registerState.text.suffix(
                        from: registerState.text.index(registerState.text.startIndex, offsetBy: registerCursor))
                }
            } else {
                markedText += registerState.text
            }
        }
        switch inputMethod {
        case .normal:
            markedText += registerTextSuffix
        case .composing(let composing):
            let displayText = composing.text.map { $0.string(for: inputMode) }.joined()
            let composingText: String
            if let okuri = composing.okuri {
                composingText =
                    "▽" + displayText + "*" + okuri.map { $0.string(for: inputMode) }.joined() + composing.romaji
            } else if composing.isShift {
                composingText = "▽" + displayText + composing.romaji
            } else {
                composingText = composing.romaji
            }

            if let currentCursor = cursor {
                if let composingCursor = composing.cursor {
                    // 先頭の "▽" 分の1を足す
                    cursor = currentCursor + composingCursor + (composing.isShift ? 1 : 0)
                } else {
                    cursor = currentCursor + composingText.count
                }
            } else {
                if let composingCursor = composing.cursor {
                    cursor = markedText.count + composingCursor + (composing.isShift ? 1 : 0)
                } else {
                    cursor = nil
                }
            }
            markedText += composingText + registerTextSuffix
        case .selecting(let selecting):
            markedText += "▼" + selecting.candidates[selecting.candidateIndex].word
            if let okuri = selecting.prev.composing.okuri {
                markedText += okuri.map { $0.string(for: inputMode) }.joined()
            }
            cursor = nil
        }
        return MarkedText(text: markedText, cursor: cursor)
    }
}

// 入力モード (値はTISInputSourceID)
enum InputMode: String {
    case hiragana = "net.mtgto.inputmethod.macSKK.hiragana"
    case katakana = "net.mtgto.inputmethod.macSKK.katakana"
    case hankaku = "net.mtgto.inputmethod.macSKK.hankaku"  // 半角カタカナ
    case eisu = "net.mtgto.inputmethod.macSKK.eisu"  // 全角英数
    case direct = "net.mtgto.inputmethod.macSKK.ascii"  // 直接入力
}
