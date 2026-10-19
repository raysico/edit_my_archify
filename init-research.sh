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
