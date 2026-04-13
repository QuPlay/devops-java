# Flink DWS 作业变更与数据修复规范

适用范围：StreamPark 上所有 `dwd_*` / `dws_*` 作业。

核心原则：**源端位点（consumer-id / offset）、聚合算子 state、Sink 表数据** 三者必须同步。错配就会出现重复统计或少算。

---

## 1. 变更分级

### L0 · 纯 SELECT 逻辑调整
改 `WHERE` 过滤条件、替换字段公式、修改 JOIN ON 条件（不影响算子 UID）。

**操作**：从最近 savepoint 恢复即可。

**前置校验**：
- 确认算子 UID 未变（Flink SQL 的 plan 不稳定，字段顺序改动也可能导致 UID 漂移）
- 若不确认，按 L1 处理

### L1 · 拓扑变更
新增 / 删除 INSERT、合并成 statement set、修改 GROUP BY 键、新增 UNION 分支、改 PRIMARY KEY。

**必须走"清零 + 重算"四步锁，顺序不能颠倒**：
1. **停作业** —— 用 `cancel`，不留 savepoint
2. **清 Sink 表**
   - TiDB：`TRUNCATE TABLE xxx`
   - Paimon：`CALL sys.drop_partition(...)` 或直接 drop/recreate 表
3. **清消费位点**
   - Paimon consumer：删除 consumer 元数据文件（`consumer/{consumer-id}`）
   - Kafka group：`--reset-offsets --to-earliest` 或 `--to-datetime`
4. **无状态启动** —— 不要 `--fromSavepoint`，或显式 `execution.savepoint.ignore-unclaimed-state=true`

⚠️ 漏掉任一步 = 重复统计或数据丢失。这次 dws_deposit_hourly ×2 故障就是拓扑改了但 state 未清导致。

### L2 · 局部数据修复（某日 / 某租户）
发现某一天、某个租户数据偏差，不想全量重跑。

**前提**：Sink 表 PK 能精确定位到要删的范围。

**操作**：
1. 停作业
2. `DELETE FROM sink WHERE stat_date = 'YYYY-MM-DD' [AND tenant_id = ...]`
3. 重置消费位点到该日 00:00 之前
4. **仍须无状态启动**（聚合算子 state 无法选择性清除）
5. 启动后监控追平

⚠️ L2 实质上仍退化为"清算子 state + 全量重放到当前"，只是 Sink 只清了一部分。如果历史数据量大，优先考虑 L1 全清。

---

## 2. 根本解法（让 Sink 自身幂等）

单靠 SOP 不够，流程漏做一步就出事。以下机制可让重放天然幂等：

### 2.1 所有 DWS 表必须是 Paimon primary-key 表
禁止用 append-only 表做 DWS。重放时 append-only 会直接追加，永远幂等不了。

### 2.2 Sink 必须是 UPSERT 语义
- TiDB sink：已是 upsert（基于 PK），OK
- Paimon sink：确认 `bucket` + `primary-key` 配置正确
- Kafka sink：避免用于 DWS

### 2.3 谨慎使用流式 SUM 累加
`GROUP BY ... SUM(x)` 的聚合 state 是增量累加，源端重放必然翻倍。改进方向：
- 小时级 / 日级聚合：尽量用**全量重算窗口**（`TUMBLE` + 完整时间窗口 close 后 emit）而非开放式聚合
- 或在 Paimon 上用 `merge-engine = 'aggregation'` 配合 changelog producer，把合并下推到 Sink

---

## 3. 变更前 Checklist

贴在 StreamPark 作业发布窗口旁：

```
[ ] 拓扑是否变动？（新增/删除 INSERT、改 GROUP BY、改 PK）
    → 是 = L1 四步锁，不是 = L0 / L2

[ ] Sink 表是否有 PK？
    → 否 = 先加 PK 再上线，否则永远无法幂等

[ ] 本次变更是否改动了金额 / 计数字段的口径？
    → 是 = 校验脚本同步更新，历史数据评估是否重刷

[ ] consumer-id 是否复用了已有值？
    → 复用且拓扑变了 = 必须清 consumer 元数据

[ ] 是否在业务低峰期？
    → 否 = 推迟到低峰期
```

**绝对禁止**：拓扑改完直接从 savepoint 恢复上线。

---

## 4. 故障应急 Runbook

发现数据验证告警时：

### 4.1 先定性
- 差值是**整数倍**（×2、×3）→ 重复统计，走 L1
- 差值是**负数**（少算）→ 源端数据未到位或聚合条件不匹配，查上游
- 差值**零散不规律** → 口径不一致，对比汇总 SQL 和校验 SQL 的 WHERE

### 4.2 回溯 commit
```bash
git reflog -20
git show <sha> --stat
git show <sha> -- <target-sql-file>
```
重点看最近一次**拓扑或字段口径**的改动。

### 4.3 决策树
```
数据偏差
├─ 跨多天 + 多指标 → L1 全清重算
├─ 单日 + 单指标    → L2 局部修复
└─ 口径不一致      → 改校验脚本而非重跑作业
```

---

## 5. 关联文档

- CLAUDE.md §"pre/prod 禁止执行 SQL"：生产修复必须走 DBA，本规范的清 Sink / 重置位点操作在 prod 都属于 DBA 范畴
- `MqConst.java`：MQ 拓扑变更同样适用"清队列 + 无状态启动"原则

---

## 6. 历史事故参考

**2026-04-13 · dws_deposit_hourly ×2**

- 改动：`goplay-dws-deposit.sql` 合并成 statement set，新增 `consumer.expiration-time`
- 操作：直接从 savepoint 恢复
- 结果：上游 `dwd_coin_deposit` 消费位点重置，但聚合算子 state 保留 → 2026-04-11 数据被聚合两次，deposit_count / amount / channel_fee 全部 ×2
- 教训：拓扑变更必须走 L1 四步锁
