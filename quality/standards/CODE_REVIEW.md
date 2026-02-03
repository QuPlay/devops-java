# Java 代码审查标准

> **审查工具**: SonarLint (IDE) + Claude Code (架构师视角)
>
> **核心目标**: 写出 10 年后依然能维护、能理解、能扩展的代码

---

## 审查流程

```
┌─────────────────────────────────────────────────────────────────┐
│                         代码审查流程                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. 阻断项检查 (必须全部通过)                                    │
│      ├── 检测到问题 ──────────▶ ❌ 终止，必须修复后重新提交        │
│      └── 全部通过 ────────────▶ 进入评分阶段                      │
│                                                                 │
│   2. 10 分制评分                                                 │
│      ├── < 8 分 ──────────────▶ ❌ 拒绝，需要优化                │
│      ├── 8 - 9 分 ────────────▶ ⚠️ 通过，建议优化                │
│      └── ≥ 9 分 ──────────────▶ ✅ 优秀                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 一、阻断项 (Blocker) — 必须修复才能 commit

> **检测到任一阻断项，立即终止，跳过打分机制**

### 问题输出格式

```
❌ [BLOCKER] 循环内查询
   └── UserServiceImpl.java:125  for 循环内调用 selectById()
   └── OrderQueryImpl.java:89    while 循环内调用 Redis get()

❌ [BLOCKER] 缺少租户条件
   └── ReportQueryImpl.java:156  wrapper.eq() 未包含 tenantId

❌ [BLOCKER] TenantContext 未清理
   └── TaskServiceImpl.java:78   setTenantId() 后未在 finally 中 clear()
```

### 1.1 性能类阻断项

| 问题 | 检测方式 | 说明 |
|------|----------|------|
| **循环内查询** | Claude Code | 禁止 for/while 循环内查询 DB/Redis |
| **循环内更新** | Claude Code | 禁止 for/while 循环内逐条 update/insert |
| **N+1 查询** | Claude Code | 禁止关联查询产生 N+1 问题 |

**错误示例**:
```java
// ❌ UserServiceImpl.java:125 - 循环内查询
for (Long userId : userIds) {
    User user = userMapper.selectById(userId);  // BLOCKER!
}

// ✅ 正确写法
List<User> users = userMapper.selectBatchIds(userIds);
Map<Long, User> userMap = users.stream()
    .collect(Collectors.toMap(User::getId, Function.identity()));
```

### 1.2 安全类阻断项

| 问题 | 检测方式 | 说明 |
|------|----------|------|
| **缺少租户条件** | Claude Code | 查询必须带 tenantId 条件 |
| **TenantContext 未清理** | Claude Code | 必须在 finally 中调用 clear() |
| **敏感信息日志泄露** | Claude Code | 密码、完整手机号等禁止打印 |
| **SQL 注入风险** | SonarLint | 禁止字符串拼接 SQL |

**错误示例**:
```java
// ❌ ReportQueryImpl.java:156 - 缺少租户条件
wrapper.eq(Order::getUserId, userId);  // BLOCKER! 可能查到其他租户数据

// ✅ 正确写法
wrapper.eq(Order::getTenantId, TenantContext.getTenantId())
       .eq(Order::getUserId, userId);
```

```java
// ❌ TaskServiceImpl.java:78 - TenantContext 未清理
public void process() {
    TenantContext.setTenantId(tenantId);
    doSomething();  // BLOCKER! 忘记清理，线程复用会串租户
}

// ✅ 正确写法
public void process() {
    try {
        TenantContext.setTenantId(tenantId);
        doSomething();
    } finally {
        TenantContext.clear();
    }
}
```

### 1.3 异常处理类阻断项

| 问题 | 检测方式 | 说明 |
|------|----------|------|
| **空 catch 吞异常** | Claude Code | catch 块禁止为空 |
| **丢失异常链** | Claude Code | 重新抛出必须包含原始异常 cause |

**错误示例**:
```java
// ❌ PayServiceImpl.java:234 - 空 catch 吞异常
try {
    doPayment();
} catch (Exception e) {
    // BLOCKER! 吞掉异常
}

// ✅ 正确写法
try {
    doPayment();
} catch (Exception e) {
    log.error("支付失败, orderId={}", orderId, e);
    throw new BusinessException(CodeInfo.PAYMENT_ERROR, e);
}
```

### 1.4 代码规范类阻断项 (pre-commit Hook 自动检测)

| 问题 | 检测方式 | 说明 |
|------|----------|------|
| **通配符 import** | pre-commit | 禁止 `import xxx.*` |
| **调试语句** | pre-commit | 禁止 `System.out/err`、`.printStackTrace()` |
| **硬编码敏感信息** | pre-commit | 禁止硬编码 password/token/secret |
| **SonarLint Blocker** | SonarLint | Blocker/Critical 级别问题必须清零 |

### 1.5 API 兼容类阻断项

| 问题 | 检测方式 | 说明 |
|------|----------|------|
| **破坏 public API** | Claude Code | 已发布的 DTO/接口不得删除字段或改变行为 |

---

## 二、评分维度 (满分 10 分)

> **阻断项全部通过后，进行以下维度评分**

### 评分输出格式

```
┌─────────────────────────────────────────────────────────────────┐
│                     代码审查评分报告                             │
├─────────────────────────────────────────────────────────────────┤
│  阻断项检查: ✅ 通过                                             │
├─────────────────────────────────────────────────────────────────┤
│  维度              得分      扣分原因                            │
│  ─────────────────────────────────────────────────────────────  │
│  代码规范          1.1/1.5   -0.4 使用 != null (OrderQuery:89)  │
│  结构设计          1.5/1.5   无扣分                              │
│  文档注释          0.6/1.0   -0.4 缺少方法 JavaDoc (Service:45) │
│  依赖注入          0.5/0.5   无扣分                              │
│  异常处理          1.0/1.0   无扣分                              │
│  日志规范          0.8/1.0   -0.2 缺少上下文 (Query:123)        │
│  安全性            0.5/0.5   无扣分                              │
│  异步线程池        0.5/0.5   无扣分                              │
│  数据库事务        1.2/1.5   -0.3 大事务 (Service:67-120)       │
│  性能并发          0.5/0.5   无扣分                              │
│  API 设计          0.5/0.5   无扣分                              │
│  ─────────────────────────────────────────────────────────────  │
│  总分: 8.7/10                                                   │
│  结果: ⚠️ 通过 (建议优化)                                        │
└─────────────────────────────────────────────────────────────────┘
```

### 2.1 代码规范 (1.5 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| Null 判断 | 0.4 | 统一 `Objects.nonNull()` / `Objects.isNull()` |
| 注释标点 | 0.2 | JavaDoc 使用英文标点 |
| 魔法值 | 0.4 | 禁止魔法值，定义常量或枚举 |
| IDEA 检测 | 0.5 | 右上角绿色 ✅ |

```
-0.4  OrderQueryImpl.java:89     使用 != null 判断
-0.4  UserServiceImpl.java:156   魔法值 status == 1
```

### 2.2 结构设计 (1.5 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 方法行数 | 0.3 | ≤ 120 行 |
| 类文件行数 | 0.2 | ≤ 1000 行 |
| 缩进层级 | 0.2 | ≤ 3 层 |
| 方法参数 | 0.2 | ≤ 8 个 |
| 认知复杂度 | 0.3 | Cognitive Complexity ≤ 15 |
| 分层依赖 | 0.3 | 禁止跨层调用 |

```
-0.3  ReportServiceImpl.java:45-180   方法超过 120 行 (135 行)
-0.3  UserController.java:67          跨层调用 UserQueryImpl
```

### 2.3 文档注释 (1 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 类 JavaDoc | 0.3 | 每个类必须有职责说明 |
| 方法 JavaDoc | 0.4 | Service/ServiceImpl 新增方法必须有 |
| 参数/返回值 | 0.2 | `@param` / `@return` 完整 |
| 异常说明 | 0.1 | `@throws` 说明抛出条件 |

```
-0.4  UserServiceImpl.java:45     新增方法缺少 JavaDoc
-0.3  ReportQueryImpl.java        类缺少 JavaDoc 说明
```

### 2.4 依赖注入 (0.5 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 字段声明 | 0.3 | 统一 `private final XxxService xxxServiceImpl;` |
| 构造注入 | 0.2 | 使用 `@RequiredArgsConstructor`，禁止 `@Autowired` |

```
-0.2  OrderServiceImpl.java:23    使用 @Autowired 字段注入
```

### 2.5 异常处理 (1 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 统一异常类型 | 0.4 | 业务异常统一使用 `BusinessException` |
| 异常信息完整 | 0.3 | 包含上下文信息 (userId, orderId 等) |
| 分层处理 | 0.3 | Controller 层统一拦截 |

```
-0.3  PayServiceImpl.java:89      异常信息缺少 orderId 上下文
```

### 2.6 日志规范 (1 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 日志级别正确 | 0.3 | ERROR/WARN/INFO/DEBUG 使用恰当 |
| 关键操作有日志 | 0.3 | 入口、出口、异常、关键分支 |
| 脱敏处理 | 0.2 | 手机号、身份证等脱敏 |
| 上下文信息 | 0.2 | 包含 userId/orderId/traceId |

```
-0.3  OrderQueryImpl.java:123     log.info 应该用 log.error
-0.2  UserServiceImpl.java:89     日志缺少 userId 上下文
```

### 2.7 安全性 (0.5 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 输入校验 | 0.3 | 外部输入必须校验 |
| 权限校验 | 0.2 | 敏感操作校验用户权限 |

### 2.8 异步线程池 (0.5 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 异步工具 | 0.25 | 统一使用 `AsyncUtils` |
| 线程池 | 0.25 | 统一使用 `AsyncExecutorAutoConfiguration` 定义的线程池 |

```
-0.25 TaskServiceImpl.java:56     自建线程池 Executors.newFixedThreadPool()
```

### 2.9 数据库事务 (1.5 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| Lambda 查询 | 0.4 | 优先 Lambda，禁止字符串字段名 |
| 批量操作 | 0.3 | 使用 saveBatch/updateBatch |
| 索引使用 | 0.3 | 查询条件需有索引支撑 |
| 事务边界 | 0.3 | @Transactional 范围最小化 |
| 事务传播 | 0.2 | 正确使用传播级别 |

```
-0.4  ReportQueryImpl.java:78     使用字符串字段名 "created_at"
-0.3  OrderServiceImpl.java:67-120  大事务，包含非 DB 操作
```

### 2.10 性能并发 (0.5 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 并发安全 | 0.3 | 共享资源正确加锁 |
| 幂等设计 | 0.2 | 关键操作支持重试 |

```
-0.2  WalletServiceImpl.java:89   金额操作非幂等
```

### 2.11 API 设计 (0.5 分)

| 子项 | 分值 | 要求 |
|------|------|------|
| 响应格式统一 | 0.2 | 统一使用 Result<T> 封装 |
| 版本控制 | 0.15 | 破坏性变更使用新版本 /v2/xxx |
| 废弃标记 | 0.15 | 废弃字段用 @Deprecated |

---

## 三、评分汇总

| 维度 | 满分 |
|------|------|
| 代码规范 | 1.5 |
| 结构设计 | 1.5 |
| 文档注释 | 1.0 |
| 依赖注入 | 0.5 |
| 异常处理 | 1.0 |
| 日志规范 | 1.0 |
| 安全性 | 0.5 |
| 异步线程池 | 0.5 |
| 数据库事务 | 1.5 |
| 性能并发 | 0.5 |
| API 设计 | 0.5 |
| **总计** | **10.0** |

---

## 四、阻断项速查表

| 类别 | 问题 | 后果 |
|------|------|------|
| 性能 | 循环内查询 | ❌ 终止 |
| 性能 | 循环内更新 | ❌ 终止 |
| 性能 | N+1 查询 | ❌ 终止 |
| 安全 | 缺少租户条件 | ❌ 终止 |
| 安全 | TenantContext 未清理 | ❌ 终止 |
| 安全 | 敏感信息日志泄露 | ❌ 终止 |
| 安全 | SQL 注入 | ❌ 终止 |
| 异常 | 空 catch 吞异常 | ❌ 终止 |
| 异常 | 丢失异常链 | ❌ 终止 |
| 兼容 | 破坏 public API | ❌ 终止 |
| 规范 | 通配符 import | ❌ 终止 |
| 规范 | 调试语句 | ❌ 终止 |
| 规范 | 硬编码敏感信息 | ❌ 终止 |

---

## 五、Claude Code 审查指令

```
请以架构师/CTO 视角审查以下代码:

