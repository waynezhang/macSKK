// SPDX-FileCopyrightText: 2022 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import InputMethodKit
import SwiftUI
import UserNotifications
import os

let logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "main")
var dictionary: UserDict!
let privateMode = CurrentValueSubject<Bool, Never>(false)
// 直接入力するアプリケーションのBundleIdentifierの集合のコピー。
// マスターはSettingsViewModelがもっているが、InputControllerからAppが参照できないのでグローバル変数にコピーしている。
// FIXME: NotificationCenter経由で設定画面で変更したことを各InputControllerに通知するようにしてこの変数は消すかも。
let directModeBundleIdentifiers = CurrentValueSubject<[String], Never>([])
// 直接入力モードを切り替えたいときに通知される通知の名前。
let notificationNameToggleDirectMode = Notification.Name("toggleDirectMode")
// 設定画面を開きたいときに通知される通知の名前
let notificationNameOpenSettings = Notification.Name("openSettings")

func isTest() -> Bool {
    return ProcessInfo.processInfo.environment["MACSKK_IS_TEST"] == "1"
}

@main
struct macSKKApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    /// ユニットテスト実行時はnil
    private let server: IMKServer?
    @ObservedObject var settingsViewModel: SettingsViewModel
    private let settingsWindowController: NSWindowController
    /// SKK辞書を配置するディレクトリ
    /// "~/Library/Containers/net.mtgto.inputmethod.macSKK/Data/Documents/Dictionaries"
    private let dictionariesDirectoryUrl: URL
    private let userNotificationDelegate = UserNotificationDelegate()
    @State private var fetchReleaseTask: Task<Void, Error>?
    #if DEBUG
    private let candidatesPanel: CandidatesPanel = CandidatesPanel()
    private let inputModePanel = InputModePanel()
    #endif

    init() {
        do {
            dictionary = try UserDict(dicts: [], privateMode: privateMode)
            dictionariesDirectoryUrl = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ).appendingPathComponent("Dictionaries")
            let settingsViewModel = try SettingsViewModel(dictionariesDirectoryUrl: dictionariesDirectoryUrl)
            let settingsWindow = SettingsWindow(settingsViewModel: settingsViewModel)
            settingsWindowController = NSWindowController(window: settingsWindow)
            self.settingsViewModel = settingsViewModel
            settingsWindowController.windowFrameAutosaveName = "Settings"
        } catch {
            fatalError("辞書設定でエラーが発生しました: \(error)")
        }
        if !isTest() && Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Input Methods" {
            guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
            else {
                fatalError("InputMethodConnectionName is not set")
            }
            server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        } else {
            server = nil
        }
        setupUserDefaults()
        if !isTest() {
            do {
                try setupDictionaries()
            } catch {
                logger.error("辞書の読み込みに失敗しました")
            }
            setupNotification()
            setupReleaseFetcher()
            setupDirectMode()
            setupSettingsNotification()
        }
    }

    var body: some Scene {
        Settings {
            // macOS 14 Sonomaから入力メニュー (NSMenu) からSettingsを呼び出すやりかたが塞がれたので
            // 代わりにNSWindowControllerを使う方針に変更しました。
            // SwiftUIなmacOSアプリはSettingsを置いておかないと空のウィンドウアプリを作るのがMenuItemExtraくらいしかないので
            // 空のSettingsを置いています。
            if #available(macOS 14, *) {
                EmptyView()
            } else {
                SettingsView(settingsViewModel: settingsViewModel)
            }
        }
        .commands {
            CommandGroup(after: .appSettings) {
                // macOS 14のAPI変更で入力メニューからアプリの設定を開きづらくなったため独自でウィンドウ表示するように変更
                Button("Open Settings…") {
                    NotificationCenter.default.post(name: notificationNameOpenSettings, object: nil)
                }
                Button("Save User Directory") {
                    do {
                        try dictionary.save()
                    } catch {
                        print(error)
                    }
                }.keyboardShortcut("S")
                #if DEBUG
                Button("AnnotationsPanel") {
                    let word = ReferredWord(yomi: "いんらいん", word: "インライン", annotations: [Annotation(dictId: "", text: String(repeating: "これはインラインのテスト用注釈です", count: 5))])
                    candidatesPanel.setCandidates(.inline, selected: word)
                    candidatesPanel.setCursorPosition(NSRect(origin: NSPoint(x: 100, y: 640), size: CGSize(width: 0, height: 30)))
                    candidatesPanel.show()
                }
                Button("Hide AnnotataionsPanel") {
                    candidatesPanel.orderOut(nil)
                }
                Button("SystemAnnotation") {
                    candidatesPanel.viewModel.systemAnnotations = ["インライン": (String(repeating: "これはシステム辞書の注釈です。", count: 5))]
                }
                Button("Show CandidatesPanel") {
                    let words = [ReferredWord(yomi: "こんにちは", word: "こんにちは", annotations: [Annotation(dictId: "", text: "辞書の注釈")]),
                                 ReferredWord(yomi: "こんばんは", word: "こんばんは"),
                                 ReferredWord(yomi: "おはようございます", word: "おはようございます")]
                    candidatesPanel.setCandidates(.panel(words: words, currentPage: 0, totalPageCount: 1), selected: words.first)
                    candidatesPanel.setCursorPosition(NSRect(origin: NSPoint(x: 100, y: 20), size: CGSize(width: 0, height: 30)))
                    candidatesPanel.show()
                }
                Button("Add Word") {
                    let words = [ReferredWord(yomi: "こんにちは", word: "こんにちは", annotations: [Annotation(dictId: "", text: "辞書の注釈")]),
                                 ReferredWord(yomi: "こんばんは", word: "こんばんは"),
                                 ReferredWord(yomi: "おはようございます", word: "おはようございます"),
                                 ReferredWord(yomi: "ついかしたよ", word: "追加したよ", annotations: [Annotation(dictId: "", text: "辞書の注釈")])]
                    candidatesPanel.setCandidates(.panel(words: words, currentPage: 0, totalPageCount: 1), selected: words.last)
                    candidatesPanel.viewModel.systemAnnotations = [words.last!.word: String(repeating: "これはシステム辞書の注釈です。", count: 5)]
                }
                Button("InputMode Panel") {
                    inputModePanel.show(at: NSPoint(x: 200, y: 200), mode: .hiragana, privateMode: true)
                }
                Button("User Notification") {
                    let release = Release(version: ReleaseVersion(major: 0, minor: 4, patch: 0),
                                          updated: Date(),
                                          url: URL(string: "https://github.com/mtgto/macSKK/releases/tag/0.4.0")!)
                    sendPushNotificationForRelease(release)
                }
                #endif
            }
        }
    }

    private func setupUserDefaults() {
        UserDefaults.standard.register(defaults: [
            "dictionaries": [
                DictSetting(filename: "SKK-JISYO.L", enabled: true, encoding: .japaneseEUC).encode()
            ],
            "directModeBundleIdentifiers": [String](),
        ])
    }

    // Dictionariesフォルダのファイルのうち、UserDefaultsで有効になっているものだけ読み込む
    private func setupDictionaries() throws {
        let childFileUrls = try FileManager.default.contentsOfDirectory(at: dictionariesDirectoryUrl,
                                                                        includingPropertiesForKeys: [.isReadableKey],
                                                                        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        let validFilenames = try childFileUrls.compactMap { fileURL -> String? in
            let resourceValues = try fileURL.resourceValues(forKeys: [.isReadableKey])
            if let isReadable = resourceValues.isReadable, isReadable {
                return fileURL.lastPathComponent
            }
            return nil
        }
        let dictSettings = UserDefaults.standard.array(forKey: "dictionaries")?.compactMap { obj in
            if let setting = obj as? [String: Any], let dictSetting = DictSetting(setting) {
                if validFilenames.contains(dictSetting.filename) {
                    return dictSetting
                }
            }
            return nil
        }
        guard let dictSettings else {
            // 再起動してもおそらく同じ理由でこけるので、リセットしちゃう
            // TODO: Notification Center経由でユーザーにも破壊的処理が起きたことを通知してある
            logger.error("環境設定の辞書設定が壊れています")
            UserDefaults.standard.removeObject(forKey: "dictionaries")
            return
        }
        settingsViewModel.dictSettings = dictSettings
    }

    // UNNotificationの設定
    private func setupNotification() {
        let center = UNUserNotificationCenter.current()
        center.delegate = userNotificationDelegate
    }

    private func setupDirectMode() {
        if let bundleIdentifiers = UserDefaults.standard.array(forKey: "directModeBundleIdentifiers") as? [String] {
            directModeBundleIdentifiers.send(bundleIdentifiers)
        }
    }

    private func setupReleaseFetcher() {
        guard let shortVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let currentVersion = ReleaseVersion(string: shortVersionString) else {
            fatalError("現在のバージョンが不正な状態です")
        }
        fetchReleaseTask = Task.detached(priority: .low) {
            var sleepDuration: Duration = .seconds(12 * 60 * 60) // 12時間休み
            while true {
                try await Task.sleep(for: sleepDuration)
                logger.log("スケジュールされていた更新チェックを行います")
                do {
                    let release = try await settingsViewModel.fetchLatestRelease()
                    if release.version > currentVersion {
                        logger.log("新しいバージョン \(release.version, privacy: .public) が見つかりました")
                        sleepDuration = .seconds(7 * 24 * 60 * 60) // 1週間休み
                        await sendPushNotificationForRelease(release)
                    } else {
                        logger.log("更新チェックをしましたが新しいバージョンは見つかりませんでした")
                    }
                } catch is CancellationError {
                    logger.log("スケジュールされていた更新チェックがキャンセルされました")
                    break
                } catch {
                    // 通信エラーなどでここに来るかも? 次回は成功するかもしれないのでログだけ吐いて続行
                    logger.error("更新チェックに失敗しました: \(error)")
                }
            }
        }
    }

    private func sendPushNotificationForRelease(_ release: Release) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization { granted, error in
            if let error {
                logger.log("通知センターへの通知ができない状態です:\(error)")
                return
            }
            if !granted {
                logger.log("通知センターへの通知がユーザーに拒否されています")
                return
            }
            let request = release.userNotificationRequest()
            center.add(request) { error in
                if let error {
                    logger.error("通知センターへの通知に失敗しました: \(error)")
                }
            }
        }
    }

    private func setupSettingsNotification() {
        Task {
            for await notification in NotificationCenter.default.notifications(named: notificationNameOpenSettings) {
                settingsWindowController.showWindow(notification.object)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
