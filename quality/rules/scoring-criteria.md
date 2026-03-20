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
2. Java 方法缺少 JavaDoc 注释（Controller 方法除外，已有请求映射注解自描述）
3. 中文标点符号出现在注释中
4. BigDecimal 使用 new BigDecimal(int) 而非 BigDecimal.valueOf() 或字符串构造
5. 字符串拼接替代 String.valueOf()（如 channelId + ""）
