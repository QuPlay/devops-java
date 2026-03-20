## 评分标准 (100分制，起始分100分)

### 致命问题 (BLOCKER - 存在即阻止提交，不打分)
1. 事务内同步调用外部服务/推送消息（应使用 TransactionCallbackUtils.doAfterCommitAsync）
2. N+1 查询 - 循环内执行数据库查询（应批量预加载）
3. 并发安全 - 余额/库存计算存在竞态条件（应使用数据库原子操作）
4. SQL 注入 - 字符串拼接 SQL（应使用参数化查询）
5. 硬编码密码/密钥/Token（bootstrap.yml 中 Nacos 连接参数禁止默认值）
6. NPE 风险判定（必须区分场景，禁止机械报告）：
   - **应报告为 critical**：用户输入/外部回调的 ID 做 getById 后未校验 null 就直接使用字段
   - **不应报告**：框架层/拦截器保证非 null 的上下文值（如 TenantContext.getTenantId()、TenantContext.getCurrency()、TenantContext.getTimezone()），这些值由拦截器在请求入口统一设置，为 null 时应该暴露 NPE 触发 TG 告警，而非静默降级
   - **不应报告**：缓存方法（*Cache.*()）内部已做 null 兜底的情况
   - **不应报告**：后台管理端传递的 ID（数据由管理员选择，记录必定存在）
   - 判断依据：追溯数据来源，可信来源不加防御，不可信来源必须防御
7. 多租户查询误报（禁止机械报告）：
   - MyBatis-Plus 租户拦截器自动追加 `tenant_id` 和 `currency` 两个字段过滤，不需要在代码中手动加 `.eq(Entity::getTenantId, ...)` 或 `.eq(Entity::getCurrency, ...)`
   - `.lambdaQuery().one()` 在租户隔离下不会返回多条记录（拦截器已保证 tenant_id + currency 维度隔离），不应报告 TooManyResultsException 风险
   - **不应报告**：查询未显式加 tenantId/currency 条件（拦截器自动处理）
   - **应报告**：使用了 `TenantIgnoreContext.setIgnore(true)` 绕过拦截器后，查询未手动加 tenantId 过滤
8. 裸创线程/线程池（new Thread / Executors.new*），应使用项目配置的线程池 Bean
9. ThreadLocal 手动 set 后未在 finally 中 clear（Job 场景 LogAspect 兜底除外）
10. 直接使用 RabbitTemplate 发送消息（应使用 MqSender.sendToExchange）
11. 无意义封装方法 - 方法体只有一行方法调用的委托/转发（ServiceImpl 对 baseMapper 的框架约定委托除外）
12. QueryWrapper 使用字符串列名（应使用 LambdaQueryWrapper，JSON 路径查询的 apply 除外）

### 严重问题 (BLOCKER - 存在即阻止提交，不打分)
1. 方法超过 120 行
2. 类超过 1000 行
3. 方法参数超过 8 个
4. 循环嵌套超过 3 层
5. 异常被吞掉（catch 块为空或仅打印日志）— 但注意：不是所有 NPE 都需要 catch，参见致命问题第 6 条
6. 资源未关闭（流、连接等）
7. PO 继承 BO/DTO（PO 字段必须和数据库表列一一对应，平铺声明）
8. BO/DTO 携带数据库注解（@TableField/@TableName）

### 一般问题 (每项 -5 分)
1. 使用 != null 或 == null（应使用 Objects.nonNull/isNull）
2. 魔法数字/字符串未定义为常量
3. 缺少必要的参数校验
4. 方法职责不单一
5. 裸用 CompletableFuture 未链 .exceptionally()（应使用 AsyncUtils.*）
6. @Async 未指定线程池名称
7. CodeInfo 错误消息含中文或句末句号（必须全英文，无句号）
8. getById null 检查未使用 Optional.ofNullable().orElseThrow() 标准写法
9. 租户信息（tenantId/currency/timezone）从参数传入而非从 TenantContext 获取

### 轻微问题 (每项 -2 分)
1. 命名不规范
2. JavaDoc 注释规则（仅针对类、接口、方法，字段不强制）：
   - **必须有 JavaDoc**：类、接口、public 方法（Controller 方法除外，已有 @Operation 自描述）
   - **不需要 JavaDoc**：PO/DTO/BO 的字段 — 已有 `@Schema(description=...)` 注解作为文档，再加 JavaDoc 是冗余。审查时不应对有 `@Schema` 的字段报缺少 JavaDoc
   - **不需要 JavaDoc**：枚举常量 — 枚举值本身语义自明（如 `NORMAL`, `BONUS`），构造参数 `desc` 已提供描述
3. 中文标点符号出现在注释中
4. BigDecimal 使用 new BigDecimal(int) 而非 BigDecimal.valueOf() 或字符串构造
5. 字符串拼接替代 String.valueOf()（如 channelId + ""）

---

## 审查误报 FAQ（持续更新）

