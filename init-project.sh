#!/bin/bash
# 项目初始化脚本｜交互式输入项目名 + 全量防误校验
# 注意：AGENTS.md 为纯规则产物，脚本只写入规则内容，不写入任何初始化流程说明
#
# 调用方式：
#   bash init-project.sh        # 推荐：最稳，只看读权限
#   ./init-project.sh           # 需执行位（chmod +x 已设置）
#   ⚠️ 不要用 sh init-project.sh：脚本使用 [[ ]]、read -p 等 bash 特性，POSIX sh 下会失败
#


# ========== 基础工具函数 ==========
PROJECT_NAME=""
PROJECT_DIR=""
REMOTE_URL=""
GH_LOGIN=""

# S9：失败统一出口；若已创建过项目目录，额外提示残留目录的清理方式
die() {
    echo ""
    echo "❌ 初始化未完成：$1"
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        echo "⚠️  已创建但未完成的项目目录：$PROJECT_DIR"
        echo "   确认不需要后可手动删除：rm -rf \"$PROJECT_DIR\""
    fi
    exit 1
}

# ========== S6：切到脚本所在目录，支持从任意工作目录调用 ==========
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)" || die "无法定位脚本所在目录"
cd "$SCRIPT_DIR" || die "无权限进入脚本所在目录：$SCRIPT_DIR"

# ========== 前置校验1：检查本机是否安装git ==========
if ! command -v git &> /dev/null
then
    echo "❌ 错误：未检测到git，请先安装git后再运行本脚本"
    exit 1
fi

# ========== 前置校验2：检查脚本所在目录下是否存在dev主工作区目录 ==========
if [ ! -d "dev" ]; then
    echo "❌ 错误：脚本所在目录（$SCRIPT_DIR）下未找到dev主工作区文件夹"
    echo "请把脚本放在【dev目录的上一级主工作区】下运行"
    exit 1
fi

# 进入dev目录
cd dev || { echo "❌ 错误：无权限进入 $SCRIPT_DIR/dev 目录"; exit 1; }

