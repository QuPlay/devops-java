## 评分标准 (100分制，起始分100分)

### 致命问题 (BLOCKER - 存在即阻止提交，不打分)
1. 事务内同步调用外部服务/推送消息（应使用 TransactionCallbackUtils.doAfterCommitAsync）
2. N+1 查询 - 循环内执行数据库查询（应批量预加载）
3. 并发安全 - 余额/库存计算存在竞态条件（应使用数据库原子操作）
4. SQL 注入 - 字符串拼接 SQL（应使用参数化查询）
5. 硬编码密码/密钥/Token
6. 关键业务路径未做 null 检查导致可能 NPE
7. 裸创线程/线程池（new Thread / Executors.new*），应使用项目配置的线程池 Bean
8. ThreadLocal 手动 set 后未在 finally 中 clear（Job 场景 LogAspect 兜底除外）
9. 直接使用 RabbitTemplate 发送消息（应使用 MqSender.sendToExchange）

### 严重问题 (BLOCKER - 存在即阻止提交，不打分)
1. 方法超过 120 行
2. 类超过 1000 行
3. 方法参数超过 8 个
4. 循环嵌套超过 3 层
5. 异常被吞掉（catch 块为空或仅打印日志）
6. 资源未关闭（流、连接等）

### 一般问题 (每项 -5 分)
1. 使用 != null 或 == null（应使用 Objects.nonNull/isNull）
2. 魔法数字/字符串未定义为常量
3. 缺少必要的参数校验
4. 方法职责不单一
5. 裸用 CompletableFuture 未链 .exceptionally()（应使用 AsyncUtils.*）
6. @Async 未指定线程池名称

### 轻微问题 (每项 -2 分)
1. 命名不规范
2. Java 方法缺少 JavaDoc 注释（Controller 方法除外，已有请求映射注解自描述）
3. 中文标点符号出现在注释中
