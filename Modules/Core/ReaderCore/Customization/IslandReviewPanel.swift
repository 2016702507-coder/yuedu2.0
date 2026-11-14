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

                // 结构、层级、卡片底色一律不碰。
                var rules = [
                    // 只限制宽度上限：大图不会撑破卡片，小头像也不会被放大。
                    // 不写 `height:auto`：书源若给图片设了固定高度，强改会变形。
                    'img,video{max-width:100% !important;}',
                    // 长链接、长数字不许把卡片顶宽（只作用在滚动容器上，不动排版）。
                    'body{overflow-x:hidden !important;}',
                    // 页面底层必须透明：书源段评页几乎都自带白底，那层白把面板
                    // 玻璃整个盖住——半屏也是白的（跟 detent 无关），而且是
                    // 「加载完才白」（网页渲染出来之前玻璃是看得见的）。
                    // 只清 html/body 的底，卡片自己的底色不动。
                    'html,body{background:transparent !important;background-color:transparent !important;background-image:none !important;}'
                ];
                if (CSS && CSS.length) rules.push(CSS);
                var text = rules.join('\n');
                if (style.textContent !== text) style.textContent = text;
                if (head.lastChild !== style) head.appendChild(style);
            }

            // html/body 之外，书源页面常在外面再套一层铺满视口的容器
            // （列表壳、内容容器），那层白同样盖住玻璃。这里只清「几乎铺满
            // 视口」的大块底：卡片、头像、按钮这类小块元素一律不碰。
            function clearShellBackdrops() {
                try {
                    var vw = window.innerWidth || 375;
                    var vh = window.innerHeight || 800;
                    var els = document.querySelectorAll('body, body *');
                    for (var i = 0; i < els.length; i++) {
                        var el = els[i];
                        if (!el || el.id === STYLE_ID) continue;
                        var r = el.getBoundingClientRect();
                        if (r.width >= vw * 0.9 && r.height >= vh * 0.3) {
                            el.style.setProperty('background-color', 'transparent', 'important');
                            el.style.setProperty('background-image', 'none', 'important');
                        }
                    }
                } catch (e) {}
            }

            function installAll() {
                install();
                clearShellBackdrops();
            }

            installAll();
            document.addEventListener('DOMContentLoaded', installAll, { once: true });
            window.addEventListener('load', function () {
                installAll();
                setTimeout(installAll, 300);
                setTimeout(installAll, 1200);
            });
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
