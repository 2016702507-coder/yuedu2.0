import Foundation

/// 点开本章说 / 热评 / 作者说 / 段评时弹出的「段评面板」。
///
/// 做法：**不重排文字，只搬结构**。
/// 书源网页那套 UI（tab、排序、输入框、页头）整个收进 `display:none` 的隐藏层，
/// 书源自己的 JS / 登录态 / java.ajax 照常在隐藏层里跑；同时把评论列表的节点**克隆**
/// 一份进面板，按「头像 / 昵称 / 标签 / 正文 / 配图 / 时间 / 回复数 / 楼中楼」打上
/// `yd*` 类名，再套一层统一字体与间距。
///
/// 为什么不按文本行重新拼卡片：书源页面千奇百怪，文字一旦被拆开重排，
/// 「第 16 段」会跑进正文、昵称和时间会粘成一行、楼中楼会丢掉——上一版就是这么错乱的。
/// 克隆 DOM 后文字、图片、表情、链接全部原样保留，最多是排版不完美，绝不会串行。
///
/// 面板自身不带底色：毛玻璃由 Swift 侧的 sheet 背景（`ultraThinMaterial`）提供，
/// 页面只负责把文字与卡片画在半透明层上。
enum IslandReviewPanel {

    /// 生成 `atDocumentStart` 注入的脚本。
    /// - Parameters:
    ///   - isNight: 当前日夜模式，决定文字与分隔线配色。
    ///   - title: 面板标题（通常取 `ReviewTarget.title`，已本地化过）。
    ///   - customCSS: 用户在「段评样式」里编辑的 CSS。只作用于本面板，
    ///     且会先剔除 `content:` 改字与 `background*` 声明——前者是更早一版
    ///     「本章热议」重复四次的原因，后者会把毛玻璃糊成一块实心板。
    static func installScript(isNight: Bool, title: String, customCSS: String) -> String {
        let modeLiteral = javaScriptStringLiteral(isNight ? "dark" : "light")
        let titleLiteral = javaScriptStringLiteral(title)
        let cssLiteral = javaScriptStringLiteral(sanitizedCSS(customCSS))

        // Swift raw string：JS 里的正则反斜杠无需转义，插值用 \#(...)。
        return #"""
        (function () {
            var PANEL_ID = '__yd_island_panel__';
            var SRC_ID = '__yd_source_root__';
            var STYLE_ID = '__yd_island_style__';
            var MODE = \#(modeLiteral);
            var TITLE = \#(titleLiteral);
            var CUSTOM = \#(cssLiteral);
            var DARK = MODE === 'dark';

            var started = false;
            var rendering = false;
            var sweeping = false;
            var timer = null;
            var failures = 0;
            var startedAt = Date.now();

            function esc(s) {
                return String(s == null ? '' : s)
                    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
                    .replace(/>/g, '&gt;').replace(/"/g, '&quot;')
                    .replace(/'/g, '&#39;');
            }
            function cls(el) { return String((el && el.className) || ''); }
            function T(el) {
                if (!el) return '';
                return String(el.textContent || '').replace(/\s+/g, ' ').trim();
            }
            function ownText(el) {
                var s = '';
                for (var i = 0; i < el.childNodes.length; i++) {
                    var n = el.childNodes[i];
                    if (n.nodeType === 3) s += n.nodeValue;
                }
                return s.replace(/\s+/g, ' ').trim();
            }
            function vis(el) {
                try {
                    var s = window.getComputedStyle(el);
                    if (!s) return false;
                    if (s.display === 'none' || s.visibility === 'hidden') return false;
                    if (parseFloat(s.opacity || '1') < 0.05) return false;
                    if (el.closest && el.closest('#' + SRC_ID)) return true;
                    var r = el.getBoundingClientRect();
                    return r.width > 4 && r.height > 4;
                } catch (e) { return false; }
            }

            var TIME_RE = /^(\d{4}[-/.]\d{1,2}[-/.]\d{1,2}(\s+\d{1,2}:\d{2}(:\d{2})?)?|\d{1,2}[-/.]\d{1,2}(\s+\d{1,2}:\d{2})?|(刚刚|今天|昨天|前天|\d+\s*(秒|分钟|小时|天|周|个月|年)前)(\s*\d{1,2}:\d{2})?)$/;
            var REPLY_RE = /^(\d+\s*)?(条)?(回复|评论)(\s*\d+)?$/;
            var LIKE_RE = /^(\d+\s*)?(个)?(赞|点赞|顶|有用)(\s*\d+)?$/;
            var CHIP_RE = /^(第\s*\d+\s*段|第\s*[0-9一二三四五六七八九十百]+\s*章|整章|章末|章节标题|标题评|作者说|本章说|段评|书友说|LV\.?\s*\d+|Lv\.?\s*\d+|等级\s*\d+|\d+\s*楼|楼主|神评|热评|精华|置顶|精选)/i;
            var JUNK_RE = /^(回复|点赞|赞|举报|展开|收起|查看更多|加载更多|查看全部|上一页|下一页|全部|默认|最新|最热|发表|发送|取消|登录|注册)$/;

            function fixSrc(im) {
                var src = im.getAttribute('src') || '';
                var lazy = im.getAttribute('data-src') || im.getAttribute('data-original') ||
                           im.getAttribute('data-lazy-src') || im.getAttribute('data-echo') || '';
                if ((!src || /^data:image\/(gif|svg)/i.test(src) || /blank|placeholder|loading/i.test(src)) && lazy) {
                    im.setAttribute('src', lazy);
                    src = lazy;
                }
                if (!src) {
                    var ss = im.getAttribute('srcset') || im.getAttribute('data-srcset') || '';
                    var first = ss.split(',')[0];
                    if (first) {
                        var url = first.trim().split(/\s+/)[0];
                        if (url) { im.setAttribute('src', url); src = url; }
                    }
                }
                if (src && src.indexOf('//') === 0) im.setAttribute('src', location.protocol + src);
                im.setAttribute('loading', 'eager');
                im.setAttribute('referrerpolicy', 'no-referrer');
                im.removeAttribute('srcset');
                im.removeAttribute('data-srcset');
            }

            // MARK: - 隐藏书源原 UI（节点保留，书源脚本照常运行）

            function ensureSourceRoot() {
                var src = document.getElementById(SRC_ID);
                if (src) return src;
                src = document.createElement('div');
                src.id = SRC_ID;
                src.style.setProperty('display', 'none', 'important');
                var panel = document.getElementById(PANEL_ID);
                var nodes = [].slice.call(document.body.childNodes);
                for (var i = 0; i < nodes.length; i++) {
                    if (nodes[i] === panel) continue;
                    src.appendChild(nodes[i]);
                }
                document.body.insertBefore(src, document.body.firstChild);
                return src;
            }
            function sweep() {
                var src = document.getElementById(SRC_ID);
                if (!src) return;
                sweeping = true;
                try {
                    var kids = [].slice.call(document.body.children);
                    for (var i = 0; i < kids.length; i++) {
                        var n = kids[i];
                        if (n === src || n.id === PANEL_ID || n.id === STYLE_ID) continue;
                        if (/^(SCRIPT|STYLE|LINK|META)$/.test(n.tagName)) continue;
                        src.appendChild(n);
                    }
                } finally { sweeping = false; }
            }

            // MARK: - 找评论列表（按重复结构聚类，不看文案）

            function depthOf(el, root) {
                var d = 0, p = el;
                while (p && p !== root) { d++; p = p.parentElement; }
                return d;
            }

            function listIn(root) {
                var best = null;
                var boxes = root.querySelectorAll('div,ul,ol,section,article,tbody,main,dl');
                for (var i = 0; i < boxes.length; i++) {
                    var box = boxes[i];
                    if (box.id === PANEL_ID) continue;
                    var kids = [];
                    for (var j = 0; j < box.children.length; j++) {
                        var k = box.children[j];
                        if (k.id === PANEL_ID) continue;
                        kids.push(k);
                    }
                    if (kids.length < 2 || kids.length > 200) continue;
                    var groups = {};
                    for (var g = 0; g < kids.length; g++) {
                        var sig = kids[g].tagName + '#' + cls(kids[g]).slice(0, 60);
                        (groups[sig] = groups[sig] || []).push(kids[g]);
                    }
                    for (var key in groups) {
                        var group = groups[key];
                        if (group.length < 2) continue;
                        var good = 0, imgN = 0, txtSum = 0;
                        for (var q = 0; q < group.length; q++) {
                            var t = T(group[q]);
                            if (t.length >= 6) good++;
                            txtSum += t.length;
                            if (group[q].querySelector('img')) imgN++;
                        }
                        if (good < 2) continue;
                        var avg = txtSum / group.length;
                        var score = group.length * 10 + Math.min(group.length, 12) * 2 +
                                    imgN * 4 + Math.min(avg, 120) * 0.2 + depthOf(box, root) * 0.6;
                        if (!best || score > best.score) best = { box: box, cards: group, score: score };
                    }
                }
                return best;
            }

            function findReplies(card) {
                var inner = listIn(card);
                if (!inner) return null;
                if (inner.cards.length < 1) return null;
                if (inner.box === card) return null;
                return inner.box;
            }

            // MARK: - 给克隆出来的卡片标角色（只加 class，不动文字）

            function tagCard(card, nested) {
                if (!card || card.nodeType !== 1) return;
                card.classList.add('ydc');
                if (nested) card.classList.add('ydc-sub');

                // 先找出子回复区，后面抽头像/正文/时间都要跳过这一块，避免把楼中楼当成本条的头像和正文
                var repsBox = nested ? null : findReplies(card);
                function inReps(el) { return !!(repsBox && (el === repsBox || repsBox.contains(el))); }

                var imgs = [];
                var allImgs = card.querySelectorAll('img');
                for (var i = 0; i < allImgs.length; i++) {
                    if (inReps(allImgs[i])) continue;
                    fixSrc(allImgs[i]);
                    imgs.push(allImgs[i]);
                }

                // 正文：直接文本占比最高、且不是「时间/回复数/点赞数/标签」的那一块
                var bestTx = null, bestScore = 0;
                var txCand = card.querySelectorAll('div,p,section,article,span,a,blockquote');
                for (var b = 0; b < txCand.length; b++) {
                    var el = txCand[b];
                    if (el.classList.contains('ydc')) continue;
                    if (inReps(el)) continue;
                    var total = T(el).length;
                    if (total < 4) continue;
                    var own = ownText(el).length;
                    if (own === 0) continue;
                    var st = T(el);
                    if (TIME_RE.test(st) || REPLY_RE.test(st) || LIKE_RE.test(st)) continue;
                    if (JUNK_RE.test(st)) continue;
                    if (CHIP_RE.test(st) && total <= 18) continue;
                    var score = own * 3 + total * 0.12;
                    if (score > bestScore) { bestScore = score; bestTx = el; }
                }

                // 头像：第一个「周边没有文字」的图片
                var av = null;
                for (var m = 0; m < imgs.length; m++) {
                    var im = imgs[m];
                    if (bestTx && bestTx.contains(im)) continue;
                    var hint = (cls(im) + ' ' + (im.getAttribute('alt') || '')).toLowerCase();
                    if (/avatar|face|head|portrait|user|touxiang|author/.test(hint)) { av = im; break; }
                    var p = im.parentElement, up = 0;
                    while (p && up < 2 && p !== card && T(p).length > 0) { p = p.parentElement; up++; }
                    if (p && p !== card && T(p).length === 0) { av = im; break; }
                }

                if (!av) {
                    // 退一步：第一张「小图」（宽度 <= 72），多半就是头像
                    for (var m2 = 0; m2 < imgs.length; m2++) {
                        var im2 = imgs[m2];
                        if (bestTx && bestTx.contains(im2)) continue;
                        var w2 = parseInt(im2.getAttribute('width') || '0', 10) ||
                                 (im2.style ? parseInt(im2.style.width || '0', 10) : 0);
                        if (w2 > 0 && w2 <= 72) { av = im2; break; }
                    }
                }

                // 时间 / 回复数 / 点赞数
                var tEl = null, rEl = null, lEl = null;
                var leaves = card.querySelectorAll('span,a,div,em,i,small,time,p,b,strong');
                for (var d = 0; d < leaves.length; d++) {
                    var le = leaves[d];
                    if (le.children.length > 0) continue;
                    if (inReps(le)) continue;
                    if (bestTx && bestTx.contains(le)) continue;
                    if (av && (le === av || le.contains(av))) continue;
                    var lt = T(le);
                    if (!lt || lt.length > 26) continue;
                    if (!tEl && TIME_RE.test(lt)) { tEl = le; continue; }
                    if (!rEl && REPLY_RE.test(lt)) { rEl = le; continue; }
                    if (!lEl && LIKE_RE.test(lt)) { lEl = le; continue; }
                }

                // 标签 / 段位：最多两个（等级 + 第几段），都并到头像那一行
                var chips = [];
                if (!nested) {
                    for (var e = 0; e < leaves.length && chips.length < 2; e++) {
                        var ce = leaves[e];
                        if (ce.children.length > 0) continue;
                        if (inReps(ce)) continue;
                        if (bestTx && bestTx.contains(ce)) continue;
                        if (ce === tEl || ce === rEl || ce === lEl) continue;
                        if (ce.parentElement && ce.parentElement.classList.contains('ydhead')) continue;
                        var ct = T(ce);
                        if (!ct || ct.length > 18) continue;
                        if (CHIP_RE.test(ct)) { chips.push(ce); continue; }
                        if (/label|tag|badge|level|lv/i.test(cls(ce)) && ct.length <= 10) { chips.push(ce); }
                    }
                }

                // 昵称：正文/标签/时间之外，最靠前的短文本
                var nm = null;
                if (!nested) {
                    var nameCand = card.querySelectorAll('a,span,div,strong,b,em');
                    for (var f = 0; f < nameCand.length; f++) {
                        var ne = nameCand[f];
                        if (ne.children.length > 0) continue;
                        if (inReps(ne)) continue;
                        if (bestTx && bestTx.contains(ne)) continue;
                        if (ne === tEl || ne === rEl || ne === lEl) continue;
                        if (chips.indexOf(ne) >= 0) continue;
                        var nt = T(ne);
                        if (!nt || nt.length < 2 || nt.length > 18) continue;
                        if (JUNK_RE.test(nt) || TIME_RE.test(nt)) continue;
                        nm = ne; break;
                    }
                }

                if (bestTx) bestTx.classList.add('ydtx');
                for (var ci = 0; ci < chips.length; ci++) chips[ci].classList.add('ydbadge');
                if (nm) nm.classList.add('ydnm');

                for (var h = 0; h < imgs.length; h++) {
                    if (imgs[h] === av) continue;
                    imgs[h].classList.add('ydpic');
                }
                if (av) {
                    av.classList.remove('ydpic');
                    av.classList.add('ydav');
                }

                // 头像 + 昵称 + 标签合成一行
                if (av || nm || chips.length) {
                    var head = document.createElement('div');
                    head.className = 'ydhead';
                    if (av) {
                        var abox = av.parentElement;
                        var good = abox && abox !== card && T(abox).length === 0 && abox.children.length <= 2 &&
                                   abox.querySelectorAll('img').length <= 1 && !abox.classList.contains('ydhead');
                        if (good) {
                            var outer = abox.parentElement;
                            if (outer && outer !== card && T(outer).length === 0 && outer.children.length <= 2 &&
                                !outer.classList.contains('ydhead') && !outer.classList.contains('ydreps')) {
                                abox = outer;
                            }
                            abox.classList.add('ydavbox');
                            head.appendChild(abox);
                        } else {
                            head.appendChild(av);
                        }
                    }
                    if (nm) head.appendChild(nm);
                    for (var cc = 0; cc < chips.length; cc++) head.appendChild(chips[cc]);
                    card.insertBefore(head, card.firstChild);
                }

                // 子回复
                if (repsBox) {
                    repsBox.classList.add('ydreps');
                    for (var r = 0; r < repsBox.children.length; r++) {
                        tagCard(repsBox.children[r], true);
                    }
                }

                // 底部：时间靠左，回复/点赞靠右
                if (tEl || rEl || lEl) {
                    var foot = document.createElement('div');
                    foot.className = 'ydfoot';
                    var left = document.createElement('span');
                    left.className = 'ydft';
                    var right = document.createElement('span');
                    right.className = 'ydfr';
                    if (tEl) left.appendChild(tEl);
                    if (rEl) { if (rEl.parentElement) rEl.parentElement.removeChild(rEl); right.appendChild(rEl); }
                    if (lEl) { if (lEl.parentElement) lEl.parentElement.removeChild(lEl); right.appendChild(lEl); }
                    if (left.childNodes.length) foot.appendChild(left);
                    if (right.childNodes.length) foot.appendChild(right);
                    if (!foot.childNodes.length) return;
                    if (repsBox && card.contains(repsBox) && repsBox.parentNode) {
                        repsBox.parentNode.insertBefore(foot, repsBox);
                    } else {
                        card.appendChild(foot);
                    }
                }
            }

            // 有些「作者说 / 作者有话说」只有一条内容，凑不出重复列表，这里退化成单卡片。
            function singleCard(root) {
                var best = null, bestDepth = -1;
                var nodes = root.querySelectorAll('div,article,section,li');
                for (var i = 0; i < nodes.length; i++) {
                    var el = nodes[i];
                    if (el.getElementById) continue;
                    var t = T(el);
                    if (t.length < 12 || t.length > 2000) continue;
                    if (!/(\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}\s+\d{1,2}:\d{2}|\d+\s*(分钟|小时|天)前|昨天|刚刚)/.test(t)) continue;
                    if (el.children.length < 2) continue;
                    if (!el.querySelector('img') && t.length < 30) continue;
                    var d = depthOf(el, root);
                    if (d > bestDepth) { bestDepth = d; best = el; }
                }
                return best;
            }

            // 真正的评论卡片：有头像、有时间、或者有「N 条回复 / N 赞」。
            // 「第 64 段 3 评」「正在加载评论数据…」「全章本章说汇总全部」这类段落索引行
            // 一条都不满足，必须挡在外面——上一版把它们当评论渲染，作者说就整页错乱。
            function isCommentCard(el) {
                if (el.querySelector('img')) return true;
                var t = T(el);
                if (TIME_RE.test(t)) return true;
                if (/(\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d+\s*(分钟|小时|天)前|刚刚|昨天)/.test(t)) return true;
                if (/(\d+)\s*(条)?回复/.test(t) && t.length > 16) return true;
                return false;
            }
            function isIndexRow(el) {
                var t = T(el).replace(/\s+/g, '');
                if (t.length > 30) return false;
                return /^第\d+段/.test(t) || /章末讨论|整章|标题评|全章本章说|段落定位|本章说/.test(t);
            }
            function indexLabel(el) {
                var t = T(el).replace(/\s+/g, ' ');
                var m = t.match(/^(第\s*\d+\s*段|整章章末讨论|章节标题评|全章本章说汇总|本章评论段落定位)/);
                var label = m ? m[1] : t.slice(0, 12);
                var c = t.match(/(\d+)\s*评/);
                return { label: label, count: c ? c[1] : '' };
            }

            function loadMoreNode(src) {
                var nodes = src.querySelectorAll('a,button,div,span,p');
                for (var i = 0; i < nodes.length; i++) {
                    var n = nodes[i];
                    if (n.children.length > 1) continue;
                    var t = T(n);
                    if (!t || t.length > 14) continue;
                    if (/^(加载更多|查看更多|点击加载|展开更多|更多评论|查看全部评论|查看全部)/.test(t)) return n;
                }
                return null;
            }

            // MARK: - 样式

            function cssText() {
                var ink = DARK ? '#ECECEC' : '#1F1E1D';
                var sub = DARK ? '#9E9A95' : '#8E8A84';
                var line = DARK ? 'rgba(255,255,255,.10)' : 'rgba(60,55,48,.09)';
                var chipBg = DARK ? 'rgba(255,255,255,.10)' : 'rgba(60,55,48,.055)';
                var chipFg = DARK ? '#C9C4BE' : '#6E6A64';
                var repBg = DARK ? 'rgba(255,255,255,.05)' : 'rgba(60,55,48,.045)';
                var avBg = DARK ? 'rgba(255,255,255,.12)' : 'rgba(60,55,48,.08)';
                var P = '#' + PANEL_ID;
                return [
                    'html,body{background:transparent !important;background-color:transparent !important;margin:0 !important;padding:0 !important;}',
                    'body{-webkit-text-size-adjust:100%;}',
                    '#' + SRC_ID + '{display:none !important;}',
                    P + '{position:relative;width:100% !important;max-width:100% !important;overflow-x:hidden;box-sizing:border-box;',
                    '  background:transparent !important;padding:0 18px 30px !important;color:' + ink + ' !important;',
                    '  font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Noto Sans CJK SC",sans-serif !important;',
                    '  -webkit-font-smoothing:antialiased;}',
                    P + ' *{box-sizing:border-box !important;-webkit-tap-highlight-color:transparent;}',
                    P + ' a{color:inherit !important;text-decoration:none !important;}',
                    P + ' img{max-width:100% !important;}',
                    P + ' .ydhd{position:relative;text-align:center;font-size:15px;font-weight:600;letter-spacing:.6px;',
                    '  color:' + ink + ' !important;padding:12px 0 14px;}',
                    P + ' .ydlist{display:block !important;padding:0 !important;margin:0 !important;background:transparent !important;}',
                    P + ' .ydc{position:relative !important;display:block !important;width:auto !important;float:none !important;',
                    '  padding:16px 0 15px !important;margin:0 !important;border:0 !important;',
                    '  border-top:.5px solid ' + line + ' !important;background:transparent !important;',
                    '  box-shadow:none !important;border-radius:0 !important;}',
                    P + ' .ydlist > .ydc:first-child{border-top:none !important;padding-top:6px !important;}',
                    P + ' .ydc .ydav{display:block !important;width:32px !important;height:32px !important;',
                    '  min-width:32px !important;min-height:32px !important;max-width:none !important;',
                    '  border-radius:50% !important;object-fit:cover !important;background:' + avBg + ' !important;',
                    '  margin:0 !important;float:none !important;border:0 !important;padding:0 !important;}',
                    P + ' .ydc .ydhead{display:flex !important;align-items:center !important;gap:0 !important;',
                    '  width:100% !important;margin:0 0 8px !important;padding:0 !important;border:0 !important;',
                    '  background:transparent !important;float:none !important;}',
                    P + ' .ydc .ydavbox{display:block !important;flex:0 0 32px !important;width:32px !important;',
                    '  height:32px !important;margin:0 9px 0 0 !important;padding:0 !important;border:0 !important;',
                    '  border-radius:50% !important;overflow:hidden !important;background:transparent !important;',
                    '  float:none !important;position:static !important;}',
                    P + ' .ydc .ydavbox .ydav{width:100% !important;height:100% !important;min-width:0 !important;',
                    '  min-height:0 !important;margin:0 !important;border-radius:50% !important;}',
                    P + ' .ydc div:empty,' + P + ' .ydc span:empty{' + 'display:none !important;}',
                    P + ' .ydc .ydpic{display:block !important;max-width:48% !important;max-height:150px !important;',
                    '  width:auto !important;height:auto !important;border-radius:10px !important;object-fit:cover !important;',
                    '  margin:9px 0 2px !important;background:' + repBg + ' !important;float:none !important;}',
                    P + ' .ydc .ydbadge{display:inline-block !important;max-width:62%;overflow:hidden;text-overflow:ellipsis;',
                    '  white-space:nowrap !important;vertical-align:middle !important;font-size:11px !important;line-height:18px !important;',
                    '  padding:0 6px !important;margin:0 0 0 6px !important;border:0 !important;border-radius:5px !important;',
                    '  background:' + chipBg + ' !important;color:' + chipFg + ' !important;font-weight:400 !important;}',
                    P + ' .ydc .ydnm{display:inline-block !important;vertical-align:middle !important;font-size:13px !important;',
                    '  font-weight:600 !important;color:' + ink + ' !important;margin:0 6px 0 0 !important;max-width:46%;overflow:hidden;',
                    '  text-overflow:ellipsis;white-space:nowrap !important;}',
                    P + ' .ydc .ydtx{display:block !important;clear:both !important;font-size:14.5px !important;',
                    '  line-height:1.72 !important;margin:2px 0 0 !important;color:' + ink + ' !important;',
                    '  letter-spacing:.1px;word-break:break-word !important;white-space:pre-wrap !important;',
                    '  text-align:left !important;text-indent:0 !important;}',
                    P + ' .ydc .ydfoot{display:flex !important;align-items:center;justify-content:space-between !important;',
                    '  gap:10px !important;clear:both !important;margin:11px 0 0 !important;padding:0 !important;',
                    '  border:0 !important;background:transparent !important;font-size:11.5px !important;line-height:16px !important;',
                    '  color:' + sub + ' !important;}',
                    P + ' .ydc .ydfoot span{font-size:11.5px !important;color:' + sub + ' !important;background:none !important;}',
                    P + ' .ydc .ydft{color:' + sub + ' !important;}',
                    P + ' .ydc .ydfr{display:flex !important;align-items:center !important;gap:14px !important;}',
                    P + ' .ydreps{display:block !important;clear:both !important;margin:12px 0 0 !important;padding:2px 12px !important;',
                    '  border:0 !important;border-radius:12px !important;background:' + repBg + ' !important;}',
                    P + ' .ydreps .ydc{border-top:.5px solid ' + line + ' !important;padding:11px 0 10px !important;}',
                    P + ' .ydreps .ydc:first-child{border-top:none !important;}',
                    P + ' .ydreps .ydc .ydavbox{flex:0 0 24px !important;width:24px !important;height:24px !important;}',
                    P + ' .ydreps .ydc .ydav{width:100% !important;height:100% !important;}',
                    P + ' .ydreps .ydc .ydtx{font-size:13.5px !important;line-height:1.62 !important;}',
                    P + ' .ydrow{display:flex !important;align-items:center !important;gap:8px !important;',
                    '  padding:15px 0 !important;border-top:.5px solid ' + line + ' !important;font-size:14px !important;',
                    '  color:' + ink + ' !important;background:transparent !important;}',
                    P + ' .ydrow:first-child{border-top:none !important;}',
                    P + ' .ydrl{flex:1 !important;color:' + ink + ' !important;}',
                    P + ' .ydrc{font-size:12px !important;color:' + sub + ' !important;}',
                    P + ' .ydchev{font-size:16px !important;color:' + sub + ' !important;line-height:1 !important;}',
                    P + ' .ydmore{margin:18px auto 6px !important;padding:10px 0 !important;width:60% !important;',
                    '  text-align:center !important;font-size:12.5px !important;color:' + chipFg + ' !important;',
                    '  border-radius:999px !important;background:' + chipBg + ' !important;}',
                    P + ' .ydempty{text-align:center;padding:40px 20px !important;font-size:13px !important;color:' + sub + ' !important;}'
                ].join('\n');
            }

            function installStyle() {
                var head = document.head || document.documentElement;
                if (!head) return;
                var style = document.getElementById(STYLE_ID);
                if (!style) {
                    style = document.createElement('style');
                    style.id = STYLE_ID;
                    document.documentElement.appendChild(style);
                }
                style.textContent = cssText() + '\n' + CUSTOM;
            }

            // MARK: - 渲染

            function render(src) {
                var found = listIn(src);
                var cards = found ? found.cards : null;
                var indexRows = [];
                var textCards = [];
                var STATUS_RE = /正在加载|加载中|暂无|没有更多|点击加载|稍后/;
                if (cards) {
                    var real = [];
                    for (var i = 0; i < cards.length; i++) {
                        var node = cards[i];
                        var t = T(node);
                        if (isIndexRow(node)) { indexRows.push(node); continue; }
                        if (STATUS_RE.test(t) && t.length <= 20) continue;
                        if (isCommentCard(node)) { real.push(node); continue; }
                        // 纯文字的一句话评论（没有头像/时间）：保留，别当噪声丢掉
                        if (t.length >= 8 && t.length <= 400) textCards.push(node);
                    }
                    cards = real.concat(textCards);
                    if (!cards.length && !indexRows.length) return false;
                } else {
                    var one = singleCard(src);
                    if (!one) return false;
                    cards = [one];
                }
                var panel = document.getElementById(PANEL_ID);
                if (!panel) {
                    panel = document.createElement('div');
                    panel.id = PANEL_ID;
                    document.body.appendChild(panel);
                }
                rendering = true;
                try {
                    panel.innerHTML = '<div class="ydhd">' + esc(TITLE || '段评') + '</div><div class="ydlist"></div>';
                    var list = panel.querySelector('.ydlist');
                    for (var i = 0; i < cards.length; i++) {
                        var card = cards[i].cloneNode(true);
                        tagCard(card, false);
                        list.appendChild(card);
                    }
                    if (indexRows.length) {
                        var idx = document.createElement('div');
                        idx.className = 'ydidx';
                        for (var r = 0; r < indexRows.length; r++) {
                            (function (node) {
                                var info = indexLabel(node);
                                var row = document.createElement('div');
                                row.className = 'ydrow';
                                row.innerHTML = '<span class="ydrl">' + esc(info.label) + '</span>' +
                                                (info.count ? '<span class="ydrc">' + esc(info.count) + ' 评</span>' : '') +
                                                '<span class="ydchev">›</span>';
                                row.addEventListener('click', function () {
                                    var a = node.querySelector('a[href]');
                                    try { (a || node).click(); } catch (e) {}
                                    setTimeout(function () { try { refresh(); } catch (e) {} }, 1500);
                                });
                                idx.appendChild(row);
                            })(indexRows[r]);
                        }
                        list.appendChild(idx);
                    }
                    if (!list.children.length) {
                        list.innerHTML = '<div class="ydempty">暂无评论</div>';
                    }
                    var more = loadMoreNode(src);
                    if (more) {
                        var btn = document.createElement('div');
                        btn.className = 'ydmore';
                        btn.textContent = '加载更多评论';
                        btn.addEventListener('click', function () {
                            try { more.click(); } catch (e) {}
                            setTimeout(refresh, 900);
                        });
                        panel.appendChild(btn);
                    }
                } finally {
                    setTimeout(function () { rendering = false; }, 0);
                }
                return true;
            }

            function refresh() {
                if (!document.body) return;
                installStyle();
                var src = ensureSourceRoot();
                sweep();
                var ok = render(src);
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    if (failures >= 6 && Date.now() - startedAt > 6000) {
                        var panel = document.getElementById(PANEL_ID);
                        if (panel && panel.parentNode) panel.parentNode.removeChild(panel);
                        src.style.setProperty('display', 'block', 'important');
                        return true;
                    }
                }
                return ok;
            }

            function start() {
                if (started || !document.body) return;
                started = true;
                refresh();
                try {
                    var bodyMo = new MutationObserver(function () {
                        if (rendering || sweeping) return;
                        sweep();
                        clearTimeout(timer);
                        timer = setTimeout(refresh, 320);
                    });
                    bodyMo.observe(document.body, { childList: true, subtree: false });

                    var srcEl = document.getElementById(SRC_ID);
                    if (srcEl) {
                        var srcMo = new MutationObserver(function () {
                            if (rendering || sweeping) return;
                            clearTimeout(timer);
                            timer = setTimeout(refresh, 320);
                        });
                        srcMo.observe(srcEl, { childList: true, subtree: true });
                    }
                } catch (e) {}
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

    /// 自定义 CSS 只保留「文字 / 字号 / 行距 / 间距」这类视觉声明。
    ///
    /// 剔除 `content:`（它会改掉面板里的文字）、`background*`（一刷就把毛玻璃糊成实心板，
    /// 上一版「根本不透明」就是旧模板给 body 刷了 0.92 的白底）和
    /// `backdrop-filter`（在已经模糊的 sheet 上再糊一层，文字会发虚）。
    private static func sanitizedCSS(_ css: String) -> String {
        guard !css.isEmpty else { return "" }
        var out = css
        let patterns = [
            #"content\s*:\s*(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^;}]*)\s*;?"#,
            #"background(-color|-image|-repeat|-size|-position|-attachment)?\s*:\s*[^;}]*;?"#,
            #"(?:-webkit-)?backdrop-filter\s*:\s*[^;}]*;?"#
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
