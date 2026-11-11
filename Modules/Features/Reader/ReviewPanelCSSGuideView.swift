import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// CSS 说明：从「孤岛 / Cay」的《孤岛 CSS 说明》改写而来，去掉它原生引擎专有的
/// 语法，补上本 App 注入网页时的降级规则与选择器映射，可导出 Markdown。
struct ReviewPanelCSSGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text(localized("段评与互动 CSS 说明"))
                    .font(DSFont.title2)
                    .foregroundStyle(DSColor.textPrimary)

                ForEach(ReviewPanelCSSGuide.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(section.title)
                            .font(DSFont.headline)
                            .foregroundStyle(DSColor.accent)
                        Text(section.body)
                            .font(.system(size: 13, design: .default))
                            .foregroundStyle(DSColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.sm)
                    .background(DSColor.surfaceTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
                }

                ShareLink(
                    item: ReviewPanelCSSGuideExport(),
                    preview: SharePreview(localized("段评与互动 CSS 说明"))
                ) {
                    Label(localized("导出 MD 说明"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .padding(.vertical, DSSpacing.md)
            }
            .padding(DSSpacing.md)
        }
        .softScrollEdges()
        .navigationTitle(localized("CSS 说明"))
        .toolbarTitleDisplayMode(.inline)
        .readerGlassSettingsSurface()
    }
}

enum ReviewPanelCSSGuide {
    struct Section {
        let title: String
        let body: String
    }

    static let sections: [Section] = [
        Section(title: "这是什么", body: """
段评与互动样式分四个区域：段评面板、评论列表、热评 / 神评论、本章说 / 作者说。每个区域一份 CSS，可存成多套模板随时切换，也能汇入汇出。

分区与内置示例取自「孤岛 / Cay」。它的段评是原生列表配自研 CSS 引擎；本 App 的段评面板是书源网页（WKWebView），所以写好的 CSS 会先经一层降级转换再注入网页：能对应的转成等价浏览器写法，专有的直接跳过。你也可以在编辑框里直接写标准浏览器 CSS，选择器会原样保留。

本章说、作者说、神评论卡片如果是书源 SVG 模板绘制的，仍按「气泡设置」里的模板显示；这里的 CSS 主要作用于段评网页。
"""),
        Section(title: "写法", body: """
直接写声明作用于整个区域：
  color: #333;
  font-size: 15px;
  background: rgba(250, 248, 243, 0.94);
  border-radius: 16px;

用选择器作用于某个部分，多个选择器用逗号分隔：
  .user { color: #3A7BD5; font-weight: 600; }
  .text, .quote { font-size: 14px; }

嵌套规则也支持：
  .card { .user { color: #B07A3B; } }

规则按顺序覆盖，注入时会自动加上 !important，压过书源网页自带的样式。清空某个区域的 CSS 即恢复该区默认外观。
"""),
        Section(title: "语义选择器（取自孤岛）", body: """
.user / .text / .quote / .avatar / .likes / .likes-icon / .likes-value
.time / .timestamp / .location / .reply-to / .reply-count / .reply-icon
.reply-count-value / .badge / .author / .card
.label / .header / .header-row / .count / .more
.note / .note-label / .note-author / .note-text / .note-avatar

这些是孤岛的语义类名，浏览器不认。注入时会展开成一组候选选择器（含 .cay-* 打标类与常见类名关键词），并在网页加载时按类名 / 文本给元素补上 .cay-* 标记，让从孤岛抄来的样式大致命中。书源网页 DOM 没有统一约定，个别选择器可能找不到对应元素。
"""),
        Section(title: "常用属性", body: """
文字：color / font-size / font-family / font-weight / font-style
      letter-spacing / line-height / text-align / text-indent
      text-shadow / opacity / content（改标签文字）
盒子：background / background-color / background-image / border / border-radius
      padding / margin / box-shadow / width / height
显示：display / visibility / transform / filter

浏览器本身支持的属性都能用。以下孤岛写法会自动转换：
  background: glass        → 半透明底 + 毛玻璃
  line-clamp: 3            → -webkit-line-clamp + 弹性盒截断
  content: "神评"          → 隐藏原文字，用 ::after 追加自订文字
  font-weight: semibold    → 600
  border: 0.5px #D8C9A8   → 自动补 solid
  @dark { … } / @light { … } → 按当前日夜模式只注入对应分支
"""),
        Section(title: "日夜与条件", body: """
@dark 里的规则只在夜间阅读主题下注入，@light 只在白天注入。也可以给同一份样式写两份：

  color: #393B45;
  @dark {
    color: #D6D3D8;
    .user { color: #C99C63; }
  }

孤岛的条件选择器（[user=alice]、:regex()、@if）、@js、::match()、{{数据}}、-cay-bubble、url(asset:…) 属于它的原生引擎专有语法，注入时会被忽略，编辑框里会给出提示。
"""),
        Section(title: "示例：橙色神评标签", body: """
font-size: 15px;
background: glass;
border-radius: 12px;
padding: 8px 12px;
line-clamp: 3;
.label {
  content: "神评";
  background: #F5A623;
  color: white;
  padding: 0 6px;
  border-radius: 6px;
}
.user { color: #B07A3B; font-weight: bold; }
"""),
        Section(title: "示例：评论原文与头像", body: """
.quote { background: rgba(136, 136, 136, 0.09); padding: 12px; line-clamp: 4; }
.avatar { width: 30px; border-radius: 6px; }
.user { font-weight: 600; }
.likes-icon { display: none; }
.location { opacity: 0.5; }
.text { line-clamp: 8; }
"""),
        Section(title: "汇入与汇出", body: """
汇出会把四个区域的 CSS 打包成一个 .json 样式包，可分享给别人；汇入支持这种样式包，也可直接汇入一份纯 CSS 文本（当作评论列表样式）。内置模板只读，左滑或长按「复制并编辑」即可得到可改的副本。
""")
    ]

    static var markdown: String {
        "# 段评与互动 CSS 说明\n\n" + sections.map { "## \($0.title)\n\n\($0.body)" }.joined(separator: "\n\n")
    }
}

struct ReviewPanelCSSGuideExport: Transferable {
    let data: Data

    init() {
        data = Data(ReviewPanelCSSGuide.markdown.utf8)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { payload in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("段评与互动CSS说明.md")
            try payload.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

#Preview {
    NavigationStack {
        ReviewPanelCSSGuideView()
    }
}
