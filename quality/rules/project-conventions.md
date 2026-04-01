## 项目基础设施使用规范

### 1. 事务与副作用 (BLOCKER)

**规则**: 事务内禁止直接发 MQ、推送通知、调用外部接口。副作用必须在事务提交成功后执行。

**正确做法**:
```java
// 事务提交后异步执行（推荐，默认使用 gameAsyncExecutor）
TransactionCallbackUtils.doAfterCommitAsync(() -> mqSender.sendToExchange(MqConst.Exchange.BET_SLIP, message));

// 事务提交后异步执行（指定线程池）
TransactionCallbackUtils.doAfterCommitAsync("pushAsyncExecutor", () -> pushAsync.pushNotifyTip(...));

// 事务提交后同步执行
TransactionCallbackUtils.doAfterCommit(() -> cache.evict(key));
```

**反模式**:
```java
// 在 @Transactional 方法中直接发 MQ（事务回滚时消息已发出，无法撤回）
@Transactional
public void deposit(...) {
    coinDepositServiceImpl.save(deposit);
    mqSender.sendToExchange(MqConst.Exchange.DEPOSIT, message);  // WRONG
}
```

**检测信号**: `@Transactional` 方法体内出现 `mqSender`、`rabbitTemplate`、`pushAsync`、`RestTemplate`、`WebClient`

---

### 2. 异步执行 (一般)

**规则**: 使用 `AsyncUtils` 统一封装，禁止裸用 `CompletableFuture`。

**正确做法**:
```java
// 单任务异步
AsyncUtils.supplyAsync(executor, () -> queryPage());

// 两个任务并行（类型安全）
var pair = AsyncUtils.supply2Async(executor, () -> queryPage(), () -> querySummary());
PageData page = pair.first();
Summary summary = pair.second();

// 多任务并行
List<Result> results = AsyncUtils.supplyAllAsync(executor, supplier1, supplier2, supplier3);

// Fire and forget
AsyncUtils.fireAndForget(executor, () -> recordLog(...));
```

**反模式**:
```java
// 裸用 CompletableFuture，异常被静默吞掉
CompletableFuture.runAsync(() -> doSomething(), executor);

// 使用默认 ForkJoinPool（无 MDC/TTL 透传）
CompletableFuture.supplyAsync(() -> query());
```

**若必须裸用 CompletableFuture**（极少数场景），必须链 `.exceptionally()` 或 `.handle()`:
```java
CompletableFuture.runAsync(() -> doSomething(), executor)
    .exceptionally(ex -> {
        log.error("async task failed", ex);
        return null;
    });
```

**检测信号**: `CompletableFuture.runAsync` / `CompletableFuture.supplyAsync` 未链 `.exceptionally` / `.handle` / `.whenComplete`

---

### 3. 线程池 (BLOCKER)

**规则**: 禁止 `new Thread()` / `Executors.new*()`，使用项目已配置的线程池 Bean。`@Async` 必须指定线程池名称。

**可用线程池**:

| Bean 名称 | 定位 | 典型场景 |
|-----------|------|----------|
| `apiAsyncExecutor` | 低延迟快返回（小队列 200） | API 层异步查询 |
| `gameAsyncExecutor` | 中等并发通用（队列 500） | 默认选择、事务后回调 |
| `taskAsyncExecutor` | 大队列吞吐优先（队列 2000） | 批处理、报表 |
| `pushAsyncExecutor` | 超大队列（队列 10000） | MQ 消费、WebSocket、Firebase |

**正确做法**:
```java
@Resource(name = "gameAsyncExecutor")
private Executor gameAsyncExecutor;

@Async("gameAsyncExecutor")
public void asyncMethod() { ... }
```

**反模式**:
```java
new Thread(() -> doSomething()).start();       // 无监控、无 MDC/TTL
Executors.newFixedThreadPool(10);              // 无界队列，OOM 风险
@Async                                         // 使用默认线程池，无法区分场景
@Async("")                                     // 空名称，等同于默认
```

**检测信号**: `new Thread(`、`Executors.new`、`@Async` 后无括号或括号内为空

---

### 4. MQ 消息 (BLOCKER)

**规则**: 消息体实现 `MqMessage` 接口（强制 `tenantId` + `currency`），发送用 `MqSender`，消费者继承 `AbstractMqConsumer`。

