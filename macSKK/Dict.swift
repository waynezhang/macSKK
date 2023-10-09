// SPDX-FileCopyrightText: 2022 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// 辞書を引くときに指定する特殊なエントリの種類を指定するオプション
enum DictReferringOption {
    /// 接頭辞を返す
    case prefix
    /// 接尾辞を返す
    case suffix
}

protocol DictProtocol {
    /**
     * 辞書を引き変換候補順に返す
     *
     * optionが設定されている場合は通常のエントリは検索しない
     *
     * - Parameters:
     *   - yomi: SKK辞書の見出し。複数のひらがな、もしくは複数のひらがな + ローマ字からなる文字列
     *   - option: 辞書を引くときに接頭辞や接尾辞から検索するかどうか。nilなら通常のエントリから検索する
     */
    func refer(_ yomi: String, option: DictReferringOption?) -> [Word]

    /**
     * 辞書にエントリを追加する。
     *
     * - Parameters:
     *   - yomi: SKK辞書の見出し。複数のひらがな、もしくは複数のひらがな + ローマ字からなる文字列
     *   - word: SKK辞書の変換候補。
     */
    mutating func add(yomi: String, word: Word)

    /**
     * 辞書からエントリを削除する。
     *
     * 辞書にないエントリ (ファイル辞書) の削除は無視されます。
     *
     * - Parameters:
     *   - yomi: SKK辞書の見出し。複数のひらがな、もしくは複数のひらがな + ローマ字からなる文字列
     *   - word: SKK辞書の変換候補。
     * - Returns: エントリを削除できたかどうか
     */
    mutating func delete(yomi: String, word: Word.Word) -> Bool

    /**
     * 現在入力中のprefixに続く入力候補を1つ返す。見つからなければnilを返す。
     *
     * 以下のように補完候補を探します。
     * ※将来この仕様は変更する可能性が大いにあります。
     *
     * - prefixが空文字列ならnilを返す
     * - ユーザー辞書の送りなしの読みのうち、最近変換したものから選択する。
     * - prefixと読みが完全に一致する場合は補完候補とはしない
     */
    func findCompletion(prefix: String) -> String?
}
