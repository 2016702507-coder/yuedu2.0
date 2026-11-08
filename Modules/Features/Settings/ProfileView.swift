import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: BookStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var gs = GlobalSettings.shared
    /// 来源配置管理, 模组 and its pages, and 聚合设置 push `ExploreNavigationRoute` values. A page
    /// opened by `navigationDestination(isPresented:)` on a stack without a path is pushed again on
    /// top of a value pushed after it (模组 reappeared over 测试仓库), so each is a value.
    @State private var path = NavigationPath()

    /// Opens one of 设置's sections (来源配置管理, 模组, 聚合设置) from this page.
    ///
    /// The path is emptied first, and that is the whole point. `path.append` on its own
    /// left whatever the last visit pushed sitting underneath: come back to 设置 by the tab
    /// bar instead of by 返回 (or tap a row twice while the push is still animating) and the
    /// next section landed on top of that stale page — 返回 then went to the page visited
    /// before, not to 设置, and a section opened twice needed two 返回s to leave. Starting
    /// from an empty path makes 设置 the parent of every section, every time.
    private func pushSection(_ route: ExploreNavigationRoute) {
        path = NavigationPath()
        path.append(route)
    }
    /// 模组's 新增模组 (its toolbar), presented from this root: the one place a module is added.
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
    /// 卡密失败文案：区分「设备已被占用」「已过期」和「卡密错误」
    private var cardKeyFailureText: String {
        switch cardKeyMembership.lastFailureReason {
        case "device_mismatch": return "此兑换码已在其他装置启用"
        case "expired": return "此兑换码已到期，请换一张新兑换码"
        case "already_forever": return "已是永久会员，无需再激活"
        case "network": return "网路连线失败，请稍后重试"
        default: return "兑换码错误，请重新输入"
        }
    }

    /// 会员卡密一行的状态：永久 / 月卡剩余天数 / 未激活。
    private var cardKeyStatusText: String {
        guard cardKeyMembership.isUnlocked else { return localized("未激活") }
        switch cardKeyMembership.plan {
        case .forever:
            return localized("永久会员")
        case .month:
            guard let days = cardKeyMembership.remainingDays, days > 0 else {
                return localized("月卡会员")
            }
            return String(format: localized("月卡会员 · 剩余 %d 天"), days)
        case .none:
            return localized("未激活")
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
            URLQueryItem(name: "subject", value: localized("yuedu app 反馈"))
        ]
        return components.url
    }

    private var appLanguageFooter: String {
        // The name iOS Settings lists the app under: the display name (阅读), not the bundle name.
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App"
        let template = localized("跟随系统语言。可在「设置 → %@ → 语言」单独设置")
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
                    // 头像、暱称、签名与阅读统计，坐在「尊享会员」之上（maintainer,
                    // 2026-11-06）。这一格自己不带卡片底，让页面背景透上来 —— 参考图里
                    // 它就是浮在纸上的一块，而不是另一张列表卡。
                    Section {
                        ReaderProfileHeader()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            // The first row measures the form's scroll for the title's fade.
                            .rootTabTitleScrollAnchor()
                    }

                    Section {
                        DSSettingsRow(
                            icon: "crown.fill",
                            title: localized("尊享会员"),
                            detail: cardKeyStatusText,
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
                    }
                    .interfaceSectionSurface()

                    // Grouped by what each is for (maintainer, 2026-10-27): 一般, 资源, 阅读, 资料, 支援.

                    // ── 一般 ──
                    // 书架显示 (每列栏数, 预设封面) lives in 外观主题's 介面 since 2026-09-29.
                    Section {
                        NavigationLink {
                            AppearanceThemeView()
                        } label: {
                            HStack {
                                Label(localized("外观主题"), systemImage: "paintpalette.fill")
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
                            title: localized("语言"),
                            action: {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                        )
                    } header: {
                        Text(localized("设置分组：一般"))
                            .foregroundStyle(DSColor.textSecondary)
                    } footer: {
                        Text(appLanguageFooter)
                            .dsSectionFooter()
                    }
                    .interfaceSectionSurface()

                    // ── 资源 ──
                    // Where every source is added (maintainer, 2026-10-27: 「把添加资源的入口都放在设置页」):
                    // each kind's page, whose toolbar adds one. 资源库 lists what is there. RSS 订阅
                    // stays in 资源库, a page to read rather than a setting (the maintainer's choice).
                    Section {
                        DSSettingsRow(
                            icon: "books.vertical.fill",
                            title: localized("来源配置管理"),
                            action: { pushSection(.sourceManager) }
                        )
                        .accessibilityIdentifier("settings_sources")

                        // 模组 (M6), here since the maintainer moved it from 资源库's •••
                        // (2026-10-17: 「模组设置页在设置好了」).
                        DSSettingsRow(
                            icon: "puzzlepiece.extension.fill",
                            title: localized("模组"),
                            action: { pushSection(.moduleManager) }
                        )
                        .accessibilityIdentifier("settings_modules")

                        NavigationLink {
                            RemoteLibrarySettingsView()
                        } label: {
                            Label(localized("远端书库"), systemImage: "server.rack")
                                .foregroundColor(DSColor.textPrimary)
                                .labelStyle(IconConsistentLabelStyle())
                        }
                        .accessibilityIdentifier("settings_remote_libraries")

                        // 聚合设置 (unified library 5d-3d, decision 21): here only, as Emby's
                        // aggregation settings sit in its user settings.
                        DSSettingsRow(
                            icon: "square.stack.3d.up.fill",
                            title: localized("聚合设置"),
                            action: { pushSection(.aggregationSettings) }
                        )
                        .accessibilityIdentifier("settings_aggregation")

                        DSSettingsRow(
                            icon: "network",
                            title: localized("网路设置"),
                            action: { showNetworkSettings = true }
                        )

                        // 下载管理 was in the tree but nothing linked to it, so the page
                        // (and the TXT export it now carries) was unreachable.
                        NavigationLink {
                            DownloadManagementView()
                        } label: {
                            Label(localized("下载管理"), systemImage: "arrow.down.circle")
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
                        Text(localized("设置分组：资源"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()

                    // ── 阅读 ──
                    Section {
                        DSSettingsRow(
                            icon: "waveform",
                            title: localized("语音朗读设置"),
                            action: { showTTSSettings = true }
                        )

                        DSSettingsRow(
                            icon: "sparkles",
                            // Named for what it is — the reader's panel is also called
                            // 「AI 助手」, and someone looking for 人物卡 went here first.
                            title: localized("AI 助手设置"),
                            detail: isAILocked ? localized("需要尊享会员") : aiAssistantDetail,
                            isLocked: isAILocked,
                            action: {
                                if isAILocked { showAIPaywall = true } else { showAISettings = true }
                            }
                        )

                        DSSettingsRow(
                            icon: "text.magnifyingglass",
                            title: localized("替换规则"),
                            action: { showReplaceRules = true }
                        )

                        // FB-139: pushed, not a sheet like 替换规则 — its file importer needs a
                        // first-level presenter on iOS 17.
                        NavigationLink {
                            TXTTocRuleListView()
                        } label: {
                            Label(localized("TXT 分章规则"), systemImage: "list.number")
                                .foregroundColor(DSColor.textPrimary)
                                .labelStyle(IconConsistentLabelStyle())
                        }
                        .accessibilityIdentifier("settings_txt_toc_rules")
                    } header: {
                        Text(localized("设置分组：阅读"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()

                    // ── 支援 ──
                    Section {
                        // 回馈中心 只剩日志 (maintainer, 2026-11-05): 送出回报、我的回馈、
                        // 截图入口全部拿掉，这一格直接就是诊断日志。
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            Label(localized("日志"), systemImage: "stethoscope")
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
                                Label(localized("关于"), systemImage: "info.circle.fill")
                                    .foregroundColor(DSColor.textPrimary)
                                    .labelStyle(IconConsistentLabelStyle())
                                Spacer(minLength: 12)
                                Text(appVersion)
                                    .font(DSFont.caption)
                                    .foregroundColor(DSColor.textSecondary)
                            }
                        }
                    } header: {
                        Text(localized("设置分组：支援"))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .interfaceSectionSurface()
                }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .rootTabTitle(localized("设置"), onScroll: .minimizesBar)
            // Back from 外观主题: its 浅色／深色 preview ends here.
            .onAppear { gs.endAppearanceSlotPreview() }
            // 来源配置管理, 模组 and 聚合设置 are `ExploreNavigationRoute` values, as are 模组's own
            // pages (官方模组, 汇入的模组, a repository, a module). None of them opens a source's
            // page, the one route that goes out to the browser, so this stack has no browser to open.
            .exploreRouteDestinations(openBrowser: { _ in })
            #if DEBUG
            // Screenshot/driver hook: `-open-diagnostics` pushes 诊断纪录 straight from
            // launch, so its appearance can be inspected without driving the tab bar. Same
            // shape as the `-browser-overlay` launch flags in `yuedu_appApp.init()`, and
            // compiled out of Release. 回馈中心 is gone, so its flag went with it.
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
            .alert(localized("尊享会员"), isPresented: $cardKeyAlert) {
                TextField(localized("请输入兑换码"), text: $cardKeyInput)
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
                Text(cardKeyWrongKey ? localized(cardKeyFailureText) : localized("输入兑换码以激活尊享会员（月卡 / 永久）"))
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
            // button, so it is a sheet like 网路设置 rather than a pushed page.
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
        AIProviderStore.shared.hasConfiguredProfile ? localized("已启用") : localized("未设置")
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

    @State private var copiedNotice: String?

    /// 这台装置在卡密后台的身份。Keychain 里的 UUID，重装不变、换机才变。
    @ObservedObject private var cardKeyMembership = CardKeyMembership.shared

    /// 关于 is down to three facts (maintainer, 2026-11-05: 「关于里面全都去掉，只保留
    /// 邮箱跟版本号，再加一个 QQ 交流群」). Everything the old page carried — policies,
    /// source code, TestFlight, 新手导览 — is gone.
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
                            Text(localized("电子邮件"))
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
                    copiedNotice = localized("群号已复制到剪贴簿。")
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
                Text(localized("点一下群号即可复制，再到 QQ 搜寻加入。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            // 设备码：重装、换机后自动恢复接不回来时的人工通道 —— 用户复制给开发者，
            // 后台按这串补绑。它存在 Keychain 里，重装不变，换机才会换。
            Section {
                Button {
                    UIPasteboard.general.string = cardKeyMembership.deviceCode
                    copiedNotice = localized("设备码已复制到剪贴簿。")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone.gen3")
                            .font(DSFont.fixed(size: 18, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundColor(DSColor.textPrimary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("设备码"))
                                .foregroundColor(DSColor.textPrimary)
                            Text(cardKeyMembership.deviceCode)
                                .font(DSFont.fixed(size: 11, design: .monospaced))
                                .foregroundColor(DSColor.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
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
                .accessibilityIdentifier("about.device_code")
            } footer: {
                Text(localized("重装或换机后会员没有恢复，把这串发给开发者，可人工补绑。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("关于"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(
            localized("已复制"),
            isPresented: Binding(
                get: { copiedNotice != nil },
                set: { if !$0 { copiedNotice = nil } }
            )
        ) {
            Button(localized("好"), role: .cancel) {}
        } message: {
            Text(copiedNotice ?? "")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(BookStore())
        .environmentObject(SubscriptionStore.shared)
}
