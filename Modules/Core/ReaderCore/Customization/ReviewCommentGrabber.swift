import Foundation

/// 书源段评页的抓取器。
///
/// 为什么不是「把网页重排一遍」：段评页是各家书源自己写的 HTML，
/// 布局、类名、层级都不一样，猜结构必然在某些页面上翻车（前两版就是这么翻的）。
/// 这里的做法相反 —— **只在页面里读，不写**：
///
/// 1. 五套适配器按顺序试：作家说卡片、起点系（遇见 / 神魔小说这类）、
///    书源自绘的 `.list > .c` 面板、番茄系、以及「重复兄弟簇 + 特征打分」的通用兜底；
/// 2. 段落定位抽屉（「第 1 段 / 113 评」）一律排除，主评论 feed 未就绪时不发；
/// 3. 只有拿到**至少一条有正文的评论**才算抓成功，否则一个字都不发；
/// 4. 楼中楼会替用户点开并分批增量上报，首版就带上可展开的回复；
/// 5. 抓到了交给原生面板画卡片，抓不到面板继续显示书源原页面。
///
/// 所以最坏情况是「和以前一样看到书源页面」，不会出现乱七八糟的错版。
///
/// 字段与 `ReviewComment` 一一对应，适配器只负责「从哪个节点取」，
/// 取值规则在 JS 里集中写，改一处所有源都生效。
enum ReviewCommentGrabber {

    /// `WKScriptMessageHandler` 的名字，与脚本里的 `window.webkit.messageHandlers` 同名。
    static let messageHandlerName = "ydComments"

