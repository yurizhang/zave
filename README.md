# 文件管理器 (Zig File Manager)

一个用 **Zig 0.16** 写的轻量级本地文件管理器,后端是纯 Zig 实现的 HTTP 服务,前端是浏览器界面。

起因很简单:macOS 的 Finder 不好用 —— 看不到完整路径、复制路径麻烦。这个项目就是要做一个**像 Windows 资源管理器那样**、能直接看到并复制完整路径的文件浏览器,顺便练 Zig 0.16 的新 I/O API。

> 不依赖任何第三方库,只用 Zig 标准库。

---

## ✨ 功能

| 功能 | 说明 |
|------|------|
| 📁 完整路径栏 | 顶部地址栏实时显示当前目录的**绝对路径**(像 Windows) |
| 📋 一键复制路径 | 「复制路径」复制当前目录;每个条目悬停也有「复制」按钮 |
| 🧭 面包屑导航 | 路径栏下方逐级可点击跳转 |
| ⬆ 上一级 | 一键返回父目录 |
| 📂 进入目录 | 双击文件夹进入;点文件复制其完整路径 |
| 🔤 自动排序 | 目录在前、文件在后,按名称排序 |
| 📏 文件大小 | 自动格式化为 B / KB / MB / GB |
| ⌨️ 手输路径 | 地址栏直接输入路径 + 回车跳转 |

---

## 🚀 快速开始

环境要求:**Zig 0.16.0**

```bash
# 编译并运行
zig build run

# 或者分两步
zig build
./zig-out/bin/filemanager
```

启动后访问:**http://127.0.0.1:8080**

服务默认监听 `127.0.0.1:8080`(只对本机开放,安全)。

---

## 🧱 项目结构

```
filemanager/
├── build.zig          # 构建脚本(定义 exe、run 步骤)
└── src/
    ├── main.zig       # HTTP 服务 + 文件系统逻辑(~190 行)
    └── index.html     # 前端界面(HTML/CSS/JS,编译时内嵌进二进制)
```

`index.html` 通过 `@embedFile("index.html")` 在**编译期**被打包进可执行文件,所以最终产物是**单个二进制**,不需要额外分发静态文件。

---

## 🏗️ 架构

```
浏览器                          Zig 后端 (127.0.0.1:8080)
  │                                    │
  │  GET /                             │
  ├───────────────────────────────────▶  返回内嵌的 index.html
  │                                    │
  │  GET /api/list?path=/Users/...     │
  ├───────────────────────────────────▶  Io.Dir.openDirAbsolute + iterate
  │                                    │  逐项 statFile 取大小
  │  ◀─────────────────────────────────  返回 JSON
  │   {"path":"...","entries":[...]}   │
```

后端只有两条路由:

- `GET /` → 返回前端页面
- `GET /api/list?path=<绝对路径>` → 返回该目录的 JSON 列表

前端是单页应用,所有导航都通过 `fetch` 调 `/api/list` 异步刷新,不刷新整页。

---

## 🔌 API 说明

### `GET /api/list`

列出指定目录的内容。

**查询参数**

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string (URL 编码) | 目标目录的绝对路径。为空时默认 `/` |

**成功响应** `200 application/json`

```json
{
  "path": "/Users/yong_zhang/Documents/zig",
  "entries": [
    { "name": "filemanager", "kind": "directory", "size": 0 },
    { "name": "notes.txt",    "kind": "file",      "size": 1024 }
  ]
}
```

- `kind`:`"directory"` 或 `"file"`(符号链接等统一归为 `file`)
- `size`:字节数;目录恒为 `0`

**错误响应**(目录不存在/无权限等)

```json
{ "error": "无法打开: /nope (FileNotFound)" }
```

---

## 🧩 用到的 Zig 0.16 新特性

0.16 重写了 I/O 模型 —— **几乎所有 I/O 操作都要显式传入一个 `Io` 对象**。本项目正好覆盖了这套新 API 的主要部分:

| 标准库模块 | 用途 |
|-----------|------|
| `std.Io.Threaded` | 创建 I/O 实例(`.init(gpa, .{})` → `.io()`) |
| `std.Io.net` | 纯 Zig 网络:`IpAddress.parse` → `listen` → `accept` |
| `std.http.Server` | HTTP 协议处理:`receiveHead` / `respond` |
| `std.Io.Dir` | 目录操作:`openDirAbsolute` + `iterate(io)` |
| `std.Io.Writer.Allocating` | 动态构建 JSON 字符串(替代旧的 ArrayList writer) |
| `@embedFile` | 编译期内嵌前端文件 |

### 与旧版本的关键差异

```zig
// 0.16:I/O 需要先建一个 Io 实例,之后处处传它
var threaded: std.Io.Threaded = .init(gpa, .{});
const io = threaded.io();

// 网络监听
var addr = try std.Io.net.IpAddress.parse("127.0.0.1", 8080);
var server = try addr.listen(io, .{ .reuse_address = true });
const stream = try server.accept(io);

// 目录遍历:iterate() 拿迭代器,next(io) 传 io
var dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
var it = dir.iterate();
while (try it.next(io)) |entry| { ... }
```

每个请求用一个 **ArenaAllocator**,处理完整体释放,避免逐块手动 free。

---

## 🗺️ 后续计划

- [ ] 真·剪切 / 复制 / 粘贴文件(后端加 move / copy 接口)
- [ ] 新建文件夹 / 重命名 / 删除
- [ ] 调用 macOS `open` 用默认程序打开文件
- [ ] 隐藏文件显示开关(目前 `.` 开头的文件也会列出)
- [ ] 文件名搜索 / 过滤
- [ ] 更细的文件类型图标

---

## ⚠️ 说明

- 仅监听 `127.0.0.1`,**不对外网开放**,适合本机使用。
- 目前是只读浏览器(列目录 + 复制路径),尚未实现文件修改类操作。
- 路径以服务进程的权限访问文件系统。

---

## 📄 License

个人学习项目,随意使用。
