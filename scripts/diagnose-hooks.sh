#!/bin/bash
# ==============================================================================
# DevOps Git Hooks 诊断脚本
#
# Usage: bash diagnose-hooks.sh
# ==============================================================================

echo "========== DevOps Git Hooks 诊断 =========="
echo ""
echo "[1] 系统信息"
echo "  OS: $OSTYPE"
echo "  Shell: $SHELL"
echo "  PWD: $(pwd)"
echo ""
echo "[2] Git 配置"
echo "  core.hooksPath: $(git config core.hooksPath || echo '未设置')"
echo "  core.autocrlf: $(git config core.autocrlf || echo '未设置')"
echo ""
echo "[3] .githooks 目录"
ls -la .githooks/ 2>/dev/null || echo "  目录不存在!"
echo ""
echo "[4] pre-commit 文件检查"
if [ -f ".githooks/pre-commit" ]; then
    echo "  文件存在: YES"
    echo "  文件权限: $(ls -la .githooks/pre-commit | awk '{print $1}')"
    echo "  文件大小: $(wc -c < .githooks/pre-commit) bytes"
    echo "  首行内容: $(head -1 .githooks/pre-commit)"
    echo "  版本文件: $(cat .githooks/.version 2>/dev/null || echo '无')"
else
    echo "  文件存在: NO"
fi
echo ""
echo "[5] Claude CLI"
echo "  命令路径: $(command -v claude || echo '未找到')"
echo "  版本: $(claude --version 2>/dev/null || echo '无法获取')"
echo ""
echo "[6] Node/npm"
echo "  node: $(node --version 2>/dev/null || echo '未安装')"
echo "  npm: $(npm --version 2>/dev/null || echo '未安装')"
echo "  npm prefix: $(npm config get prefix 2>/dev/null || echo '无法获取')"
echo ""
echo "[7] 手动测试 pre-commit"
echo "  尝试执行 .githooks/pre-commit ..."
if [ -x ".githooks/pre-commit" ]; then
    echo "  (文件可执行)"
else
    echo "  (文件不可执行，尝试添加权限)"
    chmod +x .githooks/pre-commit 2>/dev/null
fi
echo ""
echo "========== 诊断完成 =========="