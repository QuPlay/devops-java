# 代码提交自检清单

> 提交代码前，逐项确认以下检查点

---

## 阻断项 (必须全部通过，否则终止 commit)

### 性能类
- [ ] **无循环内查询** — 禁止 for/while 循环内 selectById/Redis.get
- [ ] **无循环内更新** — 禁止 for/while 循环内 updateById/insert
- [ ] **无 N+1 查询** — 关联查询使用 JOIN 或批量查询

### 安全类
- [ ] **租户条件完整** — 所有查询必须带 tenantId 条件
- [ ] **Context 已清理** — TenantContext/GameContext 在 finally 中 clear()
- [ ] **日志已脱敏** — 禁止打印密码、完整手机号、身份证
- [ ] **无 SQL 注入** — 禁止字符串拼接 SQL

### 异常处理类
- [ ] **无空 catch** — catch 块必须处理或重新抛出
- [ ] **异常链完整** — 重新抛出必须包含原始异常 cause

### 代码规范类 (pre-commit Hook 自动检测)
- [ ] **IDEA 右上角绿色 ✅** — 无红色/黄色警告
- [ ] **无 `import .*`** — 禁止通配符导入
- [ ] **无调试语句** — 无 System.out / .printStackTrace()
- [ ] **无硬编码敏感信息** — 无明文 password/token/secret

### API 兼容类
- [ ] **未破坏 public API** — 已发布的 DTO/接口字段不能删除

---

## 评分项 (影响最终得分)

### 代码规范 (1.5 分)
- [ ] **Null 判断** — 使用 `Objects.nonNull()` / `Objects.isNull()`
- [ ] **无魔法值** — 数字/字符串定义为常量或枚举
- [ ] **注释标点** — JavaDoc 使用英文标点 `()` `,` `:` `;`

### 结构设计 (1.5 分)
- [ ] **方法 ≤ 120 行**
- [ ] **类 ≤ 1000 行**
- [ ] **缩进 ≤ 3 层**
- [ ] **参数 ≤ 8 个**
- [ ] **分层正确** — Controller → Service → Query → dao/service

### 文档注释 (1 分)
- [ ] **类有 JavaDoc** — 说明职责
- [ ] **新增方法有 JavaDoc** — Service/ServiceImpl 必须
- [ ] **@param / @return 完整**

### 依赖注入 (0.5 分)
- [ ] **private final** — `private final XxxService xxxServiceImpl;`
- [ ] **构造注入** — `@RequiredArgsConstructor`，禁止 `@Autowired`

### 异常处理 (1 分)
- [ ] **统一异常类型** — 使用 `BusinessException`
- [ ] **异常信息完整** — 包含 userId/orderId 等上下文

### 日志规范 (1 分)
- [ ] **日志级别正确** — ERROR/WARN/INFO/DEBUG
- [ ] **关键操作有日志** — 入口、出口、异常
- [ ] **上下文信息** — 包含 userId/orderId

### 异步线程池 (0.5 分)
- [ ] **使用 AsyncUtils** — 统一异步工具
- [ ] **使用统一线程池** — apiAsyncExecutor/taskAsyncExecutor

### 数据库事务 (1.5 分)
- [ ] **Lambda 表达式** — `Entity::getField`，禁止 `"field_name"`
- [ ] **批量操作** — 使用 saveBatch/updateBatch
- [ ] **事务最小化** — @Transactional 范围尽量小

### 性能并发 (0.5 分)
- [ ] **并发安全** — 共享资源正确加锁
- [ ] **幂等设计** — 关键操作支持重试

### API 设计 (0.5 分)
- [ ] **响应格式统一** — 使用 Result<T>
- [ ] **废弃标记** — 废弃字段用 @Deprecated

---

## 问题输出格式示例

### 阻断项输出
```
❌ [BLOCKER] 循环内查询
   └── UserServiceImpl.java:125  for 循环内调用 selectById()

❌ [BLOCKER] 缺少租户条件
   └── ReportQueryImpl.java:156  wrapper.eq() 未包含 tenantId
```

### 扣分项输出
```
-0.4  OrderQueryImpl.java:89     使用 != null 判断
-0.4  UserServiceImpl.java:156   魔法值 status == 1
-0.3  ReportServiceImpl.java:45  新增方法缺少 JavaDoc
```

---

## 评分阈值

| 分数 | 结果 |
|------|------|
| 阻断项不通过 | ❌ 终止，必须修复 |
| < 8 分 | ❌ 拒绝，需要优化 |
| 8 - 9 分 | ⚠️ 通过，建议优化 |
| ≥ 9 分 | ✅ 优秀 |

---

> **完整标准详见**: [CODE_REVIEW.md](./CODE_REVIEW.md)
