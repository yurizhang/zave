# 文件管理器 UI 设计资源（替换 macOS Finder）

本目录是一个 **Windows 11 风格文件管理器** 的设计稿与可交互原型，作为前端实现的视觉与交互规范。Claude Code 可直接读取本文件了解设计意图，并参考 `html/file-manager.html` 的真实代码进行实现。

## 目录结构

```
design/
├── README.md              本文档（设计总结与规范）
├── UI/                    静态效果图（PNG，@2x 高清）
│   ├── 01-light-list.png  浅色 · 详细列表视图（默认形态）
│   ├── 02-light-grid.png  浅色 · 大图标网格视图
│   └── 03-dark-list.png   深色模式 · 列表视图
├── html/
│   ├── file-manager.html  可交互原型（单文件，双击即可在浏览器打开）
│   └── assets/            本地图标字体（离线可用，无需联网）
│       ├── tabler-icons.min.css
│       └── fonts/tabler-icons.woff2
└── render.py              用 Playwright 把 html 渲染成 PNG 的脚本（复现用）
```

> 实现时以 `html/file-manager.html` 为准——它是带真实尺寸、配色变量和交互逻辑的参考源码；PNG 仅作视觉对照。

## 设计目标

在 Mac 上提供一个 Windows 11 资源管理器（File Explorer）风格的界面来替代 Finder。强调四个核心区域：左侧导航树、顶部地址栏与搜索、中间文件列表（列表/网格可切换）、右侧详情预览面板。

## 整体布局（像素规格）

窗口固定参考宽度 `1160px`，圆角 `11px`，从上到下分为五层：

| 区域 | 高度 | 内容 |
|------|------|------|
| 标题栏 Title bar | 44px | 标签页（标签 34px，圆角顶部）+ 主题切换 + 最小化/最大化/关闭 |
| 命令栏 Command bar | 48px | 新建（主按钮）｜ 剪切/复制/粘贴/重命名/共享/删除 ｜ 排序/查看/显示 ｜ 更多 |
| 地址栏 Address bar | 50px | 后退/前进/向上/刷新 + 面包屑路径 + 搜索框 |
| 主体 Body | min 470px | 三栏网格：`230px` 导航树 / `1fr` 文件区 / `248px` 详情面板 |
| 状态栏 Status bar | 30px | 项目计数 + 已选信息 + 列表/网格视图切换 |

主体使用 CSS Grid：`grid-template-columns: 230px minmax(0,1fr) 248px;`

## 四大核心区域

**左侧导航树（side）** — 背景 `--side`。分组：主页 / 图库 / OneDrive；「此电脑」可折叠树（桌面、Documents、下载、图片、音乐、视频、本地磁盘 C:）；网络。当前选中项有浅色背景 + 左侧 3px 强调竖条（`--accent-line`）。

**顶部地址栏（addrbar）** — 四个导航按钮（前进态可禁用），面包屑式地址框（`此电脑 › Documents`），右侧独立搜索框，placeholder「搜索 Documents」。

**中间文件区（main）** — 两种视图，由状态栏右下角或命令栏「查看」切换：
- 列表视图：表头 `名称 / 修改日期 / 类型 / 大小`，列宽 `1fr 130px 120px 90px`，行高 38px，文件夹排在文件前面。
- 网格视图：`repeat(auto-fill, minmax(112px,1fr))`，图标 46px，文件名最多两行省略。

**右侧详情面板（details）** — 顶部 140px 预览框（大图标占位），文件名 + 类型，下面是属性表（类型、修改日期、大小、作者/页数/尺寸等，「已同步」用绿色 `--green`）。

## 配色 Token（已在 `:root` / `.dark` 中定义）

浅色模式：

```css
--bg:#eaeaea; --win:#f9f9f9; --content:#ffffff; --side:#f3f3f3;
--text:#1b1b1b; --muted:#5f5f5f; --faint:#909090;
--accent:#0067c0; --accent-soft:#e8f1fb; --accent-line:#0067c0;
--border:#e3e3e3; --border-strong:#d2d2d2; --hover:#ececec; --green:#1f7a45;
```

深色模式（`<html class="dark">`）：

```css
--bg:#1a1a1a; --win:#202020; --content:#272727; --side:#242424;
--text:#f3f3f3; --muted:#a6a6a6; --faint:#7a7a7a;
--accent:#4cc2ff; --accent-soft:#0e3a5f; --accent-line:#4cc2ff;
--border:#393939; --border-strong:#454545; --hover:#323232; --green:#4cc38a;
```

文件类型图标配色：文件夹 `--folder #e0a93a`、Word `--doc`、Excel `--xls`、图片 `--img`、PDF `--pdf`、音频 `--aud`、压缩包 `--zip`（深色模式各有对应提亮值，见 CSS）。

字体栈：`"Segoe UI","Microsoft YaHei",system-ui,-apple-system,sans-serif`。

## 图标

使用 **Tabler Icons v3.31.0（outline 描边版）**，以 webfont 形式通过 `<i class="ti ti-xxx">` 引用，已打包到 `html/assets`，离线可用。已用到的图标名（实现时可直接沿用）：

`ti-folder ti-download ti-photo ti-cloud ti-device-desktop ti-device-imac ti-music ti-movie ti-database ti-network ti-home`（导航/位置）；
`ti-file-text ti-file-spreadsheet ti-file-typography ti-file-zip`（文件类型）；
`ti-plus ti-scissors ti-copy ti-clipboard ti-pencil ti-share ti-trash ti-arrows-sort ti-layout-grid ti-layout-list ti-eye ti-dots`（命令栏）；
`ti-arrow-left ti-arrow-right ti-arrow-up ti-refresh ti-chevron-right ti-chevron-down ti-search`（导航/地址栏）；
`ti-moon ti-sun ti-minus ti-square ti-x`（窗口控件）。

## 原型已实现的交互（`file-manager.html`）

- 点击文件行 / 网格项 → 选中（浅蓝高亮）并刷新右侧详情面板；
- 列表 ↔ 大图标视图切换（状态栏右下角按钮，或命令栏「查看」）；
- 右上角月亮/太阳按钮 → 深色 / 浅色模式切换；
- 左侧导航树、标签页可点选高亮；
- 文件数据在 `<script>` 顶部的 `files` 数组里，便于扩展。

## 尚未实现 / 实现时的待办建议

- 面包屑点击与文件夹双击进入下一级（真实路径导航 + 历史栈，驱动前进/后退按钮状态）；
- 多选（Ctrl/Shift）与右键上下文菜单；
- 实际文件系统读取（当前 `files` 为静态示例数据）；
- 排序（按名称/日期/类型/大小，表头点击切换升降序）；
- 拖拽移动、键盘导航（方向键 / 回车 / F2 重命名 / Delete）。

## 复现 PNG

```bash
python3 design/render.py   # 需要 playwright + chromium
```
脚本会用无头 Chromium 打开 `html/file-manager.html`，自动切换视图/主题并截图输出到 `design/UI/`。
