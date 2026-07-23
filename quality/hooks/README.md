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

## 维护规范（改 hook 必读）

**改动本目录任何文件（`pre-commit` / `pre-push` / `commit-msg` / `check-preauthorize.py` 等），必须同时把 `.version` 版本号 +1。审查该类改动时，把「`.version` 是否已 +1」作为阻断项确认。**

原因：`.version` 是 hook 分发的唯一触发源。开发者执行 `mvn` 时，`quality/maven/hooks-installer.xml` 会拿本地 `.githooks/.version` 与本仓库 `quality/hooks/.version` 比对——**版本号一致就静默跳过，不会重新拷贝 hook**。改了脚本却忘记 +1，等于改动永远不会下发到任何人的机器，本地仍跑旧 hook，且毫无报错，极难排查。

- 版本号规则：`主.次.修订`，常规改动 +1 修订位（如 `1.9.40` → `1.9.41`）
- 一次改动一次 +1，不要攒着多次改动只 +1 一次
- 只改本 README 这类纯文档、不影响 hook 行为的，可不 +1（不需要下发）

## 版本

版本号以本目录的 [`.version`](./.version) 文件为准（单一真源）。请勿在别处硬编码版本号，避免漂移。
