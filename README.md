# DevOps-Java - 代码质量治理中心

集中管理 Java 项目的代码质量规范、Git Hooks、CI/CD 模板和静态分析配置。

## 代码审查标准 (重要)

| 文档 | 说明 |
|------|------|
| **[CLAUDE.md](quality/claude/CLAUDE.md)** | Claude Code 项目指导 (单一真相源) |
| **[CODE_REVIEW.md](quality/standards/CODE_REVIEW.md)** | 10 分制代码审查标准 (完整版) |
| **[CHECKLIST.md](quality/standards/CHECKLIST.md)** | 提交前自检清单 (速查版) |

**审查工具**:
- **SonarLint (IDE)** — 自动化静态检测，要求 IDEA 右上角绿色 ✅
- **Claude Code** — 架构师/CTO 视角智能审查，评分 ≥ 8 分方可合并

## 目录结构

```
DevOps-Java/
├── quality/
│   ├── claude/             # Claude Code 项目指导 (单一真相源)
│   │   └── CLAUDE.md       # 编码规范 + 项目知识 + 审查人格
│   ├── rules/              # Pre-commit Hook 审查规则
│   │   ├── review-prompt.md         # 审查 prompt 模板
│   │   ├── project-conventions.md   # 基础设施使用规范
│   │   └── scoring-criteria.md      # 评分标准
│   ├── standards/          # 代码质量标准 (核心)
│   │   ├── CODE_REVIEW.md  # 10 分制评分标准
│   │   └── CHECKLIST.md    # 提交前自检清单
│   ├── hooks/              # Git Hooks
│   │   ├── pre-commit      # 提交前检查 (格式、import、敏感信息)
│   │   ├── pre-push        # 推送前检查 (编译)
│   │   └── commit-msg      # 提交信息格式校验
│   ├── ci/                 # GitLab CI 模板
│   │   └── java-quality.yml
│   ├── sonar/              # SonarQube 配置
│   │   └── sonar-project.properties.template
│   ├── checkstyle/         # Checkstyle 规则
│   │   └── checkstyle.xml
│   └── editorconfig/       # 编辑器配置
│       └── .editorconfig
├── scripts/
│   ├── setup-hooks.sh      # 一键安装 Git Hooks + CLAUDE.md + 审查规则
│   └── sync-claude-md.sh   # 手动同步 CLAUDE.md（通常无需使用）
├── docs/                   # 详细文档
└── README.md
```

## 评分标准速览

| 维度 | 满分 | 主要检测工具 |
|------|------|--------------|
| 代码规范 | 1.5 | SonarLint |
| 结构设计 | 1.5 | SonarLint + Claude Code |
| 文档注释 | 1.0 | Claude Code |
| 依赖注入 | 0.5 | Claude Code |
| 异常处理 | 1.0 | Claude Code |
| 日志规范 | 1.0 | Claude Code |
| 安全性 | 0.5 | Claude Code |
| 异步线程池 | 0.5 | Claude Code |
| 数据库事务 | 1.5 | Claude Code |
| 性能并发 | 0.5 | Claude Code |
| API 设计 | 0.5 | Claude Code |
| **总计** | **10.0** | |

**阈值**: `阻断项不通过` 终止 commit | `< 8 分` 拒绝 | `8-9 分` 通过 | `≥ 9 分` 优秀

> 详细标准请查看 [CODE_REVIEW.md](quality/standards/CODE_REVIEW.md)

---

## CLAUDE.md 集中管理

`quality/claude/CLAUDE.md` 是 Claude Code 的项目指导文件，包含编码规范、项目架构知识和代码审查人格定义。

**管理策略**: 在 goplay-devops 维护唯一的 master 副本，通过 hooks 自动安装/更新机制分发到各服务仓库。

```
goplay-devops (中央仓库)              各服务仓库 (自动同步)
┌───────────────────────────┐       ┌───────────────────────────┐
│ quality/claude/CLAUDE.md  │       │ CLAUDE.md                 │ ← 项目根目录
│ (master, 手动维护)         │ ────> │ ../CLAUDE.md              │ ← 工作区根目录
│                           │       │ .git/rules/*.md           │ ← 审查规则
└───────────────────────────┘       └───────────────────────────┘
         触发时机: hooks 首次安装 / hooks 版本更新 / setup-hooks.sh --force
```

