#!/bin/bash
# ==============================================================================
# Git Hooks 安装/更新脚本
#
# 使用方式:
#   curl -fsSL https://raw.githubusercontent.com/QuPlay/devops-java/main/scripts/install-hooks.sh | bash
# ==============================================================================

DEVOPS_REPO="git@github.com:QuPlay/devops-java.git"
HOOKS_DIR=".git/hooks"
LOCAL_VERSION_FILE="$HOOKS_DIR/.version"
TEMP_DIR="/tmp/devops-java-$$"
LAST_SYNC_FILE="$HOOKS_DIR/.last-sync"

# 只在项目根目录执行（.git 是目录而非文件）
if [ ! -d ".git" ]; then
    exit 0
fi

# 检测是否在 git hook 中执行
IN_GIT_HOOK=false
if [ -n "$GIT_DIR" ] || [ -n "$GIT_INDEX_FILE" ]; then
    IN_GIT_HOOK=true
fi

# 防止多模块项目重复执行（60秒内不重复）
if [ -f "$LAST_SYNC_FILE" ]; then
    LAST_SYNC=$(cat "$LAST_SYNC_FILE" 2>/dev/null)
    NOW=$(date +%s)
    if [ -n "$LAST_SYNC" ] && [ $((NOW - LAST_SYNC)) -lt 60 ]; then
        exit 0
    fi
fi

# 获取本地版本
LOCAL_VERSION=""
[ -f "$LOCAL_VERSION_FILE" ] && LOCAL_VERSION=$(cat "$LOCAL_VERSION_FILE" 2>/dev/null | tr -d '[:space:]')

# 获取 devops-java 路径
get_devops_path() {
    if [ -d "../devops-java" ]; then
        echo "../devops-java"
    else
        rm -rf "$TEMP_DIR"
        git clone -q --depth 1 "$DEVOPS_REPO" "$TEMP_DIR" 2>/dev/null || return 1
        echo "$TEMP_DIR"
    fi
}

# 环境检测函数
check_environment() {
    echo "[DevOps] 检测开发环境..."
    local has_error=false

    if command -v python3 &> /dev/null; then
        echo "[DevOps]   ✓ python3"
    else
        echo "[DevOps]   ✗ python3 未安装 (必需)"
        has_error=true
    fi

    if command -v claude &> /dev/null; then
        echo "[DevOps]   ✓ claude CLI"
    else
        echo "[DevOps]   ✗ claude CLI 未安装"
        echo "[DevOps]     安装: npm install -g @anthropic-ai/claude-code"
        has_error=true
    fi

    local sonarlint_found=false
    [ -d ".idea/sonarlint" ] || [ -f ".idea/sonarlint.xml" ] && sonarlint_found=true
    [ -d "$HOME/Library/Application Support/JetBrains" ] && ls "$HOME/Library/Application Support/JetBrains"/*/plugins/sonarlint* >/dev/null 2>&1 && sonarlint_found=true
    [ -d "$HOME/.local/share/JetBrains" ] && ls "$HOME/.local/share/JetBrains"/*/plugins/sonarlint* >/dev/null 2>&1 && sonarlint_found=true
    [ -d "$APPDATA/JetBrains" ] && ls "$APPDATA/JetBrains"/*/plugins/sonarlint* >/dev/null 2>&1 && sonarlint_found=true

    if [ "$sonarlint_found" = true ]; then
        echo "[DevOps]   ✓ SonarQube for IDE"
    else
        echo "[DevOps]   ✗ SonarQube for IDE 未安装"
        echo "[DevOps]     安装: IDEA → Settings → Plugins → 搜索 'SonarQube for IDE'"
    fi

    if [ "$has_error" = true ]; then
        echo "[DevOps] ⚠ 请安装缺失的工具以启用完整功能"
    fi
}

# 如果本地没有 hooks，直接安装
if [ -z "$LOCAL_VERSION" ]; then
    echo "[DevOps] Git Hooks 未安装，正在安装..."
    DEVOPS_PATH=$(get_devops_path) || { echo "[DevOps] 警告: 无法获取 devops-java"; exit 0; }

    mkdir -p "$HOOKS_DIR"
    cp "$DEVOPS_PATH/quality/hooks/"* "$HOOKS_DIR/" 2>/dev/null || true
    cp "$DEVOPS_PATH/quality/hooks/".* "$HOOKS_DIR/" 2>/dev/null || true
    chmod +x "$HOOKS_DIR"/* 2>/dev/null || true

    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    NEW_VERSION=$(cat "$HOOKS_DIR/.version" 2>/dev/null | tr -d '[:space:]')
    echo "[DevOps] Git Hooks 安装完成 (v${NEW_VERSION})"
    date +%s > "$LAST_SYNC_FILE"
    check_environment

    # 如果从 git hook 中安装，返回特殊退出码 100，通知 bootstrap 重新执行
    if [ "$IN_GIT_HOOK" = true ]; then
        exit 100
    fi
    exit 0
fi

# 如果在 git hook 中执行且 hooks 已安装，跳过更新（防止自我更新导致执行错误）
if [ "$IN_GIT_HOOK" = true ]; then
    exit 0
fi

# 检查是否需要更新（比较版本）
DEVOPS_PATH=$(get_devops_path) || { date +%s > "$LAST_SYNC_FILE"; exit 0; }
REMOTE_VERSION=$(cat "$DEVOPS_PATH/quality/hooks/.version" 2>/dev/null | tr -d '[:space:]')

if [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
    echo "[DevOps] Git Hooks 更新: v${LOCAL_VERSION} -> v${REMOTE_VERSION}"
    cp "$DEVOPS_PATH/quality/hooks/"* "$HOOKS_DIR/" 2>/dev/null || true
    cp "$DEVOPS_PATH/quality/hooks/".* "$HOOKS_DIR/" 2>/dev/null || true
    chmod +x "$HOOKS_DIR"/* 2>/dev/null || true
    echo "[DevOps] Git Hooks 更新完成"
fi

[ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
date +%s > "$LAST_SYNC_FILE"
exit 0
