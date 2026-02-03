# Git Hooks

这些 hooks 由 `DevOps-Java` 仓库统一管理。

## 安装方式

```bash
# 在项目根目录执行
../DevOps-Java/scripts/setup-hooks.sh
```

## 包含的 Hooks

| Hook | 触发时机 | 功能 |
|------|---------|------|
| `pre-commit` | `git commit` 前 | 代码格式、import、敏感信息、Claude AI 审查 |
| `pre-push` | `git push` 前 | 编译检查 |
| `commit-msg` | 提交信息写入后 | 提交信息格式校验 |

## Pre-commit 检查项

| 检查项 | 级别 | 说明 |
|--------|------|------|
| SonarLint 插件 | BLOCKER | 必须安装 IDEA SonarLint 插件 |
| 通配符 import | BLOCKER | 禁止 `import .*` |
| Debug 语句 | BLOCKER | 禁止 System.out、printStackTrace |
| 敏感信息 | BLOCKER | 禁止硬编码密码/密钥 |
| Null 检查风格 | WARNING | 建议使用 Objects.nonNull/isNull |
| TODO/FIXME | WARNING | 提示待处理项 |
| 文件大小 | WARNING | 超过 1000 行提示 |
| **Claude AI 审查** | BLOCKER | 评分 < 70 分阻止提交 |

## Claude AI 代码审查

### 评分标准 (100分制)

| 问题级别 | 扣分 | 示例 |
|---------|------|------|
| 致命 | -30/项 | 事务内调外部服务、N+1查询、SQL注入、NPE风险 |
| 严重 | -10/项 | 方法>120行、异常吞掉、资源未关闭 |
| 一般 | -5/项 | 魔法数字、缺参数校验、!= null |
| 轻微 | -2/项 | 命名不规范、缺 JavaDoc |

### 配置环境变量

```bash
# 禁用 Claude 审查 (不推荐)
export CLAUDE_REVIEW_ENABLED=false

# 调整最低分数 (默认 70)
export CLAUDE_MIN_SCORE=60

# 调整超时时间 (默认 120 秒)
export CLAUDE_TIMEOUT=180

# 调整最大审查行数 (默认 2000)
export CLAUDE_MAX_LINES=3000
```

### 前提条件

需要安装 Claude CLI:

```bash
# macOS
brew install claude

# 或 npm
npm install -g @anthropic-ai/claude-code
```

## 绕过方式

```bash
git commit --no-verify
git push --no-verify
```

⚠️ 不推荐绕过，CI Pipeline 仍会执行检查。

## 版本

当前版本: 1.1.0