**修改流程**:
1. 编辑 `quality/claude/CLAUDE.md`
2. 提交到 goplay-devops
3. 升级 `quality/hooks/.version` 版本号
4. 各服务仓库下次 `mvn compile` 或 `git commit` 时自动同步

**手动同步** (无需等待版本更新，在任意服务仓库根目录执行):
```bash
../goplay-devops/scripts/sync-claude-md.sh
```

---

## 快速开始

### 1. 安装 Git Hooks

**方式一：自动安装（推荐）**

配置了 Maven hooks-installer 的项目会在 `mvn compile` 时自动安装 hooks：

```bash
# 新同事克隆项目后，直接运行 maven 命令即可
mvn compile

# 输出：
# [DevOps] Git Hooks 未安装，正在自动安装...
# [DevOps] Git Hooks 安装完成!
```

**方式二：手动安装**

```bash
# 直接执行远程脚本
curl -sSL https://raw.githubusercontent.com/QuPlay/DevOps-Java/main/scripts/setup-hooks.sh | bash

# 或克隆后执行
git clone https://github.com/QuPlay/DevOps-Java.git
cd your-project
../DevOps-Java/scripts/setup-hooks.sh
```

### 2. 集成 CI/CD

**GitLab CI**: 复制 `quality/ci/java-quality.yml` 到项目中使用

**GitHub Actions**: 可参考 `quality/ci/` 目录下的模板配置

### 3. 配置 SonarQube

复制模板到项目根目录：

```bash
cp DevOps-Java/quality/sonar/sonar-project.properties.template your-project/sonar-project.properties
```

修改项目标识：

```properties
sonar.projectKey=your-project-key
sonar.projectName=Your Project Name
```

## 质量防线架构

```
┌─────────────────────────────────────────────────────────────┐
│  第一层: IDE 实时检查                           [开发辅助]   │
│  - SonarLint 插件 (IDEA)                                    │
│  - EditorConfig 自动格式化                                   │
│  - IDEA Inspections                                         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第二层: Git Hooks (本地)                       [快速反馈]   │
│  - pre-commit: 格式检查、import 检查、敏感信息检测           │
│  - pre-push: 编译检查                                       │
│  - commit-msg: 提交信息格式                                 │
│  ⚠️ 可通过 --no-verify 绕过，但会被 CI 拦截                  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第三层: GitLab CI Pipeline                     [强制执行]   │
│  - compile: 编译检查                                        │
│  - unit-test: 单元测试                                      │
│  - code-style: 代码规范检查 (与 pre-commit 相同规则)         │
│  - sonarqube-check: 静态分析 + Quality Gate                 │
│  - dependency-check: 依赖安全扫描                           │
│  ✅ 不可绕过，推送即触发                                     │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第四层: Merge Request 规则                     [合并门禁]   │
│  - Pipeline 必须通过                                        │
│  - Code Review 必须审批                                     │
│  - SonarQube Quality Gate 通过                              │
│  ✅ 保护分支禁止直接 push                                    │
└─────────────────────────────────────────────────────────────┘
```

**核心原则**: 本地 hooks 是"快速反馈"，CI Pipeline 是"强制执行"。

## Git Hooks 详解

### Hooks 管理策略

```
DevOps-Java (中央仓库)            各业务项目
┌─────────────────────┐          ┌─────────────────────┐
│ quality/hooks/      │          │ .githooks/          │ ← 动态安装，不提交
│   ├── pre-commit    │ ──────▶  │   ├── pre-commit    │
│   ├── pre-push      │  拉取    │   ├── pre-push      │
│   └── commit-msg    │          │   └── commit-msg    │
└─────────────────────┘          └─────────────────────┘
                                 │ .gitignore          │
                                 │   └── .githooks/    │ ← 忽略，不纳入版本控制
                                 └─────────────────────┘
```