# ========== 循环交互读取项目名，直到输入完全合规 ==========
while true; do
    # M2：read 返回非零代表输入流已结束（EOF / Ctrl-D / 非交互执行），直接退出而不是空转
    if ! read -r -p "请输入项目名称（仅小写字母/数字/横杠-，且不能以横杠开头或结尾，如 my-demo）: " PROJECT_NAME; then
        echo ""
        echo "❌ 已取消：输入流已结束（EOF 或 Ctrl-D），未创建任何项目"
        exit 1
    fi

    # 校验2.1：项目名不能为空
    if [ -z "$PROJECT_NAME" ]; then
        echo "⚠️  项目名不能为空，请重新输入"
        continue
    fi

    # 校验2.2：项目名仅允许小写字母、数字、横杠；S1：禁止首尾横杠（避免歧义与被误判为命令选项）
    if [[ ! "$PROJECT_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        echo "⚠️  项目名不合法：仅允许小写英文字母、数字、横杠（-），且不能以横杠开头或结尾，不能有大写/空格/特殊符号，请重新输入"
        continue
    fi

    # 校验2.3：项目名不能过长（符合npm规范≤214字符）
    if [ "${#PROJECT_NAME}" -gt 214 ]; then
        echo "⚠️  项目名过长，请输入更短的名称"
        continue
    fi

    # 校验2.4：S2 同名项目不覆盖旧项目，提示后重新输入
    if [ -d "$PROJECT_NAME" ]; then
        echo "⚠️  dev目录下已存在同名项目【${PROJECT_NAME}】，为避免覆盖旧项目，请换一个名称"
        continue
    fi

    # 所有校验通过，跳出循环
    echo "✅ 项目名【${PROJECT_NAME}】校验通过，开始创建..."
    break
done

# ========== S5-1：本机 gh 可用时，提示 GitHub 上是否已有同名仓库（只提示，不创建） ==========
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    GH_LOGIN="$(gh api user --jq .login 2> /dev/null)"
fi
if [ -n "$GH_LOGIN" ] && gh repo view "${GH_LOGIN}/${PROJECT_NAME}" &> /dev/null; then
    echo ""
    echo "ℹ️  GitHub 上已存在同名仓库：${GH_LOGIN}/${PROJECT_NAME}"
    echo "   如需复用它，可在下一步填写：git@github.com:${GH_LOGIN}/${PROJECT_NAME}.git"
fi

# ========== M4：可选配置远端（AGENTS.md 要求推送至 github dev 分支） ==========
echo ""
echo "如需创建后立即推送至远端（github），请输入远端仓库地址；留空则跳过推送。"
# 此处 read 失败（EOF）按「跳过推送」处理，不视为错误
if ! read -r -p "远端地址（可留空跳过）: " REMOTE_URL; then
    REMOTE_URL=""
    echo ""
fi

# ========== S5-2：远端预检（只提示，不阻塞；探针不交互，避免卡在凭据输入上） ==========
if [ -n "$REMOTE_URL" ]; then
    if LSR_OUT="$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" git ls-remote "$REMOTE_URL" 2>&1)"; then
        if printf '%s\n' "$LSR_OUT" | grep -q "refs/heads/dev$"; then
            echo "⚠️  远端已存在 dev 分支，本次推送可能被拒绝（non-fast-forward），请确认是复用该仓库还是更换地址"
        else
            echo "ℹ️  远端仓库可达，暂无 dev 分支，将新建 dev 分支"
        fi
    else
        echo "⚠️  远端预检未通过：地址不存在 / 无权限 / 需要交互式凭据（预检不做交互）"
        echo "   仍会按你填写的地址尝试推送，失败时会给出补救命令"
    fi
fi

# ========== 开始创建项目 ==========
# S1：以 ./ 前缀创建，等价于终止选项解析，避免目录名被当作命令参数
mkdir "./${PROJECT_NAME}" || die "无法创建目录 dev/${PROJECT_NAME}（权限不足或同名文件已存在）"
PROJECT_DIR="$(pwd)/${PROJECT_NAME}"
cd "$PROJECT_DIR" || die "无法进入项目目录：$PROJECT_DIR"

# 写入标准AGENTS.md（用户定义的纯协作规则，脚本不改写其内容）
cat > AGENTS.md <<'EOF'
# AGENTS.md
## 术语约定
- 对话中的"你"指当前执行任务的 agent；用户要求中出现"你"的句子，除疑问句与条件从句外，按"指令"理解。
- 对话中的"AI"是对所有 AI 工具的统称（语言模型、图像/语音识别等），不按工具区分；以"AI"为主语的条款同样约束当前 agent。
- 用户要求中以“设计”开头的指令，只提供设计方案，设计方案存在多个的，在最后总结比较表格，不提供代码实现，每个方案以精确到分钟的“YYYYMMDD HH:mm”+“-”+两位数字自增编号命名，不提交git commit（例如：“20240101 10:00-01”和“20240101 10:00-02”）。方案保存在会话中，采纳的方案记录到locallog.md。
- 用户要求中以“为何”开头的指令，请理解用户的需求，并与前文设计方案进行对比，给出建议。
- 用户要求“整理到开发记录”，添加本轮决策结论与简明原因到locallog.md中。
- 用户要求“检查文档”，根据locallog.md以及当前项目代码的实际功能以及实现，检查README.md、DESIGN.md、TECH.md、CHANGELOG.md、ROADMAP.md与代码是否相符（LICENSE.md与locallog.md不在被检查文档范围），给出实现建议。
- 用户要求“实施方案XXX”或“请按照XXXX实施方案”，请根据用户的需求，提供具体的实现方案，按照行为规范修改代码。
- 用户要求“制作调试工具”，请根据用户的需求，在playground目录下建立测试工具文件夹，制作调试工具、测试数据集等。
- 用户要求“设计服务接口”，请根据用户的需求，提供服务接口的接口文档，包括接口路径、请求方法、请求参数、响应参数、错误码等，用户确认后，写入TECH.md中；该次写入属于本轮生成的变更，随本轮代码变更一并提交至dev分支。
- 用户要求“准备发布新版”，代表本轮变更通过了用户的审查；执行流程：变更package.json版本号，清理代码内临时调试打印、临时注释、硬编码调试片段等开发脏内容，更新README.md、DESIGN.md、TECH.md、CHANGELOG.md、ROADMAP.md与本次变更相符，会话中列出修改点提供给用户。所有变更仅写入本地工作区，不commit，不得直接发布到github仓库。
- 用户要求“发布新版本”，代表本“准备发布新版”后的版本获得用户确认；先提交全部变更到dev分支，再将dev合并至main主分支，基于本次package.json版本号打对应的git tag，禁止直接提交main分支。

## 行为规范
- 每次改动代码完成后，都必须回归测试，再创建对应的本地Git commit。除非用户指定，否则默认推送到github dev分支，commit message采用「类型: 变更摘要」格式；在对话中提供标记commit的版本号，以方便后续追踪和回滚。在对话中提供推荐测试方案，交付用户复核测试评审。未配置远端时只做本地 commit，并在对话中提示需要配置远端。
- 执行代码commit时，默认仅暂存本次生成的代码变更；工作区用户手动修改的文档，无需提交commit，留在工作区，仅随下一轮代码变更（用户确认后）提交至dev分支，或在「准备发布新版」阶段统一对齐，随发布流程入库。
- 生成测试数据，用于测试代码的功能和性能。
- 禁止直接向 main 分支提交代码，main 分支仅通过「发布新版本」流程完成更新。
- 直接回应，先给结论再给依据；不绕弯、不堆空话。
- 用户点名的技术栈、结构、格式与交付形态为硬约束，不得静默替换或降级；需偏离时先说明理由并征得同意。
- 非硬阻塞的问题按合理默认推进，不为小事反复发问；确实无法推进时才停下来提问。
- 全程使用用户所用语言；数据与结论可追溯，不编造事实。
- 实施代码生成规范：按「探查 → 约束 → 证据 → 执行 → 验证 → 交付」推进：
    1. **探查**：动手前完整读取需求指定的全部输入；读不到先解决读取问题，不用印象代替。
    2. **约束**：守住用户点名的范围，只改被点名的部分，保留未要求改动的内容。
    3. **证据**：每个数字、结论来自输入、具体信源或可复现计算；否则标注为待补或估算。
    4. **执行**：受阻时换通道（命令、目录、实现路径），不降级交付物。
    5. **验证**：用「可能失败」的方式回读校验（运行测试、查看渲染、抽样重算），确认通过才算完成。
    6. **交付**：写明产物名、路径与打开方式；宣布完成前确认输入已读全、约束未越界、事实可追溯、产物已验证。

## 文件与目录边界约定
- 文档类文件（README.md、DESIGN.md、TECH.md、CHANGELOG.md、ROADMAP.md、LICENSE.md）由用户自行在本地修改审查；这类文件的改动（含 AI 经用户确认后写入的改动）保留在工作区，随下一轮代码变更（用户确认后）一并由 AI 提交至dev分支，或在「准备发布新版」阶段统一对齐，随发布流程入库；提交口径见上文「行为规范」。
- locallog.md中记录开发过程的关键决策以及实现建议，包括用户需求、设计方案、实现建议、调试工具、服务接口等。属于本地决策讨论，不提交到github任何分支。
- package.json为项目版本号唯一真源数据所在文件，其他版本号都必须从package.json中获取，除“准备发布新版”外，不能直接修改package.json中的版本号。
- README.md为项目介绍文件，必须包含项目名称、版本号、作者、项目介绍、项目功能、项目依赖、项目使用方法、项目贡献者等信息。
- DESIGN.md为产品设计文档，包含用例、项目模块、项目用户视角下的功能描述等产品设计信息。
- TECH.md为项目技术文档，包含项目架构、模块设计、数据流、约束、选型决策、项目数据模型、接口设计、项目选型决策、项目约束等信息。
- CHANGELOG.md：按版本维护变更记录，记录版本号、变更时间、变更类型、变更内容，关联对应commit编号与git tag。
- ROADMAP.md：项目里程碑规划，包含目标、预计时间、里程碑状态（待开发 / 进行中 / 已完成）。
- LICENSE.md：许可证文本、版权声明、版权年份。
- test目录为项目测试目录，必须存放项目测试使用的脏数据示例数据，仅保存在本地，任何分支均不提交到git仓库。
- dev分支为项目开发分支，存放项目最新开发代码，日常开发不变更版本号，仅用于开发和测试。
- main主分支为项目发布分支，存放经过测试验收的稳定版本代码；每次通过发布流程合并dev到main，必须更新package.json中的版本号，并打对应版本号的git tag。
- research目录为项目调研目录，存放项目用到技术的备忘、代码片段、对标资料等。仅保存在本地，任何分支均不提交到git仓库。
- playground目录为项目测试类副本目录，包含脏数据、第三方对比、对标应用或对标代码等。仅保存在本地，任何分支均不提交到git仓库。
EOF

# 写入README.md模板（GitHub 风格最小版本，覆盖 AGENTS.md 要求的字段）
# 注意：本 heredoc 未加引号，${PROJECT_NAME} 会被展开，模板内不要出现其它 $ 与反引号
cat > README.md <<EOF
# ${PROJECT_NAME}

> 一句话说明这个项目做什么。

当前版本：0.0.0（唯一真源为 package.json，随「准备发布新版」流程同步）

## 项目介绍

<!-- 背景、目标、适用场景 -->

## 功能特性

- 

## 环境依赖

<!-- 运行时、依赖库、外部服务 -->

- 

## 安装

\`\`\`bash
# 安装命令示例
\`\`\`

## 使用方法

\`\`\`bash
# 启动或调用示例
\`\`\`

## 作者

- 待填写（姓名 / 联系方式）

## 贡献者

- 欢迎提交 Issue 与 Pull Request。
- 贡献者名单：hoxiudimdim

## 许可证

见 [LICENSE.md](LICENSE.md)（待填写：许可证文本、版权声明、版权年份）
EOF

# 写入package.json，自动填充输入的项目名（S3：不预填 license 字段，避免误导为已采用某许可证）
cat > package.json <<EOF
{
  "name": "${PROJECT_NAME}",
  "version": "0.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {},
  "author": ""
}
EOF

# 创建其余空文档和脏数据目录（TECH.md 为技术文档，与产品文档 DESIGN.md 并列）
touch DESIGN.md TECH.md CHANGELOG.md ROADMAP.md locallog.md LICENSE.md
mkdir test playground research

# 写入.gitignore
cat > .gitignore <<'EOF'
locallog.md
test/
playground/
research/
node_modules/
dist/
.env
EOF

# ========== 初始化git仓库（M3：dev 落地 v0.0.0 基线 → 合并到 main；不在 main 上做任何提交） ==========
git init -q || die "git init 失败"
git checkout -b dev || die "创建 dev 分支失败"
git add AGENTS.md README.md package.json DESIGN.md TECH.md CHANGELOG.md ROADMAP.md LICENSE.md .gitignore \
    || die "git add 失败（请检查上述文件是否齐全）"
git commit -q -m "chore: init project base v0.0.0" \
    || die "git commit 失败（常见原因：未配置 git 的 user.name / user.email，或 gpg 签名不可用）"

# M3：把 dev 的 v0.0.0 基线合并到 main。新仓库中 main 与 dev 同指该提交，因此这次合并无内容可合并
git checkout -b main || die "创建 main 分支失败"
git merge --ff-only dev || die "合并 dev 到 main 失败"
git checkout dev || die "切回 dev 分支失败"

# M1 回读校验：确认提交与两个分支真实存在且同指，避免「打印成功但仓库是空的」
git rev-parse --verify --quiet HEAD > /dev/null || die "回读校验失败：初始提交不存在"
git show-ref --verify --quiet refs/heads/dev || die "回读校验失败：dev 分支不存在"
git show-ref --verify --quiet refs/heads/main || die "回读校验失败：main 分支不存在"
[ "$(git rev-parse main)" = "$(git rev-parse dev)" ] || die "回读校验失败：main 与 dev 未同指初始提交"
INIT_COMMIT="$(git rev-parse --short HEAD)"
BASE_VERSION="$(sed -n 's/.*"version": "\(.*\)".*/\1/p' package.json)"

# M4：填写了远端则推送；推送失败不影响本地仓库，给出明确的补救命令
if [ -n "$REMOTE_URL" ]; then
    git remote add origin "$REMOTE_URL" || die "git remote add 失败：$REMOTE_URL"
    if ! git push -u origin dev; then
        echo ""
        echo "⚠️  推送失败：本地仓库已初始化成功，请勿删除 $PROJECT_DIR"
        echo "   修复凭据或网络后执行：cd \"$PROJECT_DIR\" && git push -u origin dev"
        exit 1
    fi
fi

# ========== 完成 ==========
echo ""
echo "✅ 全部完成！"
echo "项目路径: dev/${PROJECT_NAME}"
echo "初始提交: ${INIT_COMMIT}（分支 dev，已合并到 main）"
echo "版本基线: package.json version = ${BASE_VERSION}（未打 tag，tag 由「发布新版本」流程创建）"
echo "当前分支: dev（日常开发） | main（发布分支，与 dev 同指 ${INIT_COMMIT}）"
if [ -n "$REMOTE_URL" ]; then
    echo "远端: origin = ${REMOTE_URL}（dev 已推送并设置 upstream）"
else
    echo "远端: 未配置。AGENTS.md 要求推送至 github dev 分支，需先执行："
    echo "      cd \"$PROJECT_DIR\" && git remote add origin <地址> && git push -u origin dev"
fi
echo "被git忽略的本地文件: locallog.md / test/ 脏数据目录"
echo "待补充: LICENSE.md 为空白占位，脚本不预填任何许可证，请自行填写"
