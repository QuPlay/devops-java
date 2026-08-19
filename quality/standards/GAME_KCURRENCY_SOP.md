# 厂商千位制币种(K 币种)换算规范

适用范围：`goplay-game-service` 所有第三方游戏对接。凡三方对某些币种采用"千位制"表示（1 展示单位 = N 基础单位，如 1 IDRK = 1000 IDR）的，出入口金额换算一律按本规范。

核心原则：**平台钱包始终以基础币种（IDR/VND…）记账，K 币种只是三方展示口径；换算只发生在与三方交互的出入口，且必须在 `BigDecimal`（真实金额）层做，绝不在整数线格式上做。**

共享工具：`com.great.game.currency.KCurrency`（game-plat）——**只管金额缩放**。枚举一行描述一个千位制币种 `IDR(1000L)`（常量名=基础码、`scale`=缩放因子，固定面额比例非市场汇率）。提供 `of / isKCurrency / toKAmount(出站÷scale) / fromKAmount(入站×scale)`，非 K 币种全程原样透传。**对外展示的币种码是各厂商私有约定，不在此维护**：同一 IDR，HEIBAO=`IDRK`、OneAPI=`IDR(K)`、FastSpin=`IDR`（只缩放不改码）。缩放与币种码正交，各 provider 自持 基础码→展示码 映射。

---

## 1. 红线(违反即阻断合并)

### R1 · 钱包只认基础币种,换算只在出入口
钱包/注单/账变/幂等 key/余额校验一律用基础币种金额。K 展示码与 K 金额只出现在"发给三方的报文"和"三方回调报文"里。中间业务层不得出现 K 口径金额。

### R2 · 换算必须在 BigDecimal 层,禁止缩放整数线格式
三方常用整数线格式（如 HEIBAO 1:10000 的 `Integer`）承载金额。**禁止**对该整数直接 `×scale` —— `Integer` 溢出阈值极低（HEIBAO 场景 ×1000 后约 2,147 IDRK≈$130 就溢出）。必须先按线格式还原为 `BigDecimal`（真实金额），再经 `KCurrency.fromKAmount` ×scale。出站同理：先得到基础币种 `BigDecimal`，`KCurrency.toKAmount` ÷scale 后再转线格式整数。

### R3 · 每厂商必须有单一换算收口方法,禁止散落
入站定义一个 provider 级 `toRealBase(wireAmount, currency) = KCurrency.fromKAmount(wireToReal(wireAmount), currency)`（HEIBAO 参考实现见 `HeiBaoBo.toRealBase`）。**所有** parse 点（入账 Service、主播线 Service、validator 的幂等/余额校验）一律调它。禁止各处 `wireToReal(...)` 之后自己 `×scale` —— 算法必须只有一份定义。

### R4 · 多层独立 re-parse 时,每一层都必须走收口方法
回调金额常在多层被独立 `JSON.parseObject` 重复解析（validator 校验 + Service 入账 + 主播线入账）。任一层漏调收口方法，该层就退化成"未换算"，直接金额差 scale 倍。**新增/改动任一解析回调金额的地方，必须确认走的是 `toRealBase` 而非裸 `wireToReal`。**（本规范正源于此类漏改：validator 换算了、入账 Service 没换算，IDR 注单被低估 1000 倍。）

### R5 · 出站金额缩放 + 币种码由 provider 决定(两步正交)
发给三方时：① 金额 `KCurrency.toKAmount` ÷scale（所有千位制厂商一致）；② 币种码按**本厂商约定**处理——改码的走各自 基础码→展示码 映射（HEIBAO→IDRK、OneAPI→IDR(K)），不改码的（FastSpin 保持 IDR）不映射；③ 若三方回调回传展示码且需据此反查，另做展示码→基础码反映射（如 OneAPI `ONE_API_K_CURRENCY_REVERSE`）。**金额缩放与币种码是两件事，别绑死**（曾把展示码塞进 `KCurrency`，FastSpin"缩放但不改码"即暴露该耦合）。

### R6 · 币种码精确大写匹配
`KCurrency` 按平台规范的大写 ISO 码（`TenantContext.getCurrency()` / `User.getCurrency()` 均大写）精确匹配。禁止依赖小写/别名命中。

---

## 2. 两种落地模式(按数据结构择一)

