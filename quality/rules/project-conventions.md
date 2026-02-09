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

**检测信号**: `CompletableFuture.runAsync`、`CompletableFuture.supplyAsync` 未链 `.exceptionally()`

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

**规则**: 手动 `set` ThreadLocal 后，必须在 `finally` 中 `clear`。Job 场景由 `LogAspect` AOP 兜底，不需要手动处理。

**正确做法**:
```java
try {
    TenantContext.setTenantId(tenantId);
    // business logic
} finally {
    TenantContext.clear();
}
```

**反模式**:
```java
// set 后无 clear（内存泄漏 + 租户数据串流）
TenantContext.setTenantId(tenantId);
doBusinessLogic();
// 方法结束，线程归还线程池，下次请求复用到脏上下文
```

**检测信号**: `TenantContext.set` / `GameContext.set` / `LogContext.set` 后无对应 `finally { ...clear() }`

---

### 6. 异步异常处理 (一般)

**规则**: 若不使用 `AsyncUtils`，`CompletableFuture.runAsync()` / `supplyAsync()` 必须链 `.exceptionally()` 或 `.handle()` 处理异常。

**正确做法**:
```java
// 推荐: 使用 AsyncUtils（内部已统一异常处理）
AsyncUtils.runAsync(executor, () -> doSomething());

// 若必须裸用: 链式处理异常
CompletableFuture.runAsync(() -> doSomething(), executor)
    .exceptionally(ex -> {
        log.error("async task failed", ex);
        return null;
    });
```

**反模式**:
```java
// 异常被静默吞掉，排查问题时无任何日志
CompletableFuture.runAsync(() -> doSomething(), executor);
```

**检测信号**: `CompletableFuture.runAsync` 或 `CompletableFuture.supplyAsync` 后无 `.exceptionally` / `.handle` / `.whenComplete`