**正确做法**:
```java
// 消息体
@Data @Builder
public class DepositMessage implements MqMessage {
    private Integer tenantId;
    private String currency;
    private Long uid;
    private BigDecimal coin;
    // ...
    public static DepositMessage from(CoinDeposit po) { ... }
}

// 发送
mqSender.sendToExchange(MqConst.Exchange.DEPOSIT, DepositMessage.from(deposit));

// 消费
@Component
public class DepositConsumer extends AbstractMqConsumer {
    @RabbitListener(queues = MqConst.Queue.DEPOSIT_VIP)
    public void onDeposit(DepositMessage msg, Message message) {
        consume(msg, message, "充值-VIP升级", this::handleVipUpgrade);
    }
}
```

**反模式**:
```java
// 直接用 RabbitTemplate（无幂等校验、无统一日志）
rabbitTemplate.convertAndSend(exchange, routingKey, payload);

// 消息体不含 tenantId（下游无法设置租户上下文）
Map<String, Object> msg = Map.of("uid", uid, "coin", coin);

// 消费者不继承 AbstractMqConsumer（无幂等、无上下文管理）
@RabbitListener(queues = "...")
public void onMessage(String payload) { ... }
```

**检测信号**: `rabbitTemplate.convertAndSend`、消息类未实现 `MqMessage`、`@RabbitListener` 方法未调用 `consume()`

---

### 5. ThreadLocal 上下文 (BLOCKER)

**规则**: 仅框架层代码（Filter / Interceptor / Aspect / TenantContextExecutor）允许手动 `set/clear` ThreadLocal。业务代码禁止直接操作（见 #8）。框架层 `set` 后必须在 `finally` 中 `clear`。

**允许 set/clear 的框架层位置**: 见 #8 中的"框架层上下文管理点"表格

**反模式**:
```java
// 框架层 set 后漏 clear（内存泄漏 + 租户数据串流）
TenantContext.setTenantId(tenantId);
doBusinessLogic();
// 线程归还线程池，下次请求复用到脏上下文
```

**检测信号**: `TenantContext.set` / `GameContext.set` / `LogContext.set` 后无对应 `finally { ...clear() }`

---

### 6. REST API 路径规范 (一般，仅约束新增代码)

**规则**: 新增 API 路径使用小写，复合名词用短横线（kebab-case），资源层级用斜杠分段。存量驼峰路径保持不变。

**正确做法**:
```java
@RequestMapping("/v1/channel/")

@PostMapping("/install-guide")           // 复合名词用短横线
@PostMapping("/install-guide/update")    // 资源 + 操作
@PostMapping("/batch/replace")           // 资源层级用斜杠
@PostMapping("/group/page")              // 资源 + 操作
```

**反模式**:
```java
@PostMapping("/installGuide")            // 驼峰命名
@PostMapping("/batchReplace")            // 驼峰命名
@PostMapping("/channelGroup/save")       // 驼峰命名
```

**路径设计原则**:
1. **全小写**: 不使用大写字母
2. **复合名词用短横线**: `/install-guide` 而非 `/installGuide`（kebab-case 是 RFC 3986 推荐风格）
3. **资源层级用斜杠**: `/group/page`（group 和 page 是不同层级）
4. **操作放末段**: `/group/update` 而非 `/updateGroup`
5. **RequestMapping 基路径**: Controller 级别用 `/v1/{resource}/` 格式
6. **存量不动**: 已上线的驼峰路径保持不变，避免前后端大规模同步改动

**注意**: `@PreAuthorize` 中的 perms 字符串（如 `ops_channelManage_link`）不受此规则约束，perms 用下划线分隔层级是权限系统约定

**检测信号**: `@PostMapping` / `@GetMapping` 等注解中的路径包含大写字母

---

### 7. 禁止业务代码手动管理 TenantContext (BLOCKER)

**规则**: 业务代码中禁止 `TenantContext.setTenantId()` + `TenantContext.clear()` 手动管理上下文。上下文由框架层统一管理。

**框架层上下文管理点（仅以下场景允许 set/clear）**:

| 场景 | 管理方 | 说明 |
|------|--------|------|
| HTTP 请求 | `TenantFilter` / `TokenInterceptor` | 请求开始 set，结束 clear |
| MQ 消费 | `MqContextAspect` | `@RabbitListener` 前 set，后 clear |
| 异步任务 | `AsyncUtils.wrapContext` | 捕获提交线程上下文，异步线程自动恢复/清理 |
| Job 任务 | `TenantContextHelper` / `LogAspect` | Job 方法内按租户遍历 |
| WebSocket | `UserAuthHandler` | 认证时 set，断开 clear |
| 跨租户遍历 | `TenantContextExecutor` | 每个元素 set/clear |

