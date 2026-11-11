import Foundation

/// 把「孤岛 / Cay」风格的 CSS 降级成浏览器 CSS，并生成注入段评网页的脚本。
///
/// Cay 的 CSS 是给它自己的原生视图引擎用的，很多语法浏览器不认（`glass`、
/// `@dark`、`line-clamp`、`content` 改标签文字、`-cay-bubble`、`@js`、条件伪类…）。
/// 这里做一层转换：能对应的转成等价浏览器写法，专有的直接跳过；同时把 Cay 的
/// 语义选择器（.user / .text / .quote…）展开成一组候选选择器，配合脚本给网页
/// DOM 打标，让从 Cay 抄来的样式在书源网页上也能大致命中。
enum ReviewPanelCSSBridge {

    /// 各区域 CSS 合成一份网页样式。`isNight` 决定保留 `@dark` 还是 `@light` 分支。
    static func browserCSS(_ cssByArea: [ReviewPanelCSSArea: String], isNight: Bool) -> String {
        var output: [String] = []
        for area in ReviewPanelCSSArea.allCases {
            let raw = cssByArea[area] ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let adapted = adapt(trimmed, area: area, isNight: isNight)
            if !adapted.isEmpty {
                output.append("/* \(area.title) */\n" + adapted)
            }
        }
        return output.joined(separator: "\n\n")
    }

    /// 生成 `atDocumentStart` 注入的脚本：装样式、打标 DOM、动态内容继续监听。
    static func installScript(css: String, isNight: Bool) -> String {
        let literal = javaScriptStringLiteral(css)
        let mode = isNight ? "dark" : "light"
        return """
        (function () {
            var STYLE_ID = '__yd_review_custom__';
            var CSS = \(literal);
            var MODE = '\(mode)';
            var root = document.documentElement;
            if (root) {
                root.classList.add('yd-review-root');
                root.classList.add(MODE === 'dark' ? 'yd-dark' : 'yd-light');
                root.classList.remove(MODE === 'dark' ? 'yd-light' : 'yd-dark');
            }

            function installStyle() {
                var head = document.head || document.documentElement;
                if (!head) return;
                var style = document.getElementById(STYLE_ID);
                if (!style) {
                    style = document.createElement('style');
                    style.id = STYLE_ID;
                    style.textContent = CSS;
                } else if (style.textContent !== CSS) {
                    style.textContent = CSS;
                }
                // 永远排在最后：段评页自带的透明背景脚本会用 !important 清底色，
                // 同优先级下后写的规则才盖得住它。
                if (head.lastChild !== style) head.appendChild(style);
            }

            // 启发式打标：书源生成的网页 DOM 没有统一约定，按类名 / id / 文本
            // 关键词补上 Cay 的语义类名，让 .user / .text / .quote 这类选择器命中。
            var MARKS = [
                ['cay-avatar', /avatar|头像|face|portrait|touxiang/i],
                ['cay-user', /user|nick|author|uname|用户名|昵称|书友/i],
                ['cay-text', /content|comment-text|review-text|desc|正文|评论内容/i],
                ['cay-quote', /quote|origin|source-text|原文|引用/i],
                ['cay-likes', /like|vote|点赞|赞数|ding/i],
                ['cay-time', /time|date|timestamp|时间/i],
                ['cay-label', /label|tag|badge|标签|神评|热评/i],
                ['cay-header', /header|section-title|card-title|标题/i],
                ['cay-note', /note|author-note|作者/i],
                ['cay-card', /card|comment-item|review-item|list-item|评论/i],
                ['cay-location', /location|ip|地区|地点/i]
            ];
            var AREAS = [
                ['yd-area-hot', /hot|神评|热评|精评|精选/i],
                ['yd-area-chapter', /chapter|本章说|章评|章末/i]
            ];

            function tagNodes() {
                if (!document.body) return;
                var nodes = document.body.querySelectorAll('div,span,p,a,li,section,article,header,footer,h1,h2,h3,h4,img,small,time');
                for (var i = 0; i < nodes.length; i++) {
                    var el = nodes[i];
                    if (el.dataset && el.dataset.ydTagged === '1') continue;
                    var key = (el.className && typeof el.className === 'string' ? el.className : '') + ' ' + (el.id || '');
                    var text = (el.textContent || '').slice(0, 24);
                    for (var m = 0; m < MARKS.length; m++) {
                        if (MARKS[m][1].test(key) || (text.length < 20 && MARKS[m][1].test(text))) {
                            el.classList.add(MARKS[m][0]);
                        }
                    }
                    for (var a = 0; a < AREAS.length; a++) {
                        if (AREAS[a][1].test(key)) el.classList.add(AREAS[a][0]);
                    }
                    if (el.dataset) el.dataset.ydTagged = '1';
                }
            }

            function run() { installStyle(); tagNodes(); }
            run();
            document.addEventListener('DOMContentLoaded', run, { once: true });
            window.addEventListener('load', function () {
                run();
                setTimeout(run, 120);
                setTimeout(run, 600);
            });
            try {
                var observer = new MutationObserver(function () { run(); });
                observer.observe(document.documentElement, { childList: true, subtree: true });
                setTimeout(function () { observer.disconnect(); }, 6000);
            } catch (error) {}
        })();
        """
    }