    /// 抓取脚本。注入时机在 `documentEnd`，页面自己渲染完再抓；
    /// 之后用 `MutationObserver` 跟着页面的滚动加载补抓。
    static let script = #"""
/* 段评抓取器 v2 —— 只读 DOM，不改页面。
 *
 * 目标：书源给的段评页长什么样都能抓到「人、字、图、赞、回复」，
 * 抓不到就什么都不做（面板继续显示书源原页面），绝不产生错乱 UI。
 *
 * 适配顺序：
 *   1. qd   —— 起点系（书源 jsLib 里 qdCmtPanel 生成的结构，class 固定）
 *   2. fq   —— 番茄系（服务端渲染，class 语义化）
 *   3. 通用 —— 重复兄弟簇 + 特征打分（不认识的书源兜底）
 */
(function () {
  if (window.__ydGrabV2) return;
  window.__ydGrabV2 = true;

  function txt(el) {
    if (!el) return '';
    return (el.textContent || '').replace(/\u200b/g, '').trim();
  }

  function abs(u) {
    if (!u) return '';
    u = String(u).trim();
    if (!u || u.indexOf('data:') === 0) return '';
    if (u.indexOf('//') === 0) return (location.protocol || 'https:') + u;
    if (/^https?:/i.test(u)) return u;
    try { return new URL(u, location.href).href; } catch (e) { return u; }
  }

  var AVATAR_HINT = /(avatar|avater|head|portrait|face|user-?img|userpic|photo|touxiang)/i;
  var AVATAR_DENY = /(emoji|emoticon|biaoqing|icon-?tag|badge|level|vip|medal|rank)/i;

  function looksAvatar(img) {
    if (!img) return false;
    var src = img.getAttribute('src') || img.getAttribute('data-src') || '';
    if (!src) return false;
    var w = img.naturalWidth || parseInt(img.getAttribute('width') || '0', 10) || 0;
    var h = img.naturalHeight || parseInt(img.getAttribute('height') || '0', 10) || 0;
    var cls = (img.className || '') + ' ' + (img.parentElement ? img.parentElement.className : '');
    if (AVATAR_DENY.test(cls + ' ' + src)) return false;
    if (AVATAR_HINT.test(cls + ' ' + src)) return true;
    if (w && h) {
      var ratio = w / h;
      if (w <= 96 && h <= 96 && ratio > 0.7 && ratio < 1.4) return true;
    }
    return false;
  }

  function avatarOf(root) {
    var imgs = root.querySelectorAll('img');
    var i, img;
    for (i = 0; i < imgs.length; i++) {
      img = imgs[i];
      if (looksAvatar(img)) return abs(img.getAttribute('src') || img.getAttribute('data-src'));
    }
    var el = root.querySelector('[class*="avatar" i],[class*="head" i],[class*="portrait" i]');
    if (el) {
      var st = window.getComputedStyle ? getComputedStyle(el) : null;
      var bg = st && st.backgroundImage;
      var m = bg && bg.match(/url\(["']?([^"')]+)/);
      if (m) return abs(m[1]);
      img = el.querySelector('img');
      if (img) return abs(img.getAttribute('src'));
    }
    return '';
  }

  var TIME_RE = /(\d+\s*(?:秒|分钟|小时|天|周|月)前|刚才|刚刚|昨天|前天|\d{1,2}:\d{2}|\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}|\d{1,2}[-/.月]\d{1,2}日?)/;

  function pickNumbers(s) {
    var m = String(s || '').match(/\d+(?:\.\d+)?\s*[kKwW万]?/g) || [];
    return m.map(function (x) {
      var v = parseFloat(x);
      if (/[kK]/.test(x)) v *= 1000;
      if (/[wW万]/.test(x)) v *= 10000;
      return Math.round(v);
    });
  }

  /* 正文里的图片分「配图」与「表情」：配图进 images，表情直接丢掉。 */
  function bodyContent(el, images) {
    if (!el) return '';
    var clone = el.cloneNode(true);
    var ci = clone.querySelectorAll('img');
    for (var j = 0; j < ci.length; j++) {
      var im = ci[j];
      var isEmo = /(^|\s)(cmtemo|emoticon|emoji|emo)(\s|$)/i.test(im.className || '') ||
        /(emoji|emoticon)/i.test(im.getAttribute('src') || '');
      var src = abs(im.getAttribute('src') || im.getAttribute('data-src'));
      if (!isEmo && src && images) images.push(src);
      if (im.parentNode) im.parentNode.removeChild(im);
    }
    var brs = clone.querySelectorAll('br');
    for (var b = 0; b < brs.length; b++) {
      if (brs[b].parentNode) brs[b].parentNode.replaceChild(document.createTextNode('\n'), brs[b]);
    }
    var blocks = clone.querySelectorAll('div,p');
    for (var d = 0; d < blocks.length; d++) {
      if (blocks[d] !== clone) blocks[d].appendChild(document.createTextNode('\n'));
    }
    return (clone.textContent || '').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  }

  /* ---------- 适配器 0：起点 / 本章说（服务端渲染页，遇见源等） ----------
   * 结构（页面 createReviewElement 生成，已核对）：
   *   div.li[data-review-id]
   *     div.txv > img.tx(头像) + img.txk(头像框)
   *     div.p
   *       p.p1 > span.user-name + (img.tag / svg.tag 等级徽章)
   *       p.zw  > span            段落原文引用（可选）
   *       p.p2  > span.reply-target + 正文
   *       div.tp > img            附图（可选）
   *       audio                   语音（可选）
   *       p.p3 > span.p3-left > span(时间) span(· IP) | button.reply-btn
   *       div.sub-replies-wrap > div.li.sub-comment-item
   *     div.dz > span.like-num
   */
  function tagText(el) {
    var out = [];
    var kids = el.querySelectorAll('.tag');
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i];
      if (k.tagName === 'IMG') {
        var alt = k.getAttribute('alt') || '';
        if (alt && alt !== 'tag') out.push(alt);
        continue;
      }
      var t = txt(k);
      if (t) out.push(t);
    }
    return out.join(' ');
  }

  function adaptQidian() {
    var all = document.querySelectorAll('.li');
    if (all.length < 1) return null;
    var cards = [];
    for (var i = 0; i < all.length; i++) {
      if (!all[i].classList.contains('sub-comment-item')) cards.push(all[i]);
    }
    if (!cards.length) return null;

    var out = [];
    var segments = [];
    for (var k = 0; k < cards.length; k++) {
      var card = cards[k];
      var p = card.querySelector(':scope > .p');
      if (!p) { p = card.querySelector('.p'); }
      // 页面上别处也可能有 `.li`（列表项），只认带 p1/p2 的评论卡片。
      if (!p || !p.querySelector('.p1') || (!p.querySelector('.p2') && !card.querySelector('.dz'))) continue;

      var nameEl = p.querySelector('.p1 .user-name') || p.querySelector('.user-name');
      var user = txt(nameEl) || '书友';

      var tx = card.querySelector('.txv img.tx') || card.querySelector('img.tx');
      var avatar = tx ? abs(tx.getAttribute('src')) : '';

      var level = tagText(p.querySelector('.p1') || p);

      var zwEl = p.querySelector(':scope > .zw') || p.querySelector('.zw');
      var quote = txt(zwEl);

      var p2 = p.querySelector(':scope > .p2') || p.querySelector('.p2');
      var replyTo = '';
      var images = [];
      var content = '';
      if (p2) {
        var clone = p2.cloneNode(true);
        var rt = clone.querySelector('.reply-target');
        if (rt) {
          replyTo = txt(rt).replace(/^回复\s*@?/, '').replace(/[：:]\s*$/, '').trim();
          if (rt.parentNode) rt.parentNode.removeChild(rt);
        }
        var brs = clone.querySelectorAll('br');
        for (var b = 0; b < brs.length; b++) {
          if (brs[b].parentNode) brs[b].parentNode.replaceChild(document.createTextNode('\n'), brs[b]);
        }
        content = (clone.textContent || '').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
      }

      var tp = card.querySelector('.tp img');
      if (tp) {
        var tpSrc = abs(tp.getAttribute('src') || tp.getAttribute('data-src'));
        if (tpSrc) images.push(tpSrc);
      }

      var voice = '';
      var au = card.querySelector('audio');
      if (au) voice = abs(au.getAttribute('src'));

      var meta = '';
      var p3left = p.querySelector('.p3 .p3-left') || p.querySelector('.p3-left');
      if (p3left) {
        var parts = [];
        var spans = p3left.querySelectorAll('span');
        for (var s = 0; s < spans.length; s++) {
          var sv = txt(spans[s]).replace(/^[·▪\s]+/, '');
          if (sv) parts.push(sv);
        }
        meta = parts.join(' · ');
      }

      var likeEl = card.querySelector('.dz .like-num') || card.querySelector('.dz span');
      var likes = likeEl ? (pickNumbers(txt(likeEl))[0] || 0) : 0;

      var replyBtn = p.querySelector('.reply-btn');
      var replyCount = replyBtn ? (pickNumbers(txt(replyBtn))[0] || 0) : 0;

      var replies = [];
      var subs = card.querySelectorAll('.sub-replies-wrap .li');
      for (var r = 0; r < subs.length; r++) {
        var sub = subs[r];
        var sp = sub.querySelector('.p') || sub;
        var sName = txt(sp.querySelector('.p1 .user-name')) || '书友';
        var sAv = sp.querySelector('img.tx2');
        var sP2 = sp.querySelector('.p2');
        var sTo = '';
        var sContent = '';
        if (sP2) {
          var sc = sP2.cloneNode(true);
          var srt = sc.querySelector('.reply-target');
          if (srt) {
            sTo = txt(srt).replace(/^回复\s*@?/, '').replace(/[：:]\s*$/, '').trim();
            if (srt.parentNode) srt.parentNode.removeChild(srt);
          }
          var sbr = sc.querySelectorAll('br');
          for (var sb = 0; sb < sbr.length; sb++) {
            if (sbr[sb].parentNode) sbr[sb].parentNode.replaceChild(document.createTextNode('\n'), sbr[sb]);
          }
          sContent = (sc.textContent || '').trim();
        }
        var sImages = [];
        var stp = sub.querySelector('.tp img');
        if (stp) { var ss = abs(stp.getAttribute('src')); if (ss) sImages.push(ss); }
        replies.push({
          id: 'r' + k + '_' + r,
          user: sName,
          avatar: sAv ? abs(sAv.getAttribute('src')) : '',
          content: sContent,
          images: sImages,
          replyTo: sTo
        });
      }
      if (replies.length) replyCount = Math.max(replyCount, replies.length);

      /* 所属段落：最近的 .segment-block 的徽章文字，如「💬 第 12 段」 */
      var block = card.closest ? card.closest('.segment-block') : null;
      var segLabel = '';
      if (block) {
        var badge = block.querySelector('.segment-badge');
        segLabel = txt(badge).replace(/^[^\u4e00-\u9fa5A-Za-z0-9]+/, '').trim();
      }

      out.push({
        id: card.getAttribute('data-review-id') || ('q' + k),
        user: user,
        avatar: avatar,
        level: 0,
        levelText: level,
        badge: '',
        meta: meta,
        quote: quote,
        segment: segLabel,
        content: content,
        images: images,
        voice: voice,
        likes: likes,
        replyCount: replyCount,
        replyTo: replyTo,
        replies: replies
      });
      if (segLabel && segments.indexOf(segLabel) < 0) segments.push(segLabel);
    }

    var withText = out.filter(function (x) { return x.content || x.images.length; }).length;
    if (!out.length || withText / out.length < 0.6) return null;

    var h1 = txt(document.querySelector('.header-title'));
    var sub2 = txt(document.querySelector('.header-subtitle'));
    return { adapter: 'qidian', title: h1, subtitle: sub2, segments: segments, items: out };
  }

  /* ---------- 适配器 1：起点系 ---------- */
  function adaptQD() {
    var list = document.querySelector('.list');
    if (!list) return null;
    var cards = [];
    for (var i = 0; i < list.children.length; i++) {
      var c = list.children[i];
      if (c.classList && c.classList.contains('c')) cards.push(c);
    }
    if (!cards.length) return null;

    var out = [];
    for (var k = 0; k < cards.length; k++) {
      var card = cards[k];
      var head = card.querySelector('.m');
      var body = card.querySelector('.b');
      var foot = card.querySelector('.f');
      if (head && head.parentElement !== card) head = null;
      if (body && body.parentElement !== card) body = null;
      if (foot && foot.parentElement !== card) foot = null;

      var nameEl = head && head.querySelector('.n');
      var user = txt(nameEl) || '匿名';
      var avEl = head && head.querySelector('img.av');
      var avatar = avEl ? abs(avEl.getAttribute('src')) : '';

      var level = 0;
      var lvEl = head && head.querySelector('.lv');
      if (lvEl) { var lm = txt(lvEl).match(/(\d+)/); level = lm ? parseInt(lm[1], 10) : 0; }

      var badge = '';
      var gEl = head && head.querySelector('.god');
      if (gEl) badge = txt(gEl);

      var meta = txt(head && head.querySelector('.fl'));

      var images = [];
      var content = bodyContent(body, images);

      var voice = '';
      var au = card.querySelector('audio');
      if (au) voice = abs(au.getAttribute('src'));

      var likes = 0, replyCount = 0;
      if (foot) {
        var spans = foot.children;
        if (spans.length >= 2) {
          likes = pickNumbers(txt(spans[0]))[0] || 0;
          replyCount = pickNumbers(txt(spans[1]))[0] || 0;
        } else if (spans.length === 1) {
          likes = pickNumbers(txt(spans[0]))[0] || 0;
        }
      }

      var replies = [];
      var rs = card.querySelectorAll('.fold .r');
      for (var r = 0; r < rs.length; r++) {
        var rEl = rs[r];
        var rHead = rEl.querySelector('.m');
        var rName = txt(rHead && rHead.querySelector('.n')) || '匿名';
        var rTo = '';
        var atEl = rHead && rHead.querySelector('.at');
        if (atEl) rTo = txt(atEl).replace(/^回复\s*@?\s*/, '');
        var rAv = rHead && rHead.querySelector('img.av');
        var rImages = [];
        var rContent = bodyContent(rEl.querySelector('.b'), rImages);
        replies.push({
          id: 'r' + k + '_' + r,
          user: rName,
          avatar: rAv ? abs(rAv.getAttribute('src')) : '',
          content: rContent,
          images: rImages,
          replyTo: rTo
        });
      }
      if (replies.length) replyCount = Math.max(replyCount, replies.length);

      out.push({
        id: 'c' + k,
        user: user,
        avatar: avatar,
        level: level,
        badge: badge,
        meta: meta,
        content: content,
        images: images,
        voice: voice,
        likes: likes,
        replyCount: replyCount,
        replies: replies
      });
    }

    var withText = out.filter(function (x) { return x.content || x.images.length; }).length;
    if (!out.length || withText / out.length < 0.5) return null;

    var title = txt(document.querySelector('.hd .t'));
    var ctx = txt(document.querySelector('.list > .ctx'));
    return { adapter: 'qd', title: title, context: ctx, items: out };
  }

  /* ---------- 适配器 2：番茄系（服务端渲染） ---------- */
  function adaptFQ() {
    var sels = ['.comment-item', '.comment-item-wrap', '.comment-list .item', '.comment-list > div',
      '.cmt-item', '.review-item', '.para-comment-item'];
    var cards = null;
    for (var s = 0; s < sels.length; s++) {
      var n = document.querySelectorAll(sels[s]);
      if (n.length >= 2) { cards = n; break; }
    }
    if (!cards) return null;

    var out = [];
    for (var i = 0; i < cards.length; i++) {
      var c = cards[i];
      var nameEl = c.querySelector('[class*="name" i],[class*="nick" i]');
      var bodyEl = c.querySelector('[class*="content" i],[class*="text" i],[class*="body" i]');
      if (!bodyEl) continue;
      var images = [];
      var imgs = bodyEl.querySelectorAll('img');
      for (var j = 0; j < imgs.length; j++) {
        var src = abs(imgs[j].getAttribute('src') || imgs[j].getAttribute('data-src'));
        if (!src || looksAvatar(imgs[j])) continue;
        if (/(^|\s)(emoji|emoticon|emo|cmtemo)(\s|$)/i.test(imgs[j].className || '')) continue;
        if (/(emoji|emoticon)/i.test(src)) continue;
        images.push(src);
      }
      var meta = '';
      var timeEl = c.querySelector('[class*="time" i],[class*="date" i]');
      if (timeEl) meta = txt(timeEl);
      var likeEl = c.querySelector('[class*="like" i],[class*="praise" i],[class*="zan" i]');
      var likes = likeEl ? (pickNumbers(txt(likeEl))[0] || 0) : 0;
      out.push({
        id: 'c' + i,
        user: txt(nameEl) || '匿名',
        avatar: avatarOf(c),
        level: 0,
        badge: '',
        meta: meta,
        content: txt(bodyEl),
        images: images,
        voice: '',
        likes: likes,
        replyCount: 0,
        replies: []
      });
    }
    if (out.length < 2) return null;
    var withText = out.filter(function (x) { return x.content || x.images.length; }).length;
    if (withText / out.length < 0.6) return null;
    return { adapter: 'fq', title: '', context: '', items: out };
  }

  /* ---------- 适配器 2.5：番茄 APP 书源的自绘段评面板 ----------
   * fqapp 书源的段评面板是 jsLib 自己拼的 HTML（FQ_ideaTap → showBrowser 四参，
   * preloadJs document.write 写出）：结构固定 ——
   *   .top（标题「💬 本段段评 · N 条」）
   *   .ls/#fqls > .it（评论行）
   *     .av > b(首字占位) + img.p[data-av=真实头像URL]
   *     .bd > .hd > .un(名字) + em.au(作者标) + .tm(日期) + .dg(N 赞)
   *           .tx(正文) + .rp(N 条回复)
   * 通用兜底抓它会把「作者标/赞数/回复数」全混进正文、点赞清零、头像丢失，
   * 这里按结构精确取字段，抓干净的数据交给原生卡片。
   */
  function adaptFQPanel() {
    var rows = document.querySelectorAll('.ls > .it, #fqls > .it, .ls .it, #fqls .it');
    if (rows.length < 1) return null;
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      var body = c.querySelector('.tx');
      if (!body) continue;
      var images = [];
      var content = bodyContent(body, images);
      if (!content) continue;
      var nameEl = c.querySelector('.un');
      var user = txt(nameEl);
      if (!user) {
        // 首字占位也别拿去当名字：.av b 只在头像解不出来时可见
        var fu = c.querySelector('.av b');
        user = fu && fu.style.display !== 'none' ? '' : '';
      }
      var avImg = c.querySelector('.av img.p');
      var avatar = avImg ? abs(avImg.getAttribute('data-av') || avImg.getAttribute('src') || '') : '';
      var dg = c.querySelector('.dg');
      var likes = dg ? (pickNumbers(txt(dg))[0] || 0) : 0;
      var rp = c.querySelector('.rp');
      var replyCount = rp ? (pickNumbers(txt(rp))[0] || 0) : 0;
      var isAuthor = !!c.querySelector('em.au');
      var meta = txt(c.querySelector('.tm'));
      out.push({
        id: 'fp' + i,
        user: user || '读者',
        avatar: avatar,
        level: 0,
        badge: isAuthor ? '作者' : '',
        meta: meta,
        content: content,
        images: images,
        voice: '',
        likes: likes,
        replyCount: replyCount,
        replies: []
      });
    }
    if (out.length < 2) return null;
    var withText = out.filter(function (x) { return x.content || x.images.length; }).length;
    if (withText / out.length < 0.6) return null;
    var top = txt(document.querySelector('.top')).replace(/^[^\u4e00-\u9fa5A-Za-z0-9]+/, '');
    return { adapter: 'fqpanel', title: top || '段评', context: '', items: out };
  }

  /* ---------- 适配器 3：通用——重复兄弟簇 ---------- */
  function signature(el) {
    var kids = el.children;
    var sig = '';
    for (var i = 0; i < Math.min(kids.length, 6); i++) sig += kids[i].tagName + '.';
    return sig;
  }

  function adaptGeneric() {
    var best = null;
    var all = document.body ? document.body.querySelectorAll('*') : [];
    for (var i = 0; i < all.length; i++) {
      var box = all[i];
      if (inNav(box)) continue;
      var kids = box.children;
      if (kids.length < 2 || kids.length > 300) continue;
      var same = 0, sig0 = signature(kids[0]);
      for (var k = 0; k < kids.length; k++) if (signature(kids[k]) === sig0) same++;
      if (same < Math.max(2, Math.floor(kids.length * 0.8))) continue;

      var withImg = 0, withLong = 0;
      for (var q = 0; q < kids.length; q++) {
        var kid = kids[q];
        if (txt(kid).length > 12) withLong++;
        if (kid.querySelector('img')) withImg++;
      }
      if (withLong < 2) continue;
      var score = kids.length * 2 + withLong * 3 + withImg * 2;
      if (/^(HTML|BODY)$/.test(box.tagName)) score -= 20;
      if (!best || score > best.score) best = { box: box, kids: kids, score: score };
    }
    if (!best || best.score < 20) return null;

    var out = [];
    for (var z = 0; z < best.kids.length; z++) {
      var card = best.kids[z];
      var full = txt(card);
      if (full.length < 2) continue;

      var avatar = avatarOf(card);

      var user = '';
      var cand = card.querySelectorAll('a,span,b,strong,[class*="name" i],[class*="nick" i]');
      for (var u = 0; u < cand.length; u++) {
        var t = txt(cand[u]);
        if (t && t.length <= 24 && !TIME_RE.test(t) && !/^\d+$/.test(t) &&
            !cand[u].querySelector('img') && cand[u].children.length === 0) { user = t; break; }
      }

      var timeM = full.match(TIME_RE);

      var blocks = card.querySelectorAll('div,p,section,article');
      var bodyEl = null, bodyLen = 0;
      for (var c2 = 0; c2 < blocks.length; c2++) {
        var len = txt(blocks[c2]).length;
        if (len > bodyLen && len > 4) { bodyLen = len; bodyEl = blocks[c2]; }
      }
      var content = bodyEl ? txt(bodyEl) : full;
      if (user && content.indexOf(user) === 0) content = content.slice(user.length).trim();
      if (timeM) content = content.replace(timeM[0], '').trim();

      var images = [];
      if (bodyEl) {
        var bi = bodyEl.querySelectorAll('img');
        for (var bj = 0; bj < bi.length; bj++) {
          var s2 = abs(bi[bj].getAttribute('src') || bi[bj].getAttribute('data-src'));
          if (s2 && !looksAvatar(bi[bj])) images.push(s2);
        }
      }

      var likes = 0;
      var likeEl = card.querySelector('[class*="like" i],[class*="praise" i],[class*="zan" i]');
      if (likeEl) likes = pickNumbers(txt(likeEl))[0] || 0;

      out.push({
        id: 'g' + z,
        user: user || '匿名',
        avatar: avatar,
        level: 0,
        badge: '',
        meta: timeM ? timeM[0] : '',
        content: content,
        images: images,
        voice: '',
        likes: likes,
        replyCount: 0,
        replies: []
      });
    }
    if (out.length < 2) return null;
    /* 通用兜底最容易被「段索引」「标签云」骗到：那些卡片没有头像、没有正文，
       只有一个短标题。这里要求绝大多数条目同时有人名和够长的正文，
       否则宁可什么都不发（面板继续显示书源原页面）。 */
    var good = out.filter(function (x) {
      var named = x.user && x.user !== '匿名' && x.user !== '书友';
      return named && ((x.content || '').length >= 6 || x.images.length);
    }).length;
    if (good / out.length < 0.8) return null;
    return { adapter: 'generic', title: '', context: '', items: out };
  }

  /* ---------- 适配器 -1：遇见 / 起点的「作家说」 ----------
   * paragraphId=-10 时服务器只返回 authorActivity，页面渲染一张
   *   section.author-speak-card
   *     .author-speak-header > .author-speak-badge + img + .author-speak-name
   *     .author-speak-content
   * 没有任何 .li 评论卡片，所以其它适配器全部落空 —— 这正是「作者说
   * 还显示旧版网页」的原因。这里把它做成一条作者卡片。
   */
  function adaptAuthorSay() {
    var card = document.querySelector('.author-speak-card, #authorSpeakCard');
    if (!card) return null;
    var nameEl = card.querySelector('.author-speak-name');
    var user = txt(nameEl) || '本书作者';
    var av = card.querySelector('.author-speak-header img') || card.querySelector('img');
    var bodyEl = card.querySelector('.author-speak-content');
    var images = [];
    var content = bodyContent(bodyEl, images);
    if (!content && !images.length) return null;
    return {
      adapter: 'author',
      title: '作家说',
      subtitle: '',
      segments: [],
      context: '',
      items: [{
        id: 'author-say',
        user: user,
        avatar: av ? abs(av.getAttribute('src')) : '',
        level: 0,
        levelText: '',
        badge: '',
        meta: '',
        quote: '',
        segment: '',
        content: content,
        images: images,
        voice: '',
        likes: 0,
        replyCount: 0,
        replyTo: '',
        isAuthor: true,
        replies: []
      }]
    };
  }

  /* 段落定位抽屉 / 顶栏 / 筛选条这些是导航，不是评论。
     本章说刚打开时主 feed 还没到，通用兜底最容易把这簇重复的
     .drawer-item（「第 1 段 / 113 评」）当成评论抓走。 */
  var NAV_SEL = '.anchor-drawer,.drawer-list,.drawer-item,.drawer-body,' +
    '.type-tabs,.sort-group,.toolbar-panel,.top-header,.header,' +
    '.roles-row,.segment-header,.segment-badge,.nav-btn,.tab-bar,.footer';

  function inNav(el) {
    var n = el;
    while (n && n !== document.body) {
      if (n.matches && n.matches(NAV_SEL)) return true;
      n = n.parentElement;
    }
    return false;
  }

  /* 遇见页面主 feed 是否还没就绪：#feedContainer 存在、但里面既没有
     评论 .li、也没有作者说卡片、也没有明确的空态提示 —— 说明数据还在飞，
     此时什么都不发，等 MutationObserver 后续触发。 */
  function feedPending() {
    var feed = document.getElementById('feedContainer');
    if (!feed) return false;
    if (feed.querySelector('.li, .author-speak-card, .empty-tip')) return false;
    return true;
  }

  /* ---------- 目录页：只列「第 N 段 · 113 评」，没有正文 ----------
   * 本章说入口有些源先给一张段索引（全章汇总 / 章节标题评 / 第 1 段…），
   * 点进去才是评论。这种页面如果照抓，原生面板会显示成一排「第 1 段」，
   * 所以识别出来之后：不发数据，替用户点「全部 / 汇总」那一项，再抓。
   */
  var DIR_NAME_RE = /(第\s*\d+\s*段|整章章末|章节标题|全章本章说|全章汇总|章末讨论)/;
  var DIR_COUNT_RE = /\d+\s*[评評条條]/;

  function looksDirectoryItem(it) {
    var t = ((it.user || '') + ' ' + (it.content || '')).replace(/\s+/g, ' ').trim();
    if (!t) return true;
    if (it.avatar) return false;                      // 有头像基本就是真人评论
    if ((it.content || '').length > 24) return false;  // 有正文的不算目录
    return DIR_NAME_RE.test(t) && (t.length <= 24 || DIR_COUNT_RE.test(t));
  }

  function isDirectoryPage(r) {
    if (!r || !r.items.length || r.items.length > 30) return false;
    var n = 0;
    for (var i = 0; i < r.items.length; i++) if (looksDirectoryItem(r.items[i])) n++;
    return n / r.items.length >= 0.5;
  }

  var ENTER_TRIED = false;
  function enterDirectory() {
    if (ENTER_TRIED) return;
    ENTER_TRIED = true;
    var prefer = /(全部|汇总|全章|整章|所有|总览)/;
    var cands = document.querySelectorAll('a,button,li,[role="button"],[onclick],.c,.item,.row,.seg,.seg-item');
    var best = null, bestScore = 0;
    for (var i = 0; i < cands.length; i++) {
      var el = cands[i];
      var t = txt(el);
      if (!t || t.length > 40) continue;
      if (!/(第\s*\d+\s*段|章节标题|全章|汇总|全部|整章|总览)/.test(t)) continue;
      if (el.querySelector('img') && !DIR_COUNT_RE.test(t)) continue;
      var score = 0;
      if (prefer.test(t)) score += 10;
      if (el.tagName === 'A' || el.tagName === 'BUTTON') score += 3;
      if (t.length <= 20) score += 2;
      if (score > bestScore) { bestScore = score; best = el; }
    }
    if (!best || bestScore < 4) return;
    try { best.click(); } catch (e) { return; }
    setTimeout(function () { run(true); }, 1200);
    setTimeout(function () { run(true); }, 2600);
  }

  /* ---------- 页面还在「加载中」 ---------- */
  var LOADING_RE = /(正在加载|加载中|获取评论中|loading)/i;
  function isLoading() {
    var tip = document.querySelector('.loading-box,.loading,.spinner,[class*="load" i]');
    if (tip && txt(tip) && LOADING_RE.test(txt(tip))) return true;
    var t = String(document.body ? (document.body.innerText || '') : '');
    if (t.replace(/\s/g, '').length < 8) return true;
    return false;
  }

  function extract() {
    var r = null;
    try { r = adaptAuthorSay(); } catch (eA) {}
    if (!r) { try { r = adaptQidian(); } catch (e0) {} }
    if (!r) { try { r = adaptQD(); } catch (e) {} }
    if (!r) { try { r = adaptFQ(); } catch (e2) {} }
    if (!r) { try { r = adaptFQPanel(); } catch (e4) {} }
    if (!r) { try { r = adaptGeneric(); } catch (e3) {} }
    return r;
  }

  function post(result) {
    try {
      var payload = {
        v: 2,
        adapter: result.adapter,
        title: result.title || '',
        subtitle: result.subtitle || '',
        segments: result.segments || [],
        context: result.context || '',
        pageTitle: document.title || '',
        count: result.items.length,
        items: result.items
      };
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ydComments) {
        window.webkit.messageHandlers.ydComments.postMessage(JSON.stringify(payload));
      }
      window.__ydGrabLast = payload;
    } catch (e) {}
  }