**反模式**:
```java
// ❌ @Async 方法内手动 set/clear（TTL 已自动传递，手动 set 只覆盖了部分字段）
@Async("gameAsyncExecutor")
public void asyncMethod(CoinBetSlips coinBetSlips) {
    TenantContext.setTenantId(coinBetSlips.getTenantId());  // 漏了 currency/timezone
    try {
        doWork();
    } finally {
        TenantContext.clear();  // 清掉了 TTL 传递的完整上下文
    }
}

// ❌ fireAndForget 内手动管理（AsyncUtils 已通过 wrapContext 处理）
AsyncUtils.fireAndForget(executor, () -> {
    TenantContext.setTenantId(tenantId);  // 多余，wrapContext 已恢复
    try { doWork(); }
    finally { TenantContext.clear(); }   // 多余，wrapContext 已清理
});

// ❌ 自定义 runInTenantContext 只设 tenantId（漏 currency/timezone）
private void runInTenantContext(Integer tenantId, Runnable task) {
    TenantContext.setTenantId(tenantId);  // 冲掉了已有的完整上下文
    try { task.run(); }
    finally { TenantContext.clear(); }
}
```

**正确做法**:
```java
// ✅ @Async 方法: 什么都不用做，TTL 自动传递
@Async("gameAsyncExecutor")
public void asyncMethod(CoinBetSlips coinBetSlips) {
    doWork();  // TenantContext 已由 TTL 从调用线程传递
}

// ✅ fireAndForget: 什么都不用做，AsyncUtils 内部 wrapContext 处理
AsyncUtils.fireAndForget(executor, () -> doWork());

// ✅ 需要切换租户时: 使用 TenantContextExecutor
tenantContextExecutor.runWithTenantId(tenantId, () -> doWork());
```

**检测信号**: 业务代码（非 Filter/Interceptor/Aspect）中出现 `TenantContext.setTenantId` + `TenantContext.clear`

---

### 8. TenantContext 新增字段必须同步 AsyncUtils (BLOCKER)

**规则**: 如果 `TenantContext` 新增字段（如 timezone 之后再加 locale 等），必须同步更新以下两处，否则异步线程会丢失新字段：

1. `AsyncUtils.wrapContext` — 捕获新字段
2. `AsyncUtils.ensureTenantContext` — TTL 传递路径和捕获值兜底路径都恢复新字段

**当前三件套**: `tenantId` + `currency` + `timezone`

**上下文丢失时行为**: 抛出 `IllegalStateException` 阻断执行 + TG 告警 + 输出提交线程调用栈（定位谁在无上下文状态下提交了异步任务）

**检测信号**: `TenantContext` 新增 `set/get` 方法后，grep `AsyncUtils.wrapContext` 确认是否同步捕获

---

### 9. @Transactional 方法内禁止使用 forEachWithTenant (BLOCKER)

**规则**: `TenantContextExecutor.forEachWithTenant` 内部 catch 异常不 re-throw，在 `@Transactional` 方法内使用会导致部分失败但事务照常提交（静默数据丢失）。

**正确做法**:
```java
// ✅ 事务内: 使用 forEachWithTenantStrict（异常直接抛出，触发回滚）
@Transactional(rollbackFor = Exception.class)
public void calcMonthBill(String date) {
    tenantContextExecutor.forEachWithTenantStrict(tenants, Tenant::getId, tenant -> {
        // 任一租户失败 → 异常抛出 → 事务回滚
    });
}

// ✅ 非事务: 使用 forEachWithTenant（单个失败不影响其他）
public void syncAllTenants() {
    tenantContextExecutor.forEachWithTenant(tenants, Tenant::getId, tenant -> {
        // 单个失败记 error 日志，继续下一个
    });
}
```

**检测信号**: `@Transactional` 方法体内出现 `forEachWithTenant`（非 Strict 版本）

---

### 10. MQ 消费者业务方法需保证原子性 (BLOCKER)

**规则**: `AbstractMqConsumer.consume()` 在业务失败时会释放幂等锁并允许重投递。因此传入的业务逻辑必须具备原子性（`@Transactional`），确保失败时完整回滚，重试时可安全重入。

