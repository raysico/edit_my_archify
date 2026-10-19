#!/bin/bash
# 主工作区引导器｜把 anythinks 主工作区模板一次复现到目标根目录
# 快照来源：anythinks（2026-10-17）；内置 5 份资产 + resources/ 目录，写入后逐字节回读校验
#
# 调用方式：
#   bash init-workspace.sh                # 目标 = 脚本所在目录（典型用法：把本文件放进新根目录再运行）
#   bash init-workspace.sh --target DIR   # 显式指定目标目录（可与脚本所在目录不同）
#   bash init-workspace.sh --dry-run      # 只打印计划，不写文件、不做回读校验
#   bash init-workspace.sh --force        # 覆盖内容不同的既有文件（覆盖前自动备份 .bak-<时间戳>）
#   bash init-workspace.sh --no-self      # 不把本引导器自身复制进目标目录
#   ⚠️ 不要用 sh init-workspace.sh：脚本使用 [[ ]]、read -p 等 bash 特性，POSIX sh 下会失败
#
# 内置快照清单：
#   init-project.sh      42b1946dafd3cd2c2295ced9a6b21695   17492 字节
#   init-research.sh     0c764bdaa34a4fdb78c9d2ec29e9a85e   13839 字节
#   项目沟通规范.md            dc5655e3a413cc7ebeb351cbfa70fec2    2977 字节
#   dev/AGENTS.md        35fdbdd483f2d34001487727396bb1b8    7341 字节
#   READMEFIRST.md       7ae18db6280f6ba2169d3a70b1c25752    6779 字节
#   resources/           空目录
#
# 既有文件策略：与快照相同 → 跳过；内容不同 → 跳过并提示（仅 --force 才覆盖，且先备份）
# 退出码：0 完成（含「有未对齐项被跳过」）；1 写入失败/回读校验失败/用户取消；2 参数错误
# 不做的事：不建 research/ playground/ docs/（anythinks 现状没有这些目录；research/ 由 init-research.sh
#           首次运行时自动创建）；不初始化 git、不写 .gitignore、不联网、不改目标目录之外的任何文件

# ========== 基础变量 ==========
FORCE=0
DRY_RUN=0
WITH_SELF=1
TARGET=""
SELF=""
SELF_DIR=""
LAST_RESULT=""
CHECK_LIST=""
UNALIGNED=0
UNALIGNED_LIST=""
FAIL=0
CONFIRM=""
TARGET_FROM_DEFAULT=0
USAGE="用法: bash init-workspace.sh [--target DIR] [--dry-run] [--force] [--no-self]"

die() {
    echo ""
    echo "❌ 引导未完成：$1"
    exit 1
}

echo_md5() {  # $1=文件路径；无摘要工具时返回 unknown
    if command -v md5 &> /dev/null; then
        md5 -q "$1" 2> /dev/null
    elif command -v md5sum &> /dev/null; then
        md5sum "$1" 2> /dev/null | cut -d' ' -f1
    else
        echo "unknown"
    fi
}

expect_md5() {  # $1=相对路径；返回该资产的快照 md5
    case "$1" in
        "init-project.sh") echo "42b1946dafd3cd2c2295ced9a6b21695" ;;
        "init-research.sh") echo "0c764bdaa34a4fdb78c9d2ec29e9a85e" ;;
        "项目沟通规范.md") echo "dc5655e3a413cc7ebeb351cbfa70fec2" ;;
        "dev/AGENTS.md") echo "35fdbdd483f2d34001487727396bb1b8" ;;
        "READMEFIRST.md") echo "7ae18db6280f6ba2169d3a70b1c25752" ;;
        *) echo "" ;;
    esac
}

# ========== 参数解析 ==========
while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            [ $# -ge 2 ] || die "--target 缺少目录参数。$USAGE"
            TARGET="$2"
            shift 2
            ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force)   FORCE=1;   shift ;;
        --no-self) WITH_SELF=0; shift ;;
        -h|--help) echo "$USAGE"; exit 0 ;;
        *) echo "❌ 未知参数：$1"; echo "$USAGE"; exit 2 ;;
    esac
done

# ========== 定位自身（支持 bash / ./ / 绝对路径三种调用） ==========
SELF_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)" || die "无法定位脚本所在目录"
SELF="$SELF_DIR/$(basename -- "$0")"
CWD_REAL="$(pwd -P)"

if [ -z "$TARGET" ]; then
    TARGET="$SELF_DIR"
    TARGET_FROM_DEFAULT=1