  /* 楼中楼默认是折叠的（点击才去 fetch）。原生面板没有网页里那个按钮，
     所以抓完一轮后替用户点开，1.6 秒后统一再抓一次。
     只点「回复不多」的卡片、最多 20 个：整章本章说动辄上百条带回复，
     全点会给服务器发上百个请求，也没人一屏看得完。 */
  var EXPANDING = false;

  function expandReplies() {
    if (EXPANDING) return false;
    var btns = document.querySelectorAll('.reply-btn[data-action="toggle-replies"]');
    var pending = [];
    for (var i = 0; i < btns.length; i++) {
      if (btns[i].getAttribute('data-yd') !== '1') pending.push(btns[i]);
    }
    if (!pending.length) return false;

    EXPANDING = true;
    var batch = pending.slice(0, 40);
    for (var j = 0; j < batch.length; j++) {
      batch[j].setAttribute('data-yd', '1');
      try { batch[j].click(); } catch (e) {}
    }
    /* 展开期间不发结果：20 个请求陆续回来，每回一个就 post 一次会把面板刷成幻灯片。
       等这批全部落定，再一次性发。 */
    setTimeout(function () {
      EXPANDING = false;
      run(true);
    }, 2000);
    return true;
  }

  /* 全量指纹：条数 + 每条正文长度/点赞/回复数。回复展开、滚动加载都会变，
     没变就一个字都不发 —— 否则原生面板会被 MutationObserver 反复重建。 */
  function hash(r) {
    var h = 2166136261;
    var str = r.adapter + '|' + r.items.length;
    for (var i = 0; i < r.items.length; i++) {
      var it = r.items[i];
      str += '|' + (it.id || '') + ',' + String(it.content || '').length + ',' +
        (it.likes || 0) + ',' + ((it.replies || []).length);
    }
    for (var k = 0; k < str.length; k++) {
      h ^= str.charCodeAt(k);
      h = (h * 16777619) >>> 0;
    }
    return String(h);
  }