## 第一步: 阻断项检查
逐个检查以下问题，输出格式:
❌ [BLOCKER] 问题名称
   └── 文件名.java:行号  具体问题描述

检查项:
- 循环内查询/更新
- N+1 查询
- 缺少租户条件
- TenantContext 未清理
- 空 catch 吞异常
- 丢失异常链
- 敏感信息日志泄露
- 破坏 public API

如有阻断项，输出: "❌ 存在阻断项，必须修复后重新提交"
如无阻断项，继续第二步

## 第二步: 10 分制评分
输出格式:
维度              得分      扣分原因
─────────────────────────────────────
代码规范          X.X/1.5   -X.X 原因 (文件:行号)
...

总分: X.X/10
结果: ✅优秀 / ⚠️通过 / ❌拒绝

代码文件: [文件路径或代码]
```

---

## 六、常见扣分点速查

| 问题 | 扣分 | 文件:行号 格式示例 |
|------|------|-------------------|
| `!= null` | -0.4 | `OrderQuery.java:89` |
| 魔法值 | -0.4 | `UserService.java:156` |
| 无 JavaDoc | -0.3~0.7 | `ReportService.java:45` |
| `@Autowired` | -0.2 | `OrderService.java:23` |
| 字符串字段名 | -0.4 | `ReportQuery.java:78` |
| 自建线程池 | -0.25 | `TaskService.java:56` |
| 跨层依赖 | -0.3 | `UserController.java:67` |
| 日志级别不当 | -0.3 | `OrderQuery.java:123` |
| 大事务 | -0.3 | `OrderService.java:67-120` |
| 非幂等操作 | -0.2 | `WalletService.java:89` |

---

> **维护者**: DevOps Team
>
> **最后更新**: 2025-02
