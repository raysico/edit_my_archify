# edit_my_archify

> Edit text directly on your Archify architecture diagram and write it back — as a single local HTML file.
> 在 Archify 架构图上直接修改文字并回写：一个单文件本地 HTML 工具。

**Version / 版本**：`beta1.0.1`（唯一真源 `package.json`）
**License / 协议**：MIT
**Author / 作者**：raysico (hoxiudimdim)

---

## 项目介绍 / Introduction

Archify 把架构描述编译成自包含的交互式 HTML 成品，但没有可视化编辑器，想改图上的文字只能回到源头重出。本工具补上这一环：**导入 archify 的 `candidate.json`（IR 数据源），在自绘画布上直接点选编辑文字，并精准回写 JSON（可选同步回写同目录的 HTML 成品）**。

Archify compiles an architecture description into a self-contained interactive HTML, but has no visual editor. This tool fills that gap: **import Archify's `candidate.json` (the IR source), click to edit text directly on a self-drawn canvas, and write it back to JSON precisely (optionally also sync the compiled HTML in the same folder)**.

---

## 项目功能 / Features

- **导入**：读取单个 `candidate.json`，或选择文件夹自动匹配 json + html；无 JSON 时降级从 HTML 反解析。
- **画布自绘**：区域虚线框 + 连线折线 + 节点卡片，样式完全自控，稳定可编辑。
- **四类可编辑文字**：组件 `label / sublabel / tag`、连线 `label`、区域 `label`、卡片 `title / items`。
- **就地编辑**：点击画布对象或侧栏项打开编辑浮层，实时更新画布、侧栏与状态条。
- **回写保真**：JSON 精准替换（编辑单个字段 diff 仅 1 行）；HTML 精准标签替换，其它元素零误伤。
- **双色主题**：archify 风格亮 / 暗主题一键切换，画布、输入框与滚动条配色联动，偏好持久化。
- **零依赖单文件**：原生 JS，`file://` 双击即用，无需构建或安装。

---

## 项目依赖 / Dependencies

无运行时依赖（No runtime dependencies）。唯一产物为单文件 HTML，使用原生浏览器 API（`FileReader`、原生 SVG）。

---

## 项目使用方法 / Usage

1. 用浏览器打开 `dev/archify-text-editor/Archify文字编辑工具.html`。
2. 点击「导入 JSON 数据」选择 `candidate.json`（或「导入文件夹」自动匹配 json + html）。
3. 在画布上点击任意组件 / 连线 / 区域 / 卡片，弹出编辑浮层，修改文字。
4. 点「保存回写 candidate.json」把修改写入源文件；如需同步成品 HTML，点「同步回写 HTML」。
5. 顶栏主题按钮可切换亮 / 暗主题。

> 提示：`file://` 页面不能自动读本地文件，需通过文件选择导入；回写会下载到浏览器下载目录。

---

## 项目贡献者 / Contributors

- raysico (hoxiudimdim) — 发起者与维护者（owner / maintainer）

---

## 目录规范 / Repository Layout

| 路径 | 用途 | 是否进 git |
| --- | --- | --- |
| `dev/` | 开发代码与规则（`AGENTS.md`） | ✅ 提交 |
| `README.md` / `DESIGN.md` / `TECH.md` / `CHANGELOG.md` / `ROADMAP.md` / `LICENSE.md` | 项目文档 | ✅ 随发布入库 |
| `package.json` | 版本号唯一真源 | ✅ 提交 |
| `test/` / `research/` / `playground/` | 本地脏数据与调研副本 | ❌ 仅本地 |
| `locallog.md` | 本地开发决策 | ❌ 仅本地 |

---

## 分支策略 / Branching

- `dev`：开发分支，日常提交，不更版本号。
- `main`：发布分支，仅通过发布流程（合并 dev → 打 tag）更新。
- Commit message 采用「类型: 变更摘要」格式。