> 以下场景在代码审查中**不应报告为问题**。每条来自真实误报案例，用于校准审查精度。
> 遇到新的误报场景时，追加到对应分类下。

### NPE 类误报
| 场景 | 为什么不应报告 |
|------|----------------|
| `TenantContext.getTenantId()` / `.getCurrency()` / `.getTimezone()` 未判空 | 拦截器在请求入口统一设置，为 null 说明拦截器有 bug，应暴露 NPE 触发 TG 告警 |
| `MyMetaObjectHandler.strictInsertFill` 中 `TenantContext.getTimezone().toString()` | 同上，框架层保证非 null |
| `channelCache.getChannel(id)` 返回值未判空（后台管理端调用） | 后台管理端传的 ID 来自下拉选择，记录必定存在 |
| `*Cache.*()` 方法返回值未判空 | 缓存内部已做 null 兜底（回源查库或返回默认值） |

### 多租户类误报
| 场景 | 为什么不应报告 |
|------|----------------|
| `.lambdaQuery().one()` 未加 tenantId/currency 条件 | MyBatis-Plus 租户拦截器自动追加 tenant_id + currency 过滤 |
| `.lambdaQuery().list()` 未加 currency 条件 | 同上，拦截器同时过滤两个字段 |
| `currencyService.lambdaQuery().one()` 报 TooManyResultsException 风险 | 租户隔离下每个 tenant_id + currency 组合唯一 |

### JavaDoc 类误报
| 场景 | 为什么不应报告 |
|------|----------------|
| PO/DTO/BO 字段缺少 JavaDoc | 已有 `@Schema(description=...)` 注解，再加 JavaDoc 是冗余 |
| 枚举常量缺少 JavaDoc | 枚举值语义自明，构造参数 `desc` 已提供描述 |
| Controller 方法缺少 JavaDoc | 已有 `@Operation(summary=..., description=...)` 自描述 |

### 异常处理类误报
| 场景 | 为什么不应报告 |
|------|----------------|
| 某处可能 NPE 但没有 try-catch | 不是所有 NPE 都需要 catch，参见致命问题第 6 条的场景区分 |
| `getById()` 后直接使用结果字段（后台管理端） | 可信来源的 ID 不需要防御性编程 |
| 建议"应该给默认值而非抛异常" | 数据不一致时应快速失败，静默降级会造成数据污染 |

### 代码风格类误报
| 场景 | 为什么不应报告 |
|------|----------------|
| `ConfigInstallGuideServiceImpl.upsert()` 只有一行 `baseMapper.upsert()` | ServiceImpl 对 Mapper 的委托是框架分层约定，不属于无意义封装 |
| JSON 字段查询使用 `QueryWrapper.apply("install_config->>'$.xxx'")` | JSON 路径查询不支持 Lambda，`apply` 是唯一选择 |
| `@TableField` 的列名和驼峰字段名能对应但仍显式声明 | PO 规范要求显式映射，不依赖隐式驼峰转换 |
| `ConstData.ZERO` / `ConstData.ONE` 用作默认值或状态判断 | 项目标准常量，不是魔法数字 |
| `StatusEnum.Status.ON.getCode()` 替代直接写 `1` | 项目统一用枚举取值，不应要求改为字面量 |
| `status` 字段用 Integer 而非自定义枚举类型 | 项目全局风格，所有表的 status 都是 Integer(0/1)，不单独改 |
| `.last(ConstSql.LIMIT_ONE)` 在 lambdaQuery 中使用 | 已知唯一记录场景（如租户配置表），LIMIT 1 是正确的 |
| `@Builder.Default` 注解在 Lombok `@Builder` 的字段上 | Lombok 必需，否则 Builder 不会使用字段默认值 |

### 架构类误报
| 场景 | 为什么不应报告 |
|------|----------------|
| "BatchReplaceReqDto 承载三种替换类型的参数，应拆分" | 前端是同一个弹窗切换 tab，合并 DTO 减少前端对接成本，`@Schema` 已标注适用场景 |
| "Channel PO 直接作为 API 返回值，应该用 ResDto" | 后台管理端查询场景，PO 全量返回是合理的，不需要额外封装一层 DTO |
| "InstallGuideConfig 放在 dao.io.bo 包下不合理" | 该类是纯 POJO（无数据库注解），用于 JSON 序列化和跨层共享，bo 包是正确位置 |
| "saveInstallGuide 里手动设 tenantId/currency/createdAt" | 使用 Mapper XML 原生 SQL（upsert），不走 MyBatis-Plus 自动填充，必须手动设值 |
| "Channel 表用 JSON 字段存储安装引导配置不规范" | 渠道级配置是"覆盖全局默认值"的语义，JSON 适合此场景，且查询已用表达式索引优化 |
| "枚举定义在 BO 而非 PO 中" | 枚举跨层共用时定义在 BO 是正确的，PO 字段引用 BO 枚举（如 `InstallGuideConfig.PopupContent`） |