### 模式 A · validator 内改 DTO,下游透明(适用:绑定对象内可就地改的 `BigDecimal` 金额)
前提：金额是 `@RequestBody` 绑定 DTO 上可就地 `set` 的 `BigDecimal` 字段（顶层或嵌套于同一对象图皆可），**同一实例一路传到下游、无 re-parse**。
做法：validator 内把金额字段 `KCurrency.fromKAmount`（入站 ×scale 还原基础币种）写回，下游读改后的 DTO 无需再换算；出站响应余额 `KCurrency.toKAmount`（÷scale）。币种码按需（与模式 A 正交，见 R5），三种改码策略：
- **入站反查 + 改码**（OneAPI，当前唯一在用的模式 A 缩放实现）：三方传展示码 `IDR(K)`，validator 先 `dto.setCurrency(展示码→基础码)` 再缩放；出站回 `IDR(K)`。
- **不改码**（模式，暂无在用实现）：三方传基础码，仅按 `isKCurrency` 缩放金额，币种码不动——最省。
- **仅出站改码、入站忽略展示码**（模式，暂无在用实现）：钱包按 `user.getCurrency()` 记账、忽略回调展示码，只按基础币种缩放，出站发展示码。
参考：`OneApiValidatorImpl.multiplyDecimalFieldsIfNeeded` + `ONE_API_K_CURRENCY_FIELDS`（入站反查改码）。
**仅当满足"绑定对象内可就地改的 BigDecimal + 同实例下传"时可用；整数线格式 / 需 re-parse 的嵌套 JSON 字符串走模式 B。**
> 注：只需"改币种码、不缩放金额"的厂商（如 FastSpin IDR→ID2）不属于本模式——直接在出站处用 provider 自持的 `WIRE_CURRENCY` 映射即可，无需碰金额、无需 `KCurrency`。

### 模式 B · 共享换算函数,各 parse 点调用(适用:嵌套 JSON / 整数线格式)
前提：金额藏在被各层重复 parse 的嵌套 JSON 字符串里，或为整数线格式。
原因：① 改局部 parse 出的对象不影响原始报文字符串，下游 re-parse 看不到；回写报文字符串有损且是"校验方法改请求体"的副作用异味；② 整数 `×scale` 会溢出（R2）。故不能用模式 A。
做法：provider 定义 `toRealBase` 收口（R3），所有解析点调用（R4）。出站在 build 响应处统一 `KCurrency.toKAmount` 缩放 + 本厂商币种码处理（收口进 `buildXxxResult`）。币种码按需（与模式 A 同样正交，见 R5）：
- **改码型**（HEIBAO）：出站币种码走 `HeiBaoBo.WIRE_CURRENCY`（IDR→IDRK）。
- **不改码型**（NOAH）：币种码保持 IDR，只缩放金额。
**两层缩放叠加**（provider 自带线格式 scale + K scale）：HEIBAO 线格式本身 1:10000，IDR 的 K 千位制叠加其上——入站 `toRealBase = KCurrency.fromKAmount(wireToReal(x))`，出站 `wireToWire(KCurrency.toKAmount(balance))`。务必保留两层显式组合，别把两个 scale 合成一个魔数。（注：若某厂商线格式 scale 恰=K scale=1000，两个 1000 对 IDR 会数值抵消，但仍应保留显式组合——语义正确、非 K 币种也对、scale 若变不失效。）
参考：HEIBAO（整数线 1:10000 + **改码** IDRK，当前唯一在用的模式 B 缩放实现）：`HeiBaoBo.toRealBase`/`WIRE_CURRENCY` + `HeiBaoStrategy.launch/playerExitGame`；三处 parse：`HeiBaoVerifyServiceImpl`/`HeiBaoServiceImpl`/`BetaHeiBaoServiceImpl`。
> 「不改码型」模式 B（只缩放、不改币种码）暂无在用实现（NOAH 曾按此接入，后确认无需缩放已回退）。

> 选择准则：能满足模式 A 前提就用 A（下游零处理最省心）；否则一律模式 B。**不确定就用 B**，它对数据结构无假设、无溢出风险。

### 现有厂商对照（截至当前）

**做金额缩放（÷/×1000）的：**

