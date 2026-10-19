# Tech

> 项目：`edit_my_archify` · 版本：`beta1.0.0`（版本号以 `package.json` 为准）

## 1. 架构

- **形态**：单文件自包含 HTML（`dev/archify-text-editor/Archify文字编辑工具.html`），原生 JS，无构建、无外部依赖，`file://` 直接可用。
- **数据流**：`candidate.json`（archify IR，数据源）→ 解析为工作对象 → 画布自绘 + 可编辑 → 修改回写 JSON 与（可选）HTML 成品。

## 2. 数据模型（archify IR）

| 对象 | 字段 |
| --- | --- |
| `components[]` | `id`、`label`、`sublabel`、`tag`、`type`、`pos`、`size` |
| `connections[]` | `id`、`from`、`to`、`label`、`variant` |
| `boundaries[]` | `label`、`wraps[]`（包含的组件 id） |
| `cards[]` | `title`、`items[]` |

## 3. 关键设计决策

- **画布用 IR 自绘，而非克隆 archify 成品 SVG**：成品 SVG 依赖 archify 运行时注入的样式（布局 / 遮罩 / 区域），克隆后会塌陷（bounds 为 0×0）或渲染异常。自绘（区域虚线框 + 连线折线 + 节点卡片）样式完全自控、稳定可编辑。
- **数据源 = `candidate.json`**（用户明确指定），HTML 仅作「同步回写」源。降级路径（仅 HTML 无 JSON）从 HTML 反解析 `irFromHtml` 并回写 HTML 本身。
- **回写保真**：
  - JSON：`JSON.stringify(ir, null, 2) + "\n"`，实测编辑单个 `label` 后与原文件 diff 仅 1 行。
  - HTML：精准字符串替换，定位 `<g data-node-id>` 段内替换 `t-primary/t-context/t-fine` 文本与属性；连线 `label` 只存于 `data-edge-label` 属性（顺序在 `data-edge-id` 前），定位含 id 的整标签再替换；区域定位含 `data-composition-frame-id` 的标签替换 label。集成测试 9/9 PASS，其它元素零误伤。

## 4. 约束

- `file://` 下不能 `fetch` 本地数据，故用 `<input type=file>` + `FileReader` 读取。
- 浏览器 `file://` 下载（`a.click()`）无法被自动化等待捕获，但实际写入浏览器下载目录；回写验证以读下载目录文件为准。

## 5. 主题

- archify 风格双色主题，优先级：URL `?theme=light|dark` → `localStorage "archify-text-theme"` → `prefers-color-scheme`。
- 画布颜色通过调色板对象（亮 / 暗两套）跟随主题，切换时重绘画布。
