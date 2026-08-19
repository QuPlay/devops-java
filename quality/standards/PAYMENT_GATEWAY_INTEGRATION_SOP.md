# 三方支付通道对接规范（表单协议）

适用范围：`gp-payment-service` 所有第三方支付渠道（代收/代付/查单/余额/回调），尤其 **form-urlencoded** 协议渠道（GXP_PAY / InruPay / Fuying 等）。新渠道对接、审查支付代码时逐条对照。

核心原则：**回调是外部驱动的资金入口——绑参、验签、幂等、金额单位任一处错都会「查不到单 / 验签失败 / 多次上分 / 金额差 100 倍」。表单渠道的坑高度集中且可复用，本手册即 GXP_PAY 实战定型的检查清单。**

---

## 1. 回调接参（红线 · 违反即回调全挂）

### R1 · 表单回调必须 `@RequestParam Map<String,String>` + `new JSONObject(params)`
```java
// ✅ 正确（FuyingPay/GxpPay 范例）
@Lock4j(keys = {"#params['merchantOrderNo']"}, acquireTimeout = 10000)
public String payInNotify(@RequestParam Map<String, String> params) {
    return xxxPay.payInNotify(new JSONObject(params));
}
// ❌ 禁止：JSONObject 非 bean、无 setter，@ModelAttribute 一个字段都绑不进 → 空对象
public String payInNotify(@ModelAttribute JSONObject dto) { ... }   // dto 恒为空 → merchantOrderNo=null → "order not exists"
```
- `@ModelAttribute TypedDTO` 能绑但历史上不完整（需 RawDataContext 兜底），且验签只覆盖 DTO 字段——**不推荐**。
- JSON body 渠道才用 `@RequestBody JSONObject`；表单渠道用 `@RequestParam Map`。

### R2 · Lock4j SpEL 对 Map/JSONObject 入参用索引语法 `#params['key']`
```java
// ✅  @Lock4j(keys = {"#params['merchantOrderNo']"})
// ❌  @Lock4j(keys = {"#params.merchantOrderNo"})   // Map 无该 getter → SpelEvaluationException EL1008E → 回调 500
```
锁在进方法体之前求值，属性语法失败会让**整个回调 500 Internal server error**（不是业务错误）。

### R3 · 验签用「原文全字段」，取业务值用 DTO
```java
public String payInNotify(JSONObject data) {           // data = 原文全字段
    XxxNotifyDto dto = data.to(XxxNotifyDto.class);     // 取业务字段
    ...
    verifySign(data, secret, dto.getSign());            // 验签对 data 全字段，不对 DTO
}
```
别把 controller 改成 typed DTO 再 `JSONObject.from(dto)` 验签——会丢上游增签的未知字段，导致合法回调被拒。

---

## 2. 签名

### R4 · 「算法对、配置 secret 也对」却签不上 → 先查运行时旧 secret 缓存
现象：标准 MD5 我方 `e9d2…` vs 上游要求 `4b19…`，而 `sp_pay_channel_account.config` 里 secret 明明正确。
- **根因优先级**：① 运行时旧 secret 缓存（PaymentCache 渠道账号缓存 / 旧 JAR）→ 清缓存/重启即恢复；② 才是算法/格式。
- **判定法**：写单测用真实 `sign()` + 真 secret 复算，若 == 上游值，则代码对、是运行时旧值。
```java
// 反例排查浪费两轮：先怀疑 secret 配错、再怀疑算法，最后才发现是缓存旧 secret。
```

---

## 3. 金额单位

### R5 · 回调 amount 是「分」，订单 coin 是「元」，校验前 `/100`
```java
// ✅ payInNotifyVerifyOrder(orderNo, fromCents(dto.getAmount()), TWO)   // 分→元再比
// ❌ payInNotifyVerifyOrder(orderNo, BigDecimal.valueOf(dto.getAmount()), TWO)  // 分比元 → 永不相等 → 回调失败/永不上分
```
- 该金额**只做一致性校验、不进账变**；账变用订单自身 `coinApply/coin`（元）。校验 /100 只是让回调过校验、触发 `payInSuccess(order)`。
- 元↔分统一用基类 `toCents(BigDecimal)` / `fromCents(long)`（`AbstractFiatPayStrategy`），勿各写 `mul/div 100`。

---

## 4. 余额查询

### R6 · 分档：merchant 档是「按币种数组」，flex 档才是单对象
```java
// GXP merchant 档 /api/open/merchant/balance/query 返回：
// {"data":[{"balance":..,"currency":"IDR"},{"currency":"PKR"..}], "success":true}
GxpPayParams.ResDataDto<List<BalanceResDto>> result = postForm(...).to(new TypeReference<>(){});
String currency = TenantContext.getCurrency();
return result.getData().stream()
        .filter(b -> currency.equals(b.getCurrency()))
        .map(BalanceResDto::getBalance).filter(Objects::nonNull)
        .findFirst().orElse(BigDecimal.ZERO);   // 缺该币种 = 无此币种余额，返 0，非异常
```
- **别拿 flex 文档（单对象）套 merchant 实现**——会把数组塞进单对象 → balance 全 null。
- 同源 InruPay 是范例；余额返回原始值（是否 /100 是两家共同的单位约定，要改一起改）。

---

## 5. 幂等与资金安全

- 回调 `@Lock4j(merchantOrderNo)` 串行化并发 + `verifyOrder` 的 PENDING 守卫（已终态抛 `DUPLICATE_*`）+ controller catch 重复码应答 `success` = 三层幂等，防多次上分。
- 代付超时/网络异常**不置失败**（`payOutStatusFailure` 仅在上游明确 `success=false` 时调），留 PENDING 靠 notify/查单收敛，避免误判失败导致重复出款。
- 建单 + 推进状态在 `@Transactional`（self 代理）内原子；HTTP 出款留事务外（遵守「事务内禁副作用」）。
- 响应：回调返回**裸 `success` String**；`GlobalPayResponseBodyAdvice` 只包 `Result`，String 不被包装——GXP 才能识别成功。

---

## 6. IDR 银行码翻译（多渠道）

见 memory / 代码：共享枚举 `IdrBank`（BI 官方码身份，`payment io.enums`）+ 各渠道自持 `Map<IdrBank,String>` 覆盖表 + `IdrBank.toProviderCode(biCode, 表, provider)` 统一 fail-loud。新增 IDR 渠道复用 `IdrBank`，勿各抄 BI 码清单。IDR 代付 `accountType` 恒 `PERSONAL_BANK`、轨道由通道 `category` 定（BANK→翻绑卡码，否则 category 即钱包码），不取通道 `network`。

---

## 7. 复用基座（勿重复造轮子）

`AbstractFiatPayStrategy`：`toCents/fromCents`、`resolveClientIp`、`toJsonObject`。
`OkHttpUtils`：`toFormUrlEncoded(JSONObject)`（k=v& UTF-8 编码、跳 null）、`X_WWW_FORM_URLENCODED_UTF8`（含 charset，上游必填校验需要）。
HTTP 出口统一 `OkHttpRequestHelper.doPost`（带统一日志/成功码/类型化解析），mediaType 用 `OkHttpUtils.*` 常量。
