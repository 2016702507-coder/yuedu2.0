import Foundation

/// 点开本章说 / 热评 / 作者说 / 段评时弹出的「孤岛段评面板」。
///
/// 与旧做法的根本区别：**不再往书源网页上刷 CSS**。书源网页那套 UI（tab、神评、
/// 默认/热/最新、重复标题）整个被移进一个隐藏容器，用户看到的只有一个由这里
/// 生成的独立面板。书源自己的 JS、登录态、java.ajax 照常跑在隐藏容器里，评论数据
/// 从那边抽出来喂给面板；DOM 节点仍在，书源脚本后续追加的内容也能被继续抽取。
///
/// 透明由 Swift 侧的 `ParagraphReviewVeil` 纯色蒙版负责（外观 › 界面效果，默认 0.06），
/// 这里生成的 DOM 自身完全不带底色、不用 blur、不画阴影——`transparentBackgroundScript`
/// 会强制关掉 backdrop-filter，模糊只会把下方正文糊成雾。文字保持不透明以确保可读。
enum IslandReviewPanel {

    /// 生成 `atDocumentStart` 注入的脚本。
    /// - Parameters:
    ///   - isNight: 当前日夜模式，决定文字与分隔线配色。
    ///   - title: 面板标题（通常取 `ReviewTarget.title`，已本地化过）。
    ///   - customCSS: 用户在「段评样式」里编辑的 CSS。只作用于本面板，且先剔除
    ///     `content:` 改字声明——那正是上一版「本章热议」重复四次的元凶。
    static func installScript(isNight: Bool, title: String, customCSS: String) -> String {
        let modeLiteral = javaScriptStringLiteral(isNight ? "dark" : "light")
        let titleLiteral = javaScriptStringLiteral(title)
        let cssLiteral = javaScriptStringLiteral(sanitizedCSS(customCSS))

        // Swift raw string：JS 里的正则反斜杠无需转义，插值用 \#(...)。
        return #"""
        (function () {
            var PANEL_ID = '__yd_island_panel__';
            var SRC_ID   = '__yd_source_root__';
            var STYLE_ID = '__yd_island_style__';
            var MODE     = \#(modeLiteral);
            var TITLE    = \#(titleLiteral);
            var CUSTOM   = \#(cssLiteral);
            var DARK     = MODE === 'dark';

            var C = DARK ? {
                ink:    '#ECECEC',
                sub:    '#9A958F',
                line:   'rgba(255,255,255,.13)',
                quote:  'rgba(255,255,255,.07)',
                chip:   'rgba(240,128,95,.20)',
                chipfg: '#F0A078',
                av:     'rgba(255,255,255,.16)',
                img:    'rgba(255,255,255,.08)',
                // 面板自带半透明底：全透会让背后正文和评论文字直接叠在一起没法读。
                // 只用纯色、不加模糊——模糊会把正文糊成一层「雾」。
                sheet:  'rgba(26,25,26,.78)',
                // 文字所在的块（标题 / 引用 / 评论卡片 / 输入框）再垫一层实底，
                // 保证评论文字绝对清晰；空隙处才让背景明显透出来。
                card:   'rgba(32,31,32,.94)'
            } : {
                ink:    '#262626',
                sub:    '#86827C',
                line:   'rgba(60,55,48,.12)',
                quote:  'rgba(120,110,95,.10)',
                chip:   'rgba(232,99,63,.14)',
                chipfg: '#C05A30',
                av:     'rgba(60,55,48,.12)',
                img:    'rgba(60,55,48,.08)',
                sheet:  'rgba(255,255,255,.80)',
                card:   'rgba(255,255,255,.95)'
            };

            var rendering = false;
            var sweeping  = false;
            var timer     = null;
            var started   = false;

            function esc(s) {
                return String(s == null ? '' : s)
                    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
                    .replace(/>/g, '&gt;').replace(/"/g, '&quot;')
                    .replace(/'/g, '&#39;');
            }
            // 原 DOM 收进 display:none 的隐藏层后 innerText 会退化成没有换行的
            // textContent，所有评论文字会连成一坨。这里按块级标签自己拼行，
            // 保证隐藏层里也能读出「昵称 / 正文 / 时间」这些独立行。
            function txt(el) {
                if (!el) return '';
                var parts = [];
                function walk(n) {
                    if (n.nodeType === 3) { parts.push(n.nodeValue); return; }
                    if (n.nodeType !== 1) return;
                    var tag = n.tagName;
                    if (/^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(tag)) return;
                    if (tag === 'BR') { parts.push('\n'); return; }
                    for (var i = 0; i < n.childNodes.length; i++) walk(n.childNodes[i]);
                    // 按标签而不是 CSS display 分行：隐藏层里 innerText 会把
                    // inline-block 的昵称/等级、时间/赞/回复挤成同一行。
                    if (/^(DIV|P|LI|ARTICLE|SECTION|H[1-6]|UL|OL|TR|TD|BLOCKQUOTE|TIME|SMALL|BUTTON|HEADER|FOOTER|ASIDE|MAIN)$/.test(tag)) {
                        parts.push('\n');
                    }
                }
                for (var i = 0; i < el.childNodes.length; i++) walk(el.childNodes[i]);
                var lines = parts.join('').split(/\n+/).map(function (s) { return s.trim(); })
                    .filter(function (s) { return s.length; });
                if (lines.length >= 2) return lines.join('\n');
                var own = (el.innerText || '').trim();
                if (own && own.indexOf('\n') >= 0) return own;
                if (lines.length === 1) return lines[0];
                return (el.textContent || '').trim();
            }
            function cls(el) {
                return String((el && el.className) || '');
            }
            function isVisible(el) {
                try {
                    var s = window.getComputedStyle(el);
                    if (!s) return false;
                    if (s.display === 'none' || s.visibility === 'hidden') return false;
                    if (parseFloat(s.opacity || '1') < 0.05) return false;
                    // 隐藏层内的元素没有几何尺寸，跳过尺寸判定（否则一条都抽不到）。
                    if (el.closest && el.closest('#' + SRC_ID)) return true;
                    var r = el.getBoundingClientRect();
                    if (r.width < 8 || r.height < 6) return false;
                    return true;
                } catch (e) { return false; }
            }

            // MARK: - 样式（面板自身全透明，靠 Swift 侧蒙版压亮度）

            function cssText() {
                return [
                    'html,body{background:transparent !important;background-color:transparent !important;margin:0 !important;padding:0 !important;}',
                    '#' + SRC_ID + '{display:none !important;}',
                    '#' + PANEL_ID + '{',
                    '  position:relative;width:100%;box-sizing:border-box;',
                    '  padding:0 0 26px;',
                    '  background:' + C.sheet + ' !important;',
                    '  border-radius:22px 22px 0 0;',
                    '  color:' + C.ink + ' !important;',
                    '  font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Noto Sans CJK SC",sans-serif;',
                    '  -webkit-font-smoothing:antialiased;',
                    '}',
                    '#' + PANEL_ID + ' *{box-sizing:border-box;}',
                    '#' + PANEL_ID + ' .ydi-grab{width:36px;height:4px;border-radius:4px;',
                    '  background:' + C.line + ' !important;margin:10px auto 2px;}',
                    '#' + PANEL_ID + ' .ydi-hd{margin:0 12px 10px;padding:10px 0 12px;',
                    '  border-radius:14px;background:' + C.card + ' !important;',
                    '  text-align:center;font-size:15px;font-weight:600;color:' + C.ink + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-q{margin:0 12px 10px;padding:11px 13px;border-radius:14px;',
                    '  background:' + C.card + ' !important;font-size:13px;line-height:1.6;',
                    '  color:' + C.sub + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-c{margin:0 12px 10px;padding:12px 13px 11px;',
                    '  border-radius:14px;background:' + C.card + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-u{display:flex;align-items:center;gap:8px;margin-bottom:8px;}',
                    '#' + PANEL_ID + ' .ydi-av{width:30px;height:30px;flex:0 0 30px;border-radius:50%;',
                    '  object-fit:cover;background:' + C.av + ' !important;color:' + C.ink + ';',
                    '  font-size:13px;display:flex;align-items:center;justify-content:center;}',
                    '#' + PANEL_ID + ' .ydi-av-ph{width:30px;height:30px;flex:0 0 30px;border-radius:50%;',
                    '  background:' + C.av + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-nm{font-size:13px;font-weight:600;color:' + C.ink + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-lv{font-size:10px;padding:1px 6px;border-radius:4px;',
                    '  background:' + C.chip + ' !important;color:' + C.chipfg + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-tx{font-size:13px;line-height:1.7;margin:0 0 9px;',
                    '  color:' + C.ink + ' !important;word-break:break-word;}',
                    '#' + PANEL_ID + ' .ydi-img{display:block;width:150px;max-width:60%;height:96px;',
                    '  object-fit:cover;border-radius:8px;background:' + C.img + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-rep{margin:9px 0 0;padding:8px 10px;border-radius:8px;',
                    '  background:' + C.quote + ' !important;font-size:12px;color:' + C.sub + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-meta{display:flex;justify-content:space-between;gap:10px;',
                    '  font-size:11px;color:' + C.sub + ' !important;margin-top:9px;}',
                    '#' + PANEL_ID + ' .ydi-in{margin:2px 12px 0;border:1px solid ' + C.line + ';',
                    '  border-radius:999px;padding:10px 14px;background:' + C.card + ' !important;',
                    '  font-size:12px;color:' + C.sub + ' !important;}',
                    '#' + PANEL_ID + ' .ydi-empty{text-align:center;padding:34px 20px;',
                    '  font-size:13px;color:' + C.sub + ' !important;}'
                ].join('\n');
            }

            function installStyle() {
                var head = document.head || document.documentElement;
                if (!head) return;
                var style = document.getElementById(STYLE_ID);
                if (!style) {
                    style = document.createElement('style');
                    style.id = STYLE_ID;
                    head.appendChild(style);
                }
                // 必须排在最后：透明背景脚本用 !important 清底色，同优先级下后写的胜出。
                style.textContent = cssText() + '\n' + CUSTOM;
                if (head.lastChild !== style) head.appendChild(style);
            }

            // MARK: - 把书源原 UI 收进隐藏容器（节点保留，书源 JS 继续可用）

            function ensureSourceRoot() {
                var src = document.getElementById(SRC_ID);
                if (src) return src;
                src = document.createElement('div');
                src.id = SRC_ID;
                src.style.setProperty('display', 'none', 'important');
                var panel = document.getElementById(PANEL_ID);
                var nodes = [].slice.call(document.body.childNodes);
                for (var i = 0; i < nodes.length; i++) {
                    var n = nodes[i];
                    if (n === panel) continue;
                    src.appendChild(n);
                }
                document.body.insertBefore(src, document.body.firstChild);
                return src;
            }

            // 书源 ajax 之后新插进 body 的节点，也要收进去，否则旧界面会露出来。
            function sweep() {
                var src = document.getElementById(SRC_ID);
                if (!src) return;
                sweeping = true;
                try {
                    var kids = [].slice.call(document.body.children);
                    for (var i = 0; i < kids.length; i++) {
                        var n = kids[i];
                        if (n === src || n.id === PANEL_ID || n.id === STYLE_ID) continue;
                        if (n.tagName === 'SCRIPT' || n.tagName === 'STYLE' || n.tagName === 'LINK') continue;
                        src.appendChild(n);
                    }
                } finally { sweeping = false; }
            }

            // MARK: - 从书源 DOM 抽评论（不依赖具体 class 名，靠重复结构聚类）

            // 签名只按「标签 + 类名 + 子元素数」分组，不带文本长度：
            // 同类评论卡片的正文长短不一，带上长度会把它们拆成好几个组，
            // 结果反而选中内部那个只有正文的 .content 组，昵称头像全丢。
            function signature(el) {
                // 子元素数只取粗档：有的评论带配图有的不带，精确计数会把
                // 同一模板渲染的卡片拆成两组，晚到的一条就抽不到。
                return el.tagName + '|' + cls(el).slice(0, 70) + '|' +
                       Math.min(el.children.length, 4);
            }

            function candidates(root) {
                var all = root.querySelectorAll('div,li,article,section,tr,p');
                var out = [];
                for (var i = 0; i < all.length; i++) {
                    var el = all[i];
                    if (!isVisible(el)) continue;
                    var t = txt(el);
                    if (t.length < 14 || t.length > 1500) continue;
                    if (/<(script|style)/i.test(el.innerHTML || '')) {
                        // 仍允许：内层脚本常见于模板页
                    }
                    out.push(el);
                }
                return out;
            }

            function pickCards(root) {
                var groups = {};
                var list = candidates(root);
                for (var i = 0; i < list.length; i++) {
                    var el = list[i];
                    var k = signature(el);
                    (groups[k] = groups[k] || []).push(el);
                }
                var best = [], bestScore = 0;
                Object.keys(groups).forEach(function (k) {
                    var g = groups[k];
                    if (g.length < 2 || g.length > 80) return;
                    var total = 0;
                    for (var t = 0; t < g.length; t++) total += txt(g[t]).length;
                    var avg = total / g.length;
                    if (avg < 16) return;
                    // 组里元素互不嵌套，才算同一层卡片（而不是外层列表 + 内层块）
                    var nested = 0;
                    for (var a = 0; a < g.length && a < 6; a++) {
                        for (var b = 0; b < g.length && b < 6; b++) {
                            if (a !== b && g[a].contains(g[b])) nested++;
                        }
                    }
                    if (nested > 2) return;
                    // 评论卡片通常子元素更多、文本更长、还带时间/赞/回复；
                    // 只比数量会选到「每条正文 div」这种只有一行字的组。
                    var children = g[0].children.length;
                    var score = g.length * (1 + Math.min(children, 8) * 0.6) * (avg >= 30 ? 1.4 : 1);
                    if (/(赞|回复|·|前|昨天|去年|刚刚)/.test(txt(g[0]))) score *= 1.5;
                    if (score > bestScore) { bestScore = score; best = g; }
                });
                return best.slice(0, 60);
            }

            var TIME_RE = /(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}|\d+\s*(分钟|小时|天|月|年)前|昨天|前天|去年|刚刚|今天)/;
            var LEVEL_RE = /^(神评|热评|精选|精华|置顶|沙发|LV\.?\s*\d+|Lv\.?\s*\d+|V\d+|等级\s*\d+|楼主|作者)/i;
            // 「神评 / 热评」不列在这里：它们在评论卡片里是等级徽章，要留给 LEVEL_RE。
            var BAD_LINE = /^(本章热议|本章说|段评|全部|默认|最新|最热|热度|回复|点赞|查看更多|加载更多|上一页|下一页|登录|注册|收起|展开|全部评论|评论列表|写评论|发表|排序|筛选)$/;

            function imgSrc(im) {
                return im.getAttribute('src') || im.getAttribute('data-src') ||
                       im.getAttribute('data-original') || im.getAttribute('data-lazy-src') || '';
            }

            function parseCard(el) {
                var imgs = [].slice.call(el.querySelectorAll('img'));
                var avatar = '', photo = '';
                for (var i = 0; i < imgs.length; i++) {
                    var im = imgs[i], s = imgSrc(im);
                    if (!s || /^data:/i.test(s) || /\.(svg|gif)(\?|$)/i.test(s)) continue;
                    var hint = cls(im) + ' ' + (im.getAttribute('alt') || '');
                    if (/avatar|face|head|portrait|touxiang|头像|user/i.test(hint)) {
                        if (!avatar) avatar = s;
                    } else if (!photo) { photo = s; }
                }
                if (!avatar && imgs.length) {
                    for (var j = 0; j < imgs.length; j++) {
                        var s2 = imgSrc(imgs[j]);
                        if (s2 && !/^data:/i.test(s2)) { avatar = s2; break; }
                    }
                }
                if (avatar && avatar === photo) photo = '';

                var lines = txt(el).split(/\n+/).map(function (s) { return s.trim(); })
                    .filter(function (s) { return s.length > 0; });
                var name = '', level = '', content = '', meta = '', likes = '', replies = '', rep = '';

                for (var k = 0; k < lines.length; k++) {
                    var L = lines[k];
                    if (BAD_LINE.test(L)) continue;
                    if (!name && L.length <= 20 && !TIME_RE.test(L) && !/^\d+$/.test(L) &&
                        !/[赞回复条]$/.test(L) && !/[：:]/.test(L)) {
                        name = L; continue;
                    }
                    if (!level && LEVEL_RE.test(L) && L.length <= 12) { level = L; continue; }
                    if (TIME_RE.test(L) || /(赞|回复|·|IP|属地|来自)/.test(L)) {
                        var m = L.match(/(\d+)\s*(?:个赞|赞|likes?)/i);
                        if (m) likes = m[1];
                        var r = L.match(/(\d+)\s*条?回复|回复\s*(\d+)/);
                        if (r) replies = r[1] || r[2];
                        if (L.length <= 60) { meta = meta ? meta : L; continue; }
                    }
                    if (/^回复\s*[^：:]+[：:]/.test(L) && !rep) { rep = L; continue; }
                    if (L.length > content.length && L.length <= 600) content = L;
                }
                if (!content && lines.length) {
                    for (var q = 0; q < lines.length; q++) {
                        if (lines[q].length >= 8 && !BAD_LINE.test(lines[q])) { content = lines[q]; break; }
                    }
                }
                return {
                    avatar: avatar, photo: photo, name: name || '书友', level: level,
                    content: content, meta: meta, likes: likes, replies: replies, rep: rep
                };
            }

            // 聚类失败时的兜底：把可见文本里像评论的长行当成评论，保证面板不空。
            function fallbackCards(root) {
                var lines = txt(root).split(/\n+/).map(function (s) { return s.trim(); });
                var out = [];
                for (var i = 0; i < lines.length && out.length < 20; i++) {
                    var L = lines[i];
                    if (L.length < 8 || L.length > 400 || BAD_LINE.test(L)) continue;
                    if (TIME_RE.test(L) && L.length < 30) continue;
                    out.push({ avatar: '', photo: '', name: '书友', level: '', content: L,
                               meta: '', likes: '', replies: '', rep: '' });
                }
                return out;
            }

            function quoteText(root) {
                var q = root.querySelector('blockquote,[class*="quote" i],[class*="origin" i],[class*="source-text" i],[id*="quote" i]');
                if (q) {
                    var t = txt(q);
                    if (t.length >= 2 && t.length <= 160) return t;
                }
                return '';
            }

            // MARK: - 渲染

            function cardHTML(c) {
                var av = c.avatar
                    ? '<img class="ydi-av" src="' + esc(c.avatar) + '" alt="">'
                    : '<span class="ydi-av ydi-av-ph">' + esc(c.name.slice(0, 1)) + '</span>';
                var right = [];
                if (c.likes) right.push(c.likes + ' 赞');
                if (c.replies) right.push(c.replies + ' 条回复');
                return '<div class="ydi-c card cay-card yd-area-comment">' +
                    '<div class="ydi-u">' + av +
                        '<span class="ydi-nm user cay-user">' + esc(c.name) + '</span>' +
                        (c.level ? '<span class="ydi-lv label cay-label">' + esc(c.level) + '</span>' : '') +
                    '</div>' +
                    (c.content ? '<div class="ydi-tx text cay-text">' + esc(c.content) + '</div>' : '') +
                    (c.photo ? '<img class="ydi-img" src="' + esc(c.photo) + '" alt="">' : '') +
                    (c.rep ? '<div class="ydi-rep note cay-note">' + esc(c.rep) + '</div>' : '') +
                    '<div class="ydi-meta"><span class="time cay-time">' + esc(c.meta) + '</span>' +
                        '<span class="likes cay-likes">' + esc(right.join('　')) + '</span></div>' +
                '</div>';
            }

            function render(cards, quote) {
                var panel = document.getElementById(PANEL_ID);
                if (!panel) {
                    panel = document.createElement('div');
                    panel.id = PANEL_ID;
                    document.body.appendChild(panel);
                }
                rendering = true;
                try {
                    var body = cards.length
                        ? cards.map(cardHTML).join('')
                        : '<div class="ydi-empty">暂无评论</div>';
                    panel.innerHTML =
                        '<div class="ydi-grab"></div>' +
                        '<div class="ydi-hd header cay-header">' + esc(TITLE || '段评') + '</div>' +
                        (quote ? '<div class="ydi-q quote cay-quote">' + esc(quote) + '</div>' : '') +
                        '<div class="ydi-list">' + body + '</div>' +
                        '<div class="ydi-in">说点什么…</div>';
                } finally {
                    setTimeout(function () { rendering = false; }, 0);
                }
            }

            function refresh() {
                if (!document.body) return;
                installStyle();
                var src = ensureSourceRoot();
                sweep();
                var cards = pickCards(src).map(parseCard).filter(function (c) {
                    return c.content && c.content.length >= 2;
                });
                if (!cards.length) cards = fallbackCards(src);
                render(cards, quoteText(src));
            }

            function start() {
                if (started || !document.body) return;
                started = true;
                refresh();
                try {
                    // 只盯 body 的「直接子节点」：书源 ajax 之后新插进来的节点要收进隐藏层。
                    // 不观察 body 的 subtree，否则 render() 改写 panel.innerHTML 会自己触发自己。
                    var bodyMo = new MutationObserver(function () {
                        if (rendering || sweeping) return;
                        sweep();
                        clearTimeout(timer);
                        timer = setTimeout(function () { refresh(); }, 320);
                    });
                    bodyMo.observe(document.body, { childList: true, subtree: false });

                    // 隐藏层内部（书源把评论插回它原来的容器）变化时重新抽取。
                    var srcEl = document.getElementById(SRC_ID);
                    if (srcEl) {
                        var srcMo = new MutationObserver(function () {
                            if (rendering || sweeping) return;
                            clearTimeout(timer);
                            timer = setTimeout(function () { refresh(); }, 320);
                        });
                        srcMo.observe(srcEl, { childList: true, subtree: true });
                    }
                } catch (e) {}
                // ajax 晚到 / 首屏尚未渲染完：补几次，之后交给 MutationObserver。
                [250, 700, 1500, 3000].forEach(function (ms) {
                    setTimeout(function () { if (!rendering) refresh(); }, ms);
                });
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', start, { once: true });
            } else {
                start();
            }
            window.addEventListener('load', function () { setTimeout(start, 60); });
        })();
        """#
    }

    /// 把 Swift 字符串变成安全的 JS 字符串字面量。
    /// `ReviewPanelCSSBridge` / `JsBridgeBrowserView` 里的同名函数是各自的私有成员，
    /// 这里不能跨类型调用，故自带一份。
    private static func javaScriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        // JSON 字符串与 JS 字符串字面量兼容；额外防住 </script> 提前闭合。
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }

    /// 自定义 CSS 只保留视觉声明。`content:` 会改掉面板里的文字（上一版「本章热议」
    /// 重复四次就是它造成的），必须剔除；`@dark` / `@light` 由 `browserCSS` 先处理过。
    private static func sanitizedCSS(_ css: String) -> String {
        guard !css.isEmpty else { return "" }
        var out = css
        if let re = try? NSRegularExpression(
            pattern: #"content\s*:\s*(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^;}]*)\s*;?"#,
            options: [.caseInsensitive]
        ) {
            out = re.stringByReplacingMatches(
                in: out, options: [], range: NSRange(out.startIndex..., in: out), withTemplate: ""
            )
        }
        // 面板里的节点带了 .user/.text/.quote/.card 等语义类，自定义 CSS 能命中；
        // 但旧模板里的 .yd-area-* 裸声明可能带 position 之类，限定作用域避免影响整页。
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
