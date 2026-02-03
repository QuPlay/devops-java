# 代码产出统计

每日自动统计各开发者的代码提交量，评估是否达到高级工程师产出标准。

## 功能

- 统计昨日每位开发者的代码提交
- 计算有效代码行数（排除空行、注释、import、格式化等）
- 评估是否达到高级工程师标准
- 支持 Telegram / 企业微信 / 钉钉 群组通知

## 高级工程师标准

| 指标 | 阈值 | 说明 |
|------|------|------|
| 有效代码 | ≥ 80 行/天 | 排除空行、注释、import |
| 提交次数 | ≥ 2 次/天 | 合理拆分提交 |
| 有效代码占比 | ≥ 60% | 避免大量格式化提交 |

## 有效代码定义

以下内容**不计入**有效代码：

- 空行
- 单行注释 `//`
- 多行注释 `/* */`
- `import` 语句
- `package` 语句
- 单独的注解 `@Override`
- 单独的括号 `{` `}` `)`

## 部署方式

### 方式一：服务器 Cron（推荐）

```bash
# 1. 安装定时任务
./setup_cron.sh

# 2. 配置环境变量
sudo vim /etc/code-metrics.env

# 3. 手动测试
source /etc/code-metrics.env
python3 daily_code_stats.py
```

### 方式二：GitLab CI 定时任务

1. 在 GitLab 项目设置中添加 CI/CD Variables：
   - `GITLAB_TOKEN` (masked, protected)
   - `TELEGRAM_BOT_TOKEN` (masked, protected)
   - `TELEGRAM_CHAT_ID`

2. 在 **CI/CD > Schedules** 创建定时任务：
   - Interval: `0 18 * * *` (UTC 18:00 = 北京时间 02:00)
   - Target branch: `main`

## 环境变量

| 变量 | 必填 | 说明 |
|------|------|------|
| `GITLAB_URL` | 是 | GitLab 地址 |
| `GITLAB_TOKEN` | 是 | API Token (需要 `read_api` 权限) |
| `GITLAB_GROUP` | 是 | 统计的 Group 名称 |
| `TELEGRAM_BOT_TOKEN` | 否 | Telegram Bot Token |
| `TELEGRAM_CHAT_ID` | 否 | Telegram 群组 Chat ID |
| `WECOM_WEBHOOK` | 否 | 企业微信机器人 Webhook |
| `DINGTALK_WEBHOOK` | 否 | 钉钉机器人 Webhook |

## Telegram Bot 配置

1. 与 [@BotFather](https://t.me/BotFather) 对话创建 Bot
2. 获取 Bot Token
3. 将 Bot 添加到目标群组
4. 获取群组 Chat ID：
   ```bash
   curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
   ```
   从响应中找到 `chat.id`（群组通常是负数）

## 报告示例

```
# 代码产出日报 - 2024-01-15

> 高级工程师标准: 有效代码 >= 80 行/天, 提交 >= 2 次/天

## 开发者统计

| 状态 | 开发者 | 提交 | 新增行 | 有效行 | 有效率 | 项目 |
|------|--------|------|--------|--------|--------|------|
| ✅ | Developer A | 5 | 320 | 185 | 58% | api-service |
| ✅ | Developer B | 3 | 150 | 95 | 63% | core-module |
| ⚠️ | Developer C | 1 | 45 | 28 | 62% | task-service |

## 汇总

- 开发者: **3** 人
- 达标率: **2/3** (67%)
- 总提交: **9** 次
- 总有效代码: **308** 行
```

## 文件结构

```
scripts/metrics/
├── daily_code_stats.py   # 主脚本
├── setup_cron.sh         # Cron 安装脚本
├── .gitlab-ci.yml        # GitLab CI 配置模板
└── README.md             # 本文档
```
