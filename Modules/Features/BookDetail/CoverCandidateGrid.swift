import PhotosUI
import SwiftUI

/// One cover offered by 封面搜索 / 换封面.
///
/// `sourceId` is the book source the cover came from, and it travels with the
/// URL because that source's headers are what make a hotlink-protected CDN cover
/// download at all. Covers found on the open web have no source (`nil`).
struct CoverCandidate: Identifiable, Equatable {
    let id: String
    let coverUrl: String
    let sourceId: UUID?
    /// Book source name, or the site a web cover came from.
    let providerName: String

    init(id: String? = nil, coverUrl: String, sourceId: UUID?, providerName: String) {
        self.id = id ?? coverUrl
        self.coverUrl = coverUrl
        self.sourceId = sourceId
        self.providerName = providerName
    }
}

/// The cover grid both cover finders present: candidates stream in, the user taps
/// one. Kept in one place so the two screens can't drift on cell size, empty
/// state or VoiceOver wording.
struct CoverCandidateGrid: View {
    /// Book title, used for the placeholder art behind a cover that fails to load.
    let bookTitle: String
    let candidates: [CoverCandidate]
    let isSearching: Bool
    let hasSearched: Bool
    /// What to suggest when nothing was found — the two screens offer different
    /// next steps.
    let emptyHint: String
    let onSelect: (CoverCandidate) -> Void
    /// 直接从相簿 / 档案选一张图当封面。之前空状态只写「或从相簿选一张图片」
    /// 却不给按钮，用户点不到（反馈 2026-11-09）。留空即不显示。
    var onImportImage: ((Data) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 3
    }

    var body: some View {
        ScrollView {
            if let onImportImage {
                importCoverButton(onImportImage: onImportImage)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.lg)
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: DSSpacing.md),
                    count: columnCount
                ),
                spacing: DSSpacing.lg
            ) {
                ForEach(candidates) { candidate in
                    coverCell(candidate)
                }
            }
            .padding(DSSpacing.lg)

            statusFooter
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xxl)
        }
        .softScrollEdges()
    }

    /// 常驻在网格最上方的「导入封面」：不依赖搜索结果，找不到封面时也能用。
    /// 复用全 App 统一的 `ImageSourcePickerButton`（相簿 + 档案两条来源，
    /// iOS 17 的选单时序问题也已在组件里处理），不另造一套选择器。
    private func importCoverButton(onImportImage: @escaping (Data) -> Void) -> some View {
        ImageSourcePickerButton(
            accessibilityTitle: localized("导入封面")
        ) { result in
            switch result {
            case .success(.data(let data)):
                onImportImage(data)
            case .success(.file(let url)):
                // fileImporter 的安全域只在回调期间有效，必须在这里读完。
                if let data = try? Data(contentsOf: url) {
                    onImportImage(data)
                }
            case .failure:
                break
            }
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "square.and.arrow.down")
                    .font(DSFont.body.weight(.medium))
                Text(localized("导入封面"))
                    .font(DSFont.subheadline.weight(.medium))
                Spacer(minLength: 0)
                Text(localized("选择图片"))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .foregroundStyle(DSColor.accent)
            .padding(.horizontal, DSSpacing.lg)
            .frame(minHeight: DSLayout.minimumTapTarget)
            .background(DSColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .stroke(DSColor.accent.opacity(0.35), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if isSearching {
            HStack(spacing: DSSpacing.sm) {
                ProgressView()
                Text(
                    candidates.isEmpty
                        ? localized("正在搜寻封面…")
                        : localized("正在搜寻更多封面…")
                )
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
        } else if candidates.isEmpty && hasSearched {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(DSFont.fixed(size: 36))
                    .foregroundStyle(DSColor.textSecondary.opacity(0.4))
                    // Decorative: the text below says the same thing.
                    .accessibilityHidden(true)
                Text(localized("没有找到其他封面"))
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                Text(emptyHint)
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DSSpacing.xxl)
        }
    }

    private func coverCell(_ candidate: CoverCandidate) -> some View {
        let source = candidate.sourceId.flatMap { id in
            BookSourceStore.shared.source(id: id)
        }

        return Button {
            onSelect(candidate)
        } label: {
            VStack(spacing: DSSpacing.xs) {
                BookCoverImage(
                    coverURL: candidate.coverUrl,
                    title: bookTitle,
                    sourceBaseURL: source?.bookSourceUrl,
                    sourceHeaders: source?.parsedHeaders ?? [:]
                )
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                        .stroke(DSColor.textSecondary.opacity(0.2), lineWidth: 0.5)
                )

                Text(candidate.providerName)
                    .font(DSFont.caption2)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("封面") + localized("，") + candidate.providerName)
        .accessibilityHint(localized("点两下使用这张封面"))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    CoverCandidateGrid(
        bookTitle: "红楼梦",
        candidates: [],
        isSearching: true,
        hasSearched: true,
        emptyHint: localized("可以改用相簿里的图片，或直接贴上封面网址。"),
        onSelect: { _ in }
    )
}