    /// 把 Swift 字符串变成安全的 JS 字符串字面量。
    private static func javaScriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        // JSON 字符串与 JS 字符串字面量兼容；额外防住 </script> 提前闭合。
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }

    // MARK: - Cay CSS → 浏览器 CSS

    /// 语义选择器 → 一组候选选择器。书源网页类名五花八门，用属性 contains 兜底。
    private static let selectorAliases: [String: String] = [
        ".user": ".cay-user, .user, [class*=\"user\" i], [class*=\"nick\" i], [class*=\"uname\" i], [class*=\"author\" i]",
        ".text": ".cay-text, .text, [class*=\"content\" i], [class*=\"comment-text\" i], [class*=\"desc\" i]",
        ".quote": ".cay-quote, .quote, [class*=\"quote\" i], [class*=\"origin\" i], [class*=\"source-text\" i]",
        ".avatar": ".cay-avatar, .avatar, [class*=\"avatar\" i], img[class*=\"avatar\" i]",
        ".likes": ".cay-likes, .likes, [class*=\"like\" i], [class*=\"vote\" i], [class*=\"ding\" i]",
        ".likes-icon": ".cay-likes-icon, .likes-icon, [class*=\"like-icon\" i]",
        ".likes-value": ".cay-likes-value, .likes-value, [class*=\"like-count\" i]",
        ".time": ".cay-time, .time, [class*=\"time\" i], [class*=\"date\" i]",
        ".timestamp": ".cay-timestamp, .timestamp, [class*=\"timestamp\" i]",
        ".location": ".cay-location, .location, [class*=\"location\" i], [class*=\"ip\" i]",
        ".label": ".cay-label, .label, [class*=\"label\" i], [class*=\"tag\" i], [class*=\"badge\" i]",
        ".header": ".cay-header, .header, [class*=\"header\" i], [class*=\"section-title\" i]",
        ".header-row": ".cay-header-row, .header-row, [class*=\"header-row\" i]",
        ".count": ".cay-count, .count, [class*=\"count\" i]",
        ".more": ".cay-more, .more, [class*=\"more\" i]",
        ".note": ".cay-note, .note, [class*=\"note\" i], [class*=\"author-note\" i]",
        ".note-label": ".cay-note-label, .note-label, [class*=\"note-label\" i]",
        ".note-author": ".cay-note-author, .note-author, [class*=\"note-author\" i]",
        ".note-text": ".cay-note-text, .note-text, [class*=\"note-text\" i]",
        ".note-avatar": ".cay-note-avatar, .note-avatar, [class*=\"note-avatar\" i]",
        ".badge": ".cay-badge, .badge, [class*=\"badge\" i], [class*=\"level\" i]",
        ".author": ".cay-author, .author, [class*=\"author-tag\" i]",
        ".reply-to": ".cay-reply-to, .reply-to, [class*=\"reply-to\" i]",
        ".reply-count": ".cay-reply-count, .reply-count, [class*=\"reply-count\" i]",
        ".reply-icon": ".cay-reply-icon, .reply-icon, [class*=\"reply-icon\" i]",
        ".card": ".cay-card, .card, [class*=\"card\" i], [class*=\"item\" i], li"
    ]

    private struct Rule {
        var selector: String
        var body: String
    }

    private static func adapt(_ css: String, area: ReviewPanelCSSArea, isNight: Bool) -> String {
        let rules = parseRules(stripComments(css), isNight: isNight)
        var output: [String] = []
        for rule in rules {
            guard !rule.body.isEmpty else { continue }
            if isUnsupported(selector: rule.selector, body: rule.body) { continue }
            let expanded = expandSelectors(rule.selector, area: area)
            let (declarations, extraRules) = adaptDeclarations(rule.body, selector: expanded)
            if !declarations.isEmpty {
                output.append("\(expanded) { \(declarations) }")
            }
            output.append(contentsOf: extraRules)
        }
        return output.joined(separator: "\n")
    }

    private static func stripComments(_ css: String) -> String {
        var result = ""
        var inComment = false
        let chars = Array(css)
        var i = 0
        while i < chars.count {
            if !inComment, i + 1 < chars.count, chars[i] == "/", chars[i + 1] == "*" {
                inComment = true
                i += 2
                continue
            }
            if inComment, i + 1 < chars.count, chars[i] == "*", chars[i + 1] == "/" {
                inComment = false
                i += 2
                continue
            }
            if !inComment { result.append(chars[i]) }
            i += 1
        }
        return result
    }

    /// 字符级解析：支持顶层裸声明、嵌套规则、`@dark` / `@light` 条件块。
    /// 条件块按当前日夜模式只保留匹配分支，整块（含子规则）跳过不匹配分支。
    private static func parseRules(_ css: String, isNight: Bool) -> [Rule] {
        struct Frame {
            var selector: String
            var body: String
            var active: Bool
        }
        var rules: [Rule] = []
        var stack: [Frame] = []
        var token = ""

        func splitToken(_ text: String) -> (declarations: String, selector: String) {
            guard let last = text.lastIndex(of: ";") else { return ("", text) }
            return (String(text[...last]), String(text[text.index(after: last)...]))
        }

        for ch in css {
            if ch == "{" {
                let split = splitToken(token)
                token = ""
                if !stack.isEmpty {
                    stack[stack.count - 1].body += split.declarations
                } else {
                    // 规则块之前的顶层裸声明，Cay 允许直接写，别丢掉。
                    let bare = split.declarations.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !bare.isEmpty { rules.append(Rule(selector: "", body: bare)) }
                }
                let selector = split.selector.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = selector.lowercased()
                let isCondition = lower.hasPrefix("@dark") || lower.hasPrefix("@light")
                let parentActive = stack.last?.active ?? true
                let active: Bool
                if lower.hasPrefix("@dark") { active = parentActive && isNight }
                else if lower.hasPrefix("@light") { active = parentActive && !isNight }
                else if selector.hasPrefix("@") { active = false }
                else { active = parentActive }
                stack.append(Frame(
                    selector: isCondition ? "" : selector,
                    body: "",
                    active: active
                ))
            } else if ch == "}" {
                guard let frame = stack.popLast() else { continue }
                let body = (frame.body + token).trimmingCharacters(in: .whitespacesAndNewlines)
                token = ""
                guard frame.active, !body.isEmpty else { continue }
                if frame.selector.isEmpty {
                    // @dark / @light 里的顶层裸声明，作用于整体。
                    rules.append(Rule(selector: "", body: body))
                } else {
                    let parent = stack.last?.selector ?? ""
                    let full = parent.isEmpty ? frame.selector : parent + " " + frame.selector
                    rules.append(Rule(selector: full, body: body))
                }
            } else {
                token.append(ch)
            }
        }
        let tail = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            rules.append(Rule(selector: "", body: tail))
        }
        return rules
    }

    private static func isUnsupported(selector: String, body: String) -> Bool {
        let combined = selector + " " + body
        let markers = [
            "-cay-bubble", "-cay-text-background", "::match(", "@js", "js(",
            "attr(", "{{", ":if(", "[count", "[text", ":not(", ":is(", ":where(",
            "url(asset:", "env(safe", "@media", "@supports", "@container", "@layer"
        ]
        return markers.contains { combined.contains($0) }
    }

    /// 选择器展开 + 区域前缀。空选择器（顶层裸声明）作用于整个网页。
    /// 用占位符替换，避免 .note 把已展开的 .note-label 再次切碎。
    private static func expandSelectors(_ raw: String, area: ReviewPanelCSSArea) -> String {
        let root = "html.yd-review-root"
        if raw.isEmpty {
            switch area {
            case .panel, .comment: return "\(root) body"
            case .hot:
                // 所有点开评论后弹出的面板共用同一套样式：热评这段不再只作用于
                // 靠关键词打标出来的节点，通用评论卡片容器一并兜底，任何书源网页都吃得到。
                return "\(root) .yd-area-hot, \(root) .cay-label, \(root) .cay-card, \(root) .card, \(root) li, \(root) section"
            case .chapterNote:
                // 同上：本章说 / 作者说这段无条件覆盖每个评论面板的卡片区。
                return "\(root) .yd-area-chapter, \(root) .cay-note, \(root) .cay-card, \(root) .card, \(root) li, \(root) section"
            }
        }

        var parts: [String] = []
        let sortedKeys = selectorAliases.keys.sorted { $0.count > $1.count }
        for piece in raw.split(separator: ",", omittingEmptySubsequences: true) {
            let selector = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selector.isEmpty else { continue }
            var replaced = selector
            var aliasesByMark: [String: String] = [:]
            for (index, key) in sortedKeys.enumerated() {
                guard let alias = selectorAliases[key] else { continue }
                let mark = "\u{1}\(index)\u{1}"
                if replaced.contains(key) {
                    replaced = replaced.replacingOccurrences(of: key, with: mark)
                    aliasesByMark[mark] = alias
                }
            }
            for (mark, alias) in aliasesByMark {
                replaced = replaced.replacingOccurrences(of: mark, with: alias)
            }
            // 别名展开后每个候选都补上根前缀，避免后面的裸类选择器优先级过低，
            // 被段评页透明背景脚本的 !important 规则盖掉。
            let candidates = replaced.split(separator: ",", omittingEmptySubsequences: true)
                .map { "\(root) \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            parts.append(candidates.joined(separator: ", "))
        }
        return parts.isEmpty ? "\(root) body" : parts.joined(separator: ", ")
    }

    /// 声明体降级：玻璃、行数、字重、边框、content 改标签文字，并统一 !important。
    /// 返回主声明与额外的 ::after 规则。
    private static func adaptDeclarations(_ body: String, selector: String) -> (String, [String]) {
        let entries = body.split(separator: ";", omittingEmptySubsequences: true)
        var declarations: [String] = []
        var extraRules: [String] = []
        var contentText: String?
        var contentFontSize = "14px"

        for entry in entries {
            let raw = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let colon = raw.firstIndex(of: ":") else { continue }
            let property = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if property.isEmpty || value.isEmpty { continue }
            if property.hasPrefix("--") {
                declarations.append("\(property): \(value) !important")
                continue
            }

            if property == "text-background" || property == "-cay-text-background" || property == "mark" ||
                property.hasPrefix("-cay-bubble") || property == "max-lines" ||
                property == "columns" || property == "baseline-shift" || property == "vertical-align" ||
                property == "size" || property == "order" || property == "text-stroke" {
                continue
            }
            if property == "line-clamp" || property == "-webkit-line-clamp" {
                declarations.append("-webkit-line-clamp: \(value) !important")
                declarations.append("display: -webkit-box !important")
                declarations.append("-webkit-box-orient: vertical !important")
                declarations.append("overflow: hidden !important")
                continue
            }
            // content: "文字" —— 浏览器只在伪元素上支持，转成 ::after 追加并隐藏原文。
            if property == "content" {
                let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !unquoted.isEmpty, unquoted != "none" { contentText = unquoted }
                continue
            }
            // background: glass / liquid-glass。
            if property == "background" || property == "background-color" {
                let lower = value.lowercased()
                if lower == "glass" || lower == "liquid-glass" {
                    declarations.append("background: rgba(255, 255, 255, 0.16) !important")
                    declarations.append("backdrop-filter: blur(18px) !important")
                    declarations.append("-webkit-backdrop-filter: blur(18px) !important")
                    continue
                }
            }
            if property == "font-weight" {
                if value == "semibold" { value = "600" }
                if value == "bold" { value = "700" }
            }
            if property == "font-family" {
                if value == "serif" { value = "ui-serif, 'Songti SC', serif" }
                if value == "rounded" { value = "ui-rounded, system-ui" }
                if value == "monospace" { value = "ui-monospace, monospace" }
            }
            if property == "font-size" { contentFontSize = value }
            if property == "border", value.split(separator: " ").count == 2,
               !value.contains("solid"), !value.contains("dashed"), !value.contains("dotted") {
                value += " solid"
            }
            declarations.append("\(property): \(value) !important")
        }

        if let text = contentText, !text.isEmpty {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            declarations.append("font-size: 0 !important")
            let afterSelectors = selector.split(separator: ",")
                .map { "\($0.trimmingCharacters(in: .whitespacesAndNewlines))::after" }
                .joined(separator: ", ")
            extraRules.append(
                "\(afterSelectors) { content: \"\(escaped)\" !important; " +
                "font-size: \(contentFontSize) !important; display: inline-block !important; }"
            )
        }
        return (declarations.joined(separator: "; "), extraRules)
    }
}