**正确做法**:
```java
// ✅ 业务方法有事务保护，失败回滚后重试安全
@Transactional(rollbackFor = Exception.class)
public void handleDeposit(DepositMessage msg) {
    walletService.addBalance(msg.getUid(), msg.getCoin());
    vipService.upgrade(msg.getUid());
}
```

**反模式**:
```java
// ❌ 无事务，扣款成功但积分失败 → 重试导致重复扣款
public void handleDeposit(DepositMessage msg) {
    walletService.addBalance(msg.getUid(), msg.getCoin());
    pointService.addPoints(msg.getUid(), msg.getCoin()); // 异常 → release → 重投递 → 再次 addBalance
}
```

**检测信号**: `consume()` 的 lambda 内调用的方法涉及多个写操作但缺少 `@Transactional`

---

### 11. MqMessage.getIdempotentKey() 必须实现 (BLOCKER)

**规则**: 所有 `MqMessage` 实现类必须显式实现 `getIdempotentKey()` 方法（接口已去除 default）。忘记实现会编译报错。

**设计约定**:
- key 中**不包含** tenantId / currency（`MqSender` 通过 `TextUtils.buildKey` 自动追加租户前缀）
- 有确定性业务主键的消息返回业务 key（同一笔业务只处理一次）
- 无确定性主键的消息（事件通知等）返回 null（由 Snowflake 保证唯一）

```java
// ✅ 有业务主键
@Override
public String getIdempotentKey() {
    return uid + "|" + providerCode + "|" + roundId + "|" + orderNoBet;
}

// ✅ 无确定性主键（事件通知）
@Override
public String getIdempotentKey() {
    return null;
}
```

**检测信号**: 新增 `implements MqMessage` 的类未实现 `getIdempotentKey()`（编译失败）

---

### 12. SecurityContext 需手动传递 (一般，仅 merchant-service)

**规则**: Spring Security 的 `SecurityContextHolder` 不走 TTL，异步线程需手动捕获和恢复。

**正确做法**:
```java
final SecurityContext securityContext = SecurityContextHolder.getContext();
AsyncUtils.fireAndForget(executor, () -> {
    SecurityContextHolder.setContext(securityContext);
    try {
        doWork();  // TenantContext 由 wrapContext 自动管理
    } finally {
        SecurityContextHolder.clearContext();  // 只清 Security，不清 Tenant
    }
});
```

**检测信号**: merchant-service 的异步方法中使用 `SecurityUtils.getStoreUserId()` 但未传递 SecurityContext

---

### 13. 跨租户查询 — 禁止 save-switch-restore 模式 (BLOCKER)

**规则**: `TenantIgnoreContext.executeIgnoringTenant()` 绕过租户隔离，影响数据安全，**禁止擅自使用，必须征得 David 确认（TG @JackDv88818）**。确认通过后，使用 `TenantIgnoreContext` + 显式 `tenantId` 条件，禁止"保存原始值 → 切换 → 恢复"模式。save-switch-restore 在异常时丢失原始上下文，且对调用方有隐式副作用。

**正确做法**:
```java
// 绕过租户拦截器，显式传 tenantId 条件（编译安全 + 无副作用）
var rates = TenantIgnoreContext.executeIgnoringTenant(() ->
        tenantRateService.lambdaQuery()
                .eq(TenantRate::getTenantId, targetTenantId)
                .list());
```

**反模式**:
```java
// save-switch-restore: 异常时原始上下文丢失，调用方无感知
Integer original = TenantContext.getTenantId();
TenantContext.setTenantId(otherTenantId);
try {
    var result = tenantRateService.lambdaQuery().list();
} finally {
    if (Objects.nonNull(original)) TenantContext.setTenantId(original);
    else TenantContext.clear();
}
```

**检测信号**: 同一方法中出现 `TenantContext.getTenantId()` 赋值给局部变量 + 随后 `TenantContext.setTenantId(另一个值)`

---

### 14. @Lock4j SpEL 表达式必须引用存在的参数 (BLOCKER)

**规则**: `@Lock4j(keys = {"#param"})` 中的 SpEL 表达式必须引用方法签名中实际存在的参数。引用不存在的参数时 SpEL 解析为 null，所有调用共享同一把锁或锁完全失效。

**正确做法**:
```java
// 方法参数存在 tenantId — 直接引用
@Lock4j(keys = {"#tenantId"}, expire = 300000)
public void process(Integer tenantId) { ... }

// 无参方法 — 从 TenantContext 动态取值（per-tenant 锁）
@Lock4j(keys = {"T(com.great.utils.thread.TenantContext).getTenantId()"}, expire = 300000)
public void processAll() { ... }

// 无参方法 — 全局唯一锁（字面量字符串，注意单引号）
@Lock4j(keys = {"'globalJobLock'"}, expire = 300000)
public void globalJob() { ... }
```