**设计原则：**
- `.githooks/` 目录不提交到各项目仓库（已添加到 `.gitignore`）
- Hooks 统一从 `DevOps-Java` 拉取，便于版本同步
- 本地 hooks 可通过 `--no-verify` 绕过，但 CI 会强制检查
- 新同事克隆项目后执行 `setup-hooks.sh` 安装

### pre-commit

提交前自动执行，检查内容：

| 检查项 | 级别 | 说明 |
|-------|------|------|
| 通配符 import | ❌ BLOCKER | 禁止 `import xxx.*` |
| Debug 语句 | ❌ BLOCKER | 禁止 `System.out`、`printStackTrace()` |
| 敏感信息 | ❌ BLOCKER | 检测硬编码密码、Token |
| Null 检查风格 | ⚠️ WARNING | 建议使用 `Objects.nonNull()` |
| TODO/FIXME | ⚠️ WARNING | 提醒清理临时代码 |
| 文件行数 | ⚠️ WARNING | 超过 1000 行警告 |

绕过方式（不推荐）：
```bash
git commit --no-verify
```

### commit-msg

提交信息必须符合 Conventional Commits 规范：

```
<type>(<scope>): <subject>

类型(范围): 简短描述
```

**允许的类型：**
- `feat` - 新功能
- `fix` - Bug 修复
- `refactor` - 重构
- `docs` - 文档
- `test` - 测试
- `chore` - 构建/依赖
- `style` - 代码风格
- `perf` - 性能优化

**示例：**
```bash
feat(auth): add Google OAuth login
fix(wallet): correct balance calculation
refactor(user): extract validation logic
```

### pre-push

推送前检查：
- Maven 编译是否通过
- 是否存在未解决的冲突标记
- 是否直接推送到保护分支（警告）

## SonarQube Quality Gate

推荐配置 "Strict" Quality Gate：

| 指标 | 阈值 | 说明 |
|------|------|------|
| Coverage | ≥ 60% | 测试覆盖率 |
| Duplicated Lines | ≤ 3% | 重复代码比例 |
| Maintainability Rating | A | 可维护性评级 |
| Reliability Rating | A | 可靠性评级 |
| Security Rating | A | 安全性评级 |
| Blocker Issues | 0 | 阻塞级问题 |
| Critical Issues | 0 | 严重级问题 |

## IDEA 配置建议

### 1. 安装插件
- SonarLint
- CheckStyle-IDEA
- EditorConfig

### 2. Import 设置
```
Settings → Editor → Code Style → Java → Imports
  - Class count to use import with '*': 999
  - Names count to use static import with '*': 999
```

### 3. 保存时自动格式化
```
Settings → Tools → Actions on Save
  ✅ Reformat code
  ✅ Optimize imports
```

## GitLab 项目设置

### Merge Request 设置

```
Settings → Merge Requests:
  ✅ Pipelines must succeed
  ✅ All discussions must be resolved

Settings → Repository → Protected Branches:
  - main: Maintainers can push, Developers can merge
  - release/*: No one can push, Maintainers can merge
```

### Push Rules

```
Settings → Repository → Push Rules:
  Commit message regex: ^(feat|fix|refactor|docs|test|chore|style|perf|ci|build|revert)(\(.+\))?: .{5,100}$
```

## 常见问题

### Q: 如何临时跳过 hooks？
```bash
git commit --no-verify -m "emergency fix"
git push --no-verify
```
⚠️ 不推荐，CI Pipeline 仍会执行检查。

### Q: 如何更新 hooks？
重新执行安装脚本：
```bash
../DevOps-Java/scripts/setup-hooks.sh
```

### Q: 新同事克隆项目后需要做什么？
1. 执行 `setup-hooks.sh` 安装 hooks
2. 安装 IDEA 插件 (SonarLint)
3. 配置 IDEA import 规则

### Q: CI 检查失败如何处理？
1. 查看 Pipeline 日志
2. 本地运行 `mvn compile test`
3. 修复问题后重新提交

## 贡献指南

1. Fork 本仓库
2. 创建特性分支 `feat/xxx`
3. 提交变更
4. 创建 Merge Request

## 维护者

- DevOps Team
