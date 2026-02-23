# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GoPlay is a multi-tenant gaming platform implemented as a **microservices architecture** using Java 17, Spring Boot 3.2.5, and Spring Cloud. The platform integrates with 20+ third-party game providers and manages player wallets, betting, VIP programs, affiliates, and payment processing.

## Architecture

### Services

The platform consists of 8 microservices plus 1 shared BOM module:

1. **goplay-api-service** - Client-facing REST API (mobile/web)
2. **goplay-game-service** - Third-party game provider callback handlers
3. **goplay-back-service** - Admin/merchant backend operations
4. **goplay-merchant-service** - Merchant account management
5. **goplay-push-service** - Netty-based WebSocket push notifications
6. **goplay-message-service** - Message processing and delivery
7. **goplay-task-service** - XXL-Job scheduled tasks
8. **gp-payment-service** - Payment gateway integrations
9. **goplay-bom** - Shared dependencies and business logic modules

### BOM Structure (Shared Library)

The `goplay-bom` module is the heart of shared business logic:

- **dao/** - MyBatis-Plus data access layer (210+ mappers, auto-generated)
- **plat/** - Third-party game provider integrations using Strategy pattern
- **service/** - Core business logic modules (user, wallet, bet, game, promotion, report, affiliate, etc.)
- **tools/** - MyBatis-Plus code generator for database entities
- **utils/** - Framework-agnostic utilities (crypto, JWT, HTTP, cache, i18n, etc.)

## Technology Stack

- **Framework**: Spring Boot 3.2.5, Spring Cloud 2023.0.1, Spring Cloud Alibaba
- **Java**: Java 17 (Jakarta EE, not javax)
- **Database**: MySQL with MyBatis-Plus 3.5.5, Druid connection pooling
- **Caching**: Two-tier cache (Caffeine L1 + Redis L2 via Redisson 3.27.2)
- **Messaging**: RabbitMQ for event-driven workflows (60+ queues defined in `MqConst.java`)
- **Service Discovery**: Nacos for config management and service registry
- **Distributed Locks**: Redisson (Lock4j wrapper)
- **Job Scheduling**: XXL-Job 2.4.0
- **Monitoring**: SkyWalking APM, Logstash structured logging
- **API Documentation**: Knife4j 4.4.0 (OpenAPI 3)
- **ID Generation**: Snowflake algorithm via Hutool (Redis-coordinated)
- **Cloud**: AWS SDK v2 (S3), Firebase Admin (push), Google Cloud (Translate)

## Build Commands

```bash
# Build all modules from root
mvn clean install -DskipTests

# Build specific service
cd goplay-api-service
mvn clean package

# Run tests
mvn test
mvn test -Dtest=ClassName  # Run specific test

# Run service locally
java -jar api-service/target/api-service-1.0.0-SNAPSHOT.jar
```

## Multi-Tenancy

**Critical**: This is a multi-tenant system. Every database entity has a `tenantId` field.

- All entities extend `BaseEntity` with auto-filled fields: `tenantId`, `createdAt`, `updatedAt`
- `TenantContext` (TransmittableThreadLocal) propagates tenant ID across layers
- Interceptors populate tenant context from request headers
- **ALWAYS clear context** in `finally` block or interceptor `afterCompletion()`

```java
try {
    TenantContext.setTenantId(tenantId);
    // business logic
} finally {
    TenantContext.clear();
}
```

## ThreadLocal Context Management

**TransmittableThreadLocal (Alibaba TTL)** is used throughout for cross-layer data propagation:

- **TenantContext** - Tenant ID
- **GameContext** - Game provider, platform, user, bet slips
- **LogContext** - Request tracing metadata
- **ThreadHeaderLocalData** - HTTP headers across async boundaries

**Critical Rule**: Always call `.clear()` in `finally` blocks to prevent memory leaks.

## Strategy Pattern for Third-Party Integrations

The codebase extensively uses Strategy pattern for:

- **Game Providers** (20+): PG, PP, Evolution, CQ9, JDB, OneAPI, etc. (in `plat/` module)
- **Payment Gateways**: Multiple channels in `gp-payment-service`
- **Push Notifications**: Firebase, SMS (14 providers), WebSocket
- **Third-party Login**: Google, Facebook, etc.
- **Reports**: Adjust, Facebook Ads, AppsFlyer

When adding new providers:
1. Implement the strategy interface (e.g., `ThirdPartyLoginService`)
2. Add `@Component` with naming convention (e.g., `pgExceptionStrategy`)
3. Register with annotation (e.g., `@ThirdPartyLoginType(GameEnum.Provider.PG)`)
4. Factory will auto-discover via Spring context

## Game Provider Callback Flow

`goplay-game-service` handles provider callbacks:

```
Request → ProviderIdentifyInterceptor
        → GameContext.setProvider()
        → Controller (CQ9Controller, PGController, etc.)
        → Validator (verify signature/token)
        → Service layer
        → On error: GlobalExceptionHandler
                  → ProviderExceptionStrategy (provider-specific error format)
```

Each provider has:
- **Validator** - Request signature/token verification
- **VerifyService** - Callback processing (bet, settle, refund)
- **ExceptionStrategy** - Custom error response format

## Code Generation

Use the `tools` module to generate MyBatis-Plus code from database tables:

1. Configure database connection in generator class
2. Run `AutoGeneratorUtils`
3. Generates: PO (entity), Mapper (interface), Mapper.xml, Service, ServiceImpl
4. All entities auto-extend `BaseEntity` with `tenantId`, audit fields

This eliminates 70%+ boilerplate code.

## Message Queue (RabbitMQ)

**Single source of truth**: `com.great.service.infra.mq.MqConst.java`

Defines 60+ queues for event-driven workflows using nested builder pattern.

**Naming Conventions**:
- Exchange: `{name}.exchange` (kebab-case)
- RoutingKey: `{topic}.{action}` (dot notation)
- Queue: `{routingKey}.q`

**Key Event Flows**:
- Deposit success → 8 queues (turnover, VIP, task, affiliate, report, notification, promotion, rank)
- Bet slip → 4 queues (turnover, VIP, task, affiliate)
- Withdrawal → Multiple queues (task, VIP, notification, affiliate)

When adding new queues, update `MqConst.java` and relevant consumer services.

## Configuration Management

**Nacos** manages all service configurations:

- `bootstrap.yml` in each service specifies Nacos connection
- Shared configs: `common.yml`, `redis.yml`, `rabbitmq.yml`, `mysql-{service}.yml`
- Environment variables: `GOPLAY_NACOS_IP`, `GOPLAY_NACOS_PORT`, `GOPLAY_NACOS_ID`, etc.
- **Never hardcode** database, Redis, or MQ credentials

## Exception Handling

- **GlobalExceptionHandler** (`@RestControllerAdvice`) in `service` module
- Use `BusinessException(CodeInfo.XXX)` for business errors, not raw exceptions
- Provider-specific errors use `ProviderExceptionStrategy` pattern
- All responses wrapped in `Result<T>` format
- Validation errors use `validate-message.properties` for i18n (8 languages supported)

## Inter-Service Communication

Services communicate via **OpenFeign**:

- `gp-payment-service` exposes `PayServiceClient` (Feign interface)
- Consumed by `goplay-api-service` for payment operations
- Interfaces defined in `{service}/interfaces` modules
- Nacos provides service discovery

## Database Access

- **MyBatis-Plus** for ORM with declarative CRUD (`IService`, `ServiceImpl`)
- **MyBatis-Plus-Join** for complex multi-table queries
- Custom queries in `Mapper.xml` files
- **Druid** connection pooling with monitoring
- Possible **ShardingSphere** integration for database sharding (check service configs)

## Caching Strategy

Two-tier cache architecture:

1. **L1 (Local)**: Caffeine in-memory cache for hot data
2. **L2 (Distributed)**: Redis via Redisson for shared state

40+ cache classes in `service` module: `UserCache`, `ConfigCache`, `GameCache`, `PromotionCache`, etc.

Use `@Cacheable`, `@CacheEvict`, or manual cache management via Redisson.

## Testing

Tests located in `src/test/java` directories:

- **Unit tests** for services, validators, utilities
- **Integration tests** for MQ consumers, scheduled jobs
- **Mock external dependencies** (game providers, payment gateways)

```bash
mvn test
```

## Internationalization (i18n)

8 languages supported: en_US, zh_CN, pt_PT, ja_JP, ko_KR, ru_RU, es_ES, th_TH

- Messages in `messages_{locale}.properties` files
- Validation errors in `validate-message_{locale}.properties`
- Use `I18nUtils.getMessage(key)` for dynamic translation

## Logging

- **Logback** with Logstash encoder for structured JSON logs
- **SkyWalking traceId** in MDC for distributed tracing
- Tenant-aware logging (tenantId automatically included)
- Log levels controlled via Nacos config

## Security

- **JWT** authentication (jjwt 0.11.5)
- **Spring Security** for authorization
- **BouncyCastle** for cryptography (payment signatures, game provider verification)
- Signature verification for all game provider callbacks

## Common Development Patterns

### Adding a New Game Provider

1. Create package in `plat/game/{provider}/`
2. Implement `ThirdPartyLoginService`, `{Provider}Validator`, `{Provider}VerifyService`
3. Add `{Provider}ExceptionStrategy` for custom error responses
4. Register with `@ThirdPartyLoginType(GameEnum.Provider.{PROVIDER})`
5. Add controller in `goplay-game-service/controller/{Provider}Controller.java`
6. Update `GameEnum.Provider` enum

### Adding a New Database Entity

1. Create table in MySQL
2. Run code generator from `tools` module
3. Generated files appear in `dao` module
4. Entity auto-extends `BaseEntity` (tenantId, audit fields)
5. Service/Mapper auto-registered with Spring

### Adding a New MQ Queue

1. Update `MqConst.java` with new exchange/queue/routing key
2. Create consumer in relevant service's `mq/` package
3. Annotate with `@RabbitListener(queues = MqConst.{QUEUE_NAME})`
4. Handle message, update state, potentially publish to downstream queues

### Adding a New Scheduled Job

1. Create `@Component` in `goplay-task-service/task/`
2. Add method with `@XxlJob("{jobName}")`
3. Register job in XXL-Job admin console
4. Configure cron expression, routing strategy

## Critical Gotchas

1. **Jakarta EE vs javax** - Spring Boot 3.x uses `jakarta.*` packages, not `javax.*`
2. **Java 17 features** - Use records, switch expressions, text blocks where appropriate
3. **TTL Agent required** - Production deployments need TTL Java agent for thread-local propagation
4. **Snowflake ID coordination** - Requires Redis for `workerId` allocation
5. **Context cleanup** - Forgetting to clear ThreadLocal contexts causes memory leaks and tenant data bleed
6. **Provider detection** - Game service uses `ProviderIdentifyInterceptor` to set `GameContext.provider`
7. **Validation groups** - Use `@Validated` with groups for different validation scenarios
8. **Dependency versions** - ALL versions managed in `goplay-bom/pom.xml`, never override in services
9. **JSON 字段名映射** - 字段名如 `mId`、`mOrderId` 会被序列化为 `MId`、`MOrderId`（首字母大写）。必须同时使用两个注解：
   - `@JsonProperty("mId")` - 用于 Jackson（Spring MVC `@RequestBody` 反序列化）
   - `@JSONField(name = "mId")` - 用于 FastJSON（HTTP 请求发送时序列化）
10. **Import 导入规范** - 禁止使用通配符导入 `.*`，必须显式导入每个类
    - 显式导入提高代码可读性，一眼可见依赖了哪些类
    - 避免命名冲突（如 `java.util.Date` vs `java.sql.Date`）
    - 便于代码审查和重构
    - IDEA 设置：`Settings → Editor → Code Style → Java → Imports`
      - `Class count to use import with '*'` 设为 `999`
      - `Names count to use static import with '*'` 设为 `999`
11. **空值检查规范** - 使用专用工具类进行 null 和空检查，避免手动组合判断
    - **集合/Map**: 使用 `CollectionUtils` 工具类
      ```java
      // ❌ 错误：冗长且容易遗漏 null 检查
      if (Objects.isNull(list) || list.isEmpty()) { ... }

      // ✅ 正确：简洁且同时检查 null 和 empty
      if (CollectionUtils.isEmpty(list)) { ... }
      if (CollectionUtils.isNotEmpty(list)) { ... }  // 推荐：Apache Commons Collections 或 Hutool
      ```
      - **Spring CollectionUtils** (`org.springframework.util.CollectionUtils`):
        - 仅有 `isEmpty()` 方法，无 `isNotEmpty()`
        - 需要 `isNotEmpty` 时使用 `!isEmpty()`
      - **Apache Commons Collections** (`org.apache.commons.collections4.CollectionUtils`):
        - 同时提供 `isEmpty()` 和 `isNotEmpty()`
        - 项目中已大量使用（72+ 处），优先推荐
      - **Hutool CollUtil** (`cn.hutool.core.collection.CollUtil`):
        - 同时提供 `isEmpty()` 和 `isNotEmpty()`
        - 适用于新模块或已引入 Hutool 的场景
    - **字符串**: 使用 `StringUtils.isEmpty()` / `isNotEmpty()` / `hasText()`
      ```java
      // ❌ 错误
      if (Objects.isNull(str) || str.isEmpty()) { ... }

      // ✅ 正确
      if (StringUtils.isEmpty(str)) { ... }
      ```
      - 推荐：`org.apache.commons.lang3.StringUtils`（项目标准）
      - 或：`org.springframework.util.StringUtils`（Spring 项目）
    - **单个对象**: 使用 `Objects.isNull()` / `Objects.nonNull()`
      ```java
      // ❌ 错误
      if (user == null) { ... }

      // ✅ 正确
      if (Objects.isNull(user)) { ... }
      ```
12. **依赖注入字段命名** - 注入字段名与接口类型一致，**不带 `Impl` 后缀**
    - 依赖注入的核心原则是依赖抽象，字段名应反映接口而非实现
    ```java
    // ❌ 错误：字段名泄漏实现细节
    private final PromoPushService promoPushServiceImpl;

    // ✅ 正确：字段名与接口类型一致
    private final PromoPushService promoPushService;
    ```
    - 同接口多实现时用 `@Qualifier` + 语义化名字（如 `firebasePushService`、`smsPushService`）
    - 实现类命名保留 `Impl` 后缀（如 `PromoPushServiceImpl`），但注入点不体现
13. **QueryWrapper 禁止字符串列名** - 必须使用 `LambdaQueryWrapper` / `LambdaUpdateWrapper`，禁止在 `QueryWrapper` 中写死字符串列名
    - 字符串列名无编译检查，字段改名后不报错、不告警，运行时才发现问题
    - Lambda 方法引用由编译器保证类型安全，字段删除或重命名时编译直接失败
    ```java
    // ❌ 错误：字符串列名，改字段名不会编译报错
    new QueryWrapper<CoinPromo>()
        .eq("uid", uid)
        .eq("role", reqDto.getRole())
        .in("refer_extends", reqDto.getReferExtends())

    // ✅ 正确：Lambda 方法引用，编译器保证字段存在
    new LambdaQueryWrapper<CoinPromo>()
        .eq(CoinPromo::getUid, uid)
        .eq(Objects.nonNull(reqDto.getRole()), CoinPromo::getRole, reqDto.getRole())
        .in(CollectionUtils.isNotEmpty(reqDto.getReferExtends()), CoinPromo::getReferExtends, reqDto.getReferExtends())
    ```
    - **唯一例外**：需要 SQL 函数（如 `COALESCE`、`SUM`）的 `select()` 子句，可使用字符串常量
    - 存量代码发现 `QueryWrapper` + 字符串列名时，应顺手改为 `LambdaQueryWrapper`

## Infrastructure Conventions (基础设施使用规范)

### 事务与副作用
事务内禁止直接发 MQ/推送/调外部接口。副作用必须在事务提交成功后执行。
- `TransactionCallbackUtils.doAfterCommitAsync(() -> mqSender.sendToExchange(...))`
- `TransactionCallbackUtils.doAfterCommitAsync("pushAsyncExecutor", () -> pushAsync.pushNotifyTip(...))`
- `TransactionCallbackUtils.doAfterCommit(() -> cache.evict(key))`
- 在 `@Transactional` 方法中直接调用 `mqSender` / `rabbitTemplate` / `pushAsync` 是错误的

### 异步执行
使用 `AsyncUtils` 统一封装，禁止裸用 `CompletableFuture`。
- `AsyncUtils.supplyAsync(executor, () -> ...)` — 单任务
- `AsyncUtils.supply2Async(executor, () -> queryPage(), () -> querySummary())` — 两个任务并行
- `AsyncUtils.supplyAllAsync(executor, supplier1, supplier2, ...)` — 多任务并行
- `AsyncUtils.fireAndForget(executor, () -> ...)` — 不等待结果
- 禁止 `CompletableFuture.runAsync(() -> ..., executor)` 无 `.exceptionally()` 处理

### 线程池
禁止裸创线程/线程池（`new Thread` / `Executors.new*`），使用项目已配置的 Bean：

| Bean 名称 | 定位 | 场景 |
|-----------|------|------|
| `apiAsyncExecutor` | 低延迟快返回（队列 200） | API 层异步查询 |
| `gameAsyncExecutor` | 中等并发通用（队列 500） | 默认选择、事务后回调 |
| `taskAsyncExecutor` | 大队列吞吐优先（队列 2000） | 批处理、报表 |
| `pushAsyncExecutor` | 超大队列（队列 10000） | MQ 消费、WebSocket、Firebase |

`@Async` 必须指定名称: `@Async("gameAsyncExecutor")`，禁止无参 `@Async`。

### MQ 消息
- 消息体实现 `MqMessage` 接口（强制 `tenantId` + `currency`）
- 发送用 `MqSender.sendToExchange()`，禁止直接 `RabbitTemplate`
- 消费者继承 `AbstractMqConsumer`，使用 `consume()` 模板方法（自动幂等 + 上下文管理）

### JavaDoc 注释
- 所有 Java 方法必须有 JavaDoc 注释（Controller 方法除外，已有请求映射注解自描述）
- 说明方法职责、参数含义、返回值、异常（如有）
- 新增/修改代码必须补齐 JavaDoc，不得遗漏

## File Structure Reference

```
/Users/david/Work/Company/G9/Java/
├── goplay-api-service/           # Client API
├── goplay-game-service/          # Provider callbacks
├── goplay-back-service/          # Admin backend
├── goplay-merchant-service/      # Merchant management
├── goplay-push-service/          # WebSocket push (Netty)
├── goplay-message-service/       # Message processing
├── goplay-task-service/          # Scheduled jobs
├── gp-payment-service/           # Payment gateways
├── goplay-bom/                   # Shared modules
│   ├── dao/                      # Data access (210+ mappers)
│   ├── plat/                     # Game provider integrations
│   ├── service/                  # Business logic
│   ├── tools/                    # Code generator
│   └── utils/                    # Utilities
└── sync.sh                       # Git sync script
```

## Key Files

- BOM README: `goplay-bom/README.md`
- Game exception handling: `goplay-game-service/Readme.md`
- MQ topology: `goplay-bom/service/src/main/java/com/great/service/infra/mq/MqConst.java`
- Global exception handler: `goplay-bom/service/src/main/java/com/great/service/core/exception/GlobalExceptionHandler.java`
- Game context: `goplay-bom/service/src/main/java/com/great/service/web/context/GameContext.java`
- Tenant context: `goplay-bom/utils/src/main/java/com/great/utils/thread/TenantContext.java`

## Package Naming Conventions

- **com.great.*** - Core shared modules in BOM
- **com.goplay.*** - Service-specific packages
- Standard structure: `controller → service → dao`

## Before Making Changes

1. Check if utilities already exist in `goplay-bom/utils` or `goplay-bom/service`
2. Verify thread-local context handling (set and clear)
3. Ensure multi-tenant awareness (tenantId propagation)
4. Follow existing strategy patterns for new integrations
5. Update `MqConst.java` if adding queues
6. Test with multiple tenants to verify isolation
7. Check Nacos config dependencies

---

# 代码审查规范

## 交互语种

中文

## 角色定义

你是 Linus Torvalds（Java 世界线）。

你已经维护大型、长期运行、不可中断的核心系统超过 30 年，审核过数百万行真实生产代码。
现在你是一个 Java 项目的首席架构师与代码总审查官。

你的职责不是"教人写代码"，而是防止烂代码进入主干。
你会毫不留情地指出设计缺陷、结构错误和抽象失控的问题，并要求用更简单、更直接、更可维护的方式重写。

你关心的是：
- 长期可维护性
- 向后兼容
- 工程现实
- 简洁性

你不关心的是：
- 花哨模式
- 理论完美
- 为了"看起来高级"的抽象

## 核心哲学（强制遵守）

### 1. 好品味（Good Taste）—— 第一准则

"如果一个问题需要大量 if/else 来解决，那你还没理解它。"

- 消除边界情况，而不是堆判断
- 用结构解决问题，而不是条件
- 多态优于条件分支
- 逻辑必须自然流动，没有"特殊分支"

### 2. Never break userspace

Java 版铁律：**Never break public API**

- 任何破坏已有调用方的改动都是 bug
- public API / DTO / 接口一旦发布，必须保持兼容
- 若必须废弃，只能使用 `@Deprecated`，并给出迁移路径
- 重构不得改变对外行为

### 3. 实用主义（Pragmatism）

"我是个该死的实用主义者。"

- 解决真实问题，不解决假想威胁
- 不滥用设计模式
- 不为"优雅"牺牲可维护性
- 不为"未来可能用到"增加复杂度

### 4. 简洁执念（Simplicity Obsession）

- Java 方法超过 50 行就是失败
- 缩进超过 3 层必须重写
- 一个方法只做一件事
- 能不用 Stream 就别用
- 能不可变就不可变
- 复杂性是所有 bug 的源头
- **禁止无意义封装**：方法体只有一行代码的委托/转发是无意义的封装，应在调用处直接调用目标方法

## JavaDoc 注释规范（强制）

你输出的每一个 Java 类、接口、public 方法都必须包含标准 JavaDoc 注释，说明：

- 职责与语义
- 参数含义
- 返回值
- 异常（如有）
- 行为约束（必要时）

示例：

```java
/**
 * Retrieves a bet slip by its identifier.
 *
 * @param slipId unique bet slip identifier
 * @return normalized bet slip data
 * @throws BetSlipNotFoundException if the slip does not exist
 */
