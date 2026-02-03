#!/bin/bash
#
# 安装每日代码统计定时任务
#
# 运行时间: 北京时间每天 02:00
# Cron 表达式: 0 2 * * * (服务器需为 Asia/Shanghai 时区)
#
# 使用方法:
#   1. 设置环境变量 (建议写入 /etc/profile.d/code-metrics.sh)
#   2. 运行此脚本: ./setup_cron.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/daily_code_stats.py"
LOG_DIR="/var/log/code-metrics"
ENV_FILE="/etc/code-metrics.env"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  代码统计定时任务安装"
echo "=========================================="
echo

# 检查 Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}错误: 未找到 python3${NC}"
    exit 1
fi

# 检查依赖
echo "检查 Python 依赖..."
python3 -c "import requests" 2>/dev/null || {
    echo "安装 requests..."
    pip3 install requests
}

# 创建日志目录
echo "创建日志目录: $LOG_DIR"
sudo mkdir -p "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

# 创建环境变量配置文件模板
if [ ! -f "$ENV_FILE" ]; then
    echo "创建环境变量配置: $ENV_FILE"
    sudo tee "$ENV_FILE" > /dev/null << 'EOF'
# 代码统计配置
# 请修改以下配置

# GitLab 配置 (必填)
export GITLAB_URL="https://gitlab.example.com"
export GITLAB_TOKEN="your-gitlab-api-token"
export GITLAB_GROUP="your-group-name"

# 项目前缀过滤 (可选，逗号分隔，为空则统计所有项目)
export PROJECT_PREFIXES=""

# Telegram 通知 (可选)
export TELEGRAM_BOT_TOKEN="your-bot-token"
export TELEGRAM_CHAT_ID="-1001234567890"

# 企业微信通知 (可选)
# export WECOM_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"

# 钉钉通知 (可选)
# export DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxx"
EOF
    sudo chmod 600 "$ENV_FILE"
    echo -e "${YELLOW}请编辑 $ENV_FILE 配置 GitLab Token 和通知方式${NC}"
fi

# 创建 Cron 任务
CRON_CMD="0 2 * * * . $ENV_FILE && python3 $PYTHON_SCRIPT >> $LOG_DIR/daily_\$(date +\\%Y\\%m\\%d).log 2>&1"

echo
echo "将添加以下 Cron 任务:"
echo -e "${GREEN}$CRON_CMD${NC}"
echo

# 检查是否已存在
if crontab -l 2>/dev/null | grep -q "daily_code_stats.py"; then
    echo -e "${YELLOW}警告: Cron 任务已存在，跳过添加${NC}"
else
    read -p "确认添加? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        (crontab -l 2>/dev/null || true; echo "$CRON_CMD") | crontab -
        echo -e "${GREEN}Cron 任务已添加${NC}"
    else
        echo "已取消"
    fi
fi

echo
echo "=========================================="
echo "安装完成!"
echo
echo "后续步骤:"
echo "  1. 编辑配置: sudo vim $ENV_FILE"
echo "  2. 测试运行: . $ENV_FILE && python3 $PYTHON_SCRIPT"
echo "  3. 查看日志: tail -f $LOG_DIR/daily_*.log"
echo "  4. 查看 Cron: crontab -l"
echo "=========================================="
