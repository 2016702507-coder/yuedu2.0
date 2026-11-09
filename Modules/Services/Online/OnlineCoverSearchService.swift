import Foundation

/// 封面搜索 — covers looked up on the open web rather than in the user's sources.
///
/// This is Legado's 封面规则 (`BookCover.searchCover`) without the rule plumbing:
/// its shipped default rule queries 推书君 and 一片书喽 from JavaScript, matches
/// the result's title and author against the book, and returns the artwork. The
/// same two endpoints are queried here directly, because the rule's JS needs a
/// `data:` search URL and a `com.jayway.jsonpath` binding that our engine has no
/// other use for. There is no rule editor yet — if these endpoints ever move,
/// this is the single place that changes.
///
/// Legado stops at the first match; this keeps every distinct cover so the user
/// picks from a grid instead of accepting whatever answered first.
enum OnlineCoverSearchService {

    struct Result: Equatable {
        let coverUrl: String
        /// The site the cover came from, shown under the thumbnail.
        let providerName: String
    }

    private enum Provider: CaseIterable {
        case tuishujun
        case ypshuo

        var displayName: String {
            switch self {
            case .tuishujun: return localized("推书君")
            case .ypshuo: return localized("一片书喽")
            }
        }

        /// 每个源翻几页。之前只取第 1 页、每页 20 条，加上过严的匹配，
        /// 大部分书最后只剩 0~1 张封面（用户反馈「封面开源有点少」）。
        var pages: Int {
            switch self {
            case .tuishujun: return 3
            case .ypshuo: return 2
            }
        }

        var pageSize: Int {
            switch self {
            case .tuishujun: return 50
            case .ypshuo: return 20
            }
        }

        func requestURL(query: String, page: Int) -> URL? {
            var components: URLComponents?
            switch self {
            case .tuishujun:
                components = URLComponents(string: "https://pre-api.tuishujun.com/api/searchBook")
                components?.queryItems = [
                    URLQueryItem(name: "search_value", value: query),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "pageSize", value: String(pageSize)),
                ]
            case .ypshuo:
                components = URLComponents(string: "https://m.ypshuo.com/api/novel/search")
                components?.queryItems = [
                    URLQueryItem(name: "keyword", value: query),
                    URLQueryItem(name: "searchType", value: "1"),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            }
            return components?.url
        }

        /// Field names differ per provider; the matching rule does not.
        var fields: (title: String, author: String, cover: String) {
            switch self {
            case .tuishujun: return ("title", "author_nickname", "cover")
            case .ypshuo: return ("novel_name", "author_name", "novel_img")
            }
        }
    }

    /// Covers for `name`/`author`, deduped by URL, in provider order.
    ///
    /// Providers (and each page of each provider) are independent: one being down
    /// or slow must not cost the others, so failures are logged per request and
    /// the rest of the results stand.
    static func searchCovers(name: String, author: String) async -> [Result] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var results: [Result] = []
        var seen = Set<String>()

        await withTaskGroup(of: [Result].self) { group in
            for provider in Provider.allCases {
                for page in 1...provider.pages {
                    group.addTask {
                        await search(provider: provider, name: query, author: author, page: page)
                    }
                }
            }
            for await pageResults in group {
                for result in pageResults where seen.insert(result.coverUrl).inserted {
                    results.append(result)
                }
            }
        }
        return results
    }

    private static func search(
        provider: Provider,
        name: String,
        author: String,
        page: Int
    ) async -> [Result] {
        guard let url = provider.requestURL(query: name, page: page) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(BookCoverLoader.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                AppLogger.network(
                    "[CoverSearch] \(provider.displayName) p\(page) HTTP \(http.statusCode)"
                )
                return []
            }
            return parse(data: data, provider: provider, name: name, author: author)
        } catch {
            AppLogger.network(
                "[CoverSearch] \(provider.displayName) p\(page) request failed", error: error
            )
            return []
        }
    }

    /// Both providers answer `{ data: { data: [ … ] } }`; only the item keys differ.
    private static func parse(
        data: Data,
        provider: Provider,
        name: String,
        author: String
    ) -> [Result] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let items = payload["data"] as? [[String: Any]] else {
            AppLogger.parse("[CoverSearch] \(provider.displayName) returned an unexpected shape")
            return []
        }
        let fields = provider.fields
        return items.compactMap { item in
            guard let cover = (item[fields.cover] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !cover.isEmpty else { return nil }
            let itemTitle = item[fields.title] as? String ?? ""
            let itemAuthor = item[fields.author] as? String ?? ""
            guard matches(name: name, author: author, itemTitle: itemTitle, itemAuthor: itemAuthor)
            else { return nil }
            return Result(coverUrl: cover, providerName: provider.displayName)
        }
    }

    /// 去掉卷号、副标题、括号内容和空白后再比，让「斗罗大陆（精装版）」这类
    /// 本地书名也能对上远端不带后缀的条目。
    private static func normalized(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 括号及其内容（中英文、方括号、书名号）
        let bracketPatterns = ["\\([^)]*\\)", "（[^）]*）", "\\[[^\\]]*\\]", "【[^】]*】"]
        for pattern in bracketPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                s = regex.stringByReplacingMatches(
                    in: s, range: NSRange(s.startIndex..., in: s), withTemplate: ""
                )
            }
        }
        // 卷/部/册/篇 + 数字或中文数字的后缀
        if let regex = try? NSRegularExpression(pattern: "(第?[0-9零一二三四五六七八九十百]+[卷部册篇集].*)$") {
            s = regex.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: ""
            )
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// 之前的规则要求「本地书名包含远端标题」且「作者互含」，两道都过严：
    /// 远端返回的多是「大话红楼梦」「重生在红楼梦世界」这类衍生标题，被第一道
    /// 全部挡掉，于是几乎总是「没有找到其他封面」。现在改成双向包含 + 归一化
    /// 后再比，作者只在两边都明确且完全冲突时才否掉；本地作者为空或「未知」
    /// 时只按标题判断（导入的 TXT 通常没有作者）。
    private static func matches(
        name: String,
        author: String,
        itemTitle: String,
        itemAuthor: String
    ) -> Bool {
        let localTitle = normalized(name)
        let remoteTitle = normalized(itemTitle)
        guard !remoteTitle.isEmpty, !localTitle.isEmpty else { return false }
        guard localTitle.contains(remoteTitle) || remoteTitle.contains(localTitle) else {
            return false
        }

        // 标题一致就是同一本书，署名不同（笔名、转载署名）也该留下。
        if localTitle == remoteTitle { return true }

        let localAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteAuthor = itemAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localAuthor.isEmpty, localAuthor != localized("未知作者"),
              !remoteAuthor.isEmpty else { return true }
        return localAuthor.contains(remoteAuthor) || remoteAuthor.contains(localAuthor)
    }
}
