#!/bin/bash
# ==============================================================================
# GitLab Runner 一键安装脚本
#
# 使用方式:
#   curl -fsSL https://raw.githubusercontent.com/QuPlay/devops-java/main/scripts/install-gitlab-runner.sh | bash
#
# 或下载后执行:
#   chmod +x install-gitlab-runner.sh
#   ./install-gitlab-runner.sh
# ==============================================================================

set -e

echo "=============================================="
echo "  GitLab Runner 安装脚本"
echo "=============================================="
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "[错误] Docker 未安装，请先安装 Docker"
    exit 1
fi

echo "[信息] Docker 已安装: $(docker --version)"
echo ""

# 获取用户输入
read -p "GitLab URL (例如 https://gitlab.facaitools.com): " GITLAB_URL
read -p "Runner 注册 Token: " REGISTRATION_TOKEN
read -p "Runner 描述 (默认: shared-runner): " RUNNER_DESC
RUNNER_DESC=${RUNNER_DESC:-shared-runner}
read -p "Runner Tags (默认: docker,maven): " RUNNER_TAGS
RUNNER_TAGS=${RUNNER_TAGS:-docker,maven}

echo ""
echo "[信息] 配置信息:"
echo "  - GitLab URL: $GITLAB_URL"
echo "  - 描述: $RUNNER_DESC"
echo "  - Tags: $RUNNER_TAGS"
echo ""

# 确认
read -p "确认安装? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "已取消"
    exit 0
fi

echo ""
echo "[步骤 1/4] 创建配置目录..."
sudo mkdir -p /srv/gitlab-runner/config

echo "[步骤 2/4] 启动 GitLab Runner 容器..."
docker stop gitlab-runner 2>/dev/null || true
docker rm gitlab-runner 2>/dev/null || true

docker run -d \
  --name gitlab-runner \
  --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest

echo "[步骤 3/4] 等待容器启动..."
sleep 3

echo "[步骤 4/4] 注册 Runner..."
docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL" \
  --registration-token "$REGISTRATION_TOKEN" \
  --executor "docker" \
  --docker-image "maven:3.9-eclipse-temurin-17" \
  --description "$RUNNER_DESC" \
  --tag-list "$RUNNER_TAGS" \
  --run-untagged="true" \
  --locked="false" \
  --docker-privileged \
  --docker-volumes "/cache" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock"

echo ""
echo "=============================================="
echo "  安装完成!"
echo "=============================================="
echo ""
echo "验证 Runner 状态:"
echo "  docker exec gitlab-runner gitlab-runner list"
echo ""
echo "查看日志:"
echo "  docker logs -f gitlab-runner"
echo ""
echo "现在可以去 GitLab 查看 Runner 是否在线:"
echo "  $GITLAB_URL/admin/runners"
echo ""