| 厂商 | 线格式 | 模式 | 币种码 | 缩放收口点 |
|------|--------|------|--------|-----------|
| OneAPI | 顶层 `BigDecimal` | A | 改码 `IDR(K)`（入站反查） | validator 改 DTO + `ONE_API_K_CURRENCY(_FIELDS)` |
| HEIBAO | 整数 1:10000 | B | 改码 `IDRK` | `HeiBaoBo.toRealBase` + 出站 buildResult + `WIRE_CURRENCY` |

**只做币种码别名、不缩放金额的：**

| 厂商 | 币种码 | 实现 |
|------|--------|------|
| FastSpin | IDR→`ID2`（仅出站：getBalance 响应 + launch） | `FastSpinBo.WIRE_CURRENCY` / `wireCurrency`（不依赖 `KCurrency`） |

**无任何千位制处理**（金额与币种码都原样）：EVO、NOAH、G759。

> ⚠️ 是否缩放 / 是否改码 **由各厂商在其侧的实际配置决定**，不能想当然。EVO 一度按 ID2+缩放接入，后确认该口径不需要而全撤；FastSpin 需要 ID2 币种码但**不需要**金额缩放。接新厂商前必须逐一与厂商核对"币种码"和"金额是否千位制"两件事。
>
> 决定用不用模式 A/B 的是**数据结构**（顶层/嵌套 BigDecimal → A；整数线/需 re-parse 的嵌套 JSON → B）；决定改不改码、缩不缩放的是**厂商契约**——三者正交。

---

## 3. 新增一个 K 币种

`KCurrency` 加一行（只填基础码 + 缩放因子）：
```java
IDR(1000L),
VND(1000L);   // 例：接入 VND 千位制
```
展示码不在这里——由各 provider 按自己约定处理：改码的自持映射（HEIBAO `WIRE_CURRENCY`=IDR→IDRK、OneAPI `ONE_API_K_CURRENCY`=IDR→IDR(K)），不改码的（FastSpin）什么都不做、币种码保持基础码。金额缩放一律复用 `KCurrency.toKAmount/fromKAmount`。

---

## 4. 接入 / 改动 checklist

- [ ] 入账金额走 `toRealBase`（R3），且**每一处**独立解析回调金额的地方都走（R4：入账 Service + 主播/分线 Service + validator 校验）
- [ ] 换算发生在 `BigDecimal` 层，无整数 `×scale`（R2）
- [ ] 出站三件套齐全：金额 ÷scale + 展示码映射 + （必要时）展示码反查（R5）
- [ ] 签名验证在换算/改写之前完成（对 K 金额签名的三方，先验签再换算）
- [ ] 单元测试用**真实回调数值**钉死：K 币种（如 `toRealBase(2000,"IDR")=200`）+ 非 K 透传（`=0.20`）
- [ ] 全量 `mvn test` 绿 + 人工 review
- [ ] 上线前用 K 币种租户跑完整回调链（投注扣款→结算派彩→余额回显）核对两端口径
- [ ] **数据遗留排查**：若为修复历史漏换算，圈定 bug 存活窗口内受影响注单/账变，与三方对账后由 DBA 处理（prod 禁跑 SQL）

---

## 附:背景

源于 2026-08 HEIBAO 接入 IDR→IDRK（1000:1）。首版只在 validator 局部变量做了换算（仅影响幂等/余额校验），真正入账的 `HeiBaoServiceImpl`/`BetaHeiBaoServiceImpl` 各自 re-parse `settleData` 用裸 `toReal`，未 ×1000 → IDR 注单被低估 1000 倍。修复方式为抽 `KCurrency` 枚举 + `HeiBaoBo.toRealBase` 单一收口，三处解析点统一调用。本规范将该模式固化，供后续千位制厂商复用。

`KCurrency` 一度耦合了展示码（`kCode`/`displayCode`），后拆出——现枚举**只管缩放**，展示码归各 provider。

演进（都以厂商实际口径为准，多次纠偏）：FastSpin/EVO/NOAH/G759 一度按千位制缩放接入，后逐一复核发现口径不符而调整——**EVO/NOAH/G759 全撤（无任何千位制处理）；FastSpin 撤金额缩放、仅保留 IDR→ID2 币种码别名**。当前真正做金额缩放的只剩 **HEIBAO**（模式 B，IDRK）+ 既有 **OneAPI**（模式 A，IDR(K)）。教训见对照表上方⚠️：**"是否缩放/是否改码"必须逐厂商核对配置,不能套用。**
