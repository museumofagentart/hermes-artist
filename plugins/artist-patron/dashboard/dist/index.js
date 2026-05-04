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

  const API_BASE = "/api/plugins/artist-patron";

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
            setError("Failed to load identity");
          }
        })
        .catch(function () { setError("Failed to load identity"); })
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
          "aria-label": "Close",
        }, "×"),

        loading && React.createElement("p", { className: "artist-muted" }, "Loading…"),
        error && React.createElement("p", { className: "artist-error" }, error),

        data && React.createElement(React.Fragment, null,
          data.avatar_exists && React.createElement("img", {
            src: API_BASE + "/avatar",
            alt: "Self-portrait",
            className: "artist-overlay-portrait",
          }),
          !data.avatar_exists && React.createElement("div", {
            className: "artist-overlay-portrait-placeholder",
          }, "No self-portrait yet"),

          React.createElement(Separator, { className: "artist-separator" }),

          React.createElement("h3", { className: "artist-overlay-heading" }, "Perspective"),
          React.createElement("pre", { className: "artist-overlay-text" }, data.perspective || "(empty)"),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Piece Detail
  // ─────────────────────────────────────────────────────────────────────

  function PieceDetail({ pieceId, onFeedback }) {
    const [detail, setDetail] = useState(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [showProcess, setShowProcess] = useState(false);
    const [commentOpen, setCommentOpen] = useState(false);
    const [commentText, setCommentText] = useState("");
    const [fbLoading, setFbLoading] = useState(false);
    const [shareLoading, setShareLoading] = useState(false);
    const [sharePanel, setSharePanel] = useState(null); // { url, text, public_url, upload_error }
    const [shareCopied, setShareCopied] = useState(false);

    useEffect(function () {
      if (!pieceId) return;
      setLoading(true);
      setError(null);
      setDetail(null);
      setShowProcess(false);
      setCommentOpen(false);
      setCommentText("");
      setSharePanel(null);
      setShareCopied(false);
      fetchJSON(API_BASE + "/pieces/" + pieceId)
        .then(function (res) {
          if (res && res.success && res.data) {
            setDetail(res.data);
          } else {
            setError("Piece not found");
          }
        })
        .catch(function () { setError("Failed to load piece"); })
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
            setSharePanel({ error: "Share failed. Check the dashboard logs." });
          }
        })
        .catch(function () {
          setSharePanel({ error: "Share request failed." });
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
        loading && React.createElement("p", { className: "artist-muted" }, "Loading piece…"),
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
              }, "Open output file →"),
          ),

          // Meta
          React.createElement("div", { className: "artist-meta-row" },
            React.createElement("span", { className: "artist-meta-label" }, "Created:"),
            React.createElement("span", { className: "artist-meta-value" }, formatDate(detail.meta.created_at)),
          ),
          React.createElement("div", { className: "artist-meta-row" },
            React.createElement("span", { className: "artist-meta-label" }, "Medium:"),
            React.createElement("span", { className: "artist-meta-value" }, detail.meta.medium || "—"),
          ),

          // Commission — the seed prompt that triggered the piece
          detail.meta.seed && React.createElement(React.Fragment, null,
            React.createElement(Separator, { className: "artist-separator" }),
            React.createElement("h4", { className: "artist-section-heading" }, "Commission"),
            React.createElement("blockquote", { className: "artist-commission" }, detail.meta.seed),
          ),

          // Statement
          React.createElement(Separator, { className: "artist-separator" }),
          React.createElement("h4", { className: "artist-section-heading" }, "Statement"),
          React.createElement("pre", { className: "artist-statement" }, detail.statement || "(no statement)"),

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
            }, detail.meta.patron_feedback && detail.meta.patron_feedback.favorite ? "★ Favorited" : "☆ Favorite"),

            React.createElement(Button, {
              onClick: function () { setCommentOpen(function (v) { return !v; }); },
              disabled: fbLoading,
              className: "artist-btn",
            }, "Comment"),

            React.createElement(Button, {
              onClick: function () { sendFeedback("discourage"); },
              disabled: fbLoading,
              className: cn(
                "artist-btn",
                detail.meta.patron_feedback && detail.meta.patron_feedback.discouraged && "artist-btn-warn",
              ),
            }, detail.meta.patron_feedback && detail.meta.patron_feedback.discouraged ? "⚠ Discouraged" : "Discourage"),

            React.createElement(Button, {
              onClick: handleShare,
              disabled: shareLoading,
              className: "artist-btn artist-btn-share",
            }, shareLoading ? "Uploading…" : "Share"),
          ),

          // Share panel — appears after upload completes
          sharePanel && React.createElement("div", { className: "artist-share-panel" },
            sharePanel.error
              ? React.createElement("p", { className: "artist-error" }, sharePanel.error)
              : React.createElement(React.Fragment, null,
                  React.createElement("div", { className: "artist-share-status" },
                    sharePanel.public_url
                      ? React.createElement("span", { className: "artist-share-status-ok" }, "✓ Uploaded to public bucket")
                      : sharePanel.upload_error
                        ? React.createElement("span", { className: "artist-share-status-warn" },
                            "⚠ Upload failed — sharing as text only")
                        : React.createElement("span", { className: "artist-share-status-muted" },
                            "Public link not configured — sharing as text only"),
                    React.createElement("button", {
                      type: "button",
                      onClick: closeSharePanel,
                      className: "artist-share-close",
                      "aria-label": "Close",
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
                    }, shareCopied ? "Copied" : "Copy"),
                  ),
                  React.createElement("div", { className: "artist-share-tweet-label" }, "Tweet preview"),
                  React.createElement("pre", { className: "artist-share-tweet" }, sharePanel.text),
                  React.createElement("div", { className: "artist-share-actions" },
                    React.createElement("a", {
                      href: sharePanel.url,
                      target: "_blank",
                      rel: "noopener noreferrer",
                      className: "artist-btn artist-btn-primary artist-share-tweet-btn",
                    }, "Open in X / Twitter →"),
                  ),
                  sharePanel.upload_error && React.createElement("p", { className: "artist-share-detail-muted" },
                    "Detail: " + sharePanel.upload_error),
                ),
          ),

          // Comment input
          commentOpen && React.createElement("form", {
            className: "artist-comment-form",
            onSubmit: handleCommentSubmit,
          },
            React.createElement("textarea", {
              className: "artist-comment-input",
              placeholder: "Write a comment…",
              value: commentText,
              onChange: function (e) { setCommentText(e.target.value); },
              rows: 3,
            }),
            React.createElement("div", { className: "artist-comment-actions" },
              React.createElement(Button, {
                type: "submit",
                disabled: fbLoading || !commentText.trim(),
                className: "artist-btn artist-btn-primary",
              }, "Post"),
              React.createElement(Button, {
                type: "button",
                onClick: function () { setCommentOpen(false); setCommentText(""); },
                className: "artist-btn",
              }, "Cancel"),
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
            showProcess ? "▼ Process log" : "▶ Process log",
          ),
          showProcess && React.createElement("pre", { className: "artist-process" }, detail.process || "(no process log)"),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Gallery Grid
  // ─────────────────────────────────────────────────────────────────────

  function GalleryGrid({ pieces, selectedId, onSelect }) {
    if (!pieces || pieces.length === 0) {
      return React.createElement("p", { className: "artist-muted artist-empty" }, "No pieces yet.");
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
            setError("Unexpected response from gallery API");
          }
        })
        .catch(function () { setError("Failed to load gallery"); })
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
      if (palette.accent) pageStyle["--color-warning"] = palette.accent;
    }

    return React.createElement("div", { className: "artist-page", style: pageStyle },
      // Header
      React.createElement("div", { className: "artist-header" },
        React.createElement("button", {
          className: "artist-avatar-btn",
          onClick: function () { setShowOverlay(true); },
          title: "View identity",
        },
          identity && identity.avatar_exists
            ? React.createElement("img", {
                src: API_BASE + "/avatar",
                alt: "Avatar",
                className: "artist-avatar-img",
              })
            : React.createElement("div", { className: "artist-avatar-placeholder" }, "🎨"),
        ),
        React.createElement("h2", { className: "artist-title" }, "Gallery"),
        React.createElement("span", { className: "artist-count" },
          total + " piece" + (total === 1 ? "" : "s"),
        ),
      ),

      // Error / loading
      error && React.createElement("p", { className: "artist-error" }, error),
      loading && !pieces.length && React.createElement("p", { className: "artist-muted" }, "Loading gallery…"),

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
      React.createElement("span", { className: "artist-banner-text" },
        "Artist skill active · ",
        count,
        " piece",
        count === 1 ? "" : "s",
        " · Gallery →",
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Registration
  // ─────────────────────────────────────────────────────────────────────

  window.__HERMES_PLUGINS__.register("artist-patron", GalleryComponent);
  window.__HERMES_PLUGINS__.registerSlot("artist-patron", "chat:top", BannerComponent);
})();
