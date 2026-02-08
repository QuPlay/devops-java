#!/usr/bin/env python3
"""
每日代码产出统计

功能:
- 统计昨日每位开发者的代码提交量
- 计算有效代码行数 (排除空行、注释、import、格式化)
- 评估是否达到高级工程师产出标准

运行时间: 每日北京时间 02:00 (Cron: 0 2 * * *)

环境变量:
- GITLAB_URL: GitLab 地址 (必填，如 https://gitlab.example.com)
- GITLAB_TOKEN: GitLab API Token (需要 read_api 权限)
- GITLAB_GROUP: 统计的 Group 名称 (必填)
- PROJECT_PREFIXES: 项目前缀过滤，逗号分隔 (可选，如 "app-,service-")
- WECOM_WEBHOOK: 企业微信机器人 Webhook (可选)
- DINGTALK_WEBHOOK: 钉钉机器人 Webhook (可选)
- TELEGRAM_BOT_TOKEN: Telegram Bot Token (可选)
- TELEGRAM_CHAT_ID: Telegram 群组/频道 Chat ID (可选)
- REPORT_EMAIL: 报告接收邮箱，逗号分隔 (可选)
"""

import json
import os
import re
import requests
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional

# ============================================================
# 配置
# ============================================================

GITLAB_URL = os.getenv("GITLAB_URL", "")  # 必填: 如 https://gitlab.example.com
GITLAB_TOKEN = os.getenv("GITLAB_TOKEN", "")
GITLAB_GROUP = os.getenv("GITLAB_GROUP", "")  # 必填: GitLab Group 名称
# 项目前缀过滤，逗号分隔，如 "app-,service-"，为空则不过滤
_prefix_env = os.getenv("PROJECT_PREFIXES", "")
PROJECT_PREFIXES = tuple(p.strip() for p in _prefix_env.split(",") if p.strip()) if _prefix_env else ()

# 高级工程师产出标准 (每日)
SENIOR_ENGINEER_STANDARDS = {
    "min_effective_lines": 80,      # 最低有效代码行数
    "min_commits": 2,               # 最低提交次数
    "effective_ratio": 0.6,         # 有效代码占比阈值
}

# 有效代码过滤规则
EXCLUDE_PATTERNS = [
    r"^\s*$",                       # 空行
    r"^\s*//",                      # 单行注释
    r"^\s*/\*",                     # 多行注释开始
    r"^\s*\*",                      # 多行注释中间
    r"^\s*\*/",                     # 多行注释结束
    r"^\s*import\s+",               # import 语句
    r"^\s*package\s+",              # package 语句
    r"^\s*@\w+\s*$",                # 单独一行的注解
    r"^\s*@\w+\([^)]*\)\s*$",       # 带参数的注解
    r"^\s*\}\s*$",                  # 单独的 }
    r"^\s*\{\s*$",                  # 单独的 {
    r"^\s*\);?\s*$",                # 单独的 ) 或 );
    r"^\s*private\s+static\s+final\s+long\s+serialVersionUID",  # 序列化 ID
]


# ============================================================
# 数据结构
# ============================================================

@dataclass
class CommitStats:
    """单次提交统计"""
    sha: str
    message: str
    additions: int = 0
    deletions: int = 0
    effective_additions: int = 0
    files_changed: int = 0


@dataclass
class DeveloperStats:
    """开发者统计"""
    name: str
    email: str
    commits: List[CommitStats] = field(default_factory=list)
    total_additions: int = 0
    total_deletions: int = 0
    effective_additions: int = 0
    files_changed: int = 0
    projects: set = field(default_factory=set)

    @property
    def commit_count(self) -> int:
        return len(self.commits)

    @property
    def effective_ratio(self) -> float:
        if self.total_additions == 0:
            return 0.0
        return self.effective_additions / self.total_additions

    @property
    def meets_standard(self) -> Tuple[bool, List[str]]:
        """检查是否达到高级工程师标准"""
        issues = []
        standards = SENIOR_ENGINEER_STANDARDS

        if self.effective_additions < standards["min_effective_lines"]:
            issues.append(f"有效代码 {self.effective_additions} 行 < {standards['min_effective_lines']} 行")

        if self.commit_count < standards["min_commits"]:
            issues.append(f"提交次数 {self.commit_count} 次 < {standards['min_commits']} 次")

        if self.effective_ratio < standards["effective_ratio"] and self.total_additions > 50:
            issues.append(f"有效代码占比 {self.effective_ratio:.0%} < {standards['effective_ratio']:.0%}")

        return len(issues) == 0, issues


