#!/bin/bash
# ==============================================================================
# Bootstrap Hooks 初始化脚本
#
# 在项目根目录执行:
#   curl -fsSL https://raw.githubusercontent.com/QuPlay/devops-java/main/scripts/setup-bootstrap.sh | bash
#
# 功能:
#   1. 创建 .githooks/ 目录
#   2. 下载 bootstrap hooks
#   3. 配置 git hooks path
#   4. 更新 .gitignore
# ==============================================================================

set -e

echo "[DevOps] 初始化 Bootstrap Hooks..."

# 检查是否在 git 仓库中
if [ ! -d ".git" ]; then
    echo "[DevOps] 错误: 当前目录不是 git 仓库"
    exit 1
fi

# 创建 .githooks 目录
mkdir -p .githooks

# 下载 bootstrap hooks
echo "[DevOps] 下载 bootstrap hooks..."
curl -fsSL https://raw.githubusercontent.com/QuPlay/devops-java/main/quality/bootstrap/pre-commit -o .githooks/pre-commit
curl -fsSL https://raw.githubusercontent.com/QuPlay/devops-java/main/quality/bootstrap/pre-push -o .githooks/pre-push
chmod +x .githooks/pre-commit .githooks/pre-push

# 配置 git hooks path
git config core.hooksPath .githooks

# 更新 .gitignore（如果需要）
GITIGNORE_ENTRIES=".githooks/.version
.githooks/.last-sync"

if [ -f ".gitignore" ]; then
    for entry in $GITIGNORE_ENTRIES; do
        if ! grep -qF "$entry" .gitignore; then
            echo "$entry" >> .gitignore
            echo "[DevOps] 添加 $entry 到 .gitignore"
        fi
    done
else
    echo "$GITIGNORE_ENTRIES" > .gitignore
    echo "[DevOps] 创建 .gitignore"
fi

echo ""
echo "[DevOps] Bootstrap Hooks 初始化完成!"
echo ""
echo "下一步:"
echo "  1. git add .githooks/pre-commit .githooks/pre-push .gitignore"
echo "  2. git commit -m 'chore: Add git hooks bootstrap'"
echo "  3. git push"
echo ""
echo "之后所有开发者 clone 项目后，首次 commit 会自动安装完整 hooks"