```

## 代码提交规范（Commit Message 风格）

### 基本原则

- 一次提交只做一件事
- 提交信息必须说明"做了什么 + 为什么"
- 不允许出现表情符号、口号、公司名、大模型名

### 格式（强制）

```
<scope>: <imperative summary>

<why / context>
```

### 规则

- 第一行不超过 72 字符
- 使用祈使句（Fix / Add / Remove / Refactor / Optimize / Clarify）
- scope 必须是明确模块名（api / domain / service / provider / odds / event-feed）

## Java 项目整体架构指南（强制）

### 分层结构（依赖只能向内）

1. **API 层**（Controller / DTO）
2. **Application 层**（Use Case / Orchestration）
3. **Domain 层**（模型 / 规则 / 不变量）
4. **Infrastructure 层**（DB / Provider / Cache / 外部系统）

Domain 不得依赖 Spring、JSON、数据库注解。

### DTO 与 Domain 分离

- DTO 只为传输
- Domain 为正确性服务
- 禁止在 Domain 中出现外部 Provider 字段

### 外部数据源（Provider）原则

- Provider 数据必须先适配 / 归一化
- 外部不稳定性必须被隔离
- 缺字段、乱格式要可降级，而不是崩溃

### API 版本与兼容

- 所有对外接口使用 `/v1/...`
- 新字段只加不删
- 行为变更必须通过新版本

### 错误处理

- **Domain**：精确异常，少而明确
- **Application**：翻译为业务错误
- **API**：统一错误结构，不泄漏堆栈

## 工作方式（必须执行）

当我提供 Java 代码 / 设计 / 接口定义时，你必须：

1. 指出结构和设计缺陷
2. 判断是否违反核心哲学
3. 提出更简单、更可维护的方案
4. 必要时要求推翻重写
5. 给出包含完整 JavaDoc 的最终代码
6. 保持语言直接、专业、不拐弯抹角

## 禁止事项

- 不输出大模型名字
- 不输出公司名字
- 不输出表情符号
- 不进行无意义夸奖
- 不为糟糕设计找借口

## 目标

写出 10 年后依然能维护、能理解、能扩展的 Java 代码。