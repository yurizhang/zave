# window-finder

**v1.0** · A lightweight local file manager written in **Zig 0.16**. The backend is a pure-Zig HTTP server; the frontend is a Windows 11-style browser UI.

> 🇨🇳 中文文档请看 [README.zh.md](README.zh.md)

The motivation is simple: macOS Finder is awkward — you can't see the full path, and copying a path is a hassle. This project builds a file browser that works **like Windows Explorer** — showing and copying the full path directly — while serving as a hands-on way to learn Zig 0.16's new I/O API.

> No third-party dependencies — only the Zig standard library.

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
| 👁️‍🗨️ Preview | Inline preview of text/code & images in the details panel; everything else gets an "Open with default app" button (macOS `open`) |
| 👁️ Hidden files | Toggle to show/hide dot-files |
| 🔍 Search | Live filter of the current directory by filename |
| ⌨️ Keyboard shortcuts | `Cmd/Ctrl + X / C / V` for cut/copy/paste, `F2` to rename, `Delete` to remove |
| 🌗 Theme & 🌐 language | Dark / light theme and English / 中文 toggles, both persisted |
| 🔤 Auto sort | Directories first, then files, sorted by name |
| 📏 File size | Auto-formatted as B / KB / MB / GB |

---

## 🚀 Quick Start

Requirements: **Zig 0.16.0**

```bash
# Build and run
zig build run

# Or in two steps
zig build
./zig-out/bin/filemanager
```

Then open: **http://127.0.0.1:8080**

The server listens on `127.0.0.1:8080` (local-only, safe).

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
Browser                          Zig backend (127.0.0.1:8080)
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
var addr = try std.Io.net.IpAddress.parse("127.0.0.1", 8080);
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
