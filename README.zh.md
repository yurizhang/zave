# window-finder

**v1.6.3** · 一个快速、强大的 **macOS 文件管理器**,Windows 11 风格 —— 真正能替代 Finder,而且只是一个零依赖的 **Zig 0.16** 二进制。

> 🇬🇧 For English, see [README.md](README.md)

说句实话:macOS 的 Finder 真的不好用 —— 看不到完整路径、复制路径麻烦,而且慢得没道理。**window-finder** 把这些全解决了:一个利落的 Windows 11 风格文件管理器,能即时查看并复制完整路径,还带多标签、多选、实时预览、压缩解压、拖拽、「用命令行打开」等一大堆功能。它比 Finder 做得更多、反应更快,却只是一个小巧的、自包含的二进制。

而且整个后端是**纯 Zig** —— 不依赖任何第三方库,只用标准库 —— 所以它顺便也是一次 Zig 0.16 新 I/O API 的实战。

---

## ✨ 功能

| 功能 | 说明 |
|------|------|
| 📁 完整路径栏 | 顶部地址栏实时显示当前目录的**绝对路径**(像 Windows) |
| 📋 一键复制路径 | 「复制路径」复制当前目录;每个条目悬停也有「复制路径」按钮 |
| 🧭 面包屑导航 | 路径栏下方逐级可点击跳转 |
| ⬆ 上一级 | 一键返回父目录 |
| 📂 进入目录 | 双击文件夹进入;双击文件复制其完整路径 |
| ✂️ 剪切 / 复制 / 粘贴 | 移动或复制文件**和文件夹**(目录递归复制) |
| ➕ 新建文件夹 | 在当前位置创建目录 |
| ✏️ 重命名 | 重命名文件或文件夹(原地移动) |
| 🗑️ 删除 | 删除文件或整个目录树(带确认弹窗) |
| 🗜️ 压缩 / 解压 | 压缩任意项为 ZIP,或就地解压 ZIP(调用 `zip`/`unzip`) |
| ☑️ 多选 | Ctrl/Cmd 点选、Shift 范围选、Ctrl/Cmd+A;批量剪切/复制/粘贴、删除、拖拽 |
| 👁️‍🗨️ 预览 | 详情面板内联预览文本/代码与图片;其他类型提供「用默认程序打开」按钮(macOS `open`) |
| 👁️ 隐藏文件 | 开关:显示/隐藏 `.` 开头的文件 |
| 🔍 搜索 | 在当前目录内按文件名实时过滤 |
| ⌨️ 键盘快捷键 | `↑`/`↓` 移动选择(`Home`/`End` 首/尾),`Enter` 打开,`Cmd/Ctrl + X / C / V` 剪切/复制/粘贴,`F2` 重命名,`Delete` 删除 |
| 🌗 主题 & 🌐 语言 | 深/浅主题、中文 / English 一键切换,均会记忆 |
| 🔤 自动排序 | 目录在前、文件在后,按名称排序 |
| 📏 文件大小 | 自动格式化为 B / KB / MB / GB |

---

## 🚀 快速开始

### 直接使用(免编译,推荐)

