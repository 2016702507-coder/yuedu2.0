import Foundation

/// 点开本章说 / 热评 / 作者说 / 段评时弹出的面板。
///
/// 做法对齐孤岛（Cay / Leaflow）：**书源给的段评页原样显示，一个节点都不动。**
///
/// 早先两版都栽在同一件事上：想把网页「重排成」孤岛的样子——
/// 第一版往页面里刷 CSS 改字，刷出四个「本章热议」；
/// 第二版把评论 DOM 克隆出来按头像 / 昵称 / 正文重新拼卡片，
/// 结果头像圈套到了配图上、正文压在图片底下、楼中楼整块消失。
/// 书源页面本来就是各家自己写的 HTML，布局各不相同，
/// 任何「猜结构再重画」都必然在某些页面上翻车。
///
/// 孤岛之所以好看，是因为它把书源 `showChapterComments` 返回的那段 HTML
/// 直接用 `loadHTMLString` 显示（它自己日志里写作 inline html mode），
/// 排版、头像圈、等级标签、点赞、楼中楼全是那段 HTML 自带的样式。
///
/// 所以这里只做三件不碰结构的事：
/// 1. 让页面最底层透明，好让 sheet 的毛玻璃透出阅读器正文；
/// 2. 图片最大宽度限制在容器内，避免一张大图把卡片撑破；
/// 3. 把用户在「段评样式」里写的字号 / 行距 / 颜色注入进去（默认关闭）。
enum IslandReviewPanel {

    /// 生成 `atDocumentStart` 注入的脚本。
    /// - Parameters:
    ///   - isNight: 当前日夜模式，只用于挂 `yd-dark` / `yd-light` 类名。
    ///   - title: 预留参数，页面不改字，保持签名兼容。
    ///   - customCSS: 用户在「段评样式」里编辑的 CSS；为空时什么都不注入。
    static func installScript(isNight: Bool, title: String, customCSS: String) -> String {
        let modeLiteral = javaScriptStringLiteral(isNight ? "dark" : "light")
        let cssLiteral = javaScriptStringLiteral(sanitizedCSS(customCSS))

        return #"""
        (function () {
            var STYLE_ID = '__yd_panel_style__';
            var MODE = \#(modeLiteral);
            var CSS = \#(cssLiteral);

            var root = document.documentElement;
            if (root) {
                root.classList.add('yd-review-root');
                root.classList.add(MODE === 'dark' ? 'yd-dark' : 'yd-light');
                root.classList.remove(MODE === 'dark' ? 'yd-light' : 'yd-dark');
            }

            function install() {
                var head = document.head || document.documentElement;
                if (!head) return;
                var style = document.getElementById(STYLE_ID);
                if (!style) {
                    style = document.createElement('style');
                    style.id = STYLE_ID;
                    head.appendChild(style);
                }

                // 只有这三类规则。结构、层级、卡片底色一律不碰。
                var rules = [
                    // 大图不许撑破卡片；小头像不会被放大（max-* 只缩不放）。
                    'img,video{max-width:100% !important;height:auto !important;}',
                    // 长链接、长数字不许把卡片顶宽。
                    'body{overflow-x:hidden !important;word-break:break-word;}'
                ];
                if (CSS && CSS.length) rules.push(CSS);
                var text = rules.join('\n');
                if (style.textContent !== text) style.textContent = text;
                if (head.lastChild !== style) head.appendChild(style);
            }

            install();
            document.addEventListener('DOMContentLoaded', install, { once: true });
            window.addEventListener('load', function () { install(); setTimeout(install, 300); });
        })();
        """#
    }

    /// 把 Swift 字符串变成安全的 JS 字符串字面量。
    private static func javaScriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }

    /// 自定义 CSS 只留「字号 / 行距 / 字体 / 颜色 / 间距」。
    ///
    /// `content:` 会改掉页面上的文字（上一版「本章热议」重复四次就是它）；
    /// `background*` 一刷就把书源卡片底和毛玻璃一起糊成实心板；
    /// `backdrop-filter` 在已经模糊的 sheet 上再糊一层，字会发虚。
    private static func sanitizedCSS(_ css: String) -> String {
        guard !css.isEmpty else { return "" }
        var out = css
        let patterns = [
            #"content\s*:\s*(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^;}]*)\s*;?"#,
            #"background(-color|-image|-repeat|-size|-position|-attachment)?\s*:\s*[^;}]*;?"#,
            #"(?:-webkit-)?backdrop-filter\s*:\s*[^;}]*;?"#,
            #"(?:-webkit-)?box-shadow\s*:\s*[^;}]*;?"#
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            out = re.stringByReplacingMatches(
                in: out, options: [], range: NSRange(out.startIndex..., in: out), withTemplate: ""
            )
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