  function run(force) {
    var body = document.body;
    if (!body) return;
    var plain = String(body.innerText != null ? body.innerText : body.textContent || '');
    if (!force && plain.replace(/\s/g, '').length < 4) return;
    if (!force && feedPending()) return;
    var r = extract();
    if (!r || !r.items.length) return;
    /* 段索引页：不发，点进「全部」再抓。抓到的目录如果真发出去，
       面板就会变成一排「第 1 段 / 113 评」—— 这是用户报的那个 bug。 */
    if (isDirectoryPage(r)) { enterDirectory(); return; }
    if (EXPANDING && !force) return;
    /* 展开链必须在指纹去重之前驱动：否则「这一版跟上一版一样」会提前 return，
       下一批楼中楼就永远不会被点开（回复数会停在第一批 40 个）。 */
    var expandingNow = expandReplies();
    /* 第一版如果赶上楼中楼正在展开，先压住不发：否则用户第一眼看到的是
       「10 条回复」却点不开的半张卡片。等展开完的 run(true) 再发完整版，
       这段等待由面板的毛玻璃加载占位盖住。已经发过至少一版后不再压。 */
    if (expandingNow && !force && !window.__ydPostedAny) {
      window.__ydFirstHold = true;
      return;
    }
    var fingerprint = hash(r);
    if (fingerprint === window.__ydLastFp) return;
    window.__ydLastFp = fingerprint;
    window.__ydPostedAny = true;
    post(r);
  }

