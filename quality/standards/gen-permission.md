# 权限 SQL 生成指令

**任务目标：**
根据指定的 Controller 文件中的 `@PreAuthorize` 注解，自动生成完整的权限初始化 SQL 脚本。

---

## 权限命名规则（必读，违反即返工）

> **生效范围**：自 2026-05-27 起，**back-service 及后续所有新项目**严格执行本规范。代码评审发现违例必须返工，不接受任何例外。
>
> **不向后兼容**：项目历史代码中存在的不规范写法（如 `_del`、`thirdPartyPaymentChannelUpdate` 这类驼峰嵌动作、`_query`/`_edit`/`_list` 等非标动作词）**不会被加入映射表**，遇到时统一返工纠正。

### 1. 权限只有两种类型

| 类型 | 判定规则 | 用途 | 示例 |
|------|---------|------|------|
| **菜单 perms** | 最后一段**不在**动作映射表 | 标识页面/Tab/子模块，对应 `sp_store_auth_menu` 的菜单节点 | `benefit_box`、`benefit_box_manage`、`benefit_box_manage_audit` |
| **操作 perms** | 最后一段**在**动作映射表 | 标识按钮/操作（查看、新增、修改等） | `benefit_box_manage_view`、`benefit_box_manage_audit_export` |

**这是唯一的判定规则**。生成器（gen-permission）就靠"最后一段是否在映射表里"区分类型，不允许出现似动作但不在映射表里的写法。

### 2. 分段结构

```
菜单 perms ：  {一级菜单}_{业务模块段...}                              （无动作后缀）
操作 perms ：  {一级菜单}_{业务模块段...}_{动作后缀}                    （动作必须最末尾）
                  └── 全小写         └── snake/camel 均可        └── 必须用映射表
```

### 3. 各段写法

| 段位置 | 写法 | 示例 |
|--------|------|------|
| **一级菜单**（已预存，不生成） | 全小写 snake_case | `benefit` / `ops` / `finance` / `game_mgmt` |
| **中间业务段**（二/三/四级菜单） | snake_case 或 camelCase 均可 | `box` / `depositMgmt` / `withdrawalAudit` |
| **最后一段（动作后缀）** | **必须**使用映射表里的固定后缀 | `_view` / `_add` / `_update` / `_delete` / `_export` 等 |

