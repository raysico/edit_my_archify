# Changelog

本项目版本号唯一真源为 `package.json` 的 `version` 字段。

## [beta1.0.1] - 2026-10-20

暗色主题可读性修复与滚动条主题化。

### Changed
- 编辑浮层与侧栏输入框改用主题变量配色（`--input-bg` / `--input-border`），聚焦显示强调色描边，修复暗色主题下输入文字与底框对比不足、不可读的问题
- 新增跟随主题的滚动条样式（Firefox `scrollbar-*` + WebKit `::-webkit-scrollbar`），亮 / 暗双主题各自适配
- 底部版权版本号更新为 `Vbeta1.0.1`

## [beta1.0.0] - 2026-10-20

首个公开版本。

### Added
- 单文件 HTML 工具：导入 Archify `candidate.json` / 文件夹，在自绘画布上直接编辑文字并回写
- 数据源模型：以 `candidate.json`（archify IR）为数据源与回写目标，HTML 成品作为同步回写源
- 四类可编辑文字：组件 `label / sublabel / tag`、连线 `label`、区域 `label`、卡片 `title / items`
- 画布自绘（不依赖 archify 运行时样式）：区域虚线框 + 连线折线 + 节点卡片
- 回写保真：JSON 精准替换（diff 仅编辑字段 1 行），HTML 精准字符串替换
- archify 风格双色主题（亮 / 暗，URL 参数 / localStorage / 系统偏好三级）
- 底部版权信息 `power by hoxiudimdim Vbeta1.0.0`

### Docs
- 引入版本管理（dev / main 分支），规范化目录结构
- 编写英中文双语 README、MIT License、DESIGN / TECH / ROADMAP 文档
