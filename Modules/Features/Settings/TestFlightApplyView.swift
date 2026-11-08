import FirebaseFunctions
import SwiftUI

/// Collects an email from users who want to join the TestFlight beta. The
/// request is written to Firestore `testflightRequests` by the
/// `requestTestFlightAccess` callable, which adds the tester to the configured
/// App Store Connect beta group and lets Apple send the invite email.
struct TestFlightApplyView: View {
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @State private var email = ""
    @State private var state: TestFlightApplyState = .idle
    @State private var submissionStatus: String?
    @State private var wasAlreadySubmitted = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "testtube.2")
                        .font(DSFont.fixed(size: 40))
                        .foregroundStyle(DSColor.accent)
                        .accessibilityHidden(true)
                    Text(localized("抢先体验新功能"))
                        .font(DSFont.title3.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(localized("加入 TestFlight 测试版，抢先体验新功能并协助我们改善 Yuedu Reader。名额为永久会员专属，申请后我们会寄邀请邮件到你填写的邮箱。"))
                        .font(DSFont.footnote)
                        .foregroundColor(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.md)
            }
            .interfaceSectionSurface()

            if case .submitted = displayState {
                submittedRow
            } else if case let .blocked(reason) = displayState {
                blockedRow(reason: reason)
            } else {
                Section {
                    TextField(localized("输入你的邮箱"), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .disabled(isSubmitting)

                    Button {
                        submit()
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(DSColor.textOnAccent)
                            } else {
                                Text(localized("申请加入"))
                                    .font(DSFont.bodyBold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                    // Working, not disabled, while submitting: see `OnAccentProminentButtonStyle.work`.
                    .buttonStyle(.onAccentProminent(working: isSubmitting, title: Text(localized("申请加入"))))
                }
                .interfaceSectionSurface()
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.destructive)
                        .accessibilityLabel(errorMessage)
                }
                .interfaceSectionSurface()
            }
        }
        .softScrollEdges()
        .navigationTitle(localized("加入 TestFlight"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
    }

    private var submittedRow: some View {
        Section {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: submittedSymbol)
                    .font(DSFont.fixed(size: 44))
                    .foregroundStyle(submittedTint)
                    .accessibilityHidden(true)
                Text(submittedTitle)
                    .font(DSFont.title3.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(submittedMessage)
                    .font(DSFont.footnote)
                    .foregroundColor(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.lg)
        }
        .interfaceSectionSurface()
    }

    private var submittedSymbol: String {
        switch submissionStatus {
        case "alreadyInTestFlight":
            return "person.crop.circle.badge.checkmark"
        case "failed":
            return "exclamationmark.triangle.fill"
        default:
            return "clock.arrow.circlepath"
        }
    }

    private var submittedTint: Color {
        switch submissionStatus {
        case "alreadyInTestFlight":
            return DSColor.success
        case "failed":
            return DSColor.warning
        default:
            return DSColor.warning
        }
    }

    private func blockedRow(reason: TestFlightBlockReason) -> some View {
        Section {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: reason.symbol)
                    .font(DSFont.fixed(size: 44))
                    .foregroundStyle(DSColor.warning)
                    .accessibilityHidden(true)
                Text(reason.title)
                    .font(DSFont.title3.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(reason.message)
                    .font(DSFont.footnote)
                    .foregroundColor(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.lg)
        }
        .interfaceSectionSurface()
    }

    /// Anything the server already answered wins. Only before a submission does
    /// the locally-known plan decide, and only when it is known: `.undetermined`
    /// shows the form and lets `requestTestFlightAccess` be the authority.
    private var displayState: TestFlightApplyState {
        guard case .idle = state else { return state }
        return subscriptionStore.testFlightEligibility == .requiresLifetime
            ? .blocked(.requiresLifetime)
            : state
    }

    private var isSubmitting: Bool {
        if case .submitting = state { return true }
        return false
    }

    private var submittedTitle: String {
        if submissionStatus == "alreadyInTestFlight" {
            return localized("此邮箱已在 TestFlight")
        }
        if wasAlreadySubmitted {
            return localized("已申请过 TestFlight")
        }
        if submissionStatus == "failed" {
            return localized("申请已记录")
        }
        return localized("申请已送出")
    }

    private var submittedMessage: String {
        if submissionStatus == "alreadyInTestFlight" {
            return localized("此邮箱已经在 TestFlight；如果尚未看到测试版，请确认 Apple 帐号与 TestFlight App。")
        }
        if wasAlreadySubmitted {
            return localized("每个 Pro 帐号只能申请一次；如果尚未收到邀请，请联络管理员。")
        }
        if submissionStatus == "failed" {
            return localized("申请已记录，但邀请尚未完成，请联络管理员。")
        }
        return localized("我们会将 TestFlight 邀请寄到你的邮箱，请留意收件匣。")
    }

    private func submit() {
        guard isValidEmail(email) else {
            errorMessage = localized("请输入有效的邮箱地址")
            return
        }
        errorMessage = nil
        state = .submitting
        Task {
            do {
                let result = try await TestFlightAccessService.requestAccess(email: email)
                submissionStatus = result.status
                wasAlreadySubmitted = result.alreadySubmitted
                state = .submitted
            } catch {
                switch functionsErrorCode(from: error) {
                case 6:
                    state = .blocked(.oneSlotUsed)
                    errorMessage = nil
                case 7:
                    state = .blocked(.requiresLifetime)
                    errorMessage = nil
                default:
                    state = .idle
                    errorMessage = localized("无法送出申请，请检查网路后再试")
                }
            }
        }
    }

    private func functionsErrorCode(from error: Error) -> Int? {
        if let gatewayError = error as? GatewayAPIError {
            return gatewayError.grpcCode
        }
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain else { return nil }
        return nsError.code
    }

    /// Mirrors the backend `normalizeTestFlightEmail` check so a clearly
    /// invalid address never leaves the device. The server remains the
    /// authority; this is a UX guard, not a security boundary.
    private func isValidEmail(_ rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 254
            && trimmed.range(of: #"^[^\s@/]+@[^\s@/]+\.[^\s@/]+$"#, options: .regularExpression) != nil
    }
}

private enum TestFlightApplyState {
    case idle
    case submitting
    case submitted
    case blocked(TestFlightBlockReason)
}

private enum TestFlightBlockReason {
    case oneSlotUsed
    case requiresLifetime

    var symbol: String {
        switch self {
        case .oneSlotUsed: return "person.crop.circle.badge.exclamationmark"
        case .requiresLifetime: return "lock.circle"
        }
    }

    var title: String {
        switch self {
        case .oneSlotUsed: return localized("TestFlight 名额已使用")
        case .requiresLifetime: return localized("需要永久会员")
        }
    }

    var message: String {
        switch self {
        case .oneSlotUsed:
            return localized("这个 Pro 帐号已经申请过一个邮箱，不能再邀请第二个。")
        case .requiresLifetime:
            return localized("TestFlight 名额只开放给永久会员。月会员可以在「阅读Pro」升级为永久会员后申请。")
        }
    }
}

enum TestFlightAccessServiceError: Error {
    case invalidResponse
}

struct TestFlightAccessResult {
    let alreadySubmitted: Bool
    let status: String
}

/// Single entry point for submitting a TestFlight access request. Goes through
/// the active account backend, so the callable protocol and its idempotency
/// stay server-side on both routes.
enum TestFlightAccessService {
    @MainActor
    static func requestAccess(email: String) async throws -> TestFlightAccessResult {
        try await AccountBackendRouter.shared.current.requestTestFlightAccess(email: email)
    }
}

#Preview {
    NavigationStack {
        TestFlightApplyView()
    }
    .environmentObject(SubscriptionStore.shared)
}
