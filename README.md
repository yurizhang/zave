# window-finder

**v1.6.1** · A fast, powerful **Windows 11-style file manager for macOS** — a real Finder replacement, packed into a single dependency-free **Zig 0.16** binary.

> 🇨🇳 中文文档请看 [README.zh.md](README.zh.md)

Let's be honest: macOS Finder is clunky. You can't see the full path, copying a path is a chore, and it's slower than it has any right to be. **window-finder** fixes all of that — a snappy, Windows 11-style file manager that shows and copies the full path instantly, with tabs, multi-select, live preview, ZIP, drag-and-drop, "open in Terminal" and a lot more. It does more than Finder, gets out of your way faster, and ships as one tiny self-contained binary.

And the whole backend is **pure Zig** — no third-party dependencies, only the standard library — so it doubles as a hands-on tour of Zig 0.16's new I/O API.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 📁 Full path bar | The top address bar always shows the **absolute path** of the current directory (like Windows) |
| 📋 One-click path copy | "Copy Path" copies the current directory; each row also has a hover "Copy Path" button |
| 🧭 Breadcrumbs | Click any level under the path bar to jump there |
| ⬆ Up | Go to the parent directory |
| 📂 Navigate | Double-click a folder to enter; double-click a file to copy its full path |
| ✂️ Cut / Copy / Paste | Move or copy files **and folders** (recursive directory copy) |
| ➕ New folder | Create a directory in the current location |
| ✏️ Rename | Rename a file or folder (in-place move) |
| 🗑️ Delete | Delete a file or an entire directory tree (with a confirmation dialog) |
| 🗜️ Zip / Unzip | Compress any item to a ZIP, or extract a ZIP in place (via `zip`/`unzip`) |
| ☑️ Multi-select | Ctrl/Cmd-click, Shift-click range, Ctrl/Cmd+A; batch cut/copy/paste, delete and drag |
| 👁️‍🗨️ Preview | Inline preview of text/code & images in the details panel; everything else gets an "Open with default app" button (macOS `open`) |
| 👁️ Hidden files | Toggle to show/hide dot-files |
| 🔍 Search | Live filter of the current directory by filename |
| ⌨️ Keyboard shortcuts | `↑`/`↓` to move selection (`Home`/`End` for first/last), `Enter` to open, `Cmd/Ctrl + X / C / V` cut/copy/paste, `F2` rename, `Delete` remove |
| 🌗 Theme & 🌐 language | Dark / light theme and English / 中文 toggles, both persisted |
| 🔤 Auto sort | Directories first, then files, sorted by name |
| 📏 File size | Auto-formatted as B / KB / MB / GB |

---

## 🚀 Quick Start

### Just use it (no build) — recommended