1. 从 [最新 Release](https://github.com/yurizhang/window-finder/releases/latest) 下载 **window-finder.zip**,**双击解压**。
2. 双击 `window-finder`,系统提示*「无法打开」*——点 **完成 / Done**(因为没做代码签名)。
3. 打开 **系统设置 → 隐私与安全性**,往下滚到*「已阻止使用 window-finder…」*,点 **仍要打开 / Open Anyway**,再打开 App 并确认。

> ⚠️ **macOS 15+(Sequoia/Tahoe 26)已取消「右键 → 打开」**,必须走 **系统设置 → 隐私与安全性 → 仍要打开**,只需一次。开发者也可直接执行 `xattr -dr com.apple.quarantine window-finder.app`。在哪解压在哪跑;通用版,Apple 芯片和 Intel 都能跑。

### 从源码构建

环境要求:**Zig 0.16.0**

```bash
# 编译并运行(打开原生窗口)
zig build run

# 或者分两步
zig build
./zig-out/bin/filemanager
```

启动后访问:**http://127.0.0.1:9781**

服务默认监听 `127.0.0.1:9781`(只对本机开放,安全)。

用环境变量 `PORT` 指定端口(`PORT=9000 zig build run`);若端口被占用,会自动顺延到下一个空闲端口。 也可在界面里 **⚙ 设置 → 系统配置** 修改端口,保存后会自动重启并切换到新端口。

### 桌面 App

`zig build run` 会打开一个**原生窗口**(WKWebView 承载界面),不需要浏览器。底层 HTTP 服务作为子进程运行,窗口指向它。

- 打包成可分发的**通用**(arm64 + Intel)`.app`、`.zip` 或 `.dmg`:
  ```bash
  ./packaging/package.sh                # -> dist/window-finder.app
  ./packaging/package.sh --zip          # -> dist/window-finder.zip
  ./packaging/package.sh --zip --dmg    # 两个都要
  ```
- **下载安装说明**:App **未做代码签名**(没有付费 Apple 开发者账号)。macOS 15+(Sequoia/Tahoe):双击 → **完成**,再去 **系统设置 → 隐私与安全性 → 仍要打开**。(开发者可直接 `xattr -dr com.apple.quarantine window-finder.app`。)
- 想用浏览器而不是窗口?跑无头模式:`HEADLESS=1 zig build run`,再打开打印出的地址。
- 首次访问 桌面/文稿/下载 时 macOS 会弹权限请求(正常的隐私机制),点**允许**即可;或在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 里给 window-finder 一次性授权。

### 怎么用

- **单击**选中一行;**双击文件夹**进入。
- 用工具栏按钮(或快捷键)进行**剪切 / 复制 / 粘贴 / 删除**。
- **粘贴**会把剪贴板里的项放进当前目录。

---

## 🧱 项目结构

```
window-finder/
├── build.zig          # 构建脚本(定义 exe、run 步骤)
└── src/
    ├── main.zig       # HTTP 服务 + 文件系统逻辑
    └── index.html     # 前端界面(HTML/CSS/JS,编译时内嵌进二进制)
```

`index.html` 通过 `@embedFile("index.html")` 在**编译期**被打包进可执行文件,所以最终产物是**单个二进制**,不需要额外分发静态文件。

---

## 🏗️ 架构

```
浏览器                          Zig 后端 (127.0.0.1:9781)
  │                                    │
  │  GET /                             │
  ├───────────────────────────────────▶  返回内嵌的 index.html
  │                                    │
  │  GET /api/list?path=/Users/...     │
  ├───────────────────────────────────▶  Io.Dir.openDirAbsolute + iterate
  │  ◀─────────────────────────────────  返回 JSON 列表
  │                                    │
  │  POST /api/move | /api/copy | /api/delete
  ├───────────────────────────────────▶  rename / copy / deleteTree
  │  ◀─────────────────────────────────  { "ok": true } 或 { "error": "..." }
```

前端是单页应用,所有导航和操作都通过 `fetch` 调 API 异步刷新,不刷新整页。

---

## 🔌 API 说明

### `GET /api/list?path=<绝对路径>`

列出指定目录内容。`path` 需 URL 编码,为空时默认 `/`。

**成功** `200 application/json`

```json
{
  "path": "/Users/yurizhang/Documents",
  "entries": [
    { "name": "project", "kind": "directory", "size": 0 },
    { "name": "notes.txt", "kind": "file", "size": 1024 }
  ]
}
```

- `kind`:`"directory"` 或 `"file"`(符号链接等统一归为 `file`)
- `size`:字节数;目录恒为 `0`

### `POST /api/move?from=<绝对路径>&to=<绝对路径>`

移动(剪切粘贴)文件或目录,底层用 `renameAbsolute`。

### `POST /api/copy?from=<绝对路径>&to=<绝对路径>`

复制文件或目录(目录会**递归复制**)。

### `POST /api/delete?path=<绝对路径>`

删除文件,或整个目录树。

### `POST /api/mkdir?path=<绝对路径>`

在 `path` 创建新目录。(重命名复用 `/api/move` —— 本质就是原地移动。)

### `GET /api/file?path=<绝对路径>`

返回文件原始字节(上限 16 MB),Content-Type 按扩展名推断 —— 供详情面板预览文本和图片。

### `POST /api/open?path=<绝对路径>`

通过 macOS `open` 用默认程序打开文件或文件夹。

**错误响应**(以上接口通用)

```json
{ "error": "FileNotFound" }
```

**安全防呆**:拒绝把目录复制进它自己的子目录(防无限递归)、拒绝删除根目录 `/`、拒绝源与目标相同或非绝对路径。

---

## 🧩 用到的 Zig 0.16 新特性

0.16 重写了 I/O 模型 —— **几乎所有 I/O 操作都要显式传入一个 `Io` 对象**。本项目正好覆盖了这套新 API 的主要部分:

| 标准库模块 | 用途 |
|-----------|------|
| `std.Io.Threaded` | 创建 I/O 实例(`.init(gpa, .{})` → `.io()`) |
| `std.Io.net` | 纯 Zig 网络:`IpAddress.parse` → `listen` → `accept` |
| `std.http.Server` | HTTP 协议处理:`receiveHead` / `respond` |
| `std.Io.Dir` | 文件系统:`openDirAbsolute`、`iterate`、`renameAbsolute`、`copyFileAbsolute`、`createDirAbsolute`、`deleteTree` |
| `std.Io.Writer.Allocating` | 动态构建 JSON 字符串 |
| `@embedFile` | 编译期内嵌前端文件 |

### 与旧版本的关键差异

```zig
// 0.16:I/O 需要先建一个 Io 实例,之后处处传它
var threaded: std.Io.Threaded = .init(gpa, .{});
const io = threaded.io();

// 网络监听
var addr = try std.Io.net.IpAddress.parse("127.0.0.1", 9781);
var server = try addr.listen(io, .{ .reuse_address = true });
const stream = try server.accept(io);

// 目录遍历:iterate() 拿迭代器,next(io) 传 io
var dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
var it = dir.iterate();
while (try it.next(io)) |entry| { ... }
```

每个请求用一个 **ArenaAllocator**,处理完整体释放,避免逐块手动 free。

> **一个值得记的坑:** 0.16 的 `http.Server.respond()` 在 keep-alive 时会断言 POST 请求必须声明 body 长度。由于写操作接口是可能不带 `Content-Length` 的 POST,它们的响应里设了 `.keep_alive = false` 来绕开 body 丢弃逻辑。

---

## 🗺️ 后续计划

- [x] 剪切 / 复制 / 粘贴文件和文件夹
- [x] 删除(文件 / 整树)
- [x] 新建文件夹 / 重命名
- [x] 隐藏文件显示开关
- [x] 文件名搜索 / 过滤
- [x] 中文 / English + 深 / 浅主题切换
- [x] 复制当前路径
- [x] 文件预览(文本 / 代码 / 图片)+ 默认程序打开
- [x] PDF 内联预览(`<iframe>` 嵌入)
- [x] 右键上下文菜单
- [x] 压缩 / 解压 ZIP
- [x] 多选(Ctrl/Shift 点选)+ 批量操作
- [x] 多标签页(各自独立目录)
- [x] 拖拽移动文件
- [x] 更细的文件类型图标

---

## ⚠️ 说明

- 仅监听 `127.0.0.1`,**不对外网开放**,适合本机使用。
- 路径以服务进程的权限访问文件系统。

---

## 📄 License

[MIT](LICENSE) © 2026 Yong Zhang