**反模式**:
```java
// 方法签名无 tenantId 参数，#tenantId 解析为 null，锁 key 变成固定值
@Lock4j(keys = {"#tenantId"}, expire = 300000)
public void recalculateAll() { ... }
```

**检测信号**: `@Lock4j(keys` 中 `#xxx` 变量名不在方法参数列表中

---

### 15. 日期计算 — 禁止硬编码月天数 (一般)

**规则**: 月份天数必须动态计算，禁止硬编码 28/30/31。使用 `LocalDate.lengthOfMonth()` 或 `YearMonth.lengthOfMonth()`。

**正确做法**:
```java
// 方案 A: LocalDate
LocalDate monthStart = LocalDate.parse(date + "01", DateTimeFormatter.BASIC_ISO_DATE);
int lastDay = monthStart.lengthOfMonth();

// 方案 B: YearMonth
YearMonth ym = YearMonth.parse(date, DateTimeFormatter.ofPattern("yyyyMM"));
int lastDay = ym.lengthOfMonth();
```

**反模式**:
```java
// 硬编码 31，2 月和 30 天的月份数据遗漏
Integer endDate = Integer.parseInt(date + "31");
```

**检测信号**: 字符串拼接 `+ "31"` 或 `+ "28"` 或 `+ "30"` 用于日期范围计算

---

### 16. 租户上下文禁止层层传递 (BLOCKER)

**规则**: 当 `TenantContext` 已由框架层设置（HTTP 拦截器 / MqContextAspect / TenantContextHelper），业务方法禁止将 `tenantId`、`currency`、`timezone` 作为参数层层传递。需要这些值的方法应在内部直接调用 `TenantContext.getTenantId()` / `TenantContext.getCurrency()` / `TenantContext.getTimezone()`。

**为什么是 BLOCKER**: 参数传递导致调用方和被调方持有"两个来源"的同一份数据，重构时极易不一致（调用方传 A，方法内部又从 Context 取 B），且每新增一个调用层就要多传一个参数，污染整条调用链的方法签名。

**正确做法**:
```java
// ✅ 方法内部需要 currency 时直接获取
private void processReward(Long uid, BigDecimal coin) {
    String currency = TenantContext.getCurrency();
    codeRecords.setCurrency(currency);
    // ...
}

// ✅ 调用方不需要提取再传递
public void claim(User user) {
    processReward(user.getId(), reward.getCoin());
}
```

**反模式**:
```java
// ❌ 顶层提取，层层传递
public void claim(User user) {
    String currency = user.getCurrency();          // 提取
    processReward(user.getId(), reward.getCoin(), currency);  // 传递
}

private void processReward(Long uid, BigDecimal coin, String currency) {
    saveRecord(uid, coin, currency);               // 继续传递
}

private void saveRecord(Long uid, BigDecimal coin, String currency) {
    codeRecords.setCurrency(currency);             // 最终使用
}
```

**合法例外**（不应报告）:
- **MQ 消息体的 tenantId/currency 字段**: `MqMessage` 接口强制携带，用于消费端恢复上下文，属于序列化传输不是方法参数传递
- **跨租户操作**: `TenantIgnoreContext` 场景下需要显式传入目标租户的 tenantId（此时 TenantContext 的值不适用）
- **租户生命周期管理**: `TableResetConfigServiceImpl.createTenant(tenantId, currency)` 等创建/删除租户操作，调用时上下文可能未设置
- **目标币种非租户币种**: `WalletBase.convertWalletToCurrency(user, targetCurrency)` 中 currency 是转换目标，不是租户币种
- **原生 SQL (Mapper XML)**: 不走 MyBatis-Plus 自动填充，WHERE 条件中的 tenantId/currency 需要手动传入（但应从 TenantContext 取值，不从调用方参数传递）

**检测信号**:
- 方法签名包含 `String currency` / `Integer tenantId` 参数，且方法内部仅用于传递给下游或设置实体字段（可直接从 TenantContext 获取）
- 调用方提取 `user.getCurrency()` / `TenantContext.getCurrency()` / `header.getCurrency()` 后作为参数传入
- 同一文件中 3 个以上方法串联传递同一个 currency/tenantId 参数