1. Download **window-finder.zip** from the [latest release](https://github.com/yurizhang/window-finder/releases/latest).
2. **Double-click to unzip**, then **right-click `window-finder` → Open → Open**.

> ⚠️ The first launch **must** be **right-click → Open** (not a double-click). The app isn't code-signed, so a plain double-click shows *"cannot be opened"* — right-click → Open gets past Gatekeeper, and it's only needed once. It runs from wherever you unzipped it (no need to move it to Applications). Universal — works on Apple Silicon and Intel.

### Build from source

Requirements: **Zig 0.16.0**

```bash
# Build and run (opens a native window)
zig build run

# Or in two steps
zig build
./zig-out/bin/filemanager
```

Then open: **http://127.0.0.1:9781**

The server listens on `127.0.0.1:9781` (local-only, safe).

Set a custom port with the `PORT` env var (`PORT=9000 zig build run`). If the chosen port is busy, the server automatically tries the next ones. The port can also be changed from **Settings ⚙ → System settings** in the UI, which saves it and restarts the app on the new port.

### Desktop app

`zig build run` opens a **native window** (a WKWebView hosting the UI) — no browser needed. Under the hood the HTTP server runs as a child process and the window points at it.

- Build a distributable **universal** (arm64 + Intel) `.app`, `.zip` or `.dmg`:
  ```bash
  ./packaging/package.sh                # -> dist/window-finder.app
  ./packaging/package.sh --zip          # -> dist/window-finder.zip
  ./packaging/package.sh --zip --dmg    # both
  ```
- **Installing a downloaded build:** the app is **not code-signed** (no paid
  Apple Developer account). Easiest is the **`.zip`**: double-click to unzip,
  then **right-click window-finder → Open → Open** (runs from anywhere — no
  need to move it). Only needed once. (Or `xattr -dr com.apple.quarantine window-finder.app`.)
- Prefer the browser instead of a window? Run headless: `HEADLESS=1 zig build run`, then open the printed URL.
- macOS will ask permission the first time it touches Desktop/Documents/Downloads (normal privacy prompts). Click **Allow**, or grant **Full Disk Access** to window-finder once in System Settings → Privacy & Security.

### How to use

- **Single-click** a row to select it; **double-click** a folder to enter it.
- Use the toolbar buttons (or keyboard shortcuts) to **cut / copy / paste / delete**.
- **Paste** drops the clipboard item into the current directory.

---

## 🧱 Project Structure

```
window-finder/
├── build.zig          # Build script (defines the exe and the `run` step)
└── src/
    ├── main.zig       # HTTP server + filesystem logic
    └── index.html     # Frontend (HTML/CSS/JS, embedded into the binary at compile time)
```

`index.html` is embedded into the executable at **compile time** via `@embedFile("index.html")`, so the final artifact is a **single binary** — no extra static files to ship.

---

## 🏗️ Architecture

```
Browser                          Zig backend (127.0.0.1:9781)
  │                                    │
  │  GET /                             │
  ├───────────────────────────────────▶  returns the embedded index.html
  │                                    │
  │  GET /api/list?path=/Users/...     │
  ├───────────────────────────────────▶  Io.Dir.openDirAbsolute + iterate
  │  ◀─────────────────────────────────  returns JSON listing
  │                                    │
  │  POST /api/move | /api/copy | /api/delete
  ├───────────────────────────────────▶  rename / copy / deleteTree
  │  ◀─────────────────────────────────  { "ok": true } or { "error": "..." }
```

The frontend is a single-page app: all navigation and operations call the API via `fetch` and refresh asynchronously, without reloading the page.

---

## 🔌 API Reference

### `GET /api/list?path=<abs>`

Lists the contents of a directory. `path` is URL-encoded; empty defaults to `/`.

**Success** `200 application/json`

```json
{
  "path": "/Users/yurizhang/Documents",
  "entries": [
    { "name": "project", "kind": "directory", "size": 0 },
    { "name": "notes.txt", "kind": "file", "size": 1024 }
  ]
}
```

- `kind`: `"directory"` or `"file"` (symlinks etc. are reported as `file`)
- `size`: bytes; always `0` for directories

### `POST /api/move?from=<abs>&to=<abs>`

Moves (cut + paste) a file or directory from `from` to `to`. Backed by `renameAbsolute`.

### `POST /api/copy?from=<abs>&to=<abs>`

Copies a file or directory (directories are copied **recursively**).

### `POST /api/delete?path=<abs>`

Deletes a file, or an entire directory tree.

### `POST /api/mkdir?path=<abs>`

Creates a new directory at `path`. (Rename reuses `/api/move` — it's just an in-place move.)

### `GET /api/file?path=<abs>`

Returns the raw file bytes (capped at 16 MB) with a Content-Type guessed from the extension — used by the details panel to preview text and images.

### `POST /api/open?path=<abs>`

Opens the file or folder with the default application via macOS `open`.

**Error response** (for any of the above)

```json
{ "error": "FileNotFound" }
```

**Safety guards**: refuses to copy a directory into its own subtree (infinite recursion), refuses to delete `/`, rejects identical source/destination and non-absolute paths.

---

## 🧩 Zig 0.16 features used

Zig 0.16 reworked the I/O model — **almost every I/O operation now takes an explicit `Io` value**. This project happens to cover most of that new surface:

| Stdlib module | Used for |
|---------------|----------|
| `std.Io.Threaded` | Creating the I/O instance (`.init(gpa, .{})` → `.io()`) |
| `std.Io.net` | Pure-Zig networking: `IpAddress.parse` → `listen` → `accept` |
| `std.http.Server` | HTTP handling: `receiveHead` / `respond` |
| `std.Io.Dir` | Filesystem: `openDirAbsolute`, `iterate`, `renameAbsolute`, `copyFileAbsolute`, `createDirAbsolute`, `deleteTree` |
| `std.Io.Writer.Allocating` | Building JSON strings dynamically |
| `@embedFile` | Embedding the frontend at compile time |

### Key differences from older versions

```zig
// 0.16: build an Io instance first, then pass it everywhere.
var threaded: std.Io.Threaded = .init(gpa, .{});
const io = threaded.io();

// Networking
var addr = try std.Io.net.IpAddress.parse("127.0.0.1", 9781);
var server = try addr.listen(io, .{ .reuse_address = true });
const stream = try server.accept(io);

// Directory iteration: iterate() returns an iterator, next(io) takes io
var dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
var it = dir.iterate();
while (try it.next(io)) |entry| { ... }
```

Each request uses an **ArenaAllocator** that is freed as a whole when the request finishes, avoiding piecemeal manual frees.

> **A gotcha worth noting:** `http.Server.respond()` asserts (under keep-alive) that a POST request declares a body length. Since the mutation endpoints are POSTs that may carry no `Content-Length`, their responses set `.keep_alive = false` to bypass the body-discard path.

---

## 🗺️ Roadmap

- [x] Cut / copy / paste files and folders
- [x] Delete (file / tree)
- [x] Create new folder / rename
- [x] Toggle for hidden files
- [x] Filename search / filter
- [x] English / 中文 + dark / light toggles
- [x] Copy current path
- [x] File preview (text / code / images) + open with default app
- [x] PDF inline preview (`<iframe>` embed)
- [x] Right-click context menu
- [x] Compress / extract ZIP
- [x] Multi-select (Ctrl/Shift click) with batch operations
- [x] Multiple tabs (independent directories)
- [x] Drag-and-drop to move
- [x] Finer file-type icons

---

## ⚠️ Notes

- Listens on `127.0.0.1` only — **not exposed to the network** — suited for local use.
- Files are accessed with the permissions of the server process.

---

## 📄 License

[MIT](LICENSE) © 2026 Yong Zhang