fi
case "$TARGET" in '~'/*) TARGET="$HOME/${TARGET#\~/}" ;; esac

[ -e "$TARGET" ] && [ ! -d "$TARGET" ] && die "目标不是目录：$TARGET"
if [ ! -d "$TARGET" ]; then
    echo "ℹ️  目标目录不存在，将创建：$TARGET"
    [ "$DRY_RUN" = "1" ] || mkdir -p "$TARGET" || die "无法创建目标目录：$TARGET"
fi
if [ -d "$TARGET" ]; then
    TARGET="$(cd -- "$TARGET" && pwd -P)" || die "无法进入目标目录：$TARGET"
fi
[ "$DRY_RUN" = "1" ] || [ -w "$TARGET" ] || die "目标目录不可写：$TARGET"

echo "引导器自身: $SELF"
echo "目标目录  : $TARGET"
[ "$DRY_RUN" = "1" ] && echo "模式      : --dry-run（只打印计划，不写文件）"
[ "$FORCE" = "1" ] && echo "模式      : --force（覆盖内容不同的既有文件，覆盖前备份）"

# ========== 哨兵：默认目标（脚本所在目录）与当前目录不一致时先确认 ==========
if [ "$TARGET_FROM_DEFAULT" = "1" ] && [ "$TARGET" != "$CWD_REAL" ]; then
    echo "⚠️  未指定 --target：脚本所在目录与当前目录不同"
    echo "    脚本所在目录（默认目标）: $TARGET"
    echo "    当前目录                : $CWD_REAL"
    if [ "$DRY_RUN" = "1" ]; then
        echo "    （--dry-run：不做确认，仅打印计划）"
    else
        if ! read -r -p "仍要写入上面的默认目标吗？[y/N] " CONFIRM; then
            echo ""
            echo "❌ 已取消：输入流已结束（EOF 或 Ctrl-D），未写入任何文件"
            exit 1
        fi
        case "$CONFIRM" in
            y|Y|yes|YES) ;;
            *) echo "❌ 已取消。若要写入当前目录，请显式指定：bash $(basename -- "$SELF") --target \"$CWD_REAL\""
               exit 1 ;;
        esac
    fi
fi

# ========== 写入策略 ==========
# 返回 0 = 需要（且允许）写入；返回 1 = 跳过；真实结论见全局 LAST_RESULT
# LAST_RESULT 取值：new / overwritten / same / diff / dryrun
need_write() {
    local path="$1" expect="$2" cur=""
    if [ ! -e "$path" ]; then
        echo "  + 写入：$path"
        if [ "$DRY_RUN" = "1" ]; then LAST_RESULT="dryrun"; return 1; fi
        LAST_RESULT="new"
        return 0
    fi
    cur="$(echo_md5 "$path")"
    if [ "$cur" = "$expect" ]; then
        echo "  = 跳过（与快照相同）：$path"
        LAST_RESULT="same"
        return 1
    fi
    if [ "$FORCE" != "1" ]; then
        echo "  ! 跳过（内容不同，未覆盖）：$path"
        echo "     本地 md5 $cur"
        echo "     快照 md5 $expect"
        LAST_RESULT="diff"
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        echo "  ~ 将覆盖（--dry-run 未执行）：$path"
        LAST_RESULT="dryrun"
        return 1
    fi
    local bak="$path.bak-$(date '+%Y%m%d%H%M%S')"
    cp "$path" "$bak" || die "备份失败：$bak"
    echo "  ~ 覆盖（已备份）：$path → $(basename -- "$bak")"
    LAST_RESULT="overwritten"
    return 0
}

# 按 need_write 的结论做记账：写过的进校验清单，跳过的进未对齐清单
track() {  # $1=相对路径
    case "$LAST_RESULT" in
        new|overwritten) CHECK_LIST="$CHECK_LIST $1" ;;
        diff) UNALIGNED=$((UNALIGNED + 1)); UNALIGNED_LIST="$UNALIGNED_LIST $1" ;;
    esac
}

# ========== 资产 1/5：init-project.sh（开发类子项目初始化） ==========
if need_write "$TARGET/init-project.sh" "42b1946dafd3cd2c2295ced9a6b21695"; then
    cat > "$TARGET/init-project.sh" <<'__AA_PAYLOAD_INIT_PROJECT_SH__'
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
__AA_PAYLOAD_INIT_PROJECT_SH__
    chmod 755 "$TARGET/init-project.sh" || die "设置权限失败：$TARGET/init-project.sh"
fi
track "init-project.sh"

# ========== 资产 2/5：init-research.sh（调研类子项目初始化） ==========
if need_write "$TARGET/init-research.sh" "0c764bdaa34a4fdb78c9d2ec29e9a85e"; then
    cat > "$TARGET/init-research.sh" <<'__AA_PAYLOAD_INIT_RESEARCH_SH__'
#!/bin/bash
# 调研类子项目初始化脚本｜交互式输入课题名 + 全量防误校验
# 产物：research/<课题名>/ —— 纯本地目录：不初始化 git、不配置远端、不产生任何 commit
#
# 调用方式：
#   bash init-research.sh       # 推荐：最稳，只看读权限
#   ./init-research.sh          # 需执行位（chmod +x 已设置）
#   ⚠️ 不要用 sh init-research.sh：脚本使用 [[ ]]、read -p 等 bash 特性，POSIX sh 下会失败
#
# 与 init-project.sh 的设计差异（本脚本要点）：
#   G1  不建 git 仓库、不配远端：AGENTS.md 规定 research 目录仅保存在本地，任何分支均不提交
#   G2  课题名放宽：允许中文/英文/数字/空格/横杠/下划线（调研课题名多为中文），仍禁止路径分隔符、控制字符与首尾空白
#   G3  产物结构对齐 research/示例项目：<课题名>研究结论成果.md + 资料/
#   G4  写入调研专用 AGENTS.md（结论分级、来源可追溯、资料归档命名）
#   G5  research 目录缺失时自动创建后继续（D5 决定；原设计为报错退出，与 init-project.sh 对 dev 的口径相反）
#   G6  幂等维护根目录 .gitignore 的 research/ 规则，防止调研资料误入 git 仓库
#   M1  各步骤逐一检查退出码 + 完成后回读校验
#   M2  输入流结束（EOF / Ctrl-D / 非交互执行）时退出，不死循环
#   S2  同名课题提示后重新输入，不中止整个脚本
#   S9  失败统一出口，并提示残留目录的清理方式

# ========== 基础变量与失败出口 ==========
TOPIC_NAME=""
TOPIC_DIR=""
ROOT_DIR=""
TODAY=""
GITIGNORE_NOTE=""
CONFIRM=""

# S9：失败统一出口；若已创建过课题目录，额外提示残留目录的清理方式
die() {
    echo ""
    echo "❌ 初始化未完成：$1"
    if [ -n "$TOPIC_DIR" ] && [ -d "$TOPIC_DIR" ]; then
        echo "⚠️  已创建但未完成的调研目录：$TOPIC_DIR"
        echo "   确认不需要后可手动删除：rm -rf \"$TOPIC_DIR\""
    fi
    exit 1
}

# ========== S6：切到脚本所在目录，支持从任意工作目录调用 ==========
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)" || die "无法定位脚本所在目录"
cd "$SCRIPT_DIR" || die "无权限进入脚本所在目录：$SCRIPT_DIR"
ROOT_DIR="$SCRIPT_DIR"

# ========== G5：定位主工作区；research 目录缺失时自动创建后继续（D5 决定） ==========
if [ ! -d "research" ]; then
    # D7 哨兵：不像主工作区时先确认，避免脚本被放到别处就凭空造出 research/
    if [ ! -d "dev" ] && [ ! -f "项目沟通规范.md" ]; then
        echo "⚠️  $SCRIPT_DIR 下既没有 research/，也不像主工作区（未找到 dev/ 或 项目沟通规范.md）"
        if ! read -r -p "仍要在此创建 research/ 吗？[y/N] " CONFIRM; then
            echo ""
            echo "❌ 已取消：输入流已结束（EOF 或 Ctrl-D），未创建任何目录"
            exit 1
        fi
        case "$CONFIRM" in
            y|Y|yes|YES) ;;
            *) echo "❌ 已取消，未创建任何目录"; exit 1 ;;
        esac
    fi
    echo "ℹ️  脚本所在目录（$SCRIPT_DIR）下未找到 research 调研目录，将自动创建"
    mkdir "research" || die "无法创建目录：$SCRIPT_DIR/research（权限不足或存在同名文件）"
    echo "✅ 已创建 research 目录：$SCRIPT_DIR/research"
fi

if [ ! -w "research" ]; then
    echo "❌ 错误：无写权限：$SCRIPT_DIR/research"
    exit 1
fi

# 进入 research 目录
cd research || die "无权限进入 $SCRIPT_DIR/research 目录"

TODAY="$(date '+%Y-%m-%d')"

# ========== 循环交互读取课题名，直到输入完全合规 ==========
# 采用黑名单法校验（不用字符白名单），以兼容中文课题名
FORBIDDEN_CHARS='[/\\:*?"<>|]'
while true; do
    # M2：read 返回非零代表输入流已结束（EOF / Ctrl-D / 非交互执行），直接退出而不是空转
    if ! read -r -p "请输入调研课题名（可用中文，如 空间语义评估；允许中英文/数字/空格/-/_）: " TOPIC_NAME; then
        echo ""
        echo "❌ 已取消：输入流已结束（EOF 或 Ctrl-D），未创建任何调研目录"
        exit 1
    fi

    # 校验1：课题名不能为空
    if [ -z "$TOPIC_NAME" ]; then
        echo "⚠️  课题名不能为空，请重新输入"
        continue
    fi

    # 校验2：课题名不能过长
    # 按字节计（LC_ALL=C 强制），因为文件名上限是字节制的（APFS/EXT4 均为 255 字节），
    # 且 ${#VAR} 的结果依赖 LC_CTYPE：UTF-8 下按字符、C 下按字节，直接用它会导致校验随终端环境漂移。
    # 上限 180 字节：需为「研究结论成果.md」（21 字节）留出余量，避免文件名超限。
    NAME_BYTES="$(printf '%s' "$TOPIC_NAME" | LC_ALL=C wc -c | tr -d '[:space:]')"
    if [ "$NAME_BYTES" -gt 180 ]; then
        echo "⚠️  课题名过长（当前 ${NAME_BYTES} 字节，上限 180 字节，约合 60 个汉字或 180 个英文字符），请输入更短的名称"
        continue
    fi

    # 校验3：禁止路径分隔符与文件系统保留字符
    if [[ "$TOPIC_NAME" =~ $FORBIDDEN_CHARS ]]; then
        echo "⚠️  课题名不合法：不能包含 / \\ : * ? \" < > | 等字符，请重新输入"
        continue
    fi

    # 校验4：禁止控制字符（制表符、换行等）
    if [[ "$TOPIC_NAME" =~ [[:cntrl:]] ]]; then
        echo "⚠️  课题名不合法：不能包含制表符、换行等控制字符，请重新输入"
        continue
    fi

    # 校验5：不能以空格、点、横杠开头（点开头为隐藏目录；横杠开头易被误判为命令选项）
    if [[ "$TOPIC_NAME" == [[:space:].-]* ]]; then
        echo "⚠️  课题名不能以空格、点（.）或横杠（-）开头，请重新输入"
        continue
    fi

    # 校验6：不能以空格或点结尾（跨平台同步与命令行场景下易产生歧义）
    if [[ "$TOPIC_NAME" == *[[:space:].] ]]; then
        echo "⚠️  课题名不能以空格或点（.）结尾，请重新输入"
        continue
    fi

    # 校验7：S2 同名课题不覆盖旧课题，提示后重新输入
    if [ -e "$TOPIC_NAME" ]; then
        echo "⚠️  research 目录下已存在同名课题【${TOPIC_NAME}】，为避免覆盖旧课题，请换一个名称"
        continue
    fi

    # 所有校验通过，跳出循环
    echo "✅ 课题名【${TOPIC_NAME}】校验通过，开始创建..."
    break
done

# ========== 开始创建课题目录 ==========
# 以 ./ 前缀创建，等价于终止选项解析，避免目录名被当作命令参数
mkdir "./${TOPIC_NAME}" || die "无法创建目录 research/${TOPIC_NAME}（权限不足或同名文件已存在）"
TOPIC_DIR="$(pwd)/${TOPIC_NAME}"
cd "$TOPIC_DIR" || die "无法进入课题目录：$TOPIC_DIR"

mkdir -p "资料" "笔记" || die "创建子目录失败（资料 / 笔记）"

# 写入调研专用 AGENTS.md（本目录的协作规则，不写初始化流程说明）
cat > AGENTS.md <<EOF
# AGENTS.md（调研类子项目）

## 术语约定
- 对话中的"你"指当前执行任务的 agent；本目录是调研课题【${TOPIC_NAME}】的本地工作区。
- 本目录不是 dev 开发项目：不初始化 git 仓库、不配置远端、不产生任何 commit。
- 用户要求"调研 XXX"：按「定目标与范围 → 收集材料 → 核验来源 → 形成结论 → 交付依据」推进。

## 调研规范
- 结论分级：每条结论标注「已查证」（附来源与访问日期）或「待确认」（写明缺口与验证方式）；不编造数据与来源。
- 资料归档：外部资料存入 资料/，文件名采用「YYYYMMDD-来源-主题」，并登记到 资料/README.md 的登记表。
- 过程记录：关键判断、放弃的路线、新增待办写入 locallog.md；零散笔记与代码片段放入 笔记/。
- 交付物：结论写入「${TOPIC_NAME}研究结论成果.md」；无依据的内容只能出现在「待确认事项」，不得混入结论。
- 数据时点：引用他人数据必须写明数据截止时间与版本；估算值必须显式标注为「估算」。
- 本地优先：涉及第三方仓库、大文件、涉敏资料时只保存在本地，不引入任何提交与推送动作。

## 行为规范
- 需与用户明确调研目标与范围，根据不同的调研目标采取不同的调研策略。
- 以学习技术的调研：建立技术备忘录，记录调研过程中的技术问题、解决方法、经验教训等。
- 市场或获取数据的调研：记录调研过程中的数据来源、数据处理、数据验证等。
- 直接回应，先给结论再给依据；不绕弯、不堆空话。
- 全程使用用户所用语言；结论可追溯，不编造事实。
- 调研的多个结果之间存在矛盾，请在对话中列出对比与推荐，由用户拍板；不把互斥分支原样丢给用户。
- 确实无法完成的事项，如实说明未完成项、原因与影响，不悄悄降级后宣称完成。
EOF

# 写入主产物：研究结论成果（骨架，避免只有空文件而无法开工）
cat > "${TOPIC_NAME}研究结论成果.md" <<EOF
# ${TOPIC_NAME} 研究结论成果

> 一句话结论（先给结论，再给依据；尚未形成结论时写「尚未形成结论」）

- 课题：${TOPIC_NAME}
- 建立时间：${TODAY}
- 状态：进行中

## 1. 调研目标与范围

- 目标：
- 范围（包含什么／不包含什么）：
- 收口条件（满足什么即可结束调研）：

## 2. 已查证结论

| 序号 | 结论 | 依据（来源 + 访问日期） | 可信度 |
| --- | --- | --- | --- |
| 1 |  |  | 待评 |

## 3. 待确认事项

| 序号 | 待确认点 | 缺口 | 验证方式 | 计划时间 |
| --- | --- | --- | --- | --- |

## 4. 关键数据与出处

| 数据 | 数值 | 单位 | 数据时点 | 来源 |
| --- | --- | --- | --- | --- |

## 5. 备选方案对比

| 方案 | 要点 | 成本 | 风险 | 结论 |
| --- | --- | --- | --- | --- |

## 6. 参考资料

- 以 资料/README.md 的登记表为准，此处只列最关键的引用。

## 7. 变更记录

| 日期 | 变更 | 说明 |
| --- | --- | --- |
| ${TODAY} | 建立课题 | 由 init-research.sh 初始化 |
EOF

# 写入资料登记表（资料目录的唯一入口，落盘与登记一一对应）
cat > "资料/README.md" <<EOF
# 资料登记（${TOPIC_NAME}）

外部资料的唯一登记处：先在 资料/ 落盘，再在此登记来源与访问日期。

| 文件名 | 来源链接 | 获取时间 | 类型（官方/论文/博客/代码） | 可信度（高/中低/低） | 备注 |
| --- | --- | --- | --- | --- | --- |

## 归档约定

- 文件名格式：YYYYMMDD-来源-主题（例：20261017-官方文档-同步协议说明.pdf）。
- 网页类资料同时保存正文快照或 PDF，避免链接失效后无法追溯。
- 可信度判定：官方文档与源码为高；同行评审论文为中高；厂商宣传为低；无法核实的转述不计入结论。
EOF

# 写入本地记录（不提交任何仓库）
cat > locallog.md <<EOF
# locallog（本地记录，不提交任何仓库）

## 课题

- ${TOPIC_NAME}（建立于 ${TODAY}）

## 调研过程与关键决策

| 日期 | 决策 / 发现 | 原因 |
| --- | --- | --- |
|  |  |  |

## 放弃的路线

- 

## 待办

- [ ] 
EOF

# ========== M1 回读校验：确认目录与文件真实存在且非空 ==========
[ -d "$TOPIC_DIR" ] || die "回读校验失败：课题目录不存在"
[ -s "AGENTS.md" ] || die "回读校验失败：AGENTS.md 缺失或为空"
[ -s "${TOPIC_NAME}研究结论成果.md" ] || die "回读校验失败：研究结论成果缺失或为空"
[ -s "资料/README.md" ] || die "回读校验失败：资料/README.md 缺失或为空"
[ -s "locallog.md" ] || die "回读校验失败：locallog.md 缺失或为空"
[ -d "资料" ] || die "回读校验失败：资料 目录不存在"
[ -d "笔记" ] || die "回读校验失败：笔记 目录不存在"

# ========== G6：幂等维护根目录 .gitignore（调研资料绝不进仓库的安全网） ==========
if [ ! -f "$ROOT_DIR/.gitignore" ]; then
    printf 'research/\n' > "$ROOT_DIR/.gitignore" || die "写入 $ROOT_DIR/.gitignore 失败"
    GITIGNORE_NOTE="已创建根目录 .gitignore 并写入 research/"
elif ! grep -qxF 'research/' "$ROOT_DIR/.gitignore"; then
    printf '\n# 调研类子项目：仅保存在本地，任何分支均不提交\nresearch/\n' >> "$ROOT_DIR/.gitignore" \
        || die "追加 research/ 到根目录 .gitignore 失败"
    GITIGNORE_NOTE="已在根目录 .gitignore 追加 research/"
else
    GITIGNORE_NOTE="根目录 .gitignore 已含 research/，未改动"
fi

# ========== 完成 ==========
echo ""
echo "✅ 调研课题初始化完成！"
echo "课题目录: research/${TOPIC_NAME}"
echo "目录结构:"
echo "  research/${TOPIC_NAME}/"
echo "  ├── AGENTS.md               调研规则（结论分级 / 来源登记 / 本地优先）"
echo "  ├── ${TOPIC_NAME}研究结论成果.md   主产物：结论 + 待确认事项 + 数据出处"
echo "  ├── locallog.md             本地过程记录（不提交）"
echo "  ├── 资料/README.md          资料登记表 + 归档约定"
echo "  └── 笔记/                   零散笔记与代码片段"
echo "git 状态: 未初始化仓库、未配置远端（research 仅保存在本地，任何分支均不提交）"
echo "根目录 .gitignore: ${GITIGNORE_NOTE}"
echo ""
echo "下一步:"
echo "  1. 打开 research/${TOPIC_NAME}/${TOPIC_NAME}研究结论成果.md 填写调研目标与范围"
echo "  2. 收集到的材料放入 research/${TOPIC_NAME}/资料/，并在 资料/README.md 登记来源与访问日期"
__AA_PAYLOAD_INIT_RESEARCH_SH__
    chmod 755 "$TARGET/init-research.sh" || die "设置权限失败：$TARGET/init-research.sh"
fi
track "init-research.sh"

# ========== 资产 3/5：项目沟通规范.md（工作区级规范） ==========
if need_write "$TARGET/项目沟通规范.md" "dc5655e3a413cc7ebeb351cbfa70fec2"; then
    cat > "$TARGET/项目沟通规范.md" <<'__AA_PAYLOAD_COMM_SPEC_MD__'
# 开发沟通行为规范

面向 agent 工具的行为规范与约定

## 1. 术语约定
**开发类子项目初始化**：执行 init-project.sh 脚本，根据用户输入的项目名初始化项目目录结构。
**调研类子项目初始化**：执行 init-research.sh 脚本，根据用户输入的项目名初始化项目目录结构。
## 2. 项目结构
    - 项目根目录：包含项目的所有文件与目录。是你与我协作的根域，除终端外超过这个范围的文件与目录操作，均需要用户明确的指令级确认。
    - dev：开发类子项目目录，包含项目的所有开发相关文件与目录。
        - 项目同名目录：开发类子项目的根文件夹，名称与用户输入的项目名一致。
            - test：子项目级测试目录，包含项目的所有测试相关文件与目录。
    - research：调研类子项目目录，包含项目的所有调研相关文件与目录。
    - playground：测试类副本目录，包含脏数据、第三方对比、对标应用或对标代码等。
    - resources：工作区级资源目录，包含项目的所有资源文件与目录。
    - docs：项目总文档目录，包含项目的所有文档文件与目录。

## 3. 沟通与交互原则

- 直接回应，先给结论再给依据；不绕弯、不堆空话。
- 用户点名的技术栈、结构、格式与交付形态为硬约束，不得静默替换或降级；需偏离时先说明理由并征得同意。
- 非硬阻塞的问题按合理默认推进，不为小事反复发问；确实无法推进时才停下来提问。
- 全程使用用户所用语言；数据与结论可追溯，不编造事实。

## 4. 执行纪律

按「探查 → 约束 → 证据 → 执行 → 验证 → 交付」推进：

1. **探查**：动手前完整读取需求指定的全部输入；读不到先解决读取问题，不用印象代替。
2. **约束**：守住用户点名的范围，只改被点名的部分，保留未要求改动的内容。
3. **证据**：每个数字、结论来自输入、具体信源或可复现计算；否则标注为待补或估算。
4. **执行**：受阻时换通道（命令、目录、实现路径），不降级交付物。
5. **验证**：用「可能失败」的方式回读校验（运行测试、查看渲染、抽样重算），确认通过才算完成。
6. **交付**：写明产物名、路径与打开方式；宣布完成前确认输入已读全、约束未越界、事实可追溯、产物已验证。

## 5. 决策与风险处理

- 高影响、难回滚或影响外部系统的操作，先说明影响面与方案，供用户决策后执行。
- 存在多种可行方案时，列出对比与推荐，由用户拍板；不把互斥分支原样丢给用户。
- 发现错误时修正产物本身；改过生成逻辑后重跑全部产物。
- 确实无法完成的事项，如实说明未完成项、原因与影响，不悄悄降级后宣称完成。
__AA_PAYLOAD_COMM_SPEC_MD__
    chmod 644 "$TARGET/项目沟通规范.md" || die "设置权限失败：$TARGET/项目沟通规范.md"
fi
track "项目沟通规范.md"

# ========== 资产 4/5：dev/AGENTS.md（开发域规则，取自 init-project.sh 内置基准文本） ==========
if [ ! -d "$TARGET/dev" ]; then
    echo "  + 创建目录：$TARGET/dev"
    [ "$DRY_RUN" = "1" ] || mkdir -p "$TARGET/dev" || die "无法创建目录：$TARGET/dev"
fi

if need_write "$TARGET/dev/AGENTS.md" "35fdbdd483f2d34001487727396bb1b8"; then
    cat > "$TARGET/dev/AGENTS.md" <<'__AA_PAYLOAD_DEV_AGENTS_MD__'
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
__AA_PAYLOAD_DEV_AGENTS_MD__
    chmod 644 "$TARGET/dev/AGENTS.md" || die "设置权限失败：$TARGET/dev/AGENTS.md"
fi
track "dev/AGENTS.md"

# ========== 资产 5/5：READMEFIRST.md（新环境使用教程） ==========
if need_write "$TARGET/READMEFIRST.md" "7ae18db6280f6ba2169d3a70b1c25752"; then
    cat > "$TARGET/READMEFIRST.md" <<'__AA_PAYLOAD_READMEFIRST_MD__'
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
__AA_PAYLOAD_READMEFIRST_MD__
    chmod 644 "$TARGET/READMEFIRST.md" || die "设置权限失败：$TARGET/READMEFIRST.md"
fi
track "READMEFIRST.md"


# ========== 目录：resources/（工作区级资源目录） ==========
if [ ! -d "$TARGET/resources" ]; then
    echo "  + 创建目录：$TARGET/resources"
    [ "$DRY_RUN" = "1" ] || mkdir -p "$TARGET/resources" || die "无法创建目录：$TARGET/resources"
else
    echo "  = 已存在目录：$TARGET/resources"
fi

# ========== 可选：把引导器自身复制进目标目录，便于下次复用/更新 ==========
if [ "$WITH_SELF" = "1" ]; then
    SELF_TARGET="$TARGET/$(basename -- "$SELF")"
    if [ "$SELF" = "$SELF_TARGET" ]; then
        echo "  = 跳过（本引导器已在目标目录）：$SELF_TARGET"
    else
        if need_write "$SELF_TARGET" "$(echo_md5 "$SELF")"; then
            cp "$SELF" "$SELF_TARGET" || die "复制引导器自身失败：$SELF_TARGET"
            chmod 755 "$SELF_TARGET" || die "设置权限失败：$SELF_TARGET"
        fi
        case "$LAST_RESULT" in
            diff) UNALIGNED=$((UNALIGNED + 1)); UNALIGNED_LIST="$UNALIGNED_LIST $(basename -- "$SELF")" ;;
        esac
    fi
else
    echo "  - 按 --no-self 跳过：不复制引导器自身"
fi

# ========== 回读校验：只校验本次真正写入/覆盖的文件 ==========
if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "✅ --dry-run 结束：以上为计划，未写入任何文件（跳过回读校验）"
    exit 0
fi

echo ""
echo "回读校验（md5，只校验本次写入的文件）："
if [ -z "$CHECK_LIST" ]; then
    echo "  - 本次没有写入文件（目标已与快照一致，或全部按策略跳过）"
fi
for n in $CHECK_LIST; do
    p="$TARGET/$n"
    want="$(expect_md5 "$n")"
    got="$(echo_md5 "$p")"
    if [ ! -s "$p" ]; then
        echo "  ✗ $n：不存在或为空"
        FAIL=1
    elif [ "$got" = "unknown" ]; then
        echo "  ~ $n：已写入且非空（无 md5/md5sum，跳过逐字节比对）"
    elif [ "$got" = "$want" ]; then
        echo "  ✓ $n  $got"
    else
        echo "  ✗ $n"
        echo "     期望 $want"
        echo "     实际 $got"
        FAIL=1
    fi
done
[ -d "$TARGET/resources" ] || { echo "  ✗ resources/：目录不存在"; FAIL=1; }
[ -d "$TARGET/dev" ] || { echo "  ✗ dev/：目录不存在"; FAIL=1; }

# ========== 完成 ==========
echo ""
if [ "$FAIL" != "0" ]; then
    echo "❌ 引导未完成：回读校验失败（已写入的文件与快照不一致）：$TARGET"
    exit 1
fi
echo "✅ 主工作区引导完成！"
echo "目标目录: $TARGET"
echo "产物清单: init-project.sh / init-research.sh / 项目沟通规范.md / dev/AGENTS.md / READMEFIRST.md / resources/"
[ "$WITH_SELF" = "1" ] && echo "          $(basename -- "$SELF")（引导器自身）"
if [ "$UNALIGNED" != "0" ]; then
    echo ""
    echo "⚠️  有 $UNALIGNED 项未与快照对齐，已保留本地版本：${UNALIGNED_LIST# }"
    echo "    如需以快照覆盖：重跑并加 --force（覆盖前自动备份为 .bak-<时间戳>）"
fi
echo ""
echo "环境自检（新环境准备情况，详见 READMEFIRST.md 第 2 节；不影响本次引导结果）："
if command -v git &> /dev/null; then
    echo "  ✓ git $(git --version 2> /dev/null | awk '{print $3}')"
else
    echo "  ⚠️ 未检测到 git：init-project.sh 无法运行（init-research.sh 不受影响）"
fi
GH_NAME="$(git config --global user.name 2> /dev/null)"
GH_MAIL="$(git config --global user.email 2> /dev/null)"
if [ -n "$GH_NAME" ] && [ -n "$GH_MAIL" ]; then
    echo "  ✓ git 身份已配置：$GH_NAME <$GH_MAIL>"
else
    echo "  ⚠️ git 身份未配置（user.name / user.email）：init-project.sh 首次 commit 会失败"
    echo "     修复：git config --global user.name \"你的名字\" && git config --global user.email \"you@example.com\""
fi
if command -v md5 &> /dev/null; then
    echo "  ✓ md5 可用（回读校验做逐字节比对）"
elif command -v md5sum &> /dev/null; then
    echo "  ✓ md5sum 可用（回读校验做逐字节比对）"
else
    echo "  ⚠️ 无 md5/md5sum：回读校验降级为「文件非空」"
fi
echo "  ℹ️ bash $(bash --version 2> /dev/null | head -1 | sed 's/.*version \([0-9.]*\).*/\1/')（脚本需 bash，不能用 sh 运行）"
echo ""
echo "下一步:"
echo "  1. 先读 READMEFIRST.md（新环境准备清单 + 完整使用教程）"
echo "  2. 开发类子项目：cd \"$TARGET\" && ./init-project.sh"
echo "  3. 调研类子项目：cd \"$TARGET\" && ./init-research.sh（首次运行会自动创建 research/）"
echo "  4. 复用到别处：把 $(basename -- "$SELF") 复制到新根目录再运行（可先 --dry-run 看计划）"