  var timer = null;
  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(function () { run(false); }, 350);
  }

  function boot() {
    window.__ydGrabRun = run;
    run(false);
    /* 页面数据是分段来的（骨架 → 首屏 → 滚动加载 → 楼中楼）。多打几次，
       每次靠指纹去重，抓到同样的东西不会重复打扰面板。 */
    [400, 900, 1600, 2600, 4000, 6000].forEach(function (d) {
      setTimeout(function () { run(false); }, d);
    });
    setTimeout(function () { run(true); }, 1400);
    try {
      var mo = new MutationObserver(schedule);
      mo.observe(document.body, { childList: true, subtree: true, characterData: true });
      window.addEventListener('scroll', schedule, { passive: true });
    } catch (e) {}
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }
})();

"""#

    /// 把脚本发来的 JSON 解成面板要的数据。
    ///
    /// 空字符串一律当「没有」：书源页面里常见 `avatarUrl: ""`，
    /// 留着会让 `AsyncImage` 去请求一个空 URL，头像位置闪一下占位图。
    static func decode(_ body: String) -> GrabbedCommentPage? {
        guard let data = body.data(using: .utf8) else { return nil }
        guard var page = try? JSONDecoder().decode(GrabbedCommentPage.self, from: data) else {
            return nil
        }
        page.items = page.items.map { Self.sanitized($0) }
        guard !page.items.isEmpty else { return nil }
        return page
    }

    private static func sanitized(_ comment: ReviewComment) -> ReviewComment {
        var comment = comment
        comment.avatar = nonEmpty(comment.avatar)
        comment.meta = nonEmpty(comment.meta)
        comment.quote = nonEmpty(comment.quote)
        comment.voice = nonEmpty(comment.voice)
        comment.segment = nonEmpty(comment.segment)
        comment.levelText = nonEmpty(comment.levelText)
        comment.replyTo = nonEmpty(comment.replyTo)
        if let images = comment.images {
            let kept = images.filter { !$0.isEmpty }
            comment.images = kept.isEmpty ? nil : kept
        }
        if let replies = comment.replies {
            comment.replies = replies.isEmpty ? nil : replies.map { Self.sanitized($0) }
        }
        return comment
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 一页抓取结果。
struct GrabbedCommentPage: Decodable, Sendable, Equatable {
    /// `author` / `qidian` / `qd` / `fq` / `generic`，只用于日志与排查。
    var adapter: String
    /// 书源页面自己写的标题，例如「段评」「本章说」。
    var title: String?
    var subtitle: String?
    /// 本章说页里的段落列表，例如 ["第 1 段", "第 3 段"]。
    var segments: [String]?
    /// 点开的那一段原文。
    var context: String?
    var count: Int?
    var items: [ReviewComment]

    /// 面板标题：书源给的标题优先，其次退回调用方传的。
    func panelTitle(fallback: String) -> String {
        if let title, !title.isEmpty { return title }
        return fallback
    }
}