# ============================================================
# GitLab API
# ============================================================

class GitLabClient:
    """GitLab API 客户端"""

    def __init__(self, url: str, token: str):
        self.url = url.rstrip("/")
        self.headers = {"PRIVATE-TOKEN": token}

    def _get(self, endpoint: str, params: dict = None) -> dict | list:
        """发送 GET 请求"""
        url = f"{self.url}/api/v4{endpoint}"
        resp = requests.get(url, headers=self.headers, params=params, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def _get_all(self, endpoint: str, params: dict = None) -> list:
        """分页获取所有数据"""
        params = params or {}
        params["per_page"] = 100
        page = 1
        results = []

        while True:
            params["page"] = page
            data = self._get(endpoint, params)
            if not data:
                break
            results.extend(data)
            if len(data) < 100:
                break
            page += 1

        return results

    def get_group_projects(self, group: str) -> List[dict]:
        """获取 Group 下所有项目"""
        projects = self._get_all(f"/groups/{group}/projects", {"include_subgroups": "true"})
        # 按前缀过滤项目（如果设置了前缀）
        if PROJECT_PREFIXES:
            return [p for p in projects if p["name"].startswith(PROJECT_PREFIXES)]
        return projects

    def get_project_commits(self, project_id: int, since: str, until: str) -> List[dict]:
        """获取项目在指定时间段的提交"""
        return self._get_all(f"/projects/{project_id}/repository/commits", {
            "since": since,
            "until": until,
            "with_stats": "true",
        })

    def get_commit_diff(self, project_id: int, sha: str) -> List[dict]:
        """获取提交的 diff 详情"""
        return self._get(f"/projects/{project_id}/repository/commits/{sha}/diff")


# ============================================================
# 代码分析
# ============================================================

def is_effective_line(line: str) -> bool:
    """判断是否为有效代码行"""
    for pattern in EXCLUDE_PATTERNS:
        if re.match(pattern, line):
            return False
    return True


def count_effective_lines(diff_content: str) -> int:
    """统计 diff 中的有效新增行数"""
    effective = 0
    for line in diff_content.split("\n"):
        if line.startswith("+") and not line.startswith("+++"):
            actual_line = line[1:]  # 去掉 + 前缀
            if is_effective_line(actual_line):
                effective += 1
    return effective


def analyze_commit_diff(client: GitLabClient, project_id: int, sha: str) -> int:
    """分析单次提交的有效代码行数"""
    try:
        diffs = client.get_commit_diff(project_id, sha)
        effective = 0
        for diff in diffs:
            # 只统计 Java 文件
            if diff.get("new_path", "").endswith(".java"):
                effective += count_effective_lines(diff.get("diff", ""))
        return effective
    except Exception as e:
        print(f"Warning: Failed to analyze commit {sha}: {e}")
        return 0


# ============================================================
# 统计逻辑
# ============================================================

def collect_stats(client: GitLabClient, date: datetime) -> Dict[str, DeveloperStats]:
    """收集指定日期的代码统计"""
    # 北京时间当天 00:00 - 23:59:59
    since = date.strftime("%Y-%m-%dT00:00:00+08:00")
    until = date.strftime("%Y-%m-%dT23:59:59+08:00")

    print(f"统计时间范围: {since} ~ {until}")

    developers: Dict[str, DeveloperStats] = {}

    # 获取所有 项目
    projects = client.get_group_projects(GITLAB_GROUP)
    print(f"发现 {len(projects)} 个 项目")

    for project in projects:
        project_id = project["id"]
        project_name = project["name"]
        print(f"  分析项目: {project_name}")

        commits = client.get_project_commits(project_id, since, until)
        print(f"    发现 {len(commits)} 个提交")

        for commit in commits:
            author_email = commit.get("author_email", "unknown")
            author_name = commit.get("author_name", "Unknown")

            # 初始化开发者统计
            if author_email not in developers:
                developers[author_email] = DeveloperStats(
                    name=author_name,
                    email=author_email
                )

            dev = developers[author_email]
            dev.projects.add(project_name)

            # 提交统计
            stats = commit.get("stats", {})
            additions = stats.get("additions", 0)
            deletions = stats.get("deletions", 0)

            # 分析有效代码
            effective = analyze_commit_diff(client, project_id, commit["id"])

            commit_stats = CommitStats(
                sha=commit["id"][:8],
                message=commit.get("title", "")[:50],
                additions=additions,
                deletions=deletions,
                effective_additions=effective,
            )

            dev.commits.append(commit_stats)
            dev.total_additions += additions
            dev.total_deletions += deletions
            dev.effective_additions += effective

    return developers


# ============================================================
# 报告生成
# ============================================================

def generate_report(stats: Dict[str, DeveloperStats], date: datetime) -> str:
    """生成文本报告"""
    lines = [
        "=" * 60,
        f"代码产出日报 - {date.strftime('%Y-%m-%d')}",
        "=" * 60,
        "",
        f"高级工程师标准: 有效代码 >= {SENIOR_ENGINEER_STANDARDS['min_effective_lines']} 行/天, "
        f"提交 >= {SENIOR_ENGINEER_STANDARDS['min_commits']} 次/天",
        "",
        "-" * 60,
    ]

    # 按有效代码行数排序
    sorted_devs = sorted(stats.values(), key=lambda d: d.effective_additions, reverse=True)

    for dev in sorted_devs:
        meets, issues = dev.meets_standard
        status = "✅" if meets else "⚠️"

        lines.extend([
            "",
            f"{status} {dev.name} <{dev.email}>",
            f"   项目: {', '.join(dev.projects)}",
            f"   提交: {dev.commit_count} 次",
            f"   新增: {dev.total_additions} 行 (有效 {dev.effective_additions} 行, {dev.effective_ratio:.0%})",
            f"   删除: {dev.total_deletions} 行",
        ])

        if issues:
            lines.append(f"   待改进: {'; '.join(issues)}")

        # 显示提交详情
        if dev.commits:
            lines.append("   提交记录:")
            for c in dev.commits[:5]:  # 最多显示 5 条
                lines.append(f"     - [{c.sha}] {c.message} (+{c.additions}/-{c.deletions}, 有效+{c.effective_additions})")
            if len(dev.commits) > 5:
                lines.append(f"     ... 还有 {len(dev.commits) - 5} 条提交")

    # 汇总统计
    total_effective = sum(d.effective_additions for d in stats.values())
    total_commits = sum(d.commit_count for d in stats.values())
    qualified = sum(1 for d in stats.values() if d.meets_standard[0])

    lines.extend([
        "",
        "-" * 60,
        "汇总:",
        f"  开发者: {len(stats)} 人",
        f"  达标: {qualified}/{len(stats)} ({qualified/len(stats)*100:.0f}%)" if stats else "  达标: 0/0",
        f"  总提交: {total_commits} 次",
        f"  总有效代码: {total_effective} 行",
        "=" * 60,
    ])

    return "\n".join(lines)


def generate_markdown_report(stats: Dict[str, DeveloperStats], date: datetime) -> str:
    """生成 Markdown 格式报告"""
    lines = [
        f"# 代码产出日报 - {date.strftime('%Y-%m-%d')}",
        "",
        f"> 高级工程师标准: 有效代码 >= {SENIOR_ENGINEER_STANDARDS['min_effective_lines']} 行/天, "
        f"提交 >= {SENIOR_ENGINEER_STANDARDS['min_commits']} 次/天",
        "",
        "## 开发者统计",
        "",
        "| 状态 | 开发者 | 提交 | 新增行 | 有效行 | 有效率 | 项目 |",
        "|------|--------|------|--------|--------|--------|------|",
    ]

    sorted_devs = sorted(stats.values(), key=lambda d: d.effective_additions, reverse=True)

    for dev in sorted_devs:
        meets, _ = dev.meets_standard
        status = "✅" if meets else "⚠️"
        projects = ", ".join(list(dev.projects)[:3])
        if len(dev.projects) > 3:
            projects += f" +{len(dev.projects) - 3}"

        lines.append(
            f"| {status} | {dev.name} | {dev.commit_count} | "
            f"{dev.total_additions} | {dev.effective_additions} | "
            f"{dev.effective_ratio:.0%} | {projects} |"
        )

    # 汇总
    total_effective = sum(d.effective_additions for d in stats.values())
    total_commits = sum(d.commit_count for d in stats.values())
    qualified = sum(1 for d in stats.values() if d.meets_standard[0])

    lines.extend([
        "",
        "## 汇总",
        "",
        f"- 开发者: **{len(stats)}** 人",
        f"- 达标率: **{qualified}/{len(stats)}** ({qualified/len(stats)*100:.0f}%)" if stats else "- 达标率: 0/0",
        f"- 总提交: **{total_commits}** 次",
        f"- 总有效代码: **{total_effective}** 行",
    ])

    return "\n".join(lines)


# ============================================================
# 通知发送
# ============================================================

def send_wecom(webhook: str, content: str):
    """发送企业微信通知"""
    data = {
        "msgtype": "markdown",
        "markdown": {"content": content}
    }
    resp = requests.post(webhook, json=data, timeout=10)
    print(f"企业微信发送结果: {resp.status_code}")


def send_dingtalk(webhook: str, content: str):
    """发送钉钉通知"""
    data = {
        "msgtype": "markdown",
        "markdown": {
            "title": "代码产出日报",
            "text": content
        }
    }
    resp = requests.post(webhook, json=data, timeout=10)
    print(f"钉钉发送结果: {resp.status_code}")


def send_telegram(bot_token: str, chat_id: str, content: str):
    """发送 Telegram 通知"""
    # Telegram 支持 Markdown，但语法略有不同
    # 将标准 Markdown 转换为 Telegram MarkdownV2
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    # Telegram 对长消息有限制 (4096 字符)，需要分段发送
    max_len = 4000
    parts = []

    if len(content) <= max_len:
        parts = [content]
    else:
        # 按行分割，避免截断表格
        lines = content.split("\n")
        current = ""
        for line in lines:
            if len(current) + len(line) + 1 > max_len:
                parts.append(current)
                current = line
            else:
                current = current + "\n" + line if current else line
        if current:
            parts.append(current)

    for i, part in enumerate(parts):
        data = {
            "chat_id": chat_id,
            "text": part,
            "parse_mode": "Markdown",
            "disable_web_page_preview": True
        }
        resp = requests.post(url, json=data, timeout=10)
        if resp.status_code == 200:
            print(f"Telegram 发送成功 ({i+1}/{len(parts)})")
        else:
            print(f"Telegram 发送失败: {resp.status_code} - {resp.text}")


# ============================================================
# 主函数
# ============================================================

def main():
    """主入口"""
    if not GITLAB_URL:
        print("错误: 请设置环境变量 GITLAB_URL (如 https://gitlab.example.com)")
        return 1
    if not GITLAB_TOKEN:
        print("错误: 请设置环境变量 GITLAB_TOKEN")
        return 1
    if not GITLAB_GROUP:
        print("错误: 请设置环境变量 GITLAB_GROUP")
        return 1

    # 统计昨天的数据
    yesterday = datetime.now() - timedelta(days=1)

    print(f"代码产出统计")
    print(f"统计日期: {yesterday.strftime('%Y-%m-%d')}")
    print()

    try:
        client = GitLabClient(GITLAB_URL, GITLAB_TOKEN)
        stats = collect_stats(client, yesterday)

        if not stats:
            print("昨日无提交记录")
            return 0

        # 生成报告
        text_report = generate_report(stats, yesterday)
        md_report = generate_markdown_report(stats, yesterday)

        # 输出到控制台
        print(text_report)

        # 保存到文件
        report_dir = os.path.dirname(os.path.abspath(__file__))
        report_file = os.path.join(report_dir, f"report_{yesterday.strftime('%Y%m%d')}.md")
        with open(report_file, "w", encoding="utf-8") as f:
            f.write(md_report)
        print(f"\n报告已保存: {report_file}")

        # 发送通知
        wecom_webhook = os.getenv("WECOM_WEBHOOK")
        if wecom_webhook:
            send_wecom(wecom_webhook, md_report)

        dingtalk_webhook = os.getenv("DINGTALK_WEBHOOK")
        if dingtalk_webhook:
            send_dingtalk(dingtalk_webhook, md_report)

        # Telegram 通知
        telegram_token = os.getenv("TELEGRAM_BOT_TOKEN")
        telegram_chat_id = os.getenv("TELEGRAM_CHAT_ID")
        if telegram_token and telegram_chat_id:
            send_telegram(telegram_token, telegram_chat_id, md_report)

        return 0

    except Exception as e:
        print(f"统计失败: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit(main())
