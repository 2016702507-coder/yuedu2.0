import SwiftUI

/// 设置 › 回馈中心: send a report, follow the ones already sent, and choose whether a
/// screenshot offers a shortcut here. The diagnostic log viewer (诊断纪录) lives here too —
/// it is what a report carries.
struct FeedbackCenterView: View {
    @AppStorage(FeedbackScreenshotPrompt.enabledKey) private var screenshotPromptEnabled = true
    @State private var unreadCount = 0

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    FeedbackComposeView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(localized("回馈与改进"))
                                .foregroundStyle(DSColor.textPrimary)
                            Text(localized("回报使用问题，与支援团队沟通"))
                                .font(DSFont.subheadline)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                    .labelStyle(IconConsistentLabelStyle())
                }
                .accessibilityIdentifier("feedback_center_compose")

                NavigationLink {
                    FeedbackListView()
                } label: {
                    LabeledContent {
                        if unreadCount > 0 {
                            Text(unreadCount.formatted())
                                .font(DSFont.caption.weight(.semibold))
                                .foregroundStyle(DSColor.textOnFixedFill)
                                .padding(.horizontal, DSSpacing.sm)
                                .padding(.vertical, DSSpacing.xxs)
                                .background(DSColor.destructive, in: Capsule())
                                .accessibilityLabel(String(format: localized("%d 则未读回复"), unreadCount))
                        }
                    } label: {
                        SettingsRowLabel(localized("我的回馈"), systemImage: "bubble.left.and.text.bubble.right")
                    }
                }
                .accessibilityIdentifier("feedback_center_list")

                Toggle(isOn: $screenshotPromptEnabled) {
                    SettingsRowLabel(localized("截图后显示意见回馈入口"), systemImage: "camera.viewfinder")
                }
            }
            .interfaceSectionSurface()

            Section {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    SettingsRowLabel(localized("诊断纪录"), systemImage: "stethoscope")
                }
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("回馈中心"))
        .toolbarTitleDisplayMode(.inline)
        .task {
            // The badge follows the inbox while the page is open; a failure leaves it at
            // zero (the listener logs it, and 我的回馈 shows the error itself).
            do {
                for try await threads in FeedbackService.shared.threadUpdates() {
                    unreadCount = threads.filter(\.isUnread).count
                }
            } catch {
                unreadCount = 0
            }
        }
    }
}

#Preview {
    NavigationStack {
        FeedbackCenterView()
    }
}
