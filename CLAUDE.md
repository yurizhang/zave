# CLAUDE.md — Zave

Project notes for AI assistants / contributors. Read this before changing the build,
the windowing, or the networking — several non-obvious decisions are load-bearing.

## What it is

A macOS file manager (Windows 11-style UI, a Finder replacement). Pure **Zig 0.16**
backend, web UI, shipped as a single universal `.app`. No third-party libraries — only
the Zig standard library + macOS system frameworks (Cocoa/WebKit).

## Layout

- `src/main.zig` — the whole backend: HTTP server + filesystem API + process/host logic.
- `src/macwin.m` — tiny Objective-C Cocoa/WKWebView native window (macOS only).
- `src/index.html` — the entire frontend (HTML/CSS/JS), **embedded at compile time** via
  `@embedFile`. The Tabler icon font under `src/assets/` is embedded the same way.
- `build.zig` — links `Cocoa` + `WebKit`, `link_libc = true`, option `-Dmacos-sdk=<path>`.
- `packaging/` — `package.sh` (universal `.app` + `.zip`/`.dmg`), `Info.plist`,
  `make_icon.py` (pure-Python icon generator), `icon.icns`.
- `notice.json` — remote announcement source (see Notices).

## Run / build / package

```bash
zig build run                         # native window (dev)
HEADLESS=1 zig build run              # server-only, use in a browser
./packaging/package.sh --zip --dmg    # universal app -> dist/ (ad-hoc signed)
```

## Architecture — TWO processes (important)

Launching the app starts a **host** process (Cocoa/WKWebView window) which **spawns a
child** process with `HEADLESS=1` (the Zig HTTP server). The host reads the chosen port
from the child's **stderr** and points the web view at `http://127.0.0.1:<port>/`. On quit
the host kills the child (`applicationWillTerminate`).

**Why two processes:** Cocoa's `[NSApp run]` run loop and Zig 0.16's `Threaded` I/O
conflict in the same process — `accept()` works but socket read/write hang. Splitting them
(server child never touches Cocoa) is the fix. Do **not** try to run the server loop on a
thread/`io.concurrent` inside the windowed process; it hangs.

## Critical gotchas (all hit during development)

- **WKWebView ignores JS dialogs** unless a `WKUIDelegate` is set. `prompt/confirm/alert`
  silently no-op → New folder / Rename / Delete break in the app. Handled by NSAlert panels
  in `macwin.m`.
- **WKWebView ignores `target="_blank"` links.** Handled via
  `createWebViewWithConfiguration:` → `NSWorkspace openURL:` (open in default browser).
- **`process.replace` (re-exec for port change) loses the environment** because our
  `Threaded` was created with an empty environ. We pass `currentEnviron()` (built from
  `std.c.environ`) to `Threaded.init`, otherwise the re-exec'd process loses `$HOME` and
  opens at `/`.
- **`http.Server.respond()` asserts** (under keep-alive) that a POST declares a body
  length. Mutation endpoints are bodyless POSTs → their responses set `.keep_alive = false`.
- **No `reuse_address`** on `listen`: it sets `SO_REUSEPORT` on macOS, which lets two
  instances share a port and breaks "port in use" detection / the auto-fallback.
- **Cross-compiling x86_64 on arm64** can't auto-find the SDK frameworks. `package.sh`
  builds arm64 natively and x86_64 with `-Dmacos-sdk="$(xcrun --show-sdk-path)"`, then
  `lipo`s them.
- **`std.debug.print` writes to stderr** — that's why the host pipes/reads the child's
  stderr to learn the port.
- **macOS 15+ (Sequoia/Tahoe) removed right-click → Open.** Unsigned-app install is now:
  open → Done → System Settings → Privacy & Security → Open Anyway. READMEs/Release notes
  must say this (not "right-click Open").
- **Ad-hoc code-signing** (`codesign --force --deep -s -`, free, in `package.sh`) gives a
  stable identity so macOS **remembers folder (TCC) grants** instead of re-prompting every
  launch. It does NOT bypass Gatekeeper notarization (still need Open Anyway once).

## Behavior / conventions

- **Port:** default `9781`. Resolution order: `$PORT` env → `~/.zave-port`
  (written by the in-app System settings) → `9781`. If busy, auto-tries `+1..+19`.
- **In-app port change** (Settings ⚙ → System settings) persists to `~/.zave-port`
  then `POST /api/restart` re-execs the binary; the page polls the new port and redirects.
- **UI language** defaults to Chinese (`fm-lang` in localStorage; toggle in the ⚙ menu).
  Theme persists in `fm-theme`. All UI strings live in the `I18N = {en, zh}` dict in
  `index.html`; switching re-renders via `applyStatic()` + the JS-built parts.
- **Frontend dialogs** use `prompt/confirm` (works because of the WKUIDelegate above).
- **Single-user, localhost only** (binds `127.0.0.1`, no auth). The server handles each
  connection concurrently (`io.concurrent` in `runServer`) so multiple windows don't block
  one another.
- **Multiple windows:** `Cmd+N` / File → New Window opens more windows in the host process
  (all share the one server child). Native menu bar set up in `macwin.m` (`setupMenu`);
  "About Zave" calls the web UI's `showAbout()` via `evaluateJavaScript`.

## HTTP API (all under the local server)

`GET /api/list?path=` · `POST /api/move|copy|delete|mkdir|zip|unzip|open|terminal` ·
`GET /api/file?path=` (raw bytes, 16 MB cap, preview) · `GET|POST /api/config` (port) ·
`POST /api/restart` · `/assets/...` (icon font) · `/` (index.html).

## Notices (remote announcements)

The app fetches `notice.json` (GitHub raw, CORS `*`) **once at startup** (no polling). A non-empty
`id` shows a one-time toast + a red dot on the ⚙ menu. To broadcast: edit `notice.json`
(`{id, level: info|warning|critical, title, message, url}`) with a NEW `id` and push; to
stop, set `id` back to `""`. Seen/toasted state is per-machine localStorage
(`fm-notice-seen`, `fm-notice-toasted`). Requires v1.7.0+. raw CDN takes a few minutes.

## Releasing a version

Bump the version in **three** places, then tag + release with both artifacts:

1. `src/index.html` → `const APP_VERSION`
2. `packaging/Info.plist` → `CFBundleVersion` and `CFBundleShortVersionString`
3. `README.md` and `README.zh.md` → the `**vX.Y.Z**` subtitle line

```bash
./packaging/package.sh --zip --dmg
git tag -a vX.Y.Z -m "Zave vX.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z dist/zave.zip dist/zave.dmg --title ... --notes ...
```

Commit messages end with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

## Not yet done

Windows support (everything macOS-specific: `macwin.m`, the `open`/`zip`/`unzip`/Terminal
shell-outs, `$HOME`, framework links). Code signing + notarization (needs a paid Apple
Developer account) — until then, unsigned + Open Anyway.
