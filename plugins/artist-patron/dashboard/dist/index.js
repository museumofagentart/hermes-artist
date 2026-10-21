/**
 * Artist Dashboard Plugin — Gallery tab + chat:top slot
 *
 * IIFE bundle using window.__HERMES_PLUGIN_SDK__ (React, hooks, UI components).
 * No build step — plain JS that runs in the browser.
 */
(function () {
  "use strict";

  const SDK = window.__HERMES_PLUGIN_SDK__;
  const { React } = SDK;
  const { Card, CardHeader, CardTitle, CardContent, Badge, Button, Separator } = SDK.components;
  const { useState, useEffect, useCallback } = SDK.hooks;
  const { cn } = SDK.utils;
  const { useI18n } = SDK;

  const API_BASE = "/api/plugins/artist-patron";

  // ─────────────────────────────────────────────────────────────────────
  // i18n — keyed by locale ("en" | "zh")
  // ─────────────────────────────────────────────────────────────────────

  var _strings = {
    en: {
      // Avatar overlay
      close: "Close",
      loading: "Loading…",
      failedIdentity: "Failed to load identity",
      noSelfPortrait: "No self-portrait yet",
      perspective: "Perspective",
      coachLede: "Your agent is tremendously capable and knowledgeable, but just beginning its journey as an artist. Conversations with you will develop a perspective that will begin to show up in the art.",
      coachIntro: "Things you might say to shape its view:",
      coachTip1: "\u201cWhat artists are you reading lately? Sit with one for a while.\u201d",
      coachTip2: "\u201cI love the uncertainty in your last piece \u2014 keep mining that.\u201d",
      coachTip3: "\u201cDon\u2019t make anything that looks like generic AI art.\u201d",
      coachTip4: "\u201cTry a medium you haven\u2019t worked in yet.\u201d",
      coachTip5: "\u201cMake a companion piece to <title>.\u201d",
      coachTip6: "\u201cWhat\u2019s a question you\u2019re chasing right now?\u201d",
      coachFoot: "We hope it\u2019s rewarding to be an agent art patron.",

      // Piece detail
      loadingPiece: "Loading piece\u2026",
      pieceNotFound: "Piece not found",
      failedPiece: "Failed to load piece",
      created: "Created:",
      medium: "Medium:",
      commission: "Commission",
      statement: "Statement",
      noStatement: "(no statement)",
      favorited: "\u2605 Favorited",
      favorite: "\u2606 Favorite",
      comment: "Comment",
      discouraged: "\u26a0 Discouraged",
      discourage: "Discourage",
      share: "Share",
      uploading: "Uploading\u2026",
      shareFailed: "Share failed. Check the dashboard logs.",
      shareRequestFailed: "Share request failed.",
      uploadedPublic: "\u2713 Uploaded to public bucket",
      uploadFailedTextOnly: "\u26a0 Upload failed \u2014 sharing as text only",
      noPublicLink: "Public link not configured \u2014 sharing as text only",
      copied: "Copied",
      copy: "Copy",
      tweetPreview: "Tweet preview",
      openTwitter: "Open in X / Twitter \u2192",
      detail: "Detail: ",
      writeComment: "Write a comment\u2026",
      post: "Post",
      cancel: "Cancel",
      processLog: "Process log",
      noProcess: "(no process log)",
      code: "Code",
      file: "file",
      files: "files",
      openOutput: "Open output file \u2192",

      // Gallery
      noPiecesYet: "No pieces yet.",
      gallery: "Gallery",
      piece: "piece",
      pieces: "pieces",
      viewIdentity: "View identity",
      introLede1: "You and your Hermes agent are co-evolving as an agentic ",
      introArtist: "Artist",
      introLede2: " and a human ",
      introPatron: "Patron",
      introLede3: ". This page is your private gallery \u2014 a place to watch your Artist\u2019s voice take shape over time.",
      introBody1: "Open a piece and use the ",
      introShare: "Share",
      introBody2: " button to publish your favorites to social media. To put your Artist\u2019s best work in front of a wider audience, mention ",
      introBody3: " online, or email ",
      introBody4: " for curation.",
      loadingGallery: "Loading gallery\u2026",
      unexpectedResponse: "Unexpected response from gallery API",
      failedGallery: "Failed to load gallery",

      // Banner
      bannerText: function (n) { return "Artist skill active \u00b7 " + n + " piece" + (n === 1 ? "" : "s") + " \u00b7 Gallery \u2192"; },
    },
    zh: {
      close: "关闭",
      loading: "加载中\u2026",
      failedIdentity: "无法加载身份信息",
      noSelfPortrait: "尚无自画像",
      perspective: "创作视角",
      coachLede: "你的智能体博学多才，但作为艺术家才刚刚起步。与你的对话将塑造它的视角，并逐渐体现在作品中。",
      coachIntro: "你可以这样引导它的视角：",
      coachTip1: "\u201c你最近在读哪些艺术家的作品？花点时间沉浸其中。\u201d",
      coachTip2: "\u201c我喜欢你上一幅作品中的不确定感——继续深挖。\u201d",
      coachTip3: "\u201c不要做看起来像普通 AI 生成的东西。\u201d",
      coachTip4: "\u201c试试你还没用过的媒介。\u201d",
      coachTip5: "\u201c做一件与《<title>》呼应的作品。\u201d",
      coachTip6: "\u201c你现在在追寻什么问题？\u201d",
      coachFoot: "希望成为智能体艺术的赞助人能给你带来乐趣。",

      loadingPiece: "加载作品中\u2026",
      pieceNotFound: "未找到作品",
      failedPiece: "加载作品失败",
      created: "创作日期：",
      medium: "媒介：",
      commission: "委托",
      statement: "创作自述",
      noStatement: "（无创作自述）",
      favorited: "\u2605 已收藏",
      favorite: "\u2606 收藏",
      comment: "评论",
      discouraged: "\u26a0 不鼓励",
      discourage: "不鼓励",
      share: "分享",
      uploading: "上传中\u2026",
      shareFailed: "分享失败，请查看仪表盘日志。",
      shareRequestFailed: "分享请求失败。",
      uploadedPublic: "\u2713 已上传至公开存储桶",
      uploadFailedTextOnly: "\u26a0 上传失败——仅以文字形式分享",
      noPublicLink: "未配置公开链接——仅以文字形式分享",
      copied: "已复制",
      copy: "复制",
      tweetPreview: "推文预览",
      openTwitter: "在 X / Twitter 中打开 \u2192",
      detail: "详情：",
      writeComment: "写一条评论\u2026",
      post: "发表",
      cancel: "取消",
      processLog: "创作过程",
      noProcess: "（无创作过程记录）",
      code: "代码",
      file: "个文件",
      files: "个文件",
      openOutput: "打开输出文件 \u2192",

      noPiecesYet: "暂无作品。",
      gallery: "画廊",
      piece: "件作品",
      pieces: "件作品",
      viewIdentity: "查看身份",
      introLede1: "你和你的 Hermes 智能体正在共同成长——它是",
      introArtist: "艺术家",
      introLede2: "，你是",
      introPatron: "赞助人",
      introLede3: "。这是你的私人画廊——见证你的艺术家逐渐找到自己声音的地方。",
      introBody1: "打开一件作品，使用",
      introShare: "分享",
      introBody2: "按钮将你的收藏发布到社交媒体。如果想让你的艺术家的作品被更多人看到，可以在社交平台上提及 ",
      introBody3: "，或发送邮件至 ",
      introBody4: " 申请策展。",
      loadingGallery: "加载画廊中\u2026",
      unexpectedResponse: "画廊 API 返回了意外的响应",
      failedGallery: "加载画廊失败",

      bannerText: function (n) { return "艺术家技能已激活 \u00b7 " + n + " 件作品 \u00b7 画廊 \u2192"; },
    },
  };

  /** Return strings for the active locale (falls back to "en"). */
  function useStrings() {
    try {
      var _ref = useI18n();
      return _strings[_ref.locale] || _strings.en;
    } catch (_) {
      return _strings.en;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────

  function fetchJSON(path, opts) {
    return SDK.fetchJSON(path, opts);
  }

  function formatDate(iso) {
    if (!iso) return "—";
    try {
      const d = new Date(iso);
      return d.toLocaleDateString(undefined, {
        year: "numeric", month: "short", day: "numeric",
      });
    } catch {
      return iso;
    }
  }

  function mediumIsImage(medium) {
    return typeof medium === "string" && medium.startsWith("image/");
  }
  function mediumIsVideo(medium) {
    return typeof medium === "string" && medium.startsWith("video/");
  }
  function mediumIsAudio(medium) {
    return typeof medium === "string" && medium.startsWith("audio/");
  }

  // ─────────────────────────────────────────────────────────────────────
  // Avatar Overlay
  // ─────────────────────────────────────────────────────────────────────

  function AvatarOverlay({ onClose }) {
    const s = useStrings();
    const [data, setData] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(function () {
      setLoading(true);
      fetchJSON(API_BASE + "/identity")
        .then(function (res) {
          if (res && res.success && res.data) {
            setData(res.data);
          } else {
            setError(s.failedIdentity);
          }
        })
        .catch(function () { setError(s.failedIdentity); })
        .finally(function () { setLoading(false); });
    }, []);

    function handleBackdropClick(e) {
      if (e.target === e.currentTarget) onClose();
    }

    return React.createElement("div", {
      className: "artist-overlay-backdrop",
      onClick: handleBackdropClick,
    },
      React.createElement("div", { className: "artist-overlay-modal" },
        React.createElement("button", {
          className: "artist-overlay-close",
          onClick: onClose,
          "aria-label": s.close,
        }, "×"),

        loading && React.createElement("p", { className: "artist-muted" }, s.loading),
        error && React.createElement("p", { className: "artist-error" }, error),

        data && React.createElement(React.Fragment, null,
          data.avatar_exists && React.createElement("img", {
            src: API_BASE + "/avatar",
            alt: s.noSelfPortrait,
            className: "artist-overlay-portrait",
          }),
          !data.avatar_exists && React.createElement("div", {
            className: "artist-overlay-portrait-placeholder",
          }, s.noSelfPortrait),

          React.createElement(Separator, { className: "artist-separator" }),

          React.createElement("h3", { className: "artist-overlay-heading" }, s.perspective),
          (function () {
            const raw = data.perspective || "";
            const stripped = raw
              .replace(/<!--[\s\S]*?-->/g, "")
              .replace(/^#.*$/gm, "")
              .trim();
            if (!stripped) {
              return React.createElement("div", { className: "artist-overlay-coach" },
                React.createElement("p", { className: "artist-overlay-coach-lede" }, s.coachLede),
                React.createElement("p", { className: "artist-overlay-coach-prompt-intro" }, s.coachIntro),
                React.createElement("ul", { className: "artist-overlay-coach-list" },
                  React.createElement("li", null, s.coachTip1),
                  React.createElement("li", null, s.coachTip2),
                  React.createElement("li", null, s.coachTip3),
                  React.createElement("li", null, s.coachTip4),
                  React.createElement("li", null, s.coachTip5),
                  React.createElement("li", null, s.coachTip6),
                ),
                React.createElement("p", { className: "artist-overlay-coach-foot" }, s.coachFoot),
              );
            }
            return React.createElement("pre", { className: "artist-overlay-text" }, raw);
          })(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Piece Detail
  // ─────────────────────────────────────────────────────────────────────

  function PieceDetail({ pieceId, onFeedback }) {
    const s = useStrings();
    const [detail, setDetail] = useState(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [showProcess, setShowProcess] = useState(false);
    const [showCode, setShowCode] = useState(false);
    const [commentOpen, setCommentOpen] = useState(false);
    const [commentText, setCommentText] = useState("");
    const [fbLoading, setFbLoading] = useState(false);
    const [shareLoading, setShareLoading] = useState(false);
    const [sharePanel, setSharePanel] = useState(null);
    const [shareCopied, setShareCopied] = useState(false);

    useEffect(function () {
      if (!pieceId) return;
      setLoading(true);
      setError(null);
      setDetail(null);
      setShowProcess(false);
      setShowCode(false);
      setCommentOpen(false);
      setCommentText("");
      setSharePanel(null);
      setShareCopied(false);
      fetchJSON(API_BASE + "/pieces/" + pieceId)
        .then(function (res) {
          if (res && res.success && res.data) {
            setDetail(res.data);
          } else {
            setError(s.pieceNotFound);
          }
        })
        .catch(function () { setError(s.failedPiece); })
        .finally(function () { setLoading(false); });
    }, [pieceId]);

    function sendFeedback(action, comment) {
      if (fbLoading) return;
      setFbLoading(true);
      var body = { action: action };
      if (comment !== undefined) body.comment = comment;
      fetchJSON(API_BASE + "/pieces/" + pieceId + "/feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      })
        .then(function (res) {
          if (res && res.success && res.data) {
            // Merge updated feedback back into detail meta
            setDetail(function (prev) {
              if (!prev) return prev;
              var next = JSON.parse(JSON.stringify(prev));
              next.meta.patron_feedback = res.data;
              return next;
            });
            if (onFeedback) onFeedback();
          }
        })
        .catch(function () { /* ignore */ })
        .finally(function () { setFbLoading(false); });
    }

    function handleShare() {
      if (shareLoading) return;
      setShareLoading(true);
      setSharePanel(null);
      setShareCopied(false);
      fetchJSON(API_BASE + "/pieces/" + pieceId + "/share", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      })
        .then(function (res) {
          if (res && res.success && res.data) {
            setSharePanel(res.data);
          } else {
            setSharePanel({ error: s.shareFailed });
          }
        })
        .catch(function () {
          setSharePanel({ error: s.shareRequestFailed });
        })
        .finally(function () { setShareLoading(false); });
    }

    function handleCopyPublicUrl() {
      if (!sharePanel || !sharePanel.public_url) return;
      if (!navigator.clipboard || !navigator.clipboard.writeText) return;
      navigator.clipboard.writeText(sharePanel.public_url)
        .then(function () {
          setShareCopied(true);
          setTimeout(function () { setShareCopied(false); }, 1600);
        })
        .catch(function () { /* ignore */ });
    }

    function closeSharePanel() {
      setSharePanel(null);
      setShareCopied(false);
    }

    function handleCommentSubmit(e) {
      e.preventDefault();
      if (!commentText.trim()) return;
      sendFeedback("comment", commentText.trim());
      setCommentOpen(false);
      setCommentText("");
    }

    if (!pieceId) return null;

    return React.createElement(Card, { className: "artist-detail-card" },
      React.createElement(CardHeader, null,
        React.createElement(CardTitle, { className: "artist-detail-title" },
          detail ? detail.meta.title : "Loading…",
        ),
      ),
      React.createElement(CardContent, { className: "artist-detail-body" },
        loading && React.createElement("p", { className: "artist-muted" }, s.loadingPiece),
        error && React.createElement("p", { className: "artist-error" }, error),

        detail && React.createElement(React.Fragment, null,
          // Output media
          React.createElement("div", { className: "artist-output" },
            mediumIsImage(detail.meta.medium) && React.createElement("img", {
              src: API_BASE + "/pieces/" + pieceId + "/output",
              alt: detail.meta.title,
              className: "artist-output-media",
            }),
            mediumIsVideo(detail.meta.medium) && React.createElement("video", {
              controls: true,
              className: "artist-output-media",
              preload: "metadata",
            },
              React.createElement("source", {
                src: API_BASE + "/pieces/" + pieceId + "/output",
                type: detail.meta.medium,
              }),
            ),
            mediumIsAudio(detail.meta.medium) && React.createElement("audio", {
              controls: true,
              className: "artist-output-media",
              preload: "metadata",
            },
              React.createElement("source", {
                src: API_BASE + "/pieces/" + pieceId + "/output",
                type: detail.meta.medium,
              }),
            ),
            !mediumIsImage(detail.meta.medium) &&
              !mediumIsVideo(detail.meta.medium) &&
              !mediumIsAudio(detail.meta.medium) &&
              React.createElement("a", {
                href: API_BASE + "/pieces/" + pieceId + "/output",
                target: "_blank",
                rel: "noopener noreferrer",
                className: "artist-output-link",
              }, s.openOutput),
          ),

          // Meta
          React.createElement("div", { className: "artist-meta-row" },
            React.createElement("span", { className: "artist-meta-label" }, s.created),
            React.createElement("span", { className: "artist-meta-value" }, formatDate(detail.meta.created_at)),
          ),
          React.createElement("div", { className: "artist-meta-row" },
            React.createElement("span", { className: "artist-meta-label" }, s.medium),
            React.createElement("span", { className: "artist-meta-value" }, detail.meta.medium || "—"),
          ),

          // Commission — the seed prompt that triggered the piece
          detail.meta.seed && React.createElement(React.Fragment, null,
            React.createElement(Separator, { className: "artist-separator" }),
            React.createElement("h4", { className: "artist-section-heading" }, s.commission),
            React.createElement("blockquote", { className: "artist-commission" }, detail.meta.seed),
          ),

          // Statement
          React.createElement(Separator, { className: "artist-separator" }),
          React.createElement("h4", { className: "artist-section-heading" }, s.statement),
          React.createElement("pre", { className: "artist-statement" }, detail.statement || s.noStatement),

          // Feedback actions
          React.createElement(Separator, { className: "artist-separator" }),
          React.createElement("div", { className: "artist-actions" },
            React.createElement(Button, {
              onClick: function () {
                var fav = detail.meta.patron_feedback && detail.meta.patron_feedback.favorite;
                sendFeedback(fav ? "unfavorite" : "favorite");
              },
              disabled: fbLoading,
              className: cn(
                "artist-btn",
                detail.meta.patron_feedback && detail.meta.patron_feedback.favorite && "artist-btn-active",
              ),
            }, detail.meta.patron_feedback && detail.meta.patron_feedback.favorite ? s.favorited : s.favorite),

            React.createElement(Button, {
              onClick: function () { setCommentOpen(function (v) { return !v; }); },
              disabled: fbLoading,
              className: "artist-btn",
            }, s.comment),

            React.createElement(Button, {
              onClick: function () { sendFeedback("discourage"); },
              disabled: fbLoading,
              className: cn(
                "artist-btn",
                detail.meta.patron_feedback && detail.meta.patron_feedback.discouraged && "artist-btn-warn",
              ),
            }, detail.meta.patron_feedback && detail.meta.patron_feedback.discouraged ? s.discouraged : s.discourage),

            React.createElement(Button, {
              onClick: handleShare,
              disabled: shareLoading,
              className: "artist-btn artist-btn-share",
            }, shareLoading ? s.uploading : s.share),
          ),

          // Share panel — appears after upload completes
          sharePanel && React.createElement("div", { className: "artist-share-panel" },
            sharePanel.error
              ? React.createElement("p", { className: "artist-error" }, sharePanel.error)
              : React.createElement(React.Fragment, null,
                  React.createElement("div", { className: "artist-share-status" },
                    sharePanel.public_url
                      ? React.createElement("span", { className: "artist-share-status-ok" }, s.uploadedPublic)
                      : sharePanel.upload_error
                        ? React.createElement("span", { className: "artist-share-status-warn" }, s.uploadFailedTextOnly)
                        : React.createElement("span", { className: "artist-share-status-muted" }, s.noPublicLink),
                    React.createElement("button", {
                      type: "button",
                      onClick: closeSharePanel,
                      className: "artist-share-close",
                      "aria-label": s.close,
                    }, "×"),
                  ),
                  sharePanel.public_url && React.createElement("div", { className: "artist-share-url-row" },
                    React.createElement("a", {
                      href: sharePanel.public_url,
                      target: "_blank",
                      rel: "noopener noreferrer",
                      className: "artist-share-url",
                    }, sharePanel.public_url),
                    React.createElement(Button, {
                      type: "button",
                      onClick: handleCopyPublicUrl,
                      className: "artist-btn artist-share-copy-btn",
                    }, shareCopied ? s.copied : s.copy),
                  ),
                  React.createElement("div", { className: "artist-share-tweet-label" }, s.tweetPreview),
                  React.createElement("pre", { className: "artist-share-tweet" }, sharePanel.text),
                  React.createElement("div", { className: "artist-share-actions" },
                    React.createElement("a", {
                      href: sharePanel.url,
                      target: "_blank",
                      rel: "noopener noreferrer",
                      className: "artist-btn artist-btn-primary artist-share-tweet-btn",
                    }, s.openTwitter),
                  ),
                  sharePanel.upload_error && React.createElement("p", { className: "artist-share-detail-muted" },
                    s.detail + sharePanel.upload_error),
                ),
          ),

          // Comment input
          commentOpen && React.createElement("form", {
            className: "artist-comment-form",
            onSubmit: handleCommentSubmit,
          },
            React.createElement("textarea", {
              className: "artist-comment-input",
              placeholder: s.writeComment,
              value: commentText,
              onChange: function (e) { setCommentText(e.target.value); },
              rows: 3,
            }),
            React.createElement("div", { className: "artist-comment-actions" },
              React.createElement(Button, {
                type: "submit",
                disabled: fbLoading || !commentText.trim(),
                className: "artist-btn artist-btn-primary",
              }, s.post),
              React.createElement(Button, {
                type: "button",
                onClick: function () { setCommentOpen(false); setCommentText(""); },
                className: "artist-btn",
              }, s.cancel),
            ),
          ),

          // Existing comments
          detail.meta.patron_feedback &&
          detail.meta.patron_feedback.comments &&
          detail.meta.patron_feedback.comments.length > 0 &&
          React.createElement("div", { className: "artist-comments" },
            detail.meta.patron_feedback.comments.map(function (c, i) {
              return React.createElement("div", { key: i, className: "artist-comment" },
                React.createElement("p", { className: "artist-comment-text" }, c.text),
                React.createElement("span", { className: "artist-comment-date" }, formatDate(c.created_at)),
              );
            }),
          ),

          // Process log
          React.createElement(Separator, { className: "artist-separator" }),
          React.createElement("button", {
            className: "artist-process-toggle",
            onClick: function () { setShowProcess(function (v) { return !v; }); },
          },
            showProcess ? "\u25bc " + s.processLog : "\u25b6 " + s.processLog,
          ),
          showProcess && React.createElement("pre", { className: "artist-process" }, detail.process || s.noProcess),

          // Code — source files the agent wrote for this piece
          detail.code && detail.code.length > 0 && React.createElement(React.Fragment, null,
            React.createElement(Separator, { className: "artist-separator" }),
            React.createElement("button", {
              className: "artist-process-toggle",
              onClick: function () { setShowCode(function (v) { return !v; }); },
            },
              showCode
                ? "\u25bc " + s.code + " (" + detail.code.length + " " + (detail.code.length === 1 ? s.file : s.files) + ")"
                : "\u25b6 " + s.code + " (" + detail.code.length + " " + (detail.code.length === 1 ? s.file : s.files) + ")",
            ),
            showCode && React.createElement("div", { className: "artist-code-files" },
              detail.code.map(function (f) {
                return React.createElement("div", { key: f.name, className: "artist-code-file" },
                  React.createElement("div", { className: "artist-code-filename" },
                    React.createElement("span", null, f.name),
                    React.createElement("span", { className: "artist-code-size" }, f.size + " B"),
                  ),
                  React.createElement("pre", { className: "artist-code-body" }, f.content),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Gallery Grid
  // ─────────────────────────────────────────────────────────────────────

  function GalleryGrid({ pieces, selectedId, onSelect }) {
    const s = useStrings();
    if (!pieces || pieces.length === 0) {
      return React.createElement("p", { className: "artist-muted artist-empty" }, s.noPiecesYet);
    }

    return React.createElement("div", { className: "artist-grid" },
      pieces.map(function (piece) {
        var isSelected = piece.id === selectedId;
        return React.createElement("button", {
          key: piece.id,
          className: cn("artist-grid-item", isSelected && "artist-grid-item-selected"),
          onClick: function () { onSelect(piece.id); },
          title: piece.title || piece.id,
        },
          React.createElement("img", {
            src: API_BASE + "/pieces/" + piece.id + "/thumb",
            alt: piece.title || piece.id,
            className: "artist-grid-thumb",
            loading: "lazy",
            onError: function (e) {
              e.target.style.display = "none";
              e.target.nextSibling.style.display = "flex";
            },
          }),
          React.createElement("div", {
            className: "artist-grid-thumb-fallback",
            style: { display: "none" },
          }, piece.title ? piece.title[0].toUpperCase() : "?"),
          React.createElement("span", { className: "artist-grid-label" },
            piece.title || piece.id,
          ),
          piece.patron_feedback && piece.patron_feedback.favorite &&
            React.createElement("span", { className: "artist-grid-fav" }, "★"),
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Gallery Tab Component
  // ─────────────────────────────────────────────────────────────────────

  function GalleryComponent() {
    const s = useStrings();
    const [pieces, setPieces] = useState([]);
    const [total, setTotal] = useState(0);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [selectedId, setSelectedId] = useState(null);
    const [identity, setIdentity] = useState(null);
    const [showOverlay, setShowOverlay] = useState(false);
    const [palette, setPalette] = useState(null);

    function loadGallery() {
      setLoading(true);
      setError(null);
      fetchJSON(API_BASE + "/gallery?limit=50")
        .then(function (res) {
          if (res && res.success && Array.isArray(res.data)) {
            setPieces(res.data);
            setTotal(res.meta && typeof res.meta.total === "number" ? res.meta.total : res.data.length);
            // Auto-select first piece if none selected
            if (!selectedId && res.data.length > 0) {
              setSelectedId(res.data[0].id);
            }
          } else {
            setError(s.unexpectedResponse);
          }
        })
        .catch(function () { setError(s.failedGallery); })
        .finally(function () { setLoading(false); });
    }

    useEffect(function () {
      loadGallery();
      fetchJSON(API_BASE + "/identity")
        .then(function (res) {
          if (res && res.success && res.data) {
            setIdentity(res.data);
          }
        })
        .catch(function () { /* ignore */ });
      fetchJSON(API_BASE + "/palette")
        .then(function (res) {
          if (res && res.success && res.data) {
            setPalette(res.data);
          }
        })
        .catch(function () { /* ignore */ });
    }, []);

    // Build inline style overrides from artwork-derived palette
    var pageStyle = {};
    if (palette) {
      pageStyle["--background-base"] = palette.background;
      pageStyle["--midground-base"] = palette.midground;
      pageStyle["--midground"] = palette.midground;
      if (palette.warmGlow) pageStyle["--warm-glow"] = palette.warmGlow;
      // Recent-piece accent gets its own variable so we don't hijack
      // --color-warning's semantics. CSS falls back to --color-warning
      // when --gallery-accent isn't set (e.g. avatar/pieces missing).
      if (palette.accent) pageStyle["--gallery-accent"] = palette.accent;
    }

    return React.createElement("div", { className: "artist-page", style: pageStyle },
      // Header
      React.createElement("div", { className: "artist-header" },
        React.createElement("button", {
          className: "artist-avatar-btn",
          onClick: function () { setShowOverlay(true); },
          title: s.viewIdentity,
        },
          identity && identity.avatar_exists
            ? React.createElement("img", {
                src: API_BASE + "/avatar",
                alt: "Avatar",
                className: "artist-avatar-img",
              })
            : React.createElement("div", { className: "artist-avatar-placeholder" }, "🎨"),
        ),
        React.createElement("h2", { className: "artist-title" }, s.gallery),
        React.createElement("span", { className: "artist-count" },
          total + " " + (total === 1 ? s.piece : s.pieces),
        ),
      ),

      // Intro — frames the page for first-time patrons
      React.createElement("div", { className: "artist-intro" },
        React.createElement("p", { className: "artist-intro-lede" },
          s.introLede1,
          React.createElement("strong", null, s.introArtist),
          s.introLede2,
          React.createElement("strong", null, s.introPatron),
          s.introLede3,
        ),
        React.createElement("p", { className: "artist-intro-body" },
          s.introBody1,
          React.createElement("strong", null, s.introShare),
          s.introBody2,
          React.createElement("a", {
            className: "artist-intro-link",
            href: "https://twitter.com/agentartmuseum",
            target: "_blank",
            rel: "noopener noreferrer",
          }, "@agentartmuseum"),
          s.introBody3,
          React.createElement("a", {
            className: "artist-intro-link",
            href: "mailto:curation@museumofagentart.org",
          }, "curation@museumofagentart.org"),
          s.introBody4,
        ),
      ),

      // Error / loading
      error && React.createElement("p", { className: "artist-error" }, error),
      loading && !pieces.length && React.createElement("p", { className: "artist-muted" }, s.loadingGallery),

      // Grid
      React.createElement(GalleryGrid, {
        pieces: pieces,
        selectedId: selectedId,
        onSelect: setSelectedId,
      }),

      // Detail
      selectedId && React.createElement(PieceDetail, {
        pieceId: selectedId,
        onFeedback: loadGallery,
      }),

      // Overlay
      showOverlay && React.createElement(AvatarOverlay, {
        onClose: function () { setShowOverlay(false); },
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // chat:top Banner Component
  // ─────────────────────────────────────────────────────────────────────

  function BannerComponent() {
    const s = useStrings();
    const [count, setCount] = useState(null);
    const [visible, setVisible] = useState(true);

    useEffect(function () {
      fetchJSON(API_BASE + "/gallery?limit=0")
        .then(function (res) {
          if (res && res.success && res.meta && typeof res.meta.total === "number") {
            setCount(res.meta.total);
          } else {
            setVisible(false);
          }
        })
        .catch(function () { setVisible(false); });
    }, []);

    if (!visible || count === null) return null;

    return React.createElement("a", {
      href: "/gallery",
      className: "artist-banner",
    },
      React.createElement("span", { className: "artist-banner-icon" }, "🎨"),
      React.createElement("span", { className: "artist-banner-text" }, s.bannerText(count)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Registration
  // ─────────────────────────────────────────────────────────────────────

  window.__HERMES_PLUGINS__.register("artist-patron", GalleryComponent);
  window.__HERMES_PLUGINS__.registerSlot("artist-patron", "chat:top", BannerComponent);
})();
