import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: BookStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var gs = GlobalSettings.shared
    /// 來源配置管理, 模組 and its pages, and 聚合設定 push `ExploreNavigationRoute` values. A page
    /// opened by `navigationDestination(isPresented:)` on a stack without a path is pushed again on
    /// top of a value pushed after it (模組 reappeared over 測試倉庫), so each is a value.
    @State private var path = NavigationPath()

    /// Opens one of 設定's sections (來源配置管理, 模組, 聚合設定) from this page.
    ///
    /// The path is emptied first, and that is the whole point. `path.append` on its own
    /// left whatever the last visit pushed sitting underneath: come back to 設定 by the tab
    /// bar instead of by 返回 (or tap a row twice while the push is still animating) and the
    /// next section landed on top of that stale page — 返回 then went to the page visited
    /// before, not to 設定, and a section opened twice needed two 返回s to leave. Starting
    /// from an empty path makes 設定 the parent of every section, every time.
    private func pushSection(_ route: ExploreNavigationRoute) {
        path = NavigationPath()
        path.append(route)
    }
    /// 模組's 新增模組 (its toolbar), presented from this root: the one place a module is added.
    @StateObject private var moduleFlow = RuleModuleAddFlow()
    @State private var showReplaceRules = false
    @State private var showTTSSettings = false
    @State private var showNetworkSettings = false
    @State private var showCacheManagement = false
    @State private var cardKeyInput = ""
    @State private var cardKeyAlert = false
    @ObservedObject private var cardKeyMembership = CardKeyMembership.shared
    @State private var cardKeyWrongKey = false
    @State private var showAISettings = false
    @State private var showAIPaywall = false
    #if DEBUG
    @State private var autoOpenDiagnostics = false
    #endif
    /// 卡密失败文案：区分「设备已被占用」和「卡密错误」
    private var cardKeyFailureText: String {
        switch cardKeyMembership.lastFailureReason {
        case "device_mismatch": return "此卡密已在其他裝置啟用"
        case "network": return "網路連線失敗，請稍後重試"
        default: return "卡密錯誤，請重新輸入"
        }
    }

    private let feedbackEmail = "2961361138@qq.com"
    /// 交流群 (maintainer, 2026-11-05). Tapping the row copies the number — a QQ group
    /// invitation URL needs the group to be joinable by link, and this one is searched
    /// by number instead.
    private let qqGroup = "649975499"

    private var feedbackMailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: localized("yuedu app 反饋"))
        ]
        return components.url
    }

    private var appLanguageFooter: String {
        // The name iOS Settings lists the app under: the display name (閱讀), not the bundle name.
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App"
        let template = localized("跟隨系統語言。可在「設定 → %@ → 語言」單獨設定")
        return String(format: template, appName)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appearanceThemeName: String {
        gs.appearanceTheme(
            for: colorScheme,
            isProActive: subscriptionStore.hasAccess(.readerThemePacks)
        ).localizedName
    }

    var body: some View {
        NavigationStack(path: $path) {
                Form {
                    Section {
                        DSSettingsRow(
                            icon: "crown.fill",
                            title: localized("會員卡密"),
                            detail: cardKeyMembership.isUnlocked ? localized("永久會員") : localized("未激活"),
                            action: {
                                // 这里的弹窗绑定的是 cardKeyAlert，不是 showCardKeyEntry；
                                // 之前只置了后者，导致点这一行毫无反应。
                                cardKeyInput = ""
                                cardKeyWrongKey = false
                                cardKeyAlert = true
                                // 顺带拉一次远端名单：后台改完卡密，这一行点开就能用新号。
                                Task { await cardKeyMembership.refreshIfNeeded(force: true) }
                            }
                        )
                        .accessibilityIdentifier("settings_card_key_row")
                        // The first row measures the form's scroll for the title's fade.
                        .rootTabTitleScrollAnchor()
                    }
                    .interfaceSectionSurface()

                    // Grouped by what each is for (maintainer, 2026-10-27): 一般, 資源, 閱讀, 資料, 支援.

                    // ── 一般 ──
                    // 書架顯示 (每列欄數, 預設封面) lives in 外觀主題's 介面 since 2026-09-29.
                    Section {
                        NavigationLink {
                            AppearanceThemeView()
                        } label: {
                            HStack {
                                Label(localized("外觀主題"), systemImage: "paintpalette.fill")
                                    .foregroundColor(DSColor.textPrimary)
                                    .labelStyle(IconConsistentLabelStyle())
                                Spacer(minLength: 12)
                                Text(appearanceThemeName)
                                    .font(DSFont.caption)
                                    .foregroundColor(DSColor.textSecondary)
                            }
                        }

                        DSSettingsRow(
                            icon: "globe",
                            title: localized("語言"),
                            action: {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                        )
                    } header: {
                        Text(localized("設定分組：一般"))
                            .foregroundStyle(DSColor.textSecondary)
                    } footer: {
                        Text(appLanguageFooter)
                            .dsSectionFooter()
                    }
                    .interfaceSectionSurface()

                    // ── 資源 ──
                    // Where every source is added (maintainer, 2026-10-27: 「把添加資源的入口都放在設置頁」):
                    // each kind's page, whose toolbar adds one. 資源庫 lists what is there. RSS 訂閱
                    // stays in 資源庫, a page to read rather than a setting (the maintainer's choice).
                    Section {
                        DSSettingsRow(
                            icon: "books.vertical.fill",
                            title: localized("來源配置管理"),
                            action: { pushSection(.sourceManager) }
                        )
                        .accessibilityIdentifier("settings_sources")

                        // 模組 (M6), here since the maintainer moved it from 資源庫's •••
                        // (2026-10-17: 「模組設定頁在設置好了」).
                        DSSettingsRow(
                            icon: "puzzlepiece.extension.fill",
                            title: localized("模組"),
                            action: { pushSection(.moduleManager) }
                        )
                        .accessibilityIdentifier("settings_modules")

                        NavigationLink {
                            RemoteLibrarySettingsView()
                        } label: {
                            Label(localized("遠端書庫"), systemImage: "server.rack")
                                .foregroundColor(DSColor.textPrimary)
                                .labelStyle(IconConsistentLabelStyle())
                        }
                        .accessibilityIdentifier("settings_remote_libraries")

                        // 聚合設定 (unified library 5d-3d, decision 21): here only, as Emby's
                        // aggregation settings sit in its user settings.
                        DSSettingsRow(
                            icon: "square.stack.3d.up.fill",
                            title: localized("聚合設定"),
                            action: { pushSection(.aggregationSettings) }
                        )
                        .accessibilityIdentifier("settings_aggregation")

                        DSSettingsRow(
                            icon: "network",
                            title: localized("網路設定"),
                            action: { showNetworkSettings = true }
                        )

                        // 下載管理 was in the tree but nothing linked to it, so the page
                        // (and the TXT export it now carries) was unreachable.
                        NavigationLink {
                            DownloadManagementView()
                        } label: {
                            Label(localized("下載管理"), systemImage: "arrow.down.circle")
                                .foregroundColor(DSColor.textPrimary)
                                .labelStyle(IconConsistentLabelStyle())
                        }
                        .accessibilityIdentifier("settings_downloads")

                        DSSettingsRow(
                            icon: "internaldrive",
                            title: localized("缓存管理"),
                            action: { showCacheManagement = true }
                        )
                        .accessibilityIdentifier("settings_cache")
                    } header: {
                        Text(localized("設定分組：資源"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()

                    // ── 閱讀 ──
                    Section {
                        DSSettingsRow(
                            icon: "waveform",
                            title: localized("語音朗讀設定"),
                            action: { showTTSSettings = true }
                        )

                        DSSettingsRow(
                            icon: "sparkles",
                            // Named for what it is — the reader's panel is also called
                            // 「AI 助手」, and someone looking for 人物卡 went here first.
                            title: localized("AI 助手設定"),
                            detail: isAILocked ? localized("需要卡密") : aiAssistantDetail,
                            isLocked: isAILocked,
                            action: {
                                if isAILocked { showAIPaywall = true } else { showAISettings = true }
                            }
                        )

                        DSSettingsRow(
                            icon: "text.magnifyingglass",
                            title: localized("替換規則"),
                            action: { showReplaceRules = true }
                        )
                    } header: {
                        Text(localized("設定分組：閱讀"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()

                    // ── 支援 ──
                    Section {
                        // 回饋中心 只剩日誌 (maintainer, 2026-11-05): 送出回報、我的回饋、
                        // 截圖入口全部拿掉，這一格直接就是診斷日誌。
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            Label(localized("日誌"), systemImage: "stethoscope")
                                .foregroundColor(DSColor.textPrimary)
                                .labelStyle(IconConsistentLabelStyle())
                        }
                        .accessibilityIdentifier("settings_feedback_center")

                        NavigationLink {
                            AboutSupportView(
                                appVersion: appVersion,
                                feedbackEmail: feedbackEmail,
                                feedbackMailURL: feedbackMailURL,
                                qqGroup: qqGroup
                            )
                        } label: {
                            HStack {
                                Label(localized("關於"), systemImage: "info.circle.fill")
                                    .foregroundColor(DSColor.textPrimary)
                                    .labelStyle(IconConsistentLabelStyle())
                                Spacer(minLength: 12)
                                Text(appVersion)
                                    .font(DSFont.caption)
                                    .foregroundColor(DSColor.textSecondary)
                            }
                        }
                    } header: {
                        Text(localized("設定分組：支援"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()
                }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .rootTabTitle(localized("設定"), onScroll: .minimizesBar)
            // Back from 外觀主題: its 淺色／深色 preview ends here.
            .onAppear { gs.endAppearanceSlotPreview() }
            // 來源配置管理, 模組 and 聚合設定 are `ExploreNavigationRoute` values, as are 模組's own
            // pages (官方模組, 匯入的模組, a repository, a module). None of them opens a source's
            // page, the one route that goes out to the browser, so this stack has no browser to open.
            .exploreRouteDestinations(openBrowser: { _ in })
            #if DEBUG
            // Screenshot/driver hook: `-open-diagnostics` pushes 診斷紀錄 straight from
            // launch, so its appearance can be inspected without driving the tab bar. Same
            // shape as the `-browser-overlay` launch flags in `yuedu_appApp.init()`, and
            // compiled out of Release. 回饋中心 is gone, so its flag went with it.
            .navigationDestination(isPresented: $autoOpenDiagnostics) {
                DiagnosticsView()
            }
            .onAppear {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-open-diagnostics") {
                    autoOpenDiagnostics = true
                }
            }
            #endif
            .sheet(isPresented: $showNetworkSettings) {
                NetworkSettingsView()
            }
            .alert(localized("會員卡密"), isPresented: $cardKeyAlert) {
                TextField(localized("請輸入卡密"), text: $cardKeyInput)
                    // 同 CardKeyUnlockView：卡密可含大小写，别让系统自动大写或纠错。
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(localized("激活")) {
                    let key = cardKeyInput
                    Task {
                        if await cardKeyMembership.activate(key) {
                            cardKeyWrongKey = false
                            cardKeyInput = ""
                            subscriptionStore.cardKeyMembershipDidChange()
                        } else {
                            cardKeyWrongKey = true
                            // Alert 已在关闭动画中；稍候重弹，避免同帧重设 isPresented 失效。
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { cardKeyAlert = true }
                        }
                    }
                }
                .disabled(cardKeyInput.isEmpty)
                Button(localized("取消"), role: .cancel) {}
            } message: {
                // 卡密对但设备不符时，提示「卡密错误」会让人一直重输
                Text(cardKeyWrongKey ? localized(cardKeyFailureText) : localized("輸入卡密以激活永久會員"))
            }
            .sheet(isPresented: $showAISettings) {
                AISettingsView()
            }
            .sheet(isPresented: $showAIPaywall) {
                CardKeyUnlockView()
            }
            .sheet(isPresented: $showReplaceRules) {
                ReplaceRuleListView()
            }
            .sheet(isPresented: $showTTSSettings) {
                TTSSettingsView()
            }
            // 缓存管理 was in the tree with no entry either; it owns its own close
            // button, so it is a sheet like 網路設定 rather than a pushed page.
            .sheet(isPresented: $showCacheManagement) {
                CacheManagementView(service: CacheManagementService(coverOwner: store))
            }
            // The only file importer on this root (one per view: SwiftUI presents just one).
            .ruleModuleAddFlow(moduleFlow)
        }
        .environment(\.ruleModuleAddFlow, moduleFlow)
    }

    /// AI is Pro, its settings included (`ReaderPremiumVisibilityPolicy.allowsAI`).
    private var isAILocked: Bool {
        !ReaderPremiumVisibilityPolicy(isProActive: subscriptionStore.isProActive).allowsAI
    }

    /// Says whether AI is usable at a glance. A reader who has not set it up should not have
    /// to open the screen to find that out.
    private var aiAssistantDetail: String {
        AIProviderStore.shared.hasConfiguredProfile ? localized("已啟用") : localized("未設定")
    }

    @ViewBuilder func AccountRowContent() -> some View {
        HStack(spacing: 15) {
            AccountAvatarView(size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(gs.isLoggedIn ? (gs.accountDisplayName.isEmpty ? localized("已登入") : gs.accountDisplayName) : localized("尚未登入"))
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Text(gs.accountSubtitle)
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

}

private struct AboutSupportView: View {
    @Environment(\.openURL) private var openURL
    let appVersion: String
    let feedbackEmail: String
    let feedbackMailURL: URL?
    let qqGroup: String

    @State private var showCopiedGroup = false

    /// 關於 is down to three facts (maintainer, 2026-11-05: 「關於裡面全都去掉，只保留
    /// 郵箱跟版本號，再加一個 QQ 交流群」). Everything the old page carried — policies,
    /// source code, TestFlight, 新手導覽 — is gone.
    var body: some View {
        List {
            Section {
                HStack {
                    Label(localized("版本"), systemImage: "number")
                        .foregroundColor(DSColor.textPrimary)
                        .labelStyle(IconConsistentLabelStyle())
                    Spacer(minLength: 12)
                    Text(appVersion)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                }
                .accessibilityIdentifier("about.version")

                Button {
                    if let url = feedbackMailURL {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .font(DSFont.fixed(size: 18, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundColor(DSColor.textPrimary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("電子郵件"))
                                .foregroundColor(DSColor.textPrimary)
                            Text(feedbackEmail)
                                .font(DSFont.caption)
                                .foregroundColor(DSColor.textSecondary)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "arrow.up.right")
                            .font(DSFont.caption)
                            .foregroundColor(DSColor.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about.email")

                Button {
                    UIPasteboard.general.string = qqGroup
                    showCopiedGroup = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(DSFont.fixed(size: 18, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundColor(DSColor.textPrimary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("QQ 交流群"))
                                .foregroundColor(DSColor.textPrimary)
                            Text(qqGroup)
                                .font(DSFont.caption)
                                .foregroundColor(DSColor.textSecondary)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "doc.on.doc")
                            .font(DSFont.caption)
                            .foregroundColor(DSColor.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("about.qq_group")
            } footer: {
                Text(localized("點一下群號即可複製，再到 QQ 搜尋加入。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("關於"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(localized("已複製"), isPresented: $showCopiedGroup) {
            Button(localized("好"), role: .cancel) {}
        } message: {
            Text(localized("群號已複製到剪貼簿。"))
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(BookStore())
        .environmentObject(SubscriptionStore.shared)
}
