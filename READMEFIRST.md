# READMEFIRST.md

> 新环境使用教程：拿到这个工作区（或拿到 `init-workspace.sh`）后，先读这一份，再动手。
> 快照来源：anythinks 主工作区（2026-10-17）。本文件由 `init-workspace.sh` 初始化时随其他产物一并产出。

## 1. 这是什么

一个「主工作区」骨架：开发类子项目、调研类子项目、资源与规范分层放置，用初始化脚本保证每个子项目结构一致。

引导一次后你会得到：

| 路径 | 用途 | 是否进 git 仓库 |
| --- | --- | --- |
| `dev/` | 开发类子项目目录（`init-project.sh` 在这里建项目） | 项目内提交；`.gitignore` 忽略 `locallog.md`、`test/`、`playground/`、`research/`、`node_modules/`、`dist/`、`.env` |
| `dev/AGENTS.md` | 开发域规则（agent 的执行依据） | 建议纳入版本管理或同步盘 |
| `resources/` | 工作区级资源目录 | 视用途自定 |
| `init-workspace.sh` | 工作区引导器（本文件的产出者） | 建议同上 |
| `init-project.sh` | 开发类子项目初始化 | 建议同上 |
| `init-research.sh` | 调研类子项目初始化 | 建议同上 |
| `项目沟通规范.md` | 工作区级协作规范（术语、结构、沟通原则、执行纪律） | 建议纳入版本管理或同步盘 |
| `READMEFIRST.md` | 本文件（新环境教程） | 建议同上 |

用到时才出现的目录：

| 路径 | 何时出现 | 用途 | 是否进 git 仓库 |
| --- | --- | --- | --- |
| `research/` | 首次运行 `init-research.sh` 时自动创建 | 调研类子项目目录 | 否，仅本地 |
| `playground/` | 需要放脏数据、对标代码、第三方副本时自建 | 测试类副本目录 | 否，仅本地 |
| `docs/` | 需要工作区级文档时自建 | 项目总文档目录 | 视用途自定 |

## 2. 本机需要准备什么

### 2.1 一条命令自检

```bash
bash --version | head -1
git --version
echo "user.name  = $(git config --global user.name  || echo 未配置)"
echo "user.email = $(git config --global user.email || echo 未配置)"
command -v md5 >/dev/null && echo "md5 可用" || { command -v md5sum >/dev/null && echo "md5sum 可用" || echo "无摘要工具"; }
```

### 2.2 必装 / 必配

1. **bash**——macOS 自带的 3.2 就够，不必升级。
   - 所有脚本都用了 `[[ ]]`、`read -p` 等 bash 特性：**只能用 bash 运行，不能 `sh`**。
   - 正确：`bash init-workspace.sh` 或 `./init-workspace.sh`；错误：`sh init-workspace.sh`。
2. **git**——只有开发类流程需要（`init-project.sh` 会强制检查；`init-research.sh` 不需要）。
3. **git 身份必须配置**，否则 `init-project.sh` 第一次 `git commit` 会失败：

   ```bash
   git config --global user.name "你的名字"
   git config --global user.email "you@example.com"
   ```

4. **目录可写**——不要把工作区放在只读介质或系统受管目录（如 `/System`、`/Library`）下。
5. **摘要工具**——macOS 自带 `md5`，Linux 一般是 `md5sum`；引导器用它做写入后的逐字节回读校验，缺失时只降级提示，不报错。

### 2.3 可选

- **GitHub CLI（`gh`）**：`init-project.sh` 检测到且已登录时，会提示 GitHub 上是否已有同名仓库（只提示，不自动创建）。
- **同步 / 备份工具**（百度网盘、pixcall、iCloud 等）：本模板把 `research/`、`playground/`、`test/` 视为纯本地内容，同步盘是它们的合适归宿。
- **不需要 Node.js**：`package.json` 只是开发子项目的版本号真源占位，不参与构建。

## 3. 首次使用（三步）

```bash
# 1. 准备一个空的项目根目录，把 init-workspace.sh 放进去
mkdir -p ~/我的项目 && cd ~/我的项目 && cp /path/to/init-workspace.sh .

# 2. 先看计划（可选但推荐，不会写任何文件）
bash init-workspace.sh --dry-run

# 3. 执行
bash init-workspace.sh
```

成功时会打印每个文件的 md5 回读校验（`✓` 全部通过）、产物清单和本机环境自检。

## 4. 日常使用

```bash
./init-project.sh     # 开发类子项目：输入项目名 → 生成 dev/<项目名>/，初始化 git（dev + main 分支）
./init-research.sh    # 调研类子项目：输入课题名 → 生成 research/<课题名>/，不建 git 仓库
```

- **开发类项目名**：仅小写字母、数字、横杠，不能以横杠开头或结尾；同名项目会要求换名，不覆盖。
- **调研类课题名**：允许中文、英文、数字、空格、`-`、`_`；禁止 `/ \ : * ? " < > |` 与控制字符；不能以空格、点、横杠开头，不能以空格或点结尾；同名课题不覆盖。
- **调研类子项目不建 git 仓库、不配远端**：按规范仅保存在本地，任何分支均不提交。
- 规范类文件的权威说明见 `项目沟通规范.md`；开发子项目的规则见 `dev/AGENTS.md`。

## 5. 引导器参数

| 参数 | 作用 |
| --- | --- |
| `--target DIR` | 指定目标目录（默认 = 脚本所在目录） |
| `--dry-run` | 只打印计划，不写文件、不做回读校验 |
| `--force` | 覆盖内容不同的既有文件（覆盖前自动备份为 `.bak-<时间戳>`） |
| `--no-self` | 不把引导器自身复制进目标目录 |

既有文件策略：与快照相同 → 跳过；内容不同 → 跳过并提示（默认不覆盖，避免冲掉你的本地修改）。

退出码：`0` 完成（含「有未对齐项被跳过」）；`1` 写入失败 / 回读校验失败 / 用户取消；`2` 参数错误。

## 6. 常见问题

**Q：提示「未检测到git」** → 先装 git：`xcode-select --install`，或 `brew install git`。

**Q：`git commit 失败`** → 九成是没配身份，见 2.2 第 3 条。

**Q：引导器提示「有 N 项未与快照对齐」** → 目标目录里的同名文件与快照不同，已被保留、未覆盖。确认要以快照覆盖时加 `--force`（会先备份）。

**Q：想双击运行** → 把 `init-workspace.sh` 复制一份改名为 `init-workspace.command`，内容不用改，Finder 里双击即可（会打开终端）。

**Q：怎么判断引导器里的快照是否过期** → 与脚本头部「内置快照清单」的 md5 逐项比对：

```bash
md5 init-project.sh init-research.sh 项目沟通规范.md dev/AGENTS.md READMEFIRST.md   # 会带文件名，便于对照
# Linux 若只有 md5sum：md5sum 同样的文件列表
```

**Q：能不能在 Windows 用** → 脚本是 bash 的，需在 WSL 或 Git Bash 下运行，并自行确认 `md5`/`md5sum` 与换行符差异。

**Q：目标目录和脚本所在目录不一样怎么办** → 默认目标是脚本所在目录；两者不一致时引导器会先确认。要写到当前目录就显式指定：`bash init-workspace.sh --target "$PWD"`。