完整动作后缀映射表见 [Step 6 子权限操作名映射表](#子权限操作名映射表-menu_name-和中文翻译)。

### 4. 核心铁律

#### 4.1 动作后缀永远在最末尾

**动作后缀（`_view` / `_add` / `_update` / `_delete` / `_export` ...）必须是权限字符串的最后一段，后面不允许再挂任何内容。**

动作权限是叶子节点，不能再当父级。要新增子模块（更深层级），必须把子模块**插在父模块和动作之间**，绝不允许追加在动作之后。

#### 4.2 业务段禁止使用动作词

中间业务段禁止与动作映射表中的关键字重名：`view` / `add` / `update` / `delete` / `remove` / `export` / `import` / `sort` / `detail` / `status` / `create`。

**为什么**：算法只看最后一段判类型，中间段重名动作词技术上"能跑"，但人读起来语义混乱 —— `benefit_box_view_config_view` 没人能一眼判断"box 下的 view 子模块的 config 查看按钮"还是其他结构。语义清晰优先于命名自由。

### 5. 父子层级的正确表达

层级通过数据库 `parent_id` 字段表达，**不靠路径字符串无限叠加**。同一棵子树下，菜单节点和它的操作权限共享同一个 `perms` 前缀；不同子树下出现的同名动作（如两个 `_view`）彼此独立，各自 `parent_id` 不同。

```
benefit_box                              (二级菜单 M — 菜单 perms)
└── benefit_box_manage                    (三级菜单 C — 菜单 perms，manage 功能模块)
    ├── benefit_box_manage_view           (操作权限 — manage 的查看按钮)
    ├── benefit_box_manage_update         (操作权限 — manage 的修改按钮)
    └── benefit_box_manage_audit          (四级菜单 C — 菜单 perms，manage 下的子模块)
        ├── benefit_box_manage_audit_view      (操作权限 — audit 的查看)
        └── benefit_box_manage_audit_update    (操作权限 — audit 的修改)
```

注意：`benefit_box_manage_view` 与 `benefit_box_manage_audit_view` **不是**父子关系 —— 它们的 `parent_id` 分别指向 `benefit_box_manage` 和 `benefit_box_manage_audit`。

### 6. perms 全局唯一性

`sp_store_auth_menu.perms` 字段在数据库层面**全局唯一**。菜单表不分租户，所有租户共享同一套权限定义；按租户隔离的是**角色表**（`sp_store_role` 带 `tenant_id`）和**角色-菜单关联表**（`sp_store_role_auth_menu` 带 `tenant_id`），各租户通过为本租户的角色挂载不同权限来实现差异化。

**强制约束：**
- 任意两条 perms 不允许相同，即使分属不同子树
- 不同二级菜单下**禁止**使用相同末尾段组合的 perms（例如 `benefit_box_view` 和 `ops_box_view` 不可共存）
- 多 Controller 批量生成时，生成器必须先做全局去重 + 冲突检测，发现冲突立即报错终止
- 评审阶段必须确认 `SELECT COUNT(*) FROM sp_store_auth_menu WHERE perms = 'xxx'` 返回 0

**冲突规避建议：**
- 业务段应包含足够区分度的命名，依靠二级菜单前缀自然隔离（如 `benefit_box_overview_view` 和 `ops_channel_overview_view` 通过 `benefit_box` / `ops_channel` 区分）
- 避免短到一个词的业务段（如单独的 `_box`、`_view`、`_list`），容易跨模块撞车

### 7. 字符集与长度约束

#### 7.1 允许字符

仅 `[a-zA-Z0-9_]`，禁止：
- 连字符 `-`（用 `_` 代替）
- 点号 `.`
- 中文、空格、其他特殊字符

#### 7.2 长度约束

| 约束项 | 上限 | 说明 |
|--------|------|------|
| 整条 perms | ≤ 100 字符 | 数据库 `sp_store_auth_menu.perms` 字段长度限制（预留余量） |
| 单段（`_` 分割后每段） | ≤ 30 字符 | 单段超 30 字符说明业务命名过粗，应拆分子模块 |
| 业务段驼峰单词数 | ≤ 3 个 | 超 3 个说明层级未拆分到位，应作为子菜单单独成段 |

**示例：**
```
✅ benefit_box_manageBatchAudit_update              (业务段 3 词，OK)
❌ benefit_box_manageBatchAuditApprovalReject_update (业务段 5 词，应拆为四级菜单 benefit_box_audit_approvalReject_update)
```

### 8. 反面示例（禁止，新代码出现一律打回）

| 错误写法 | 错误原因 | 正确写法 |
|---------|---------|---------|
| `benefit_box_manage_view_audit` | 动作 `_view` 后面挂了 `_audit`，违反"动作必须最后"铁律 | `benefit_box_manage_audit_view` |
| `benefit_box_manage_query` | `_query` 不在映射表，会被误判为菜单节点 | `benefit_box_manage_view` |
| `benefit_box_manage_edit` | `_edit` 不在映射表 | `benefit_box_manage_update` |
| `benefit_box_manage_list` | `_list` 不在映射表 | `benefit_box_manage_view` |
| `benefit_box_manage_del` | `_del` 简写不在映射表 | `benefit_box_manage_delete` |
| `finance_onlineDeposit_thirdPartyPaymentChannelUpdate` | 动作 `Update` 揉进驼峰，不是独立 `_` 段，会被误判为菜单 | `finance_onlineDeposit_thirdPartyPaymentChannel_update` |
| `benefit_BoxManage_view` | 一级菜单（`benefit`）不能驼峰 | `benefit_boxManage_view` |
| `benefit_box_management` | 似菜单非菜单，看不出是页面入口还是按钮 | 菜单写 `benefit_box_manage`；操作写 `benefit_box_manage_view` |
| `benefit_box_mgmtBatchAcd_view` | 缩写歧义大（Mgmt? Acd?） | `benefit_box_manageBatchAudit_view` |
| `benefit_box_view_config_view` | 业务段用 `view` 这种动作词，可读性差，容易引发歧义 | `benefit_box_overview_config_view` |

### 9. 生成器识别算法（gen-permission 依赖此规则）

生成器按以下步骤识别每条 perms：

1. **前置校验**：先跑[违例检测](#违例处理拒绝生成-sql)，发现任何违例立即终止，**不生成任何 SQL**
2. **拆分**：按 `_` 拆段
3. **判类型**：检查最后一段是否在动作后缀映射表中
   - **是** → 操作 perms（`menu_type='C'`，叶子节点）
   - **否** → 菜单 perms（`menu_type='M'` 或 `'C'`，按层级 + 原型图确定）
4. **建层级**：对所有菜单 perms 按公共前缀分组，每个菜单 perms 的 `parent_id` 指向其上一级菜单 perms；每个操作 perms 的 `parent_id` 指向其去掉最后一段动作后剩下的菜单 perms

**关键依赖**：步骤 3 完全依赖映射表，所以非标动作词（`_del`/`_query`/`_edit`/`_list`/`Update` 驼峰嵌入等）必然识别错误，没有补救空间。

#### 违例处理：拒绝生成 SQL

生成器在 Step 2（提取权限）之后、Step 3（分析层级）之前执行**前置校验**，发现任何一条违例立即终止并报错，要求开发者改名后重跑：

| 校验项 | 检测规则 | 报错示例 |
|--------|---------|---------|
| 非标动作词 | 最后一段长得像动作但不在映射表（`_del`/`_query`/`_edit`/`_list`/`_remove` 之外的） | `❌ ops_xxx_del: '_del' 不在动作映射表，应使用 '_delete'` |
| 驼峰嵌动作 | 最后一段不在映射表，且以动作词驼峰结尾（如 `xxxUpdate`/`xxxDelete`/`xxxView`） | `❌ ops_xxx_thirdPartyUpdate: 动作必须独立 _ 段，应改为 'ops_xxx_thirdParty_update'` |
| 业务段使用动作词 | 中间任一段（非最后段）等于动作映射表中的关键字 | `❌ benefit_box_view_config_view: 业务段 'view' 与动作词冲突` |
| 一级菜单驼峰 | 第一段含大写字母 | `❌ benefit_BoxManage_view: 一级菜单 'benefit' 段不可与下一段连写驼峰，应为 'benefit_boxManage_view'` |
| 字符非法 | 含 `[^a-zA-Z0-9_]` 字符 | `❌ benefit-box_view: 含非法字符 '-'` |
| 长度超限 | 整条 > 100 字符，或单段 > 30 字符 | `❌ ...ApprovalReject_update: 单段 'manageBatchAuditApprovalReject' 超过 30 字符` |
| 全局唯一冲突 | 与 `sp_store_auth_menu` 已有 perms 重复 | `❌ benefit_box_view: 与已有 perms 冲突，请改名` |

**强制语义**：违例不允许"先生成再修"，必须先在 Controller 改名通过校验后再跑生成器。

### 10. 命名口诀

> **菜单写到底，操作加后缀；后缀查表用，动作永末位。**

### 11. 新增动作后缀的流程

若业务场景需要全新动作（如 `_publish`、`_approve`），不能直接在 Controller 里写，必须：

1. 在团队评审会议提案，说明业务必要性与现有动作（如 `_update`）无法覆盖的理由
2. 评审通过后更新 [Step 6 映射表](#子权限操作名映射表-menu_name-和中文翻译)，补充 `menu_name`（英文）和 `translation`（中文）
3. 同步更新前端 i18n 配置
4. 完成上述步骤后，新动作后缀才允许出现在代码中

---

## 执行流程

### Step 1: 查找并读取 Controller 文件

根据用户提供的参数，查找对应的 Controller 文件：
- 如果提供的是类名（如 `PromoMysteryBoxController`），则在项目中搜索该文件
- 如果提供的是完整路径，直接读取该文件

读取文件完整内容。

---

### Step 2: 提取所有权限信息

从 Controller 文件中提取所有 `@PreAuthorize` 注解中的权限字符串：
- 搜索所有 `@PreAuthorize("hasAuthority('xxx')")` 模式
- 提取所有权限 perms
- 去重并按字母序排序

---

### Step 3: 分析权限层级结构与权限类型

根据提取的权限列表，自动识别层级结构（支持二级、三级、四级及更深层级），并标注每个节点的 **权限类型**。

#### 3.1 层级识别规则

1. **主菜单 (二级菜单)**：所有权限的最长公共前缀
   - 例如：`benefit_box_manage_view`、`benefit_box_record_view` → 主菜单为 `benefit_box`

2. **功能模块 (三级菜单)**：去掉主菜单前缀后，再次提取公共前缀
   - 例如：`benefit_box_manage_view`、`benefit_box_manage_update` → 功能模块为 `benefit_box_manage`

3. **子模块 (四级及更深层级菜单)**：递归识别嵌套层级
   - 判断规则：如果权限前缀包含已识别的三级菜单前缀，且中间还有其他段落，则为四级菜单
   - 例如：`benefit_box_statistics_detail_view` 包含三级菜单 `benefit_box_statistics`，中间段落为 `detail`，则 `benefit_box_statistics_detail` 为四级菜单
   - 递归规则：四级菜单可继续包含五级菜单，以此类推

4. **子权限 (操作权限)**：完整的权限字符串，且后缀匹配映射表
   - 例如：`benefit_box_manage_view` (后缀 `_view` 在映射表中)
   - 例如：`benefit_box_statistics_detail_export` (后缀 `_export` 在映射表中)

#### 3.2 权限类型分类 (menu_type)

**必须对照原型图确定每个权限节点的类型**，原型图不明确时找开发人员确认。

| 权限类型 | menu_type | 判断依据 | 示例 |
|---------|-----------|---------|------|
| **侧边栏菜单** | `M` | 在左侧导航栏中显示，点击后跳转到独立页面 | 运营管理、渠道管理、盲盒管理 |
| **页内 Tab** | `C` | 页面内部的 Tab 切换，不产生路由跳转 | 渠道链接 Tab、渠道组 Tab、统计详情 Tab |
| **按钮/操作** | `C` | 页面内的操作按钮，控制增删改查导出等行为 | 操作-查询、操作-新增、操作-修改 |

**分类规则：**
- **一级菜单** (`M`): 已预先存在（如 `ops`、`benefit`、`finance`），不需要生成
- **二级菜单** (`M`): 左侧导航栏的页面入口，点击后打开独立页面
- **三级菜单**: 根据原型图判断
  - 如果是页面内的 **Tab 切换** → `menu_type = 'C'`
  - 如果是左侧导航栏的 **子菜单**（有独立路由） → `menu_type = 'M'`
- **四级及更深层级**: 通常为 `'C'`（页内组件或嵌套 Tab）
- **操作权限**: 始终为 `'C'`（按钮/动作）

**输出分组结果示例：**
```
主菜单 (二级, M): benefit_box
  ├─ 功能模块1 (三级, Tab/C): benefit_box_manage
  │   ├─ benefit_box_manage_view (按钮/C)
  │   └─ benefit_box_manage_update (按钮/C)
  ├─ 功能模块2 (三级, Tab/C): benefit_box_record
  │   ├─ benefit_box_record_view (按钮/C)
  │   └─ benefit_box_record_export (按钮/C)
  ├─ 功能模块3 (三级, Tab/C): benefit_box_statistics
  │   ├─ benefit_box_statistics_view (按钮/C)
  │   ├─ benefit_box_statistics_export (按钮/C)
  │   └─ 子模块1 (四级, Tab/C): benefit_box_statistics_detail
  │       ├─ benefit_box_statistics_detail_view (按钮/C)
  │       └─ benefit_box_statistics_detail_export (按钮/C)
  ...
```

---

### Step 4: 询问用户配置

使用 AskUserQuestion 工具询问以下配置：

1. **一级父菜单 perms** (必填)
   - 选项：benefit / ops / finance / game_mgmt / activity 等
   - 描述：主菜单将挂载到哪个一级菜单下

2. **主菜单中文名称** (必填)
   - 根据主菜单 perms 推荐默认名称
   - 用户可自定义

3. **每个二级菜单的 sort 值** (必填,逐个询问)
   - **重要**: 必须为每个识别出的二级菜单单独询问 sort 值
   - 询问格式: "请输入二级菜单 '{perms}' ({中文名}) 的 sort 值"
   - 提供参考选项:
     - 自定义输入 (推荐)
     - 3000-3999 (财务模块)
     - 7000-7999 (福利模块)
     - 8000-8999 (游戏模块)
   - 如果有多个二级菜单,按顺序逐个询问

4. **功能模块是否需要拆分或合并** (可选)
   - 默认按照识别结果生成
   - 用户可选择将某些模块独立或合并


**示例询问（单个二级菜单情况）：**
```json
{
  "questions": [
    {
      "question": "主权限菜单 'benefit_box' 应该挂在哪个一级菜单下？",
      "header": "父级菜单",
      "multiSelect": false,
      "options": [
        {"label": "福利管理 (benefit)", "description": "独立的福利模块"},
        {"label": "运营管理 (ops)", "description": "运营配置模块"},
        {"label": "财务管理 (finance)", "description": "财务相关模块"}
      ]
    },
    {
      "question": "主菜单的中文名称应该是？",
      "header": "菜单名称",
      "multiSelect": false,
      "options": [
        {"label": "盲盒管理", "description": "直译"},
        {"label": "福利盒管理", "description": "强调福利属性"}
      ]
    },
    {
      "question": "请输入二级菜单 'benefit_box' (盲盒管理) 的 sort 值",
      "header": "Sort 值",
      "multiSelect": false,
      "options": [
        {"label": "7000", "description": "福利模块起始值"},
        {"label": "7100", "description": "福利模块第二个菜单"},
        {"label": "8000", "description": "游戏模块起始值"}
      ]
    }
  ]
}
```

**示例询问（多个二级菜单情况 - 如 finance 模块有 8 个二级菜单）：**
```json
{
  "questions": [
    {
      "question": "请输入二级菜单 'finance_depositMgmt' (提现管理) 的 sort 值",
      "header": "Sort-提现管理",
      "multiSelect": false,
      "options": [
        {"label": "3010", "description": "财务模块第 1 个菜单"},
        {"label": "3000", "description": "自定义: 财务模块起始值"}
      ]
    },
    {
      "question": "请输入二级菜单 'finance_withdrawalAudit' (稽核管理) 的 sort 值",
      "header": "Sort-稽核管理",
      "multiSelect": false,
      "options": [
        {"label": "3020", "description": "财务模块第 2 个菜单"},
        {"label": "3100", "description": "自定义: 跳号分配"}
      ]
    }
    // ... 依次询问所有 8 个二级菜单
  ]
}
```

---

### Step 5: 生成 SQL 脚本

根据权限层级和用户配置，生成完整的 SQL 脚本，包含以下 6 个部分：

#### 5.1 全局变量初始化
```sql
-- 全局变量初始化
SET @nowTime := REPLACE(UNIX_TIMESTAMP(CURRENT_TIMESTAMP(3)), '.', '');
```

#### 5.2 主菜单插入（二级菜单）
```sql
-- 1. 新增 {主菜单名称} 主权限菜单 - 二级菜单
SET @maxId := (SELECT MAX(id) FROM sp_store_auth_menu);
SET @pId := (SELECT id FROM sp_store_auth_menu WHERE perms = '{parent_perms}');

INSERT INTO `sp_store_auth_menu` (`id`, `parent_id`, `menu_name`, `description`, `associated_id`, `menu_type`, `perms`, `sort`, `status`, `remark`, `created_by`, `updated_by`, `created_at`, `updated_at`)
SELECT @maxId+1, @pId, '{EnglishName}', '', NULL, 'M', '{main_perms}', {sort}, 1, '', 'admin', 'admin', @nowTime, @nowTime
WHERE NOT EXISTS (SELECT 1 FROM sp_store_auth_menu WHERE perms = '{main_perms}');
```

> **注意**: 二级菜单为侧边栏页面入口，`menu_type = 'M'`。三级及以下根据原型图确定类型（详见 Step 3.2）。

#### 5.3 功能模块循环插入（三级菜单 + 四级菜单 + 子权限）

**对每个功能模块递归插入：**

1. **插入三级菜单 (sort 在二级菜单内从 1000 开始递增)**
```sql
-- {N}. 新增 {功能模块名称} 三级菜单
SET @maxId := (SELECT MAX(id) FROM sp_store_auth_menu);
SET @pId := (SELECT id FROM sp_store_auth_menu WHERE perms = '{main_perms}');

-- sort 值: 第 1 个三级菜单=1000, 第 2 个=1100, 第 3 个=1200...
INSERT INTO `sp_store_auth_menu` (...)
SELECT @maxId+1, @pId, '{EnglishFeatureName}', '', NULL, 'C', '{feature_perms}', {1000 + (N-1) * 100}, 1, '', 'admin', 'admin', @nowTime, @nowTime
WHERE NOT EXISTS (SELECT 1 FROM sp_store_auth_menu WHERE perms = '{feature_perms}');
```

1.1 **插入四级菜单 (如果存在, sort 在父菜单内从 1000 开始递增)**
```sql
-- {N}.{M}. 新增 {子模块名称} 四级菜单
SET @maxId := (SELECT MAX(id) FROM sp_store_auth_menu);
SET @pId := (SELECT id FROM sp_store_auth_menu WHERE perms = '{parent_feature_perms}');

-- sort 值: 第 1 个四级菜单=1000, 第 2 个=1100, 第 3 个=1200...
INSERT INTO `sp_store_auth_menu` (...)
SELECT @maxId+1, @pId, '{EnglishSubFeatureName}', '', NULL, 'C', '{sub_feature_perms}', {1000 + (M-1) * 100}, 1, '', 'admin', 'admin', @nowTime, @nowTime
WHERE NOT EXISTS (SELECT 1 FROM sp_store_auth_menu WHERE perms = '{sub_feature_perms}');
```

2. **插入子权限（按 100 递增，从 1000 开始）**
```sql
-- 新增 {功能模块名称} 子权限
SET @maxId := (SELECT MAX(id) FROM sp_store_auth_menu);
SET @pId := (SELECT id FROM sp_store_auth_menu WHERE perms = '{feature_perms}');

-- 第 1 个操作权限: sort = 1000
INSERT INTO `sp_store_auth_menu` (...)
SELECT @maxId+1, @pId, 'Operation-Query', '', NULL, 'C', '{feature_perms}_view', 1000, 1, '', 'admin', 'admin', @nowTime, @nowTime
WHERE NOT EXISTS (SELECT 1 FROM sp_store_auth_menu WHERE perms = '{feature_perms}_view');

-- 第 2 个操作权限: sort = 1100
SET @maxId := (SELECT MAX(id) FROM sp_store_auth_menu);
INSERT INTO `sp_store_auth_menu` (...)
SELECT @maxId+1, @pId, 'Operation-Modify', '', NULL, 'C', '{feature_perms}_update', 1100, 1, '', 'admin', 'admin', @nowTime, @nowTime
WHERE NOT EXISTS (SELECT 1 FROM sp_store_auth_menu WHERE perms = '{feature_perms}_update');

-- 第 3 个操作权限: sort = 1200
SET @maxId := (SELECT MAX(id) FROM sp_store_auth_menu);
INSERT INTO `sp_store_auth_menu` (...)
SELECT @maxId+1, @pId, 'Operation-Export', '', NULL, 'C', '{feature_perms}_export', 1200, 1, '', 'admin', 'admin', @nowTime, @nowTime
WHERE NOT EXISTS (SELECT 1 FROM sp_store_auth_menu WHERE perms = '{feature_perms}_export');

-- ... 其他子权限按 1300, 1400, 1500... 递增
```

**排序值规则 (重要)：**
- **二级菜单 (主菜单, type='M')**: 用户自定义 (Step 4 询问, 如 5030)
- **三级菜单 (功能模块)**: 从 1000 开始, 每次递增 100
  - 第 1 个三级菜单: 1000
  - 第 2 个三级菜单: 1100
  - 第 3 个三级菜单: 1200
  - 第 N 个三级菜单: 1000 + (N-1) × 100
- **四级菜单 (子功能模块)**: 在父菜单内从 1000 开始, 每次递增 100
  - 第 1 个四级菜单: 1000
  - 第 2 个四级菜单: 1100
  - 第 N 个四级菜单: 1000 + (N-1) × 100
- **操作权限 (子权限, type='C')**: 在每个父菜单内从 1000 开始, 每次递增 100
  - 第 1 个操作: 1000
  - 第 2 个操作: 1100
  - 第 3 个操作: 1200
  - 第 N 个操作: 1000 + (N-1) × 100
- **menu_type 分类规则**: 根据原型图判断（详见 Step 3.2）
  - `'M'` = 侧边栏菜单（有独立路由的页面入口）
  - `'C'` = 页内组件（Tab 切换、按钮操作）
  - 原型图不明确时，必须找开发人员确认
- 每个 INSERT 前必须重新查询 `@maxId`

#### 5.4 角色关联插入（必须包含）
```sql
-- ============================================================
-- 10. 新增权限与 admin 角色关联关系
-- ============================================================
SET @baseRoleMenuId := (SELECT IFNULL(MAX(id), 0) FROM sp_store_role_auth_menu);

INSERT INTO sp_store_role_auth_menu
(id, tenant_id, role_id, menu_id, created_at, updated_at)
SELECT
    @baseRoleMenuId := @baseRoleMenuId + 1 AS id,
    r.tenant_id,
    r.id       AS role_id,
    m.id       AS menu_id,
    @nowTime   AS created_at,
    @nowTime   AS updated_at
FROM sp_store_role r
JOIN sp_store_auth_menu m
    ON m.perms IN (
        -- 主菜单
        '{main_perms}',
        -- 功能模块1
        '{feature1_perms}',
        '{feature1_perms}_view',
        '{feature1_perms}_update',
        -- 功能模块2
        '{feature2_perms}',
        '{feature2_perms}_view',
        '{feature2_perms}_export',
        -- ... 依次列出所有权限
    )
LEFT JOIN sp_store_role_auth_menu rm
    ON rm.tenant_id = r.tenant_id
   AND rm.role_id  = r.id
   AND rm.menu_id  = m.id
WHERE r.role_name = 'admin'
  AND rm.id IS NULL
ORDER BY m.id;
```

**重要说明：**
- **必须列出所有权限**：IN 子句中需包含所有二级菜单、三级菜单、四级菜单和操作权限的 perms
- **幂等性保证**：使用 LEFT JOIN + `rm.id IS NULL` 确保重复执行不会产生重复关联
- **自动递增 ID**：使用变量赋值 `@baseRoleMenuId := @baseRoleMenuId + 1` 自动生成 ID
- **多租户支持**：自动关联 `tenant_id` 字段

#### 5.5 中文翻译插入 (sp_translation)

**翻译规则:**
- **必须插入翻译**: 二级菜单, 三级菜单/Tab, 四级菜单, 不在标准映射表中的按钮
- **不需要插入翻译**: 标准操作按钮 (`Operation-Add`, `Operation-Modify`, `Operation-Delete`, `Operation-Export` 等) — 全局已有翻译
- 使用 **INSERT ... WHERE NOT EXISTS** 保证幂等

```sql
-- 翻译插入
SET @transMaxId := (SELECT IFNULL(MAX(id), 0) FROM sp_translation);

-- {菜单英文名} → {中文翻译}
INSERT INTO sp_translation (id, table_name, column_name, source, translation, source_language, translation_language, is_machine_translated, created_at, updated_at, updated_by)
SELECT @transMaxId := @transMaxId + 1, 'sp_store_auth_menu', 'menu_name', '{EnglishMenuName}', '{中文翻译}', 'en', 'zh', 0, @nowTime, @nowTime, 'admin'
WHERE NOT EXISTS (SELECT 1 FROM sp_translation WHERE source = '{EnglishMenuName}' AND translation_language = 'zh' AND table_name = 'sp_store_auth_menu');
```

#### 5.6 权限清单注释
```sql
-- ============================================================
-- 权限清单汇总（1 个二级菜单，N 个三级菜单，M 个子权限）
-- ============================================================
-- 权限层级结构：
--
-- {parent_perms} ({父菜单名} - 一级菜单，需预先存在)
--   └── {main_perms} ({主菜单名} - 二级主菜单)    - sort: {sort}
--        ├── {feature1_perms} ({功能1} - 三级菜单) - sort: {sort}
--        │    ├── {feature1_perms}_view          ({操作1})
--        │    └── {feature1_perms}_update        ({操作2})
--        ...
-- ============================================================
```

---

### Step 6: 命名规范与映射

#### 子权限操作名映射表 (menu_name 和中文翻译)

| perms 后缀  | menu_name (英文)    | translation (中文) |
|-----------|-------------------|------------------|
| `_view`   | Operation-Query   | 操作-查看               |
| `_add`    | Operation-Add     | 操作-新增               |
| `_update` | Operation-Modify  | 操作-修改               |
| `_delete` | Operation-Delete  | 操作-删除               |
| `_remove` | Operation-Delete  | 操作-删除               |
| `_export` | Operation-Export  | 操作-导出               |
| `_import` | Operation-Import  | 操作-导入               |
| `_sort`   | Operation-Sort    | 操作-排序               |
| `_detail` | Operation-Details | 操作-详情               |
| `_status` | Operation-On/Off  | 操作-开启/关闭            |
| `_create` | Operation-Add     | 操作-新增               |

**排序值规则 (重要):**
- ✅ **正确做法**: 在每个三级菜单内, 按子权限出现顺序从 1000 开始, 每次递增 100
- ❌ **错误做法**: 按权限后缀固定排序值 (如 `_view` 必须是 1000)

**示例 1: 三级菜单 `benefit_box_manage` 下有 4 个子权限**
```
benefit_box_manage_view    → sort: 1000 (第 1 个出现)
benefit_box_manage_detail  → sort: 1100 (第 2 个出现)
benefit_box_manage_update  → sort: 1200 (第 3 个出现)
benefit_box_manage_status  → sort: 1300 (第 4 个出现)
```

**示例 2: 三级菜单 `benefit_box_record` 下有 2 个子权限**
```
benefit_box_record_view    → sort: 1000 (第 1 个出现, 重新从 1000 开始)
benefit_box_record_export  → sort: 1100 (第 2 个出现)
```

#### 功能模块名称翻译推荐

根据 perms 自动推荐英文菜单名：

| perms 包含关键词 | 推荐英文名 | 推荐中文名 |
|----------------|----------|----------|
| `manage` | Management | 管理 |
| `record` | Record | 记录 |
| `statistics` | Statistics | 统计 |
| `config` | Configuration | 配置 |
| `physical` | Physical Order | 实物订单 |
| `report` | Report | 报表 |
| `log` | Log | 日志 |

---

### Step 7: 输出文件

将生成的 SQL 脚本保存到 **merchant-service 根目录下的 `.permissions/` 目录**：
```
goplay-merchant-service/.permissions/{controller_name}_permissions.sql
```

> `.permissions/` 目录已加入 `.gitignore`（Windows/macOS/Linux 均兼容），仅本地使用，不提交到仓库。

**文件命名规则：**
- Controller 名称：`PromoMysteryBoxController.java`
- 输出文件名：`promo_mystery_box_permissions.sql`

**生成完成后告知用户：**
```
✅ 权限初始化 SQL 已生成：
   文件路径：goplay-merchant-service/.permissions/promo_mystery_box_permissions.sql

📊 生成统计：
   - 二级菜单：1 个
   - 三级菜单：5 个
   - 子权限：15 个
   - 总行数：210 行


⚠️  执行前请确认：
   1. sp_store_auth_menu 表中已存在父菜单 (perms = 'benefit')
   2. 排序值无冲突
   3. 权限名称符合业务需求
```

---

## 排序值分配规则

### 二级菜单 (主菜单) 排序值
- **用户自定义** (Step 4 询问)
- 第一位数字区分大类:
  - 2xxx: 运营模块
  - 3xxx: 财务模块
  - 5xxx: 福利模块
  - 7xxx: 游戏模块
  - 8xxx: 活动模块

**示例:**
- 主菜单 `benefit_box`: 5030 (福利模块第 3 个菜单)

### 三级菜单 (功能模块) 排序值
- **起始值**: 1000
- **递增规则**: 在父菜单 (二级菜单) 内从 1000 开始, 每次递增 100
- **公式**: 1000 + (索引 - 1) × 100

**示例: 某二级菜单下有 4 个三级菜单**
```
第 1 个三级菜单: 1000
第 2 个三级菜单: 1100
第 3 个三级菜单: 1200
第 4 个三级菜单: 1300
```

### 四级及更深层级菜单排序值
- **起始值**: 1000
- **递增规则**: 在父菜单 (三级或更高级菜单) 内从 1000 开始, 每次递增 100
- **公式**: 1000 + (索引 - 1) × 100

**示例: 某三级菜单下有 2 个四级菜单**
```
第 1 个四级菜单: 1000
第 2 个四级菜单: 1100
```

### 子权限 (操作权限) 排序值
- **起始值**: 1000 (在每个父菜单内独立计数)
- **递归规则**: 按出现顺序从 1000 开始, 每次递增 100
- **公式**: 1000 + (索引 - 1) × 100
- **父菜单**: 可以是三级菜单、四级菜单或更深层级菜单

**示例 1: 三级菜单下有 4 个子权限**
```
第 1 个操作: 1000
第 2 个操作: 1100
第 3 个操作: 1200
第 4 个操作: 1300
```

**示例 2: 四级菜单下有 2 个子权限 (在该四级菜单内从 1000 开始)**
```
第 1 个操作: 1000
第 2 个操作: 1100
```

---

## 关键技术要点

### 1. 幂等性保证
所有 INSERT 语句都使用：
```sql
WHERE NOT EXISTS (SELECT 1 FROM sp_store_auth_menu WHERE perms = 'xxx')
```

### 2. 不使用 FROM DUAL
MySQL 5.7+ 标准语法，简化代码。

### 3. 全局时间戳
只在开头计算一次 `@nowTime`，所有后续操作共享。

### 4. 独立翻译 UPDATE
每个菜单一个 UPDATE 语句，便于维护和修改。

---

## 使用示例

### 示例 1：提供类名
```
/gen-permission PromoMysteryBoxController
```

### 示例 2：提供完整路径
```
/gen-permission D:\G9\goplay-merchant-service\merchant-service\src\main\java\com\great\merchant\service\controller\PromoMysteryBoxController.java
```

### 示例 3：批量生成（未来支持）
```
/gen-permission PromoBonusController PromoRewardController
```

---

**立即执行上述流程，生成完整的权限初始化 SQL 脚本。**
