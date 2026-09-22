# 10 变量与单位字典（唯一权威版）

> 本文件是《经纬》首版 SimCore 的**唯一权威变量契约**，由三份独立草案
> （`_drafts/spine_accounting`、`_drafts/spine_engineering`、`_drafts/spine_testability`）综合裁定而成。
> 草案已作废，只作为裁定依据保留；实现与测试一律以本文件、`11_data_contract.md`、`12_simulation_contract.md` 为准。
>
> 权威需求来源：`docs/ref/plan_v1.0.txt`（计划书 v1.0）。本文件不推翻已锁定的工程决策。
> 凡计划书未写清之处，取最保守选择，并登记进 `13_open_questions.md`。

---

## 0 通用约定

### 0.1 记数单位（唯一定义，任何地方不得另立）

| 符号 | 含义 | 存储 | 定义 |
|---|---|---|---|
| `U` | 记账货币单位 | 仅展示 | 基年全年名义 GDP ≡ 100 U |
| `μU` | 货币最小单位 | int64 | **1 U = 1 000 000 000 μU**；基年全年名义 GDP = 100 000 000 000 μU；基年季度名义 GDP = 25 000 000 000 μU |
| `Q_s` | 部门 s 的基年产品单位 | 仅展示 | 每部门各有自己的 Q_s，**不可跨部门相加** |
| `μQ_s` | 部门 s 产品最小单位 | int64 | 1 Q_s = 1 000 000 μQ_s |
| `μU/Q_s` | 价格 | int64 | **基年全部门价格 = 1 000 000 000** |
| `μQ_s/季` | 季度产能 | int64 | 资本的产能轨直接以「每季可产出多少 μQ_s」计量 |
| `ppm` | 比率／系数／弹性／指数 | int64 | 百万分之一；1.000000 = 1 000 000 |
| `persons` | 人口 | int64 ≥ 0 | 整数人，不可分割 |
| `units` | 不可再分件数（住房套、席位、槽位、席） | int64 ≥ 0 | — |
| `q` | 季度索引 | int64 | q = 0 为基年第 1 季；首版 q ∈ [0, 39]，压力测试 q ∈ [0, 119] |

> **货币刻度（裁定 R-SCALE-01，破坏性变更，已执行）**：`U_SCALE` 由 1 000 000 改为 **1 000 000 000**。
> 改的理由不是「想要更多位数」，而是旧刻度在**每人／每套**这一层塌掉了：旧刻度下人均季度劳动报酬约 1.4 μU
> （工资只能取 {1, 2, 3}，技能溢价被迫是 100% / 50%）、最小可表达租金 1 μU/套/季 乘 793 万套已等于季度 GDP 的约 32%、
> ±3% 的有界平滑对 1…3 的整数永远算出 0。三处是同一病因的三个表现，只能改刻度，不能逐个打补丁。
>
> **随之改动的常量**：`BASE_PRICE` 1 000 000 → **1 000 000 000**；`BASE_YEAR_GDP_UU` 100 000 000 → **100 000 000 000**；
> `AMOUNT_MAX` 4×10¹² → **4×10¹⁵**；`PRICE_MIN` / `PRICE_MAX` 400 000 / 2 500 000 → **400 000 000 / 2 500 000 000**。
> **不动的常量**：`Q_SCALE`（1 000 000）、`PPM`（1 000 000）、`QTY_MAX`（1×10¹²）——实物刻度与比率刻度与货币刻度无关。
>
> **由此产生的两条全局后果**，每一条都在下文逐处落地，不是「其余类推」：
> (a) `AMOUNT_MAX × PPM` 与 `QTY_MAX × PRICE_MAX` 都**真的溢出 int64**，一切「先乘后除」必须走
> `mul_div_floor(a, b, c)`（§13）；
> (b) 基年价计价的库存，其 μU 数值不再等于 μQ_s 数值，而是等于 **1 000 倍**的 μQ_s 数值（§2.3）。

**指数（基期 = 100）一律用 ppm 存储**：`1 000 000` 表示基期 100.00。展示层按 `显示值 = 存储值 / 10 000` 渲染，
换算只写在 Presentation 层。SimCore 内不存在「100 分制」的字段。

**禁止浮点**：`res://sim/**` 与 `res://systems/**` 内任何 `float`、`PackedFloat*`、小数字面量一律构建失败
（INV-001）。浮点只允许出现在 Presentation 的格式化函数中，且该函数不得回写任何状态。

### 0.2 字段后缀（强制，机器可检查）

| 后缀 | 含义 | 例 |
|---|---|---|
| `_uu` | 金额（μU） | `cash_uu` |
| `_uqs` | 实物数量（μQ_s） | `output_actual_uqs` |
| `_uu_per_qs` | 价格 | `price_uu_per_qs` |
| `_uqs_per_q` | 产能（μQ_s/季） | `capacity_active_uqs_per_q` |
| `_ppm` | 比率／系数／指数 | `unemployment_ppm` |
| `_persons` | 人数 | `population_persons` |
| `_units` | 件数 | `housing_capacity_units` |
| `_q` | 季度索引 | `maturity_q` |
| `_count` | 计数器 | `toggle_count` |
| `_memo_uu` | **表外备查**金额（承诺、额度），**禁止进入任何资产负债恒等式** | `committed_memo_uu` |

> **裁定**：草案 A/B 使用 `_uU` / `_uQs` 这类混合大小写，违反已锁定的「JSON 键名与代码标识符英文 snake_case」。
> 本文件统一采用草案 C 的全小写形式。这是**破坏性命名裁定**，三份文档与全部代码一律照此执行。

### 0.3 命名空间（存量／流量／派生／内容）

| 前缀 | 类 | 语义 | 生命周期 | 是否进 `state_hash` |
|---|---|---|---|---|
| `state.*` | **存量 S** | 时点余额，跨季结转 | 永久 | 是 |
| `flow.*` | **流量 F** | 只对某一季有意义 | 每季 S01 显式清零 | 是（重放与复核需要） |
| `derived.*` | **派生 D** | 可由 S/F 按确定公式重算 | 读时计算 | 否（但进派生一致性检查 INV-014） |
| `param.*` / `content.*` | **内容 C** | 内容包只读常量 | 运行期不可写 | 否（进 `content_hash`） |
| `log.*` | 日志 | 可再生的追溯记录 | 每季重建 | 否（进重放对比） |

> **裁定**：三份草案分别用「字段名带 `_q` 后缀」「类别列」「`flow.` 前缀」区分流量。
> 取草案 C 的 `flow.` 前缀：它使「S01 清零全部流量」成为对**一个注册表**的遍历，而不是对字段名的字符串匹配，
> 因此 INV-013（可写子集白名单）与 `test_u_flow_reset` 都可以机器执行。

### 0.4 稳定 ID

```
region.beiyuan | region.zhongzhou | region.haijia | region.xiling
sector.agri | sector.manu | sector.energy | sector.services
cell.<region>.<sector>                       # 16 个生产单元（物理与财务同一实体）
pubserv.<region>                             # 4 个公共服务非市场生产者（services 的子账户）
group.<region>.<age>.<skill>                 # age ∈ minor|working|elder, skill ∈ low|mid|high, 36 个
policy.P01 .. policy.P12
event.E01 .. event.E12
shock.S01 .. shock.S03
param.<snake_name>
bond.<batch_id>                              # batch_id = q<qqq>_<nn>，开局存量债 issue_q 为负
project.<policy_code>_<issue_q>_<nnn>
bloc.agri_coop | bloc.business | bloc.labor_public
agent.<owner>                                # 账本主体，见 §2.1
account.<agent_id>.<code>                    # 复式账本科目，见 §2.2
rng.shock | rng.event | rng.demography | rng.market | rng.politics | rng.reserved
txn.<qqq>.<nnnnnn>                           # 交易号
scenario.<name> | paramset.<name>
```

规则：

1. ID 全小写 ASCII，段间 `.`，段内 `_`；正则 `^[a-z][a-z0-9_]*(\.[a-zA-Z0-9_]+)*$`，
   其中政策／事件／冲击编号段允许大写（`P04`、`E11`、`S02`）。
2. **ID 一经进入任何已发布存档即永不复用、永不改名**。改名必须新增 ID，并在 `content/id_aliases.json`
   登记 `old -> new` 供旧档读取；新内容文件中出现别名侧 ID 即校验失败。删除的实体在
   `content/tombstones.json` 留墓碑。
3. **运行期生成的 ID 只来自单调计数器** `state.meta.entity_seq`；禁止使用时间戳、指针地址、哈希（INV-010 的前提）。
4. 集合在 JSON 中一律用带 `id` 字段的对象数组或以 ID 为键的 map，**数组下标不得作为标识**。

> **裁定（ID 段序）**：草案 A 写 `firm.<sector>.<region>`（部门在前），草案 B/C 用 `cell.<region>.<sector>`。
> 取地区在前，与已锁定的 `group.<region>.<age>.<skill>` 保持同一读法。

### 0.5 稠密下标（契约的一部分，不得重排）

```
region: 0 beiyuan(北原)  1 zhongzhou(中州)  2 haijia(海岬)  3 xiling(西岭)
sector: 0 agri(农业)     1 manu(制造)       2 energy(能源)  3 services(服务)
age:    0 minor(未成年)  1 working(劳动年龄) 2 elder(老年)
skill:  0 low(低)        1 mid(中)          2 high(高)

R = 4, S = 4, A = 3, K = 3, CELL = 16, GROUP = 36

idx_cell(r, s)        = r * 4 + s          # 0..15
idx_group(r, a, k)    = r * 9 + a * 3 + k  # 0..35
idx_io(s_from, s_to)  = s_from * 4 + s_to  # 0..15
idx_inv(cell, s_in)   = cell * 4 + s_in    # 0..63
idx_emp(cell, k)      = cell * 3 + k       # 0..47
idx_od(r_from, r_to)  = r_from * 4 + r_to  # 0..15
```

下标顺序的任何改动都是 schema 破坏性变更：必须升 `schema_version` 并写迁移函数（INV-136）。

### 0.6 内存布局（性能门槛的前提）

1. **不存在「每个实体一个对象」**。地区、部门、cell、群组、政策全部是定长数组下标。
   只有数量可变的两类实体（债券批次、项目）用 SoA（结构体数组拆成若干平行 `PackedInt64Array`），
   **只增不删**：已结清批次改状态位，下标永久稳定，日志可回指。
2. 所有数组在 `LOAD` 期一次性 `resize()` 到最终长度。
3. **SimCore 运行期不新建 `RefCounted`、不使用 `Dictionary` 键查找、不出现 `String`**。
   `ID → 下标` 的解析在加载期完成，存入 `IdRegistry`；运行期只传 `int`。
4. 需要「二维」时用一维 `PackedInt64Array` + §0.5 的索引函数；禁用 `Array[Variant]`。
5. 中间结果写入 `TurnRunner` 预分配的 scratch 数组，每步入口 `fill(0)`。

### 0.7 写入者代号（「谁能修改它」列）

| 代号 | 含义 |
|---|---|
| `LOAD` | 剧本载入 / 存档反序列化，只发生在季度推进之外 |
| `MIG` | 存档版本迁移函数 |
| `CMD` | 玩家命令校验通过后写入**命令缓冲与 `pending_*`**，绝不直接改账 |
| `S01`…`S08` | 结算八步（见 `12_simulation_contract.md`） |
| `DERIVED` | 无写入者，读时计算 |

**任一字段出现两个结算步作为写入者，必须在 12 号文件中说明「为什么同一季两次写入不会互相放大」**。
不存在 `S09`，也不存在 `apply_balance_fix()` 这类函数（计划书 §13）。

### 0.8 越界行为（只有三种，第四种被禁止）

| 行为码 | 语义 | 典型场景 |
|---|---|---|
| `REJECT` | 拒绝命令，状态完全不变，写 `log.rejections`（带原因码） | 玩家把税率设成 −5% |
| `ARREARS` | 不改账，登记欠付／延期／取消／未满足需求，继续结算 | 现金不足以付工程款 |
| `FAULT` | 视为程序缺陷，结算中止，导出故障包 | 人口不守恒、借贷不等 |

**禁止第四种：静默夹逼（silent clamp）。** `clamp()` 只允许出现在**明确登记为有界平滑**的位置
（价格、工资、指数、支持度、招聘摩擦），且每次夹逼必须写一条 `log.clamp`（INV-069）。

### 0.9 整数算术三条铁律

1. **不存在四舍五入。** 全系统只有 `idiv_floor`、`idiv_ceil` 与最大余数法三种，
   每个调用点必须写注释 `# rounding: floor|ceil|lr, reason=...`（静态检查 INV-002）。
   新刻度下追加一条**入口约束**：凡形如 `floor(a·b/c)` 的「先乘后除」一律经 `mul_div_floor(a, b, c)`，
   凡形如 `ceil(a·b/c)` 的一律写成 `−mul_div_floor(−a, b, c)`；**禁止先 `mul(a, b)` 再 `idiv_floor(·, c)`**
   （理由与证明见 §13）。取整方向不因此改变——变的只是不溢出的算法，不是语义。
2. **拆分（split）**：把已存在的一笔 `T` 分给 n 个去向，必须用 `split_largest_remainder`，
   `Σ 分项 == T` 精确成立（INV-003）。
3. **计提（accrual）与换算（conversion）分开处理**：

| 类别 | 定义 | 取整 | 余数去向 |
|---|---|---|---|
| 拆分 | 已存在金额分给多方 | 最大余数法 | 无余数（精确） |
| 计提 | 对**存量**按利率计提、形成**持续债权债务** | floor | 并入该实体的 `*_remainder_ppmuu` 累加器，满 1 000 000 结转 1 μU（INV-004）。**首版只有债券票息适用此条**。新刻度下余数**不得**写成 `mul(a, b) % c`（裸乘必溢出），须用 §13 的拆商式 `(r·b) mod c` |
| 换算 | 数量×价格、税基×税率、折旧、一切 ppm 缩放 | floor（或按 §0.10 用 ceil） | 写 `log.rounding` 备查，**不产生债权债务**（INV-005）。被截掉的部分从未存在过，禁止设「余数池」，否则会凭空造钱 |

### 0.10 每个取整方向的保守性理由（对照表，实现时逐处引用）

第四列是 **R-SCALE-01 后的逐条复核结论**。复核的问题只有两个：
**(1) 取整方向是否还成立？(2) 新刻度下这一处的乘法是否还能裸乘？**
复核结果：**十三条原有条目的取整方向无一改变**——保守性理由都只依赖「谁多谁少」，与刻度无关；
改变的只是其中六条的**算法形态**（裸乘会溢出，必须走 `mul_div_floor`）。

| 场景 | 方向 | 保守方向理由 | 新刻度复核（R-SCALE-01） |
|---|---|---|---|
| 年度额拆到四季 | 最大余数法 | 四季合计必须精确等于年计划（计划书 §05） | 方向不变。权重是 `season_factor_ppm`，Σw = 1 000 000，可拆总额上界 9 223 372 036 854 μU ≈ 9 223 U；年支出计划 22 U，裕度 419× |
| 一笔支出拆到多个收款方 | 最大余数法 | 双边入账必须严丝合缝 | 方向不变。**权重是 μU 债权额，受 §13 的最大余数法入口断言约束**，见 §13 末尾 |
| 债券等额本金拆到各期 | 最大余数法 | 各期和 == 面值（INV-037） | 方向不变。权重全为 1，Σw = 期数 ≤ 24，上界 ≈ 3.8×10¹⁷ μU，远高于任何面值，无风险 |
| 配给可供量到各需求方 | 最大余数法 | 分配之和 == 可供量（INV-060） | 方向不变。全程 μQ_s 口径，`Q_SCALE` 未变，裕度与旧刻度**逐位相同** |
| 群组权重加总为全国 | 最大余数法 | 加权和不失真（INV-124） | 方向不变。权重是人口（未变），Σw = 24 000 000，可拆总额上界 384 307 168 202 μU ≈ 384 U ＝ 15.4 倍季度 GDP；旧刻度是 15 360 倍，**裕度缩水 1 000 倍**，见 §13 末尾 |
| 数量 × 价格 → 金额 | floor | 少收钱优于凭空多收 | 方向不变。**裸乘溢出**（1e12 × 2.5e9 = 2.5e21）：必须写 `mul_div_floor(qty_uqs, price_uu_per_qs, Q_SCALE)` |
| **产量 → 投入消耗量** | **ceil** | **绝不允许少耗料多出产**（INV-046） | 方向不变。μQ × μQ/Q_SCALE，与货币刻度无关，裸乘 1e18 不溢出；仍按 §0.9 统一写成 `−mul_div_floor(−q_actual, a_coeff, Q_SCALE)` |
| **产量 → 用工人数** | **ceil** | 绝不允许少算用工 | 方向不变。`labor_coeff` 是「人/Q_s」，与货币刻度无关，无溢出风险 |
| 投入可用量 → 产量上限 | floor | 绝不允许超出物料约束 | 方向不变。μQ 口径，与货币刻度无关；写成 `mul_div_floor(inventory_uqs, Q_SCALE, a_coeff)`，裸乘上界 1e18，裕度 9.2× |
| 税额 = 税基 × 税率 | floor | 少征税优于多征税 | 方向不变。**税基是 μU、可达 `AMOUNT_MAX`，裸乘溢出**（4e15 × 1e6 = 4e21）：必须走 `mul_ppm` → `mul_div_floor` |
| 利息 = 本金 × 票息率 | floor + 余数累加器 | 逐批次计算后求和；长期不漂移（INV-036/041） | 方向不变。**裸乘溢出**（4e15 × 1e5 = 4e20）：商走 `mul_div_floor(outstanding, coupon, PPM)`，余数走 `(r·b) mod c`（§13）。`≤ 1 μU/批次` 的漂移上界在新刻度下是**旧刻度的千分之一**，白赚的收紧 |
| 折旧 | floor | 少计折旧优于凭空减资产 | 方向不变。**资本账面值是 μU、可达 `AMOUNT_MAX`，裸乘溢出**：必须走 `mul_ppm` → `mul_div_floor` |
| 价格与工资调整步长 | floor 后 clamp | 有界平滑（INV-066/067） | 方向不变。`PRICE_MAX × PPM` = 2.5e15 不溢出（裕度 3 689×）。**这是 R-SCALE-01 的直接受益项**：旧刻度下 ±3% 作用在 1…3 的整数工资上恒为 0，新刻度下人均季度报酬约 1 360 μU，±3% ≈ 40 μU，平滑第一次真正生效 |
| **总额 → 人均**（人均可支配收入、人均劳动报酬、`living_index` 的人均归一化） | **floor** | 少算优于高估民生：人均口径只进展示与主观量，宁可低报 | **新增条目**。旧刻度下全国人均实际收入只有 1…6 六个取值，`living_index` 的人均归一化只剩约 1 位有效数字，floor 与 ceil 的差别能占满量程；新刻度下约 3 100 级（4 位有效数字），floor 的偏置退回到可忽略。分母是 `persons`，与 `PPM` 相乘上界 2.4e13，无溢出 |
| **总额 → 每套**（住房季度使用成本、租金） | **floor** | 少收租优于向居民多收 | **新增条目**。旧刻度下最小可表达租金 1 μU/套/季 × 793 万套 ≈ 季度 GDP 的 32%，合法区间与设计目标区间**不相交**，逐地区 floor 成 0；新刻度下同一档只占 0.032%，目标档位约 315 μU/套/季，floor 才有意义 |

---

## 1 全局、时间与确定性

| 稳定 ID | 中文名 | 类 | 单位 | 维度 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|---|
| `state.meta.schema_version` | 状态结构版本 | S | int | 全局 | ≥ 1 | 代码常量 | LOAD/MIG | INV-135 |
| `state.meta.build_id` | 构建标识 | S | 字符串 | 全局 | 非空 | 构建期注入 | LOAD | INV-014 |
| `state.meta.content_hash` | 内容包哈希 | S | hex64 | 全局 | 64 位 hex | 载入时计算 | LOAD | INV-134 |
| `state.meta.state_hash_prev` | 上季状态哈希 | S | hex64 | 全局 | — | — | S01 | INV-014 |
| `state.meta.scenario_id` | 剧本 ID | S | 字符串 | 全局 | `scenario.chengwan` | 剧本 | LOAD | — |
| `state.meta.param_set_version` | 参数集版本 | S | int | 全局 | ≥ 1 | 剧本 | LOAD | INV-134 |
| `state.meta.replay_unreliable` | 重放不可靠标记 | S | bool | 全局 | — | false | LOAD | INV-014 |
| `state.meta.command_seq` | 已受理命令序号 | S | int | 全局 | 单调 ≥ 0 | 0 | CMD | INV-010 |
| `state.meta.entity_seq` | 实体 ID 分配序号 | S | int | 全局 | 单调 ≥ 0 | 0 | S02, S07 | INV-010 |
| `state.time.q` | 当前待结算季度 | S | 季 | 全局 | 0 .. `horizon_q` | 0 | **S08** | INV-012 |
| `state.time.horizon_q` | 本局总季数 | S | 季 | 全局 | 40 或 120 | 剧本／命令行 | LOAD | INV-012 |
| `state.time.phase` | 结算阶段游标 | S | 枚举 `idle\|S01..S08` | 全局 | — | `idle` | S01..S08 | INV-012 |
| `state.meta.run_terminated` | 本局已终止 | S | bool | 全局 | — | false | S08 | INV-128 |
| `state.meta.termination_reason` | 终止原因码 | S | 枚举 | 全局 | `none\|horizon\|lost_election\|lost_confidence\|fiscal_restructuring_failed` | `none` | S08 | INV-128 |
| `derived.time.year_index` | 年序号 | D | 年 | 全局 | `idiv_floor(q, 4)` | — | DERIVED | — |
| `derived.time.quarter_in_year` | 年内季序（0 起） | D | int | 全局 | `q − 4·year_index` | — | DERIVED | — |

> **裁定（`q` 的写入者与语义）**：草案 A/B 在 S01 递增 `q`，并因此需要为「第 0 季首次结算」开例外；
> 草案 C 在 S07 写 `q`。本文件裁定：**`state.time.q` 是「本次正在结算的季度」，整季结算期间恒定不变，
> 只在 S08 末递增一次**。好处：(a) 没有首季例外；(b) 全部八步读到的 `q` 语义一致；
> (c) `q` 只有一个写入点，INV-012 可用静态检查落地。

> **裁定（选举与审查的季度索引）**：计划书 §08 说「第 16、32 季举行简化选举」「预算每 4 季审查」。
> 因 `q` 从 0 起，第 16 季 = `q = 15`，第 32 季 = `q = 31`，第 40 季 = `q = 39`。
> 草案 A/B 写成 `q ∈ {16, 32}` 是**差一错误**，草案 C 正确。裁定采用 **`q ∈ {15, 31}`**，
> 预算审查在 `q ≡ 3 (mod 4)`（每年第 4 季）。

---

## 2 账本底座

### 2.1 账本主体（agent）

首版共 **60 个主体**，加载期枚举，运行期不新建。「无来源资金」在结构上不可表达：不存在第 61 个主体。

| 主体 ID 模式 | 数量 | 说明 | 持有现金 |
|---|---|---|---|
| `agent.gov` | 1 | 政府（国库） | 是 |
| `agent.cell.<region>.<sector>` | 16 | 生产单元（市场生产者），物理量与财务量同一主体 | 是 |
| `agent.pubserv.<region>` | 4 | 公共服务非市场生产者，`sector.services` 的子账户 | **否**（其支付由 `agent.gov` 执行） |
| `agent.group.<region>.<age>.<skill>` | 36 | 36 个居民群组 | 是 |
| `agent.invpool` | 1 | 居民投资池（国债的国内对手方） | 是 |
| `agent.row` | 1 | 外部世界（Rest of World） | 是 |
| `agent.opening` | 1 | 开账对手方；开账完成后现金恒为 0，永不再参与交易 | 是（恒 0） |

持有现金的主体共 **55 个**。

> **裁定（生产的权威粒度）**：草案 A 用 16 个 `firm.<s>.<r>`；草案 B 用 16 个 cell 且财务也在 cell 级；
> 草案 C 把物理放 cell、财务留部门（4 个）。裁定取 **16 个 cell，物理与财务同体**。
> 理由：计划书 §05 的四地区开局约束（灌溉、电网、住房、环境）必须落到生产约束上才有东西可解释（B/C 一致）；
> 而 C 的「物理 cell / 财务部门」拆分会制造跨地区调货的现金与物流成本归属缝隙（C 自己登记为 OQ-02），
> 缝隙处最容易出现「既不违反不变量又不符合直觉」的账。信息更全可向下聚合，反之不可。

> **裁定（外部世界是显式主体）**：采用草案 A 的立场，`agent.row` 是完整账户主体并持有现金。
> 于是「全经济现金变动之和为 0」是真闭合检验，而不是「国内闭合、国外随便」。

### 2.2 科目表（chart of accounts）

科目 ID：`account.<agent_id>.<code>`；库存科目为 `account.<agent_id>.inv.<sector>`。

| 科目代码 | 中文名 | 方向 | 单位 | 适用主体 | 备注 |
|---|---|---|---|---|---|
| `cash` | 现金 | 资产 | μU | 见 §2.1 | 恒 ≥ 0（INV-016） |
| `inv.<sector>` | 产品库存 | 资产 | μU（**恒等于 1 000 × μQ_s 数值**，见 §2.3） | cell / gov / row | 4 个产品 |
| `wip` | 在建工程 | 资产 | μU | gov / cell | 已履约但未完工的累计支出 |
| `capital` | 已投运固定资产 | 资产 | μU | cell / pubserv / gov | 与产能台账挂钩 |
| `housing` | 住房资产 | 资产 | μU | gov / cell(services) | 公共住房与市场住房 |
| `recv` | 应收款（含应收未收税） | 资产 | μU | 全部 | — |
| `bondhold` | 持有的政府债券（面值口径） | 资产 | μU | invpool / row | — |
| `deposit_claim` | 对投资池的存款债权 | 资产 | μU | group | 与 invpool 的 `deposit_liab` 配对 |
| `pay` | 应付款／欠付 | 负债 | μU | 全部 | 计划书 §07「欠付另记」 |
| `debt` | 计息借款 | 负债 | μU | gov | **只含计息借款** |
| `deposit_liab` | 对居民的存款负债 | 负债 | μU | invpool | — |
| `nw` | 净值 | 平衡项 | μU | 全部 | 派生，不独立存储 |

### 2.3 库存计价规则（关键裁定）

**所有库存按基年价格 1 000 000 000 μU/Q_s 恒定计价。**

定义一个换算常量，全文与全部代码只用这一个：

```
BASE_VALUE_PER_UQS = BASE_PRICE / Q_SCALE = 1 000 000 000 / 1 000 000 = 1 000   # μU 每 μQ_s，整除，无余数
```

- 结果：`inv.<sector>` 科目的 μU 数值**恒等于 1 000 倍**的该产品库存数量 μQ_s 数值。
  一个数字乘一个常数的两种读法，数量账与价值账永不脱钩，也不需要任何成本流假设（先进先出／加权平均）。
  **这个 1 000 是精确整除出来的，换算不产生任何取整余数**，所以 R-14 的全部好处一点不少。
- 代价：不承认持有损益。买方付出的现金与入库价值之差记入买方的 `flow.cell.<c>.price_variance_uu`
  （= `mul_div_floor(qty_uqs, base_price, Q_SCALE) − paid_uu`，即 `1 000 × qty_uqs − paid_uu`，可正可负），
  当季结转入经营结果。
- **这不是国民账户标准做法**，是首版为换取整数精确对账而做的显式简化。
  它对 GDP 三法的影响不是 0，必须用 §9.3 的价差调节项显式对账，**不得假装残差为零**。

> **R-SCALE-01 同步警示（本节是整次刻度迁移里最容易漏改的一处）**：旧刻度下
> `BASE_PRICE / Q_SCALE = 1 000 000 / 1 000 000 = 1`，所以「μU 数值恒等于 μQ_s 数值」曾经字面成立，
> 于是全文与全部代码里出现过大量直接拿 `qty_uqs` 当金额用的写法（`price_variance = qty_uqs − value_uu` 就是其一）。
> 新刻度下该比值是 **1 000**，这些写法**每一处都会少算 1 000 倍**，而且因为量纲仍是 μU、数值仍是正整数，
> 它**不会触发任何溢出或区间检查**——只会安静地把价差调节项算错，让 INV-115 在一个看起来合理的数上失败。
> 凡遇到 `qty_uqs` 与 `_uu` 直接相减／相加／比较的表达式，一律先补 `mul_div_floor(·, base_price, Q_SCALE)`。

> **裁定（对草案 A 的一处纠正）**：草案 A 主张「三法由同一批分录分类汇总，残差由构造恒为 0」。
> 该主张在基年价计价下**不成立**：生产法用基年价计存货与中间消耗，支出法用现价计最终需求，
> 两者相差恰好等于全部入库交易的价差之和。本文件保留 A 的「分类法」（因为它使覆盖性可检查），
> 但把恒等式改写为 `gdp_expenditure == gdp_production + price_variance_total`（INV-115），
> 并要求该调节项**逐笔可追溯**（INV-119）。详见 §9.3 的推导。

### 2.4 居民投资池 `agent.invpool`

政府债券的国内对手方。它不是银行：**不创造货币**，只把居民存款转换成持债。

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.invpool.cash_uu` | 投资池现金 | S | μU | ≥ 0 | 剧本 | S02, S06 | INV-016, INV-024 |
| `state.invpool.bondhold_uu` | 投资池持债（面值口径） | S | μU | ≥ 0 | 剧本（= Σ holder==invpool 的未偿本金） | S02 | INV-024, INV-025 |
| `state.invpool.deposit_liab_uu` | 对居民的存款负债 | S | μU | ≥ 0 | 剧本 | S06 | **INV-024** |
| `flow.invpool.interest_received_uu` | 本季收到的债券利息 | F | μU | ≥ 0 | — | S02 | INV-036 |
| `flow.invpool.interest_distributed_uu` | 本季分配给群组的利息 | F | μU | ≥ 0 | — | S06 | INV-024 |

`INV-024` 的完整形式：`Σ_g state.group.deposit_uu == state.invpool.deposit_liab_uu
== state.invpool.cash_uu + state.invpool.bondhold_uu`，逐季精确成立。
利息按各组 `deposit_uu` 份额用最大余数法分回 `flow.group.property_income_uu`，
`Σ interest_distributed == Σ interest_received`（精确，S06）。

### 2.5 账本条目

账本是可测试性的核心：**所有钱的移动只有一条通路** `post()`（12 号文件 §0.2）。
一次 `post()` 产生一笔 `txn`，含 ≥ 2 条**有符号**过账行；行存储为列式平行数组。

| 列 | 稳定 ID | 含义 | 类型 |
|---|---|---|---|
| 0 | `log.ledger.txn_id[]` | 交易号 `txn.<qqq>.<nnnnnn>`（存为整数对） | int64 |
| 1 | `log.ledger.q[]` | 季度 | int64 |
| 2 | `log.ledger.step[]` | 产生步骤 1..8 | int64 |
| 3 | `log.ledger.kind[]` | 交易类型码（见 11 号文件 §5.3） | int64 |
| 4 | `log.ledger.account[]` | 科目下标 | int64 |
| 5 | `log.ledger.delta_uu[]` | 有符号金额（资产增 +，负债增 −） | int64 |
| 6 | `log.ledger.qty_uqs[]` | 关联数量（有符号，可为 0） | int64 |
| 7 | `log.ledger.product[]` | 关联产品下标（−1 表示无） | int64 |
| 8 | `log.ledger.cause[]` | 来源操作码（政策／项目／事件／冲击／规则） | int64 |
| 9 | `log.ledger.entity_ref[]` | 相关实体下标（项目／债券／群组／政策） | int64 |
| 10 | `log.ledger.prod_class[]` | 生产法分类码（含 `none`） | int64 |
| 11 | `log.ledger.exp_class[]` | 支出法分类码（含 `none`） | int64 |
| 12 | `log.ledger.inc_class[]` | 收入法分类码（含 `none`） | int64 |

**展示文案不进日志**。日志只有整数；文案由 Presentation 用 `cause` 码查模板表生成。
这既满足计划书 §13「每条变化附带实体 ID、来源操作、金额／数量、时间和约束」，也保证 SimCore 零字符串。

其它日志通道（同为列式，见 §12）：`log.physical`、`log.rejections`、`log.arrears`、`log.constraint_diag`、
`log.rounding`、`log.clamp`、`log.rng`、`log.explanations`。

---

## 3 政府与债券

### 3.1 政府存量

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.gov.cash_uu` | 国库现金 | S | μU | **≥ 0** | 剧本 = 2 000 000 000（= 2 U） | S02,S04,S05,S06 | INV-016, INV-027 |
| `state.gov.arrears_uu` | 政府欠付（不计息） | S | μU | ≥ 0 | 0 | S02,S04,S06 | INV-030 |
| `state.gov.arrears_by_payee_uu[]` | 分收款方欠付 | S | μU | ≥ 0 | 0 | S02,S04,S06 | INV-030 |
| `state.gov.tax_receivable_uu` | 应收未收税 | S | μU | ≥ 0 | 0 | S06 | INV-031 |
| `state.gov.wip_uu` | 政府在建工程 | S | μU | ≥ 0 | 剧本 | S04,S07 | INV-092 |
| `state.gov.capital_uu` | 政府已投运资产 | S | μU | ≥ 0 | 剧本 | S06,S07 | INV-020 |
| `state.gov.housing_uu` | 公共住房资产 | S | μU | ≥ 0 | 剧本 | S07 | INV-083 |
| `state.gov.committed_memo_uu` | 已签合同未来承诺 | memo | μU | ≥ 0 | 剧本 | S02,S04,S07 | INV-032 |
| `state.gov.reserved_memo_uu` | 本季已预留资金 | memo | μU | 0..cash | 0 | S02,S04 | INV-033 |
| `state.gov.credit_limit_domestic_memo_uu` | 国内融资额度（**增量额度**，同 §8.4） | memo | μU | ≥ 0 | 剧本 | S02 | INV-034 |
| `state.gov.service_opex_committed_uu` | 已投运服务的每季运行费义务 | S | μU/季 | ≥ 0 | 剧本 | S07 | INV-102 |
| `state.gov.tax_capacity_ppm` | 征收能力 | S | ppm | 0..1 000 000 | 剧本 | S07（P11） | INV-031 |
| `state.gov.tax_capacity_built_ppm` | 征收能力建成水平（P11 落点抬到的最高值；断供后回升上限，R-P11-02） | S | ppm | [基年值, 1 000 000] | 剧本（== 基年征收能力） | S07（P11） | — |
| `state.gov.receipts_annualized_uu` | 上季经常性收入 × 4（§2.6 偿债率分母；R-DSR-01） | S | μU | ≥ 0 | 剧本（年度计划收入） | S06 | INV-038 |
| `state.gov.payment_priority[]` | 支付优先级序列 | S | 枚举×8 | 8 类的一个全排列 | 剧本 | CMD→S02 | INV-039 |
| `state.gov.deferral_flag[]` | 各科目本季延期标记 | S | 0/1 | — | 0 | S02,S04 | — |
| `state.gov.rounding_residual_uu` | 取整余数登记账 | S | μU | 任意 | 0 | S02,S04,S05,S06 | INV-005 |
| `derived.gov.debt_uu` | 计息债务余额 | D | μU | ≥ 0 | — | DERIVED | INV-028, INV-035 |

### 3.2 政府流量（每季 S01 清零）

| 稳定 ID | 中文名 | 单位 | 维度 | 写入者 | 不变量 |
|---|---|---|---|---|---|
| `flow.gov.receipts_income_tax_uu` | 个人所得税 | μU | 全国／群组 | S06 | INV-027 |
| `flow.gov.receipts_profit_tax_uu` | 企业利润税 | μU | 全国／cell | S06 | INV-027 |
| `flow.gov.receipts_other_uu` | 其它收入（公共服务收费等） | μU | 全国 | S05,S06 | INV-027 |
| `flow.gov.new_borrowing_uu` | 新增借款 | μU | 全国 | S02 | INV-027, INV-029 |
| `flow.gov.primary_paid_uu` | 基本支出实付（不含利息与本金） | μU | 全国 | S04,S05 | INV-027 |
| `flow.gov.interest_paid_uu` | 利息实付 | μU | 全国／批次 | S02 | INV-027, INV-036 |
| `flow.gov.principal_paid_uu` | 还本实付 | μU | 全国／批次 | S02 | INV-027, INV-028, INV-029 |
| `flow.gov.recognized_writeoffs_uu` | 确认减记 | μU | 全国／批次 | S02 | INV-028 |
| `flow.gov.pay_public_wages_uu` | 公共部门工资 | μU | 地区 | S04 | INV-101 |
| `flow.gov.pay_transfers_uu[]` | 法定转移（P03 等） | μU | 群组 | S04 | INV-003 |
| `flow.gov.pay_subsidies_uu[]` | 企业补助（P09） | μU | cell | S04 | INV-097, INV-113 |
| `flow.gov.pay_project_uu[]` | 项目履约付款 | μU | 项目 | S04 | INV-087, INV-092 |
| `flow.gov.pay_opex_uu[]` | 已投运服务运行费 | μU | 地区×服务 | S04 | INV-102 |
| `flow.gov.pay_procurement_uu` | 政府采购（商品与服务） | μU | 部门 | S05 | INV-062 |
| `flow.gov.arrears_added_uu` | 本季新增欠付 | μU | 收款方 | S02,S04,S06 | INV-030 |
| `flow.gov.arrears_cleared_uu` | 本季清偿欠付 | μU | 收款方 | S02,S04 | INV-030 |
| `flow.gov.nonmarket_output_uu` | 公共非市场产出（按成本） | μU | 地区 | S06 | INV-101 |
| `flow.gov.final_consumption_uu` | 政府最终消费（支出法 G） | μU | 全国 | S06 | INV-115 |
| `flow.gov.gross_capital_formation_uu` | 政府资本形成 | μU | 全国 | S06 | INV-115 |

### 3.3 债券批次（SoA，只增不删）

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|
| `state.bond.id[]` | 批次 ID | S | 字符串 | `bond.q<qqq>_<nn>` | LOAD,S02 | INV-010 |
| `state.bond.issue_q[]` | 发行季 | S | 季 | 开局存量债为负 | LOAD,S02 | — |
| `state.bond.principal_initial_uu[]` | 发行本金 | S | μU | > 0 | LOAD,S02 | INV-028 |
| `state.bond.principal_outstanding_uu[]` | 未偿本金 | S | μU | 0..initial | S02 | INV-028, INV-035 |
| `state.bond.coupon_ppm_per_q[]` | 季度票息率 | S | ppm/季 | 0..100 000 | **仅发行时** | INV-036 |
| `state.bond.maturity_q[]` | 到期季 | S | 季 | > `issue_q` | LOAD,S02 | INV-037 |
| `state.bond.amortization[]` | 摊还方式 | S | `bullet\|level_principal` | — | LOAD,S02 | INV-037 |
| `state.bond.holder[]` | 债权人 | S | `invpool\|row` | — | LOAD,S02 | INV-025, INV-034 |
| `state.bond.status[]` | 状态 | S | `active\|matured\|defaulted\|restructured\|written_off` | `active` | S02 | INV-035 |
| `state.bond.accrued_unpaid_interest_uu[]` | 已计未付利息 | S | μU | ≥ 0 | S02 | INV-030 |
| `state.bond.interest_remainder_ppmuu[]` | 票息取整余数累加器 | S | μU·ppm | 0..999 999 | S02 | INV-004, INV-041 |
| `state.bond.writeoff_uu[]` | 累计减记 | S | μU | ≥ 0 | S02 | INV-028 |
| `flow.bond.interest_due_uu[]` | 本季应付利息 | F | μU | ≥ 0 | S02 | INV-036 |
| `flow.bond.principal_due_uu[]` | 本季应还本金 | F | μU | ≥ 0 | S02 | INV-037 |

> **裁定（利息与还本在哪一步）**：草案 A 把利息放 S06，草案 B/C 放 S02。计划书 §13 第 02 步明写
> 「处理到期债务」。裁定采用 **S02**，`flow.gov.interest_paid_uu` 与 `principal_paid_uu` 的唯一写入者是 S02；
> S06 只做恒等式终检（INV-027）。

> **裁定（票息取整余数）**：草案 A 主张 floor 丢弃，草案 B/C 主张余数累加结转。
> 票息是**对存量按率计提并形成持续债权债务**，余数是真实的分数义务，丢弃会在 120 季里系统性少付。
> 裁定采用累加器结转（§0.9 的「计提」类），并限定**首版只有票息适用此条**，避免累加器泛滥。

---

## 4 生产单元 `cell.<region>.<sector>`（16 个）

### 4.1 产能与资本

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.cell.capacity_active_uqs_per_q[]` | 在用产能 | S | μQ_s/季 | ≥ 0 | 剧本 | **S01**（转入）, S06（折旧） | INV-054, INV-056 |
| `state.cell.capacity_pending_uqs_per_q[]` | 待投运产能 | S | μQ_s/季 | ≥ 0 | 0 | S07（完工写入） | INV-054, INV-091 |
| `state.cell.capital_value_uu[]` | 生产资本账面值 | S | μU | ≥ 0 | 剧本 | S06（折旧）, S07（投运） | INV-020, INV-056 |
| `state.cell.wip_uu[]` | 企业在建工程 | S | μU | ≥ 0 | 0 | S05,S07 | INV-092 |
| `state.cell.maintenance_backlog_ppm[]` | 维护欠账 | S | ppm | 0..上限参数 | 0 | S07 | INV-055 |

> **裁定（「当季完工资产下一季才供能」的落点）**：草案 A 用 S01 快照 `capital_effective`；
> 草案 B 用 S01 做 `pending → active`；草案 C 用 S07 末 swap。
> 裁定取 **A + B 的合并形式**：S07 只写 `capacity_pending`，S01 执行
> `capacity_active += capacity_pending; capacity_pending = 0`。
> 理由：(a) `capacity_active` 的**增量写入点全局唯一**（A 的纪律），完工事件在结构上够不到它；
> (b) pending 缓冲让「本季完工量」是一个可被断言的独立字段（B/C 的可测性）；
> (c) C 的「S07 末 swap」依赖「S05 在 S07 之前」这一隐含顺序，一旦将来插入步骤就会静默失效，故不取。

### 4.2 物理流量与库存

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|
| `state.cell.demand_expect_uqs[]` | 需求预期（跨季平滑量，存档必含） | S | μQ_s | ≥ 0 | 剧本 | S03 | INV-043 |
| `flow.cell.output_plan_uqs[]` | 计划产量 | F | μQ_s | ≥ 0 | S03 | INV-043 |
| `flow.cell.bound_plan_uqs[]` | 约束值·计划 | F | μQ_s | ≥ 0 | S05 | INV-043, INV-045 |
| `flow.cell.bound_capacity_uqs[]` | 约束值·产能 | F | μQ_s | ≥ 0 | S05 | 同上 |
| `flow.cell.bound_labor_uqs[]` | 约束值·劳动 | F | μQ_s | ≥ 0 | S05 | 同上 |
| `flow.cell.bound_energy_uqs[]` | 约束值·能源 | F | μQ_s | ≥ 0 或 `SENTINEL` | S05 | INV-044 |
| `flow.cell.bound_materials_uqs[]` | 约束值·材料 | F | μQ_s | ≥ 0 或 `SENTINEL` | S05 | INV-044 |
| `flow.cell.binding_code[]` | 本季最紧约束 | F | 0 计划/1 产能/2 劳动/3 能源/4 材料 | — | S05 | INV-045 |
| `flow.cell.output_actual_uqs[]` | 实际产量 | F | μQ_s | ≥ 0 | S05 | INV-043, INV-047 |
| `state.cell.inventory_output_uqs[]` | 成品库存 | S | μQ_s | ≥ 0 | 剧本 / S05 | INV-047, INV-048, INV-049 |
| `state.cell.inventory_input_uqs[]` | 投入品库存（64 = 16×4） | S | μQ_s(j) | ≥ 0 | 剧本 / S05 | INV-047, INV-050 |
| `flow.cell.consumed_input_uqs[]` | 本季生产耗用（64） | F | μQ_s(j) | ≥ 0 | S05 | INV-046, INV-047 |
| `flow.cell.purchased_input_uqs[]` | 本季购入投入（64） | F | μQ_s(j) | ≥ 0 | S05 | INV-047, INV-050 |
| `flow.cell.sold_uqs[]` | 本季售出 | F | μQ_s | ≥ 0 | S05 | INV-047, INV-059 |
| `flow.cell.spoilage_uqs[]` | 损耗 | F | μQ_s | ≥ 0 | S05 | INV-047, INV-053 |
| `flow.cell.unmet_demand_uqs[]` | 未满足需求 | F | μQ_s | ≥ 0 | S05 | INV-059, INV-064 |
| `flow.cell.energy_allocated_uqs[]` | 本季获配电力 | F | μQ_energy | ≥ 0 | S05 | INV-051, INV-060 |
| `flow.cell.energy_unused_uqs[]` | 当季作废电力 | F | μQ_energy | ≥ 0 | S05 | INV-051 |
| `flow.region.emissions_uqe[]` | 本季排放 | F | μQ_e | ≥ 0 | S05 | INV-057 |

### 4.3 就业

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.cell.employment_persons[]` | 在岗人数（48 = 16×3） | S | 人 | ≥ 0 | 剧本 | S03, S07 | INV-076, INV-077, INV-080 |
| `flow.cell.hires_persons[]` | 本季招聘（48） | F | 人 | ≥ 0 | S03 | INV-080 |
| `flow.cell.separations_persons[]` | 本季离岗（48） | F | 人 | ≥ 0 | S03, S07 | INV-080 |
| `flow.cell.wage_bill_uu[]` | 工资总额 | F | μU | ≥ 0 | S04 | INV-079 |

> **裁定（就业的写入者）**：草案 B 允许 S04 在「付不起工资」时二次写 `employed`，自己也登记为风险 Q-SIM-07。
> 裁定**不允许**：招工与裁员只在 S03 决定，且 S03 内已含「工资资金闸」（草案 A/C 一致）。
> S07 可以减少在岗人数，但**只能作为人口流出（死亡、退休、迁出）的配对后果**，且减少量必须精确等于
> 该 cell 对应群组的流出就业人数（INV-080）。这保证「同一季两次写入不会互相放大」。

### 4.4 财务流量

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|
| `state.cell.cash_uu[]` | 经营现金 | S | μU | ≥ 0 | 剧本 / S02,S04,S05,S06 | INV-016 |
| `state.cell.loss_carryforward_uu[]` | 结转亏损 | S | μU | ≥ 0 | 0 / S06 | INV-116 |
| `flow.cell.gross_output_uu[]` | 总产出（名义） | F | μU | ≥ 0 | S06 | INV-111 |
| `flow.cell.intermediate_uu[]` | 中间投入（名义） | F | μU | ≥ 0 | S06 | INV-111, INV-053 |
| `flow.cell.value_added_uu[]` | 增加值（名义） | F | μU | 可为负 | S06 | INV-111, INV-112 |
| `flow.cell.value_added_real_uu[]` | 增加值（基年价） | F | μU | 可为负 | S06 | INV-117 |
| `flow.cell.price_variance_uu[]` | 采购价差 | F | μU | 可正可负 | S05 | INV-115, INV-119 |
| `flow.cell.depreciation_uu[]` | 价值折旧 | F | μU | ≥ 0 | S06 | INV-056 |
| `flow.cell.depreciation_uqs_per_q[]` | 产能折旧 | F | μQ_s/季 | ≥ 0 | S06 | INV-056 |
| `flow.cell.operating_surplus_uu[]` | 营业盈余（含固定资本消耗） | F | μU | 可为负 | S06 | INV-116 |
| `flow.cell.profit_pretax_uu[]` | 税前利润 | F | μU | 可为负 | S06 | INV-116 |
| `flow.cell.tax_profit_paid_uu[]` | 已缴利润税 | F | μU | ≥ 0 | S06 | INV-031 |
| `flow.cell.distributed_uu[]` | 向居民分配的财产收入 | F | μU | ≥ 0 | S06 | INV-086 |
| `flow.cell.subsidy_received_uu[]` | 收到的补助 | F | μU | ≥ 0 | S04 | INV-113 |
| `flow.cell.investment_uu[]` | 本季投资支出 | F | μU | ≥ 0 | S05 | INV-092, INV-115 |
| `flow.cell.invest_intent_uu[]` | 扩产意愿额 | F | μU | ≥ 0 | S03 | INV-116 |

### 4.5 技术系数（内容包只读）

| 稳定 ID | 中文名 | 单位 | 长度 | 区间 | 说明 |
|---|---|---|---|---|---|
| `content.io.io_coeff_uqs_per_qs[]` | 投入产出系数 a(from→to) | μQ_from / Q_to | 16 | ≥ 0 | `== 0` ⇒ 跳过该约束，不做除零 |
| `content.io.labor_coeff_persons_per_qs[]` | 分技能单位产品用工 | 人 / Q_s | 48 = 16×3 | ≥ 0 | `== 0` ⇒ 跳过该技能档 |
| `content.io.energy_coeff_uqs_per_qs[]` | 单位产品耗电 | μQ_energy / Q_s | 16 | ≥ 0 | `== 0` ⇒ 跳过 |
| `content.io.spoilage_ppm[]` | 季度库存损耗率 | ppm | 4 | 0..100 000 | 计入中间消耗（INV-053） |
| `content.io.depreciation_ppm_per_q[]` | 季度折旧率 | ppm | 4 | 0..100 000 | 产能轨与价值轨同率 |
| `content.io.capacity_per_capital_uu_ppm[]` | 每 μU 资本形成的产能 | μQ_s/季 每 μU | 4 | > 0 | **只在投运时使用一次**；R-SCALE-01 下值已 ÷1 000，见下方注 |
| `content.io.emission_ppm[]` | 单位产量排放系数 | ppm | 4 | ≥ 0 | — |
| `content.storable[]` | 产出是否可库存 | 0/1 | 4 | — | `sector.energy` 与 `sector.services` 必须为 0 |

> **R-SCALE-01 同步（分母带 μU 的系数方向相反）**：本表只有 `capacity_per_capital_uu_ppm` 的**分母是 μU**。
> μU 变细 1 000 倍 ⇒ 同样一笔真实资本对应的 μU 数字大了 1 000 倍 ⇒ 该系数必须 **÷1 000** 才能维持同一物理关系。
> 内容层已改为 `[200, 180, 55, 160]`（四个值均能整除，迁移无精度损失）。
> **这是整份契约里唯一一个「跟着货币刻度反向走」的系数**，也是迁移器按键名 ×1 000 的规则唯一够不到的一类，
> 因此在此显式登记，不靠读者推断。
> 代价：该系数现在只有约 0.5%～1.8% 的整数粒度。若基年重拟合需要更细的控制，
> 应提出契约修订（改为「每 10³ μU」口径并同步改名），**不得私自另立第二套比率刻度**。

> **裁定（资本双轨）**：草案 B 主张产能轨与价值轨互不换算、允许比例漂移；草案 C 要求两者永远同源。
> 整数 floor 下「永远同源」不可实现（每季都会累积取整差）。裁定取 **B 的双轨 + C 的载入期一致性检查**：
> 两轨用**同一个** `depreciation_ppm_per_q`；只在**载入期**与**投运瞬间**要求
> `|capacity − mul_ppm(capital_value_uu, capacity_per_capital_uu_ppm)| ≤ 1 μQ_s`
> （新刻度下 `capital_value_uu` 可达 `AMOUNT_MAX`，**不得写成裸乘再除 1e6**，见 §13 M1）；此后允许漂移，
> 由诊断指标 `derived.cell.capacity_value_drift_ppm` 监测，漂移超阈值只报警不改数。登记为 OQ-206。

> **裁定（技能替代）**：草案 A 提供 `skill_substitution_ppm` 允许向下替代；草案 B 用 `skill_mix` 分档配给
> （实质不替代）；草案 C 明确禁止替代。裁定 **首版不允许技能替代**：错配直接压低 `bound_labor`。
> 理由：替代矩阵是三份草案里唯一没有任何计划书依据的自创机制，且会让「技能错配」失去可观察性。
> 替代规则留待校准阶段按证据引入（OQ-207）。

---

## 5 公共服务 `pubserv.<region>`（4 个）

`sector.services` 的**非市场子账户**（计划书 §03），不走市场销售，产出按成本计价进 GDP。

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.pubserv.capacity_active_uqs_per_q[]` | 服务容量（在用） | S | μQ_services/季 | ≥ 0 | 剧本 | S01（转入）, S06（折旧） | INV-102 |
| `state.pubserv.capacity_pending_uqs_per_q[]` | 待投运容量 | S | μQ_services/季 | ≥ 0 | 0 | S07 | INV-091 |
| `state.pubserv.capital_value_uu[]` | 资产账面值 | S | μU | ≥ 0 | 剧本 | S06,S07 | INV-020 |
| `state.pubserv.availability_ppm[]` | 实际可用率 | S | ppm | 0..1 000 000 | 1 000 000 | S07 | INV-102 |
| `state.pubserv.employment_persons[]` | 公共部门在职（4×3） | S | 人 | ≥ 0 | 剧本 | S03, S07 | INV-076, INV-077 |
| `state.pubserv.establishment_persons[]` | 公共部门编制（补员上限，R-PUBSTAFF-01） | S | 人 | ≥ 0 | 剧本（开局在岗） | S03 | INV-076 |
| `state.pubserv.teachers_persons[]` | 在岗教师 | S | 人 | ≥ 0 | 剧本 | S03, S07 | INV-081 |
| `state.pubserv.health_staff_persons[]` | 在岗医护 | S | 人 | ≥ 0 | 剧本 | S03, S07 | INV-103 |
| `state.pubserv.queue_persons[]` | 排队人数（按服务种类） | S | 人 | ≥ 0 | 0 | S05 | INV-103 |
| `flow.pubserv.funding_ratio_ppm[]` | 本季拨款到位率 | F | ppm | 0..1 000 000 | — | S04 | INV-102 |
| `flow.pubserv.delivered_uqs[]` | 实际交付服务量 | F | μQ_services | ≥ 0 | — | S05 | INV-103 |
| `flow.pubserv.wage_bill_uu[]` | 公共部门工资 | F | μU | ≥ 0 | — | S04 | INV-101 |
| `flow.pubserv.intermediate_uu[]` | 中间消耗 | F | μU | ≥ 0 | — | S05 | INV-101 |
| `flow.pubserv.depreciation_uu[]` | 固定资本消耗 | F | μU | ≥ 0 | — | S06 | INV-101 |
| `flow.pubserv.output_uu[]` | 非市场产出（成本计价） | F | μU | ≥ 0 | — | S06 | INV-101 |

---

## 6 人口群组 `group.<region>.<age>.<skill>`（36 个）

`minor` 档的 `skill` 表示**教育准备程度**，不表示劳动技能（计划书 §08）。允许空组，空组仍参与全部恒等式检查。

### 6.1 人口与流动

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.group.population_persons[]` | 人口 | S | 人 | ≥ 0 | 剧本 | S07 | INV-071, INV-072 |
| `state.group.participation_ppm[]` | 劳动参与率 | S | ppm | 0..1 000 000（非 working 组必须 0） | 剧本 | S07 | INV-074, INV-075 |
| `state.group.employed_persons[]` | 分部门在岗（36×5：4 部门 + pubserv） | S | 人 | ≥ 0 | 剧本 | S03, S07 | INV-077 |
| `flow.group.births_persons[]` | 出生（流入 `minor.low`） | F | 人 | ≥ 0 | — | S07 | INV-071, INV-072 |
| `flow.group.deaths_persons[]` | 死亡 | F | 人 | ≥ 0 | — | S07 | INV-071, INV-072 |
| `flow.group.age_in_persons[]` / `age_out_persons[]` | 成年／退休转入转出 | F | 人 | ≥ 0 | — | S07 | INV-072, INV-074 |
| `flow.group.skill_in_persons[]` / `skill_out_persons[]` | 技能档转入转出 | F | 人 | ≥ 0 | — | S07 | INV-072, INV-082 |
| `flow.group.migrate_flow_persons[]` | 迁移流（来源组→去向组，稀疏列式） | F | 人 | ≥ 0 | — | S07 | INV-073 |
| `flow.group.migrate_rejected_persons[]` | 被住房／成本挡回 | F | 人 | ≥ 0 | — | S07 | INV-084 |
| `state.group.education_cohort_persons[]` | 结业队列（36×8 季槽） | S | 人 | ≥ 0 | 0 | S07 | INV-081, INV-082 |
| `derived.group.labor_force_persons[]` | 劳动力 | D | 人 | ≥ 0 | — | DERIVED | INV-075 |
| `derived.group.unemployed_persons[]` | 失业人数 | D | 人 | ≥ 0 | — | DERIVED | INV-075 |

### 6.2 收入、消费、储蓄

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|
| `state.group.cash_uu[]` | 群组现金 | S | μU | ≥ 0 | 剧本 / S04,S05,S06,S07 | INV-016 |
| `state.group.deposit_uu[]` | 投资池存款债权 | S | μU | ≥ 0 | 剧本 / S06 | INV-024 |
| `flow.group.wage_income_uu[]` | 工资收入 | F | μU | ≥ 0 | S04 | INV-079, INV-086 |
| `flow.group.transfer_income_uu[]` | 转移收入（失业保障等） | F | μU | ≥ 0 | S04 | INV-086 |
| `flow.group.support_in_uu[]` / `support_out_uu[]` | 组间赡养转移（收／付） | F | μU | ≥ 0 | S04 | **INV-085** |
| `flow.group.property_income_uu[]` | 财产收入（企业分配 + 存款利息） | F | μU | ≥ 0 | S06 | INV-086 |
| `flow.group.income_tax_paid_uu[]` | 已缴个税 | F | μU | ≥ 0 | S06 | INV-031 |
| `flow.group.fees_paid_uu[]` | 公共服务收费（R-FEE-01，可支配收入扣减项） | μU | 群组 | S06 | INV-086 |
| `flow.group.consumption_uu[]` | 消费支出合计 | F | μU | ≥ 0 | S05 | INV-063 |
| `flow.group.consumption_by_product_uu[]` | 分产品消费支出（36×4） | F | μU | ≥ 0 | S05 | INV-062 |
| `flow.group.consumption_by_product_uqs[]` | 分产品消费量（36×4） | F | μQ_s | ≥ 0 | S05 | INV-059 |
| `flow.group.housing_cost_uu[]` | 住房支出 | F | μU | ≥ 0 | S05 | INV-083 |
| `flow.group.unmet_consumption_uu[]` | 因配给未实现的消费 | F | μU | ≥ 0 | S05 | INV-064 |
| `flow.group.savings_uu[]` | 储蓄 | F | μU | 可为负 | S06 | **INV-086** |
| `derived.group.disposable_income_uu[]` | 可支配收入 | D | μU | 可为负 | DERIVED | INV-086 |

> **裁定（未成年与老年组的消费资金来源）**：只有草案 A 处理了这个问题。
> 裁定采用 A 的方案：**显式的组间赡养转移**，双边入账，`Σ support_in == Σ support_out`（INV-085），
> 默认只在同一地区内发生（跨地区赡养首版设 0，OQ-208）。
> 不允许「未成年／老年组的消费能力凭空出现」这类隐性补贴。

### 6.3 生活、住房、服务与态度

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.group.housing_units_occupied[]` | 占用住房 | S | 套 | ≥ 0 | 剧本 | S07 | INV-083 |
| `state.group.service_access_ppm[]` | 服务可及性（36×3：医疗／教育／公用） | S | ppm | 0..1 000 000 | 剧本（**各组可以不同**） | S07 | INV-103 |
| `content.group.base_service_access_ppm[]` | 基年服务可及性基准（3：医疗／教育／公用） | C | ppm | 0..1 000 000 | 载入期按人口加权算出 | **LOAD（此后只读）** | INV-103 |
| `state.group.consumption_index_ppm[]` | 实际消费指数 | S | ppm | ≥ 0 | 剧本 = 1 000 000 | S07 | INV-149 |
| `state.group.living_index_ppm[]` | 当期生活指数 | S | ppm | ≥ 0 | 剧本 = 1 000 000 | S08 | INV-121 |
| `state.group.expectation_ppm[]` | 未来预期 | S | ppm | 0..2 000 000 | 剧本 | S08 | INV-121 |
| `state.group.trust_ppm[]` | 程序信任 | S | ppm | 0..1 000 000 | 剧本 | S08 | INV-121, INV-122 |
| `state.group.support_ppm[]` | 对执政团队支持度 | S | ppm | 0..1 000 000 | 剧本 | S08 | INV-123, INV-124 |
| `state.group.base_living_index_ppm[]` | 生活指数基准（第 0 季结算后锚定，R-SUPPORT-02） | S | ppm | 0..LIVING_MAX | 剧本→第 0 季锚定 | S08(q=0) | INV-123 |
| `state.group.base_expectation_ppm[]` | 未来预期基准（同上） | S | ppm | 0..EXPECTATION_MAX | 剧本→第 0 季锚定 | S08(q=0) | INV-123 |
| `state.group.base_trust_ppm[]` | 程序信任基准（同上） | S | ppm | 0..1 000 000 | 剧本→第 0 季锚定 | S08(q=0) | INV-123 |
| `derived.group.housing_burden_ppm[]` | 住房负担率 | D | ppm | ≥ 0 | — | DERIVED | INV-083 |

**民生基线口径（计划书 §05）**：`state.group.consumption_index_ppm` 与 `derived.living.public_service_index_ppm`
的**基期全国人口加权值恒为 1 000 000**，展示为 100.0。这是**相对基准**；
报告与 UI 中禁止出现「国际排名」「世界第 N」措辞（静态文案检查，INV-149）。

> **裁定 R-ACCESS-01（`service_access_ppm` 的区间与恒等式二选一，已执行）**
>
> **`state.group.service_access_ppm` 不在上述加权恒等式之列。** 原先本节要求它的基期人口加权值也恒为 1 000 000，
> 而本节同时规定它的区间是 `0…1 000 000`。两条联立**只有一个解**：36 组全取 1 000 000。
> 后果有二：(a) 任何形如 `{health: 620000, …}` 的剧本示例在载入期必然失败；
> (b) **开局的服务可及性不平等被彻底抹平**，与计划书 §08「保留受益和受损的分布」直接冲突。
> 两条都要，就等于要求一个空集；这不是参数没配好，是两条约束互斥。
>
> **裁定：删除加权恒等式，保留区间。** `service_access_ppm` 的语义就是「相对自身基准的可及率」，
> 区间 `0…1 000 000` 保留，**各组可以不同**，基年即可承载地区与技能间的服务不平等。
> 对应地，`11_data_contract.md` 的 `V-POP-07` 中关于服务可及性的那一项已被删除（`consumption_index_ppm`
> 与 `living_index_ppm` 两项不受影响，仍然要求加权值 == 1 000 000）。
>
> **两张清单不要混**：上面「民生基线口径」段落说的是**计划书 §05 的两个展示指数**
> （`consumption_index_ppm` 与 `derived.living.public_service_index_ppm`，由 INV-149 检查）；
> `V-POP-07` 说的是**剧本载入期的三个群组字段**（`consumption_index_ppm`、`living_index_ppm`、
> 原先还有服务可及性）。R-ACCESS-01 只从后者删掉服务可及性那一项，前者一个字没动——
> `derived.living.public_service_index_ppm` 是按**实际交付量**算的全国指数，
> 与按组存储的 `service_access_ppm` 是两个不同的量，不要因为都叫「服务」就合并。
>
> **`content.group.base_service_access_ppm[]`（新增，只读）**：长度 3，按服务种类（0 医疗 / 1 教育 / 2 公用）。
> 载入期由 36 组的 `service_access_ppm` 按 `population_persons` 加权（最大余数法，INV-124 同款）算出，
> **此后任何一步都不得写它**。它的唯一用途是给后续季度做**相对比较的分母**：
> 「全国服务可及性比基年好了还是差了」问的是 `Σ_g pop_g · access_g / Σ_g pop_g` 与它的比值，
> 而不是与常数 1 000 000 的比值——恒等式删掉之后，基年加权值不再必然是 1 000 000，必须把它记下来。
> **它不单独进 `content_hash`**（其全部输入已在内容包内，再哈希一遍等于制造第二个事实来源），
> 也不进 `state_hash`（它是 `content.*`，见 §0.3 与 §11）；它由内容包唯一确定，因此重放不受影响。

---

## 7 地区 `region.<r>`（4 个）

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `content.region.adjacency[]` | 邻接矩阵（16） | C | 0/1 | 对称、对角 0 | 剧本 | LOAD | INV-150 |
| `content.region.logistics_cost_ppm[]` | 物流成本加成（16） | C | ppm | 0..1 000 000 | 剧本 | LOAD | INV-062 |
| `content.region.migration_cost_uu[]` | 迁移成本（16） | C | μU/人 | ≥ 0 | 剧本 | LOAD | INV-084 |
| `state.region.grid_capacity_uqs_per_q[]` | 电网输配容量 | S | μQ_energy/季 | ≥ 0 | 剧本 | S01, S06 | INV-051, INV-102 |
| `state.region.grid_capacity_pending_uqs_per_q[]` | 待投运电网容量 | S | μQ_energy/季 | ≥ 0 | 0 | S07 | INV-091 |
| `state.region.housing_capacity_units[]` | 住房容量 | S | 套 | ≥ 0 | 剧本 | S01, S07 | INV-083 |
| `state.region.housing_stock_units[]` | 住房存量 | S | 套 | ≤ capacity | 剧本 | S01, S07 | INV-083 |
| `state.region.housing_pending_units[]` | 待交付住房 | S | 套 | ≥ 0 | 0 | S07 | INV-091 |
| `state.region.irrigation_index_ppm[]` | 灌溉设施指数 | S | ppm | 0..2 000 000 | 剧本 | **S01**（转入） | P07 作用点；INV-091 |
| `state.region.irrigation_index_pending_ppm[]` | 待生效灌溉增量 | S | ppm | ≥ 0 | 0 | S07（完工写入） | INV-091 |
| `state.region.port_capacity_uqs_per_q[]` | 港口通行能力 | S | μQ/季 | ≥ 0 | 剧本 | **S01**（转入）, S06（折旧） | P08；INV-104 |
| `state.region.port_capacity_pending_uqs_per_q[]` | 待投运港口能力 | S | μQ/季 | ≥ 0 | 0 | S07（完工写入） | INV-091 |
| `state.region.construction_slots_total[]` | 施工队列槽位总数 | S | 槽 | 1..8 | 剧本 | S07 | INV-094 |
| `state.region.emissions_stock_uqe[]` | 累计排放 | S | μQ_e | ≥ 0 | 剧本 | S07 | INV-057 |
| `state.region.env_exposure_ppm[]` | 环境暴露指数 | S | ppm | 0..3 000 000 | 剧本 | S07 | INV-057 |
| `flow.region.construction_capacity_uqs[]` | 本季施工能力（由服务 cell **实际**产量折出） | F | μQ_services | ≥ 0 | — | **S05** | **INV-088** |
| `flow.region.construction_used_uqs[]` | 本季已占用施工能力 | F | μQ_services | ≥ 0 | — | S05 | INV-088 |
| `flow.region.electricity_supply_uqs[]` | 本季可供电力 | F | μQ_energy | ≥ 0 | — | S05 | INV-051 |
| `flow.region.electricity_demand_uqs[]` | 本季电力需求 | F | μQ_energy | ≥ 0 | — | S03 | INV-051 |
| `derived.region.population_persons[]` | 地区人口 | D | 人 | ≥ 0 | — | DERIVED | INV-141 |
| `derived.region.housing_occupied_units[]` | 已占用住房 | D | 套 | ≥ 0 | — | DERIVED | INV-083 |
| `derived.region.electricity_availability_ppm[]` | 电力可用率 | D | ppm | 0..1 000 000 | — | DERIVED | INV-051 |
| `derived.region.construction_slots_used[]` | 已占槽位 | D | 槽 | ≥ 0 | — | DERIVED | INV-094 |

> **裁定（施工能力的表达）**：草案 A 只有 μQ 施工能力（由服务部门产出份额派生），草案 B 用剧本给定的产能存量，
> 草案 C 只有整数槽位。裁定**两者并存**：
> (a) `flow.region.construction_capacity_uqs` —— **物理施工量**，由本地区 `cell.<r>.services` 的实际产量按
> `param.construction_share_cap_ppm` 上限折出，决定进度**推进多快**；
> (b) `state.region.construction_slots_total` —— **并发项目槽位**，决定同时能开工**多少个**。
> 两条约束各自对应一条可测的失败路径（进度停滞 vs 排队拥堵），缺一则「施工拥堵」只能被测出一种形态。

---

## 8 项目、政策、政治、外部世界

### 8.1 项目队列（SoA，只增不删）

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|
| `state.project.id[]` | 实例 ID | S | 字符串 | 唯一 | S02 | INV-010 |
| `state.project.policy_idx[]` | 来源政策 | S | int | 0..11 | S02 | INV-099 |
| `state.project.region_idx[]` | 所在地区 | S | int | 0..3 | S02 | — |
| `state.project.status[]` | 状态 | S | 枚举 `planned\|in_progress\|suspended\|completed\|commissioned\|cancelled` | `planned` | S01（completed→commissioned）,S02,S04,S05,S07 | INV-090 |
| `state.project.total_cost_uu[]` | 合同总额 | S | μU | > 0 | S02 | INV-092 |
| `state.project.planned_quarters[]` | 计划工期 | S | 季 | 1..24 | S02 | INV-092 |
| `state.project.spend_plan_uu[]` | 分季分项支出计划 | S | μU | ≥ 0 | S02 | INV-092 |
| `state.project.paid_uu[]` | 已付（分项） | S | μU | ≥ 0 | S04 | INV-087, INV-092 |
| `state.project.delivery_progress_ppm[]` | 交付进度 | S | ppm | 0..1 000 000 | S05 | INV-089, INV-090 |
| `state.project.construction_progress_ppm[]` | 施工进度 | S | ppm | 0..1 000 000 | S05 | **INV-087**, INV-088 |
| `state.project.required_construction_uqs[]` | 所需施工服务总量 | S | μQ_services | > 0 | S02 | INV-088 |
| `state.project.required_equipment_uqs[]` | 所需设备总量 | S | μQ_manu | ≥ 0 | S02 | INV-089 |
| `state.project.queue_slot_held[]` | 占用槽位 | S | 0/1 | — | S02, S07 | INV-094 |
| `state.project.capacity_effect_uqs_per_q[]` | 完工新增产能 | S | μQ/季 | ≥ 0 | S02 | INV-091 |
| `state.project.capacity_target[]` | 产能落点（编码目标数组与下标） | S | int | — | S02 | INV-091 |
| `state.project.opex_per_q_uu[]` | 投运后每季运行费 | S | μU | ≥ 0 | S02 | INV-102 |
| `state.project.commissioned_q[]` | 投运季 | S | 季 | ≥ 完工季 + 1，或 −1 | S01 | INV-091 |
| `state.project.residual_value_uu[]` | 未完工残值 | S | μU | ≥ 0 | S02, S07 | INV-093 |
| `state.project.cancel_penalty_uu[]` | 取消赔偿 | S | μU | ≥ 0 | S02 | INV-093 |
| `state.project.suspension_reason[]` | 中断原因码 | S | 枚举 `none\|financing\|delivery\|congestion\|fuel\|no_demand\|deferred` | S02,S04,S05 | INV-100 |
| `state.project.defer_count[]` | 已受理的延期次数（R-DEFER-01） | S | 次 | [0, `param.max_defer_count`] | S02 | INV-094 |
| `state.project.defer_quarters_total[]` | 各次延期季数之和 | S | 季 | [0, `param.max_defer_quarters`] | S02 | — |
| `state.project.defer_until_q[]` | 延期到期季（未延期 0） | S | 季 | ≥ 0 | S02 | — |
| `state.project.defer_fee_uu[]` | 累计延期赔偿（已付与转欠付之和） | S | μU | ≥ 0 | S02 | INV-016 |

### 8.2 政策状态（12 项）

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|
| `state.policy.enabled[]` | 是否生效 | S | 0/1 | — | S02 | INV-095 |
| `state.policy.enacted_q[]` | 通过季 | S | 季 | −1 未通过 | S02 | INV-095 |
| `state.policy.effective_from_q[]` | 生效季（含时滞） | S | 季 | ≥ `enacted_q + lag` | S02 | **INV-095**, INV-098 |
| `state.policy.params_ppm[]` / `params_uu[]` | 政策参数（12×4） | S | ppm / μU | 模板 `valid_range` | S02 | INV-099 |
| `state.policy.pending_params[]` | 已提交待生效参数 | S | 同上 | — | **CMD** | INV-138 |
| `state.policy.region_mask[]` | 作用地区位掩码 | S | int | 0..15 | S02 | — |
| `state.policy.budget_committed_uu[]` | 累计已承诺 | S | μU | ≥ 0 | S02 | INV-032 |
| `state.policy.budget_spent_uu[]` | 累计已支出 | S | μU | ≥ 0 | S04 | INV-096 |
| `state.policy.toggle_count[]` | 开关次数 | S | 计数 | ≥ 0 | S02 | INV-098 |
| `state.policy.cooldown_until_q[]` | 冷却截止 | S | 季 | ≥ 0 | S02 | INV-098 |
| `state.policy.claim_ledger[]` | 领取登记（防重领，稀疏 claim_key → 已付额） | S | μU | ≥ 0 | S04 | **INV-097** |
| `state.policy.exit_pending_q[]` | 退出倒计时 | S | 季 | −1 | S02 | — |
| `state.policy.opex_landed_uu[]` | 落点季并入长期运行费义务的每季额（累计；行政类撤回时清零，R-P10-01） | S | μU/季 | ≥ 0 | S02, S07 | — |
| `derived.policy.blocked_reason[]` | 无法执行原因码 | D | 枚举 | `none\|authority\|budget\|cooldown\|precondition\|queue\|exited` | DERIVED | **INV-100** |

### 8.3 政治与集团

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.politics.seats_total` | 总席位 | S | 席 | > 0，奇数 | 剧本 | LOAD | INV-126 |
| `state.politics.seats_gov` | 执政席位 | S | 席 | 0..`seats_total` | 剧本 | S08 | INV-126 |
| `state.politics.term_index` | 任期序号 | S | int | ≥ 0 | 0 | S08 | — |
| `state.politics.next_election_q` | 下次选举季 | S | 季 | ∈ {15, 31} | 剧本 | S08 | **INV-127** |
| `state.politics.next_budget_review_q` | 下次预算审查季 | S | 季 | `q ≡ 3 (mod 4)` | 剧本 | S02 | INV-127 |
| `flow.politics.budget_review_due` | 本季是否预算审查季 | F | 0/1 | — | 0 | S02 | INV-127 |
| `state.politics.mandate_goal` | 任期目标 | S | `industry\|livelihood\|fiscal` | — | 开局选择 | LOAD | — |
| `state.politics.mandate_status` | 留任资格 | S | `ok\|at_risk\|lost` | — | `ok` | S08 | INV-128 |
| `state.politics.admin_capacity_ppm` | 行政执行能力 | S | ppm | 0..1 000 000 | 剧本 | S07 | **INV-125** |
| `state.politics.legal_authority_mask` | 已获法定权限 | S | 位掩码 | — | 剧本 | S08 | INV-099 |
| `state.bloc.org_power_ppm[]` | 组织力（3） | S | ppm | 0..1 000 000 | 剧本 | S08 | INV-125, INV-129 |
| `state.bloc.stance_ppm[]` | 对各政策立场（3×12） | S | ppm | −1 000 000..1 000 000 | 剧本 | S08 | INV-125 |
| `state.bloc.resource_uu[]` | 集团资源（3） | S | μU | ≥ 0 | 剧本 | S08 | INV-129 |
| `content.bloc.veto_domains[]` | 可否决的改革域 | C | id 列表 | 固定 | 剧本 | LOAD | INV-099 |
| `derived.bloc.membership_persons[]` | 成员规模（加权人数） | D | 人 | ≥ 0 | — | DERIVED | INV-129 |
| `derived.politics.support_national_ppm` | 全国支持度 | D | ppm | 0..1 000 000 | — | DERIVED | **INV-124** |
| `derived.politics.support_region_ppm[]` | 地区支持度 | D | ppm | 0..1 000 000 | — | DERIVED | INV-124 |

### 8.4 外部世界（`agent.row` 的业务视图）

首版固定汇率，无外币债务与估值变动（计划书 §07）。

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `content.world.fx_rate_ppm` | 汇率 | C | ppm | **恒 1 000 000** | 常量 | 无（写入即 FAULT） | **INV-105** |
| `state.world.export_demand_ppm[]` | 出口需求指数（4） | S | ppm | ≥ 0 | 剧本 | S01（冲击） | INV-108 |
| `state.world.import_price_ppm[]` | 进口价格指数（4） | S | ppm | > 0 | 剧本 | S01（冲击） | INV-108 |
| `state.world.delivery_capacity_uqs[]` | 外部交付能力（4） | S | μQ_s/季 | ≥ 0 | 剧本 | S01 | **INV-104** |
| `state.world.credit_limit_uu` | 外部信用额度（**增量额度**，见下） | S | μU | ≥ 0 | 剧本 | S01, S02 | INV-034 |
| `state.world.credit_used_uu` | 已用额度（**只计本局新借**） | S | μU | 0..limit | **0（开局存量外债不计入）** | S02 | INV-034 |
| `state.world.sovereign_rate_ppm_per_q` | 当季主权融资利率 | S | ppm/季 | 0..100 000 | 剧本 | S01, S02 | INV-038 |
| `state.world.shock_active[]` | 冲击激活（3） | S | 0/1 | — | 0 | S01 | INV-109 |
| `state.world.shock_remaining_q[]` | 剩余季数（3） | S | 季 | ≥ 0 | 0 | S01 | INV-109 |
| `state.world.shock_magnitude_ppm[]` | 冲击强度（3） | S | ppm | 各自区间 | 0 | S01 | INV-109 |
| `state.world.current_account_uu` | 经常账户累计 | S | μU | 任意 | 0 | S06 | **INV-106** |
| `flow.world.exports_uu` / `exports_uqs[]` | 出口额／量 | F | μU / μQ_s | ≥ 0 | — | S05 | INV-059 |
| `flow.world.imports_uu` / `imports_uqs[]` | 进口额／量 | F | μU / μQ_s | ≥ 0 | — | S05 | INV-104 |
| `derived.world.external_debt_uu` | 政府外债（**存量，不占用额度**） | D | μU | ≥ 0 | — | DERIVED | **INV-107** |
| `derived.world.net_foreign_position_uu` | 净对外头寸 | D | μU | 任意 | — | DERIVED | INV-110 |

> **裁定 R-CREDIT-01（外部信用额度是增量额度，已执行）**
>
> `state.world.credit_limit_uu` 约束的是**本局新增的外部借款**，**开局已有的存量外债不占用它**。
> 因此 `state.world.credit_used_uu` 的初值是 0，尽管开局 `derived.world.external_debt_uu` 并不是 0
> （`bond.holder == row` 的两个批次，合计 16 000 000 000 μU = 16 U）。**这不是口径遗漏，是裁定结果，必须显式写在此处**：
>
> - **理由**：存量外债的约束**已经由还本付息的现金流表达了**——它每季从 `state.gov.cash_uu` 里实打实地扣钱，
>   扣不动就走 `ARREARS` 直到 `fiscal_restructuring_failed`（INV-040）。
>   若再让它占一次额度，同一笔债务就被计了两次：一次作为现金流出，一次作为融资空间的消耗。
>   **重复计价不是「更保守」，是把一个可解释的约束换成两个互相掩盖的约束**——玩家会看到「我明明还得起，却借不到」
>   而找不到任何一条能追溯的理由，这正是计划书 §13 要杜绝的东西。
> - **可用额度的唯一公式**：`external_capacity = credit_limit_uu − credit_used_uu`（INV-034）。
>   `credit_used_uu` 只在 `holder == row` 的**新发**批次成交时增加；存量批次的还本**不释放**额度
>   （额度是本局的累计发行上限，不是循环授信）。
> - **与冲击的关系**：S03 冲击按 `credit_limit_uu = mul_ppm(base_credit_limit_uu, ·)` 压低**上限**，
>   不追缴已借；若压低后 `credit_used_uu > credit_limit_uu`，**不得强制回收**，只是 `external_capacity` 取 0。
> - **本条同时写在 `content/scenarios/chengwan/world.json`**，两处必须一字不差；不得靠读者推断。
>
> **国内额度没有对称的 `credit_used` 存量计数器**：INV-034 的国内侧是
> `min(credit_limit_domestic_memo_uu, invpool.cash_uu)`，**每季重新求值**，因此它本身就是增量口径，
> 不需要也不允许再引入一个「已用国内额度」的存量字段。

---

## 9 价格、市场与核算

### 9.1 价格与工资

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 初值来源 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|---|
| `state.price.sector_uu_per_qs[]` | 部门现行价格（4） | S | μU/Q_s | `[400 000 000, 2 500 000 000]` | 剧本 = 1 000 000 000 | **S08 末 swap** | INV-065, INV-066 |
| `state.price.pending_uu_per_qs[]` | 下季价格（4） | S | μU/Q_s | 同上 | = 现行价 | **仅 S07** | INV-065 |
| `content.price.base_uu_per_qs[]` | 基年价格（4） | C | μU/Q_s | **恒 1 000 000 000** | 常量 | LOAD | INV-148 |
| `state.price.wage_uu_per_person_q[]` | 季度工资率（3 技能） | S | μU/人/季 | > 0 | 剧本 | S07（写 pending）, S08（swap） | INV-070 |
| `state.price.wage_pending_uu_per_person_q[]` | 下季工资率 | S | μU/人/季 | > 0 | = 现行 | 仅 S07 | INV-070 |
| `state.price.housing_rent_uu_per_unit_q[]` | 住房季度使用成本（4 地区） | S | μU/套/季 | > 0 | 剧本 | S07 | INV-083 |
| `flow.price.gap_ppm[]` | 供需缺口信号（4） | F | ppm | −1 000 000..1 000 000 | — | S07 | INV-067 |
| `state.price.clamp_budget_used_count` | 本局累计夹逼次数 | S | 计数 | ≥ 0 | 0 | S07 | **INV-069** |
| `derived.price.consumer_index_ppm` | 居民消费价格指数 | D | ppm | > 0，基年 1 000 000 | — | DERIVED | **INV-117** |

> **裁定（价格分地区与否）**：三份草案中只有草案 A 的市场量带地区维度。裁定采用 **全国按部门统一价格（4 个）**，
> 地区差异经 `content.region.logistics_cost_ppm` 体现在跨区交易的买方加价上。理由：计划书 §06 未要求地区价；
> 4 个价格使「价格只在一处更新一次」的静态检查简单可靠。登记为 OQ-209。

> **裁定（价格边界与步长）**：A 取 `[25%, 400%]` 与 ±4%/±3%；B 取 `[40%, 250%]` 与 ±3%；C 取 `[25%, 400%]` 与 ±6%。
> 裁定取**最紧的护栏 + 最强的暴露**：边界 `[400 000 000, 2 500 000 000]` μU/Q_s（= 基年价的 `[40%, 250%]`，B），
> 单季步长 `param.price_step_max_ppm = 30 000 ppm`，对称 ±3%（B；在基年价上等于 ±30 000 000 μU/Q_s），
> **同时**强制每次夹逼写 `log.clamp` 并计入 `clamp_budget_used_count`；压力测试中该计数超过
> `param.price_clamp_budget_count` 即判失败（INV-069）。
> 这样「护栏收紧」不会变成「撞墙被掩盖」——撞墙会直接让测试红掉。A 的非对称步长没有依据，不取。

### 9.2 市场

| 稳定 ID | 中文名 | 类 | 单位 | 维度 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|
| `flow.market.supply_uqs[]` | 本季可售供给 | F | μQ_s | 部门 | S05 | INV-059 |
| `flow.market.demand_uqs[]` | 本季需求 | F | μQ_s | 部门×买方类 | S05 | INV-059 |
| `flow.market.traded_uqs[]` | 实际成交 | F | μQ_s | 部门×买方类 | S05 | INV-059, INV-060 |
| `flow.market.unmet_demand_uqs[]` | 未满足需求 | F | μQ_s | 部门×买方类 | S05 | INV-059, INV-064 |
| `flow.market.rationing_rule[]` | 本季配给规则 | F | `none\|priority\|proportional` | 部门 | S05 | INV-061 |
| `flow.market.inventory_target_uqs[]` | 目标库存 | F | μQ_s | cell | S03 | — |

买方类（固定顺序，配给优先级见 12 号文件 §4.2）：`0 居民 / 1 公共服务 / 2 政府采购 / 3 企业投入与补库 / 4 出口`。

### 9.3 核算派生量（只读输出，不进 SimCore 决策）

| 稳定 ID | 中文名 | 单位 | 计算位置 | 不变量 |
|---|---|---|---|---|
| `derived.gdp.production_uu` | 名义 GDP（生产法，**权威口径**） | μU | S06 | **INV-111, INV-112** |
| `derived.gdp.expenditure_uu` | 名义 GDP（支出法分解） | μU | S06 | **INV-115** |
| `derived.gdp.income_uu` | 名义 GDP（收入法分解） | μU | S06 | **INV-116** |
| `derived.gdp.price_variance_total_uu` | 价差调节项 | μU | S06 | **INV-115, INV-119** |
| `derived.gdp.real_uu` | 实际 GDP（基年价） | μU | S06 | **INV-117** |
| `derived.gdp.annual_nominal_uu` | 滚动四季名义 GDP | μU | S06 | INV-118 |
| `derived.labor.unemployment_ppm` | 失业率（分母是劳动力） | ppm | S03 | **INV-075** |
| `derived.fiscal.debt_to_gdp_ppm` | 债务/GDP | ppm | S06 | 展示用，不替代偿付能力分析 |
| `derived.fiscal.debt_service_ratio_ppm` | 偿债率 | ppm | S06 | INV-038 |
| `derived.fiscal.next4q_debt_service_uu` | 未来四季到期本金＋利息 | μU | S06 | 计划书 §07 财政页必须展示 |
| `derived.living.consumption_index_ppm` | 全国消费指数 | ppm | S07 | INV-149 |
| `derived.living.public_service_index_ppm` | 全国公共服务指数 | ppm | S07 | INV-149 |
| `derived.income_quantile_uu[5]` | 收入五分位近似 | μU | S08 | **INV-120** |

**三法关系的精确形式（这是本次综合中最关键的一处纠正）**

设：库存按基年价计价（§2.3），于是任一入库交易同时产生
`price_variance = 1 000 × qty_uqs − paid_uu`（买方视角，正数表示买得比基年价便宜；
`1 000` 即 §2.3 的 `BASE_VALUE_PER_UQS = BASE_PRICE / Q_SCALE`，**R-SCALE-01 之前这个系数是 1**）。
逐项推导（详见 12 号文件 §6.4）给出：

```
derived.gdp.production_uu   = Σ_cell value_added_uu + Σ_region pubserv.output_uu
derived.gdp.expenditure_uu  = 居民消费 + 政府最终消费 + 总资本形成 + 存货变动(基年价) + 出口 − 进口
derived.gdp.price_variance_total_uu
                            = Σ 全部「入库交易」的 (mul_div_floor(qty_uqs, base_price, Q_SCALE) − paid_uu)
                            = Σ 全部「入库交易」的 (1 000 × qty_uqs − paid_uu)

INV-115:  derived.gdp.expenditure_uu == derived.gdp.production_uu + derived.gdp.price_variance_total_uu
INV-116:  derived.gdp.income_uu      == derived.gdp.production_uu
```

`INV-116` 成立是因为营业盈余按残差定义（`operating_surplus = value_added − wage_bill`），
所以收入法是**恒等式而非独立计算**；它的真实检验内容是 §9.4 的**覆盖性检验**。

### 9.4 分录三重分类与覆盖性检验

每条账本行在登记时必须带三个分类码（`prod_class` / `exp_class` / `inc_class`），取值含 `none`。
三种口径由同一批分录按不同标签汇总。真正的检验不是残差，而是：

- **完备性**：按 `kind` 反查白名单，凡应被分类的 `kind` 出现 `none` 即 FAULT（INV-114）。
- **互斥性**：同一行在同一口径下不得被计入两个类。
- **白名单**：`kind ∈ {新增借款, 还本, 补助, 转移支付, 组间赡养, 税款}` 在三种口径下**全部为 `none`**
  （借款不是收入、还本不是 GDP、补助不重复计入最终产出 —— INV-029、INV-113）。

> **裁定**：草案 A 的「分类法」被采纳，因为它把「三法一致」从一场必然失败的整数对账，
> 变成一场可以通过的覆盖性检查。A 自己登记的风险（漏打标签会让三法同时漏同一笔而残差仍为 0）
> 由 INV-114 的「按 kind 反查白名单」兜住，并要求该检验本身有单元测试
> （`test_u_gdp_class_coverage`，用一个故意漏标的 kind 证明它会红）。

---

## 10 随机流与确定性

**首版不使用 Godot 的 `RandomNumberGenerator`。** 计划书 §12[8] 已承认其算法是实现细节、跨版本不保证。
SimCore 自带**计数器式确定性抽样**：

```
draw(stream, q, index) = splitmix64( root_seed XOR SALT[stream] XOR (q << 32) XOR index )
```

| 稳定 ID | 中文名 | 类 | 单位 | 区间 | 写入者 | 不变量 |
|---|---|---|---|---|---|---|
| `state.rng.root_seed` | 根种子 | S | uint64（存为 int64 位型） | 全域 | LOAD | INV-010 |
| `state.rng.draw_count[]` | 各流抽样计数（6） | S | 计数 | ≥ 0 | S01,S03,S07,S08 | INV-009, INV-010 |
| `content.rng.salt[]` | 6 条流的盐值 | C | int64 | 固定常量 | — | INV-136 |

| 下标 | 流 ID | 用途 | 谁抽 |
|---|---|---|---|
| 0 | `rng.shock` | 3 类外生冲击的到达、强度与持续期 | S01 |
| 1 | `rng.event` | 12 个事件模板的触发判定 | S08 |
| 2 | `rng.demography` | 出生、死亡、迁移的整数化抖动 | S07 |
| 3 | `rng.market` | 配给并列打散、企业扩产抽签 | S03, S05 |
| 4 | `rng.politics` | 集团表态抖动、席位转换尾数 | S08 |
| 5 | `rng.reserved` | 预留（不使用；占位保证 schema 稳定） | — |

> **裁定（随机数实现）**：草案 B 用计数器式 splitmix64；草案 C 用自研 splitmix64 播种 + xoshiro256\*\* 演进状态；
> 草案 A 未明确排除引擎 RNG。裁定采用 **B 的计数器式**，理由：
> (a) 流之间**结构性独立**——多写一条新闻只推进 `rng.event` 的计数器，`rng.shock` 的任何取值不变
> （计划书 §12 明文要求）；
> (b) 存档只需 `root_seed` + 6 个计数器，不存内部状态，天然满足「读档不重抽」；
> (c) 可从任意季直接重算任意一次抽样，便于二分定位重放分歧；
> (d) 避免 C 自己登记的风险——xoshiro 实现若有细微错误会静默产生偏斜采样。
> **取模偏差的处理**：草案 B 的 `draw01_ppm` 与草案 C 的 `min + raw mod (max-min+1)` 都有偏差且都被登记为
> 待决问题。裁定**用拒绝采样消除偏差**（12 号文件 §0.4），代价是极小的期望重抽次数，收益是删掉一个待决问题。
> `splitmix64` 必须有已知测试向量的单元测试，`SALT[]` 一经发布不得更改（否则全部存档重放失效）。

每次抽样写一条 `log.rng`：`{stream, draw_index, purpose_code, raw_u64, mapped_value}`（INV-011）。

---

## 11 派生量与哈希

```
canonical(x):
  int    -> int64 小端 8 字节
  数组   -> uint32 长度（小端） + 逐元素 8 字节
  字符串 -> uint32 字节长度 + UTF-8 字节（仅用于 SoA 的 ids[]）
  条目   -> uint16 id 字节长度 + id 的 UTF-8 + uint8 类型标签 + 值
  float  -> 抛 E_FLOAT_IN_STATE

state_hash     = sha256_hex( 全部 state.* 与 flow.* 条目，按稳定 ID 字节序升序拼接 )
subsystem_hash = sha256_hex( 单个子系统的同样编码 )
                 子系统 ∈ {meta, time, gov, bond, cell, pubserv, group, region,
                           project, policy, politics, world, price, market, rng}
content_hash   = sha256_hex( 各内容文件按相对路径升序，逐文件先规范化再拼接 )
replay_hash    = sha256_hex( canonical(command_log) )
```

**哈希排除清单**：`state.meta.state_hash_prev` 自身、全部 `log.*`、全部 `derived.*`、
一切 `label_zh` / `desc_zh` / `report_template_id` / 时间戳。

- 排除文案 ⇒ 改一句中文不会让老存档失效，也不会造成重放「分歧」误报。
- 排除派生量 ⇒ 派生一致性由 INV-014 单独检查（调试构建每季重算并比对）。
- **排除清单本身被测试锁定**（`test_u_hash_coverage`：反射遍历状态树，断言除白名单外每个字段都进哈希）。

---

## 12 日志通道

| 稳定 ID | 内容 | 写入者 | 不变量 |
|---|---|---|---|
| `log.ledger` | 账本过账行（§2.5） | S02..S06 | INV-015, INV-139 |
| `log.physical` | 实物流水 `{q, step, from, to, product, qty_uqs, cause}` | S04, S05 | INV-047, INV-139 |
| `log.rejections` | 命令拒绝 `{command_id, code, detail}` | CMD, S02 | INV-137 |
| `log.arrears` | 欠付事件 `{payee, amount_uu, reason}` | S02, S04, S06 | INV-030 |
| `log.constraint_diag` | 逐 cell 五项约束值、最紧项与 slack | S05 | INV-045 |
| `log.rounding` | 取整记录 `{site_code, total, parts, residual}` | 各步 | INV-005 |
| `log.clamp` | 夹逼记录 `{field_code, raw, clamped, bound}` | S03, S07, S08 | INV-069 |
| `log.rng` | 抽样记录 | S01, S03, S07, S08 | INV-011 |
| `log.explanations` | 结构化复盘 `{entity, cause, amount, qty, q, constraint, kind}` | S08 | **INV-140** |

日志采用列式存储（平行 `PackedInt64Array` + 写游标），预分配 `param.log_capacity_rows = 8192` 行；
满则按 1.5 倍扩容并写一条告警。**SimCore 内不出现任何展示文案。**

`log.explanations.kind ∈ {accounted, inferred, projected}`（已经发生 / 规则推断 / 情景预测），
三类分离且 `projected` 条目**禁止回写任何状态字段**（静态检查，INV-140）。

---

## 13 溢出安全余量（R-SCALE-01 后已全部重算）

int64 上界 `INT64_MAX = 9 223 372 036 854 775 807 ≈ 9.2234e18`。首版硬上限：

```
AMOUNT_MAX = 4_000_000_000_000_000  # 4e15 μU = 4e6 U ≈ 40 000 倍基年全年 GDP
QTY_MAX    = 1_000_000_000_000      # 1e12 μQ_s = 1e6 Q_s        （R-SCALE-01 不动）
PRICE_MIN  =   400_000_000          # 基年价的 40%
PRICE_MAX  = 2_500_000_000          # 基年价的 250%
PPM        = 1_000_000              # （R-SCALE-01 不动）
Q_SCALE    = 1_000_000              # （R-SCALE-01 不动）
```

### 13.1 新刻度下两处契约上界**真的溢出 int64**

这是 R-SCALE-01 最硬的一条后果，必须先摆在最前面，因为它推翻了旧版 §13 的整套写法：

```
mul(AMOUNT_MAX, PPM)      = 4e15 × 1e6  = 4.0e21   ÷ INT64_MAX = 433.7   ⇒ 溢出约 434 倍
mul(QTY_MAX, PRICE_MAX)   = 1e12 × 2.5e9 = 2.5e21  ÷ INT64_MAX = 271.1   ⇒ 溢出约 271 倍
```

旧刻度下这两处分别是 4e18（裕度 2.3×）与 2.5e18（裕度 3.7×），**都还装得下**，
所以旧版 §13 才敢写 `idiv_floor(mul(x, p), 1e6)` 这种「先乘后除」。
`AMOUNT_MAX` 与 `PRICE_MAX` 各自 ×1 000 之后，这两条**同时**越界，且**越界幅度是两位数到三位数倍**，
不是「差一点」——任何「把上限调小一点就能糊过去」的想法在这里不成立：
要把 `mul(AMOUNT_MAX, PPM)` 塞回 int64，`AMOUNT_MAX` 得降到 9.2e12，那只有基年全年 GDP 的 92 倍，
连一局 120 季的累计流量都装不下。**所以必须换算法，不是换参数。**

### 13.2 `mul_div_floor(a, b, c)`：唯一合法的「先乘后除」入口

```
mul_div_floor(a, b, c) ≡ floor(a · b / c)          # 前置 c > 0
实现：q = floor_div(a, c)          # 商
      r = a − q·c                  # 余数，floor_div 语义保证 0 ≤ r < c
      返回 q·b + floor_div(r·b, c)
```

**为什么它精确等于数学真值**（不是近似、不是「误差可忽略」）：

由 `a = q·c + r` 得 `a·b = q·c·b + r·b`，两边除以 `c`：

```
a·b / c = q·b + r·b / c
```

`q·b` 是整数，**整数可以自由地穿过 floor**（`floor(n + x) = n + floor(x)`，n ∈ ℤ），于是

```
floor(a·b / c) = q·b + floor(r·b / c)
```

右边正是实现返回的值。等号是**恒等**，对任意符号的 `a`、`b` 与任意 `c > 0` 都成立——
前提只有一条：`q` 必须是**向下取整**的商、`r` 必须是**非负**的余数（`0 ≤ r < c`），
这正是 `floor_div` 的语义，也正是 GDScript 裸 `/` 与 `%` **给不了**的语义（裸 `/` 向零截断、裸 `%` 取被除数符号）。
拿裸算符去拼这个恒等式，负数一侧就会差 1。

**中间量的界**（为什么它不溢出）：

```
|q| ≤ |a|/c + 1        ⇒   |q·b| ≤ |a·b|/c + |b|      （即「真值的量级」再加一个 |b|）
0 ≤ r < c              ⇒   |r·b| < c·|b|
                           |floor(r·b/c)| ≤ |b|
```

即 **`mul_div_floor` 的中间量不超过 `max(|a·b|/c + |b|, c·|b|)`**，而 `|a·b|/c` 正是真值的量级。
推论（也是它的适用边界，必须写清楚）：**它只在 `c` 足够大时才降阶**。
`c` 很小的时候 `q ≈ a`、`q·b ≈ a·b`，它并不会变出裕度——**这不是缺陷，是正确性**：
那种情形下真值本身就装不下 int64，任何算法都只能报溢出。
换句话说，`mul_div_floor` 的保证是「**只要真值与 `c·|b|` 都装得下，它就不溢出**」，而不是「它永不溢出」。

对本契约的两个关键场景，`c` 都是 1e6（`PPM` 或 `Q_SCALE`），降阶正好落在需要的地方：

| 场景 | `a` 上界 | `b` 上界 | `c` | 拆商后 `q·b` | 拆商后 `r·b` | 中间量裕度 | 真值 |
|---|---|---|---|---|---|---|---|
| `mul_ppm` 于 `AMOUNT_MAX` | 4e15 | 1e6 | 1e6 | 4e9 × 1e6 = **4.0e15** | < 1e12 | **2 305.8×** | 4e15 ≤ `AMOUNT_MAX` ✓ |
| 数量 × 价格（M3） | 1e12 | 2.5e9 | 1e6 | 1e6 × 2.5e9 = **2.5e15** | < 2.5e15 | **3 689.3×** | 2.5e15 ≤ `AMOUNT_MAX` ✓ |
| 本金 × 票息率（≤ 100 000 ppm） | 4e15 | 1e5 | 1e6 | 4e9 × 1e5 = **4.0e14** | < 1e11 | **23 058.4×** | 4e14 ≤ `AMOUNT_MAX` ✓ |

最后一列顺带证明了**两组契约上界互相自洽**：在 `QTY_MAX` 与 `PRICE_MAX` 同时顶格时，
一笔交易的金额真值是 2.5e15 μU，仍 ≤ `AMOUNT_MAX` = 4e15 μU，不会出现「数量和价格都合法、金额却必然违反 INV-007」的死角。
（旧刻度同款检算是 1e12 × 2.5e6 / 1e6 = 2.5e12 ≤ 4e12，**比例一模一样**——这正是 R-SCALE-01
把 `AMOUNT_MAX` 与 `PRICE_*` 同时 ×1 000 而 `QTY_MAX` 不动的原因。）

### 13.3 逐条重算的乘法裕度表

| 乘法 | 裸乘的积 | 裸乘是否溢出 | 必须的写法 | 重算后的裕度 |
|---|---|---|---|---|
| `amount × ppm` | 4e15 × 1e6 = 4.0e21 | **溢出 434×** | `mul_ppm` → `mul_div_floor(x, p, PPM)` | 2 305.8×（中间量 4.0e15） |
| `qty × price` | 1e12 × 2.5e9 = 2.5e21 | **溢出 271×** | `mul_div_floor(qty, price, Q_SCALE)` | 3 689.3×（中间量 2.5e15） |
| `principal × coupon_ppm` | 4e15 × 1e5 = 4.0e20 | **溢出 43×** | `mul_div_floor(outstanding, coupon, PPM)` | 23 058.4×（中间量 4.0e14） |
| `capital × depreciation_ppm` | 4e15 × 1e5 = 4.0e20 | **溢出 43×** | `mul_ppm` → `mul_div_floor` | 23 058.4× |
| `tax_base × tax_rate_ppm` | 4e15 × 1e6 = 4.0e21 | **溢出 434×** | `mul_ppm` → `mul_div_floor` | 2 305.8× |
| `qty × Q_SCALE`（约束换算） | 1e12 × 1e6 = 1.0e18 | 否 | `mul_div_floor(qty, Q_SCALE, coeff)` | 9.2×（**全表最紧的一处**） |
| `price × ppm`（边界与步长） | 2.5e9 × 1e6 = 2.5e15 | 否 | `mul_ppm` | 3 689.3× |
| `persons × ppm` | 2.4e7 × 1e6 = 2.4e13 | 否 | `mul_ppm` | 384 307× |
| `ppm × ppm`（M2 合成系数） | 3e6 × 3e6 = 9.0e12 | 否 | `floor_div(mul(p1, p2), PPM)` | 1 024 819×（ppm 的首版最大区间上界是 3 000 000，见 `env_exposure_ppm`） |
| `total × weight`（最大余数法） | 见 §13.5 | **视权重而定** | `split_largest_remainder` + 入口断言 | 见 §13.5 |

**全表最紧的一处仍然是 `qty × Q_SCALE` 的 9.2×**，而它与货币刻度无关，因此**与旧刻度逐位相同**——
R-SCALE-01 没有动过这一处的裕度。凡货币侧的乘法，走 `mul_div_floor` 之后裕度都在 2 300× 以上，
比旧刻度的 2.3× 反而宽了三个数量级：**降阶带来的裕度增益远大于刻度放大带来的损失**。

### 13.4 乘法前缩放规则（强制）

- **M0**：一切乘法走 `IntMath.mul(a, b)`（本项目实现 `JWMath.mul`），内部
  `if b != 0 and absi(a) > INT64_MAX / absi(b): FAULT(INT_OVERFLOW)`。
  **用显式 `if` 而不是 `assert`**：Godot 的 `assert()` 在 release 构建会被剥离。
- **M1**：`mul_ppm(x, p) = mul_div_floor(x, p, PPM)`，前置 `|x| ≤ AMOUNT_MAX`。
  **旧写法 `idiv_floor(mul(x, p), 1e6)` 在新刻度下必然溢出，已作废。**
- **M2**：**禁止连乘两个 ppm**。必须用 `mul_ppm_2(x, p1, p2) = mul_div_floor(x, floor_div(mul(p1, p2), PPM), PPM)`
  （先合并系数，只取整一次）。合成那一步的 `mul(p1, p2)` 上界 9e12，可以裸乘。
- **M3**：价格乘数量先降阶：`amount = mul_div_floor(qty_uqs, price_uu_per_qs, Q_SCALE)`。
  **旧写法 `idiv_floor(mul(qty, price), 1e6)` 已作废。**
- **M4**：分配类计算先算权重和再逐项分，`item_i` 由 `split_largest_remainder` 给出；
  禁止先做 `total / W` 再乘（会放大取整误差）。入口断言见 §13.5。
- **M5**：累加器与日志金额同用 `AMOUNT_MAX` 检查。若 120 季压力测试触界，说明模型已发散，
  应按计划书 §13「修规则、步长、参数或初值」处理，**不得提高上限了事**。
- **M6（新增，计提余数）**：`a·b mod c` **不得**写成 `mul(a, b) % c`。用同一套拆商式：
  由 `a·b = q·c·b + r·b` 得 `a·b mod c = (r·b) mod c`，而 `r·b < c·|b|`，不溢出。
  首版唯一适用处是债券票息余数（INV-004 / INV-036 / INV-041）。
- **M7（新增，向上取整）**：`ceil(a·b/c)` 写成 `−mul_div_floor(−a, b, c)`。
  正确性：`ceil(x) = −floor(−x)`，而 `mul_div_floor(−a, b, c) = floor(−a·b/c) = −ceil(a·b/c)`，两次取负抵消，**精确**。
  适用于 §0.10 的两条 ceil 条目（产量 → 投入消耗量、产量 → 用工人数，INV-046）。
  **`JWMath` 目前没有 `mul_div_ceil` 包装函数**，调用点必须自己写这个取负形式并附 `# rounding: ceil, reason=...`。

### 13.5 最大余数法的入口断言（本次重算发现的唯一一处**真·冲突**）

旧表述：入口断言 `|total| ≤ INT64_MAX / Σweights`。**在新刻度下它会拒绝基年第一季就要做的一个合法计算。**

实例（§2.4 规定的「利息按各组 `deposit_uu` 份额用最大余数法分回 36 组」，S06）：

```
total = Σ 四个 holder==invpool 批次的本季票息（逐批次 floor 后求和）
      = 8e9·8000/1e6 + 7e9·8500/1e6 + 10e9·9500/1e6 + 9e9·11000/1e6
      = 64 000 000 + 59 500 000 + 95 000 000 + 99 000 000
      = 317 500 000 μU
Σweights = Σ_g state.group.deposit_uu = 43 000 000 000 μU
旧断言上界 = floor(INT64_MAX / 43 000 000 000) = 214 497 024 μU
317 500 000 > 214 497 024  ⇒  基年第一次付息就会 FAULT(INT_OVERFLOW)
```

而**实际发生的乘法根本没有溢出**：最大一组存款是 7 726 328 000 μU，
`317 500 000 × 7 726 328 000 = 2.453e18 ≤ INT64_MAX`，**裕度 3.76×**。
旧刻度下同一处是 `total = 317 500`、`Σw = 43 000 000`、上界 214 497 024 112，宽裕约 675 000 倍。
`total` 与 `Σw` **同时**被 ×1 000，所以这一处的裕度是按 **10⁶** 缩水的——
**全契约只有最大余数法这一条的裕度随刻度平方退化**，因为只有它的乘数两端都是货币量。
一般化：当权重本身是 μU 金额且 `total ≈ Σw`（按债权比例分一笔钱）时，旧断言退化为
`total ≤ √INT64_MAX = 3 037 000 499 μU ≈ 3.04 U ≈ 季度 GDP 的 12%`；旧刻度下这同一个数是 3 037 U ≈ 121 倍季度 GDP。

**裁定：入口断言改为乘法不溢出的充要条件**

```
|total| · max_i |w_i| ≤ INT64_MAX          （逐权重的精确条件）
```

**这是把替身换成本尊，不是放宽护栏**，理由逐条：

1. 被保护的东西是 INV-006「整数乘法不得溢出」。函数内实际执行的乘法是 `mul(total, w_i)`，
   它不溢出的**充要条件**就是 `|total|·max_i|w_i| ≤ INT64_MAX`。`Σweights` 版是一个**充分不必要**的替身
   （因为 `max_i|w_i| ≤ Σ|w_i|`），在旧刻度下松得看不出来，在新刻度下开始误杀。
2. 第二段 `rem_i = total·w_i − base·Σw`，其中 `base = floor(total·w_i / Σw)`，故 `base·Σw ≤ total·w_i`，
   已被同一条件覆盖；`Σ base ≤ total` 也在界内。**函数内不存在任何以 `Σw` 为乘数的乘法**——
   这正是旧断言选错乘数的地方。
3. 每次 `mul()` 内部仍有 M0 的逐次精确检查兜底，入口断言只是 fail-fast，不是最后一道防线。
4. 计算成本为零：求 `Σw` 的那一趟循环里顺手取 `max`。

**遗留（必须同步，本轮无权改）**：`sim/jw_math.gd::split_lr_into` 目前实现的仍是 `Σweights` 版
（`if total > floor_div(JWUnits.INT64_MAX, w_sum)`）。在它改成 `max_i |w_i|` 版之前，
**基年 S06 的票息分配会误报 `INT_OVERFLOW`**。不得用「把断言删掉」或「改成警告」绕过——
那是把一个可证明的条件换成没有条件。

> **裁定（R-12 重述，取代旧文）**：草案 A 的「单笔金额上限 1e15 μU」在旧刻度下就已在 `amount × ppm` 处溢出，是错误的；
> 草案 B 的 9e12 正确但 `qty × 1e6 = 3e18` 只剩 3 倍裕度且被自己登记为风险。
> 旧版本文件取 `QTY_MAX` 1e12、`AMOUNT_MAX` 4e12，使当时最紧的一处也有 2.3 倍裕度。
> **R-SCALE-01 后 `AMOUNT_MAX` 改为 4e15**（相对基年 GDP 的倍数不变，仍是 4 万倍），
> 代价是货币侧的裸乘全部越界，收益是把「靠上限压住裕度」换成「靠算法消掉裕度问题」：
> 走 `mul_div_floor` 之后货币侧最紧处有 2 305 倍裕度，比旧刻度的 2.3 倍好三个数量级。
> **上限不再是防溢出的主要手段，`mul_div_floor` 才是；`AMOUNT_MAX` 退回它本来的职责——
> 「这个数大到不像话，模型多半已经发散」的业务护栏（INV-007）。**

---

## 14 不变量总表（INV-001 … INV-152）

**列说明**：**层** = 检查发生在哪里（`SimCore` = 结算期运行时检查，`静态` = 构建期源码扫描，
`加载` = 内容包／存档载入期，`测试` = 只能由测试用例证伪）。
**级** = 失败等级（P0 = 错账／坏档／崩溃，P1 = 机制错误）。

### 14.1 算术、单位与确定性

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-001 | SimCore 与 systems 内不存在 `float`；状态树序列化遇 float 即 `E_FLOAT_IN_STATE` | 静态 + SimCore | 构建 / 每次序列化 | P0 |
| INV-002 | 不存在裸 `/` 与 `%`；一切除法经 `idiv_floor` / `idiv_ceil` / **`mul_div_floor`** / `mul_ppm` / `mul_ppm_2` / `split_largest_remainder`，且每个调用点有 `# rounding:` 注释。**「先乘后除」只允许 `mul_div_floor`（ceil 侧写 `−mul_div_floor(−a, b, c)`）；出现 `idiv_floor(mul(a, b), c)` 形态即构建失败**（§13 M1/M3/M7） | 静态 | 构建 | P0 |
| INV-003 | 任何金额／数量拆分：`Σ 分项 == 原额`（最大余数法，后置断言） | SimCore | 每次拆分 | P0 |
| INV-004 | 计提余数进入实体的 `*_remainder_ppmuu` 累加器，满 1 000 000 结转 1 μU；首版只有票息适用。**余数按 §13 M6 的 `(r·b) mod c` 求，禁止 `mul(a, b) % c`（新刻度下裸乘必溢出）** | SimCore | S02 | P0 |
| INV-005 | 换算余数写 `log.rounding`，不产生债权债务；`gov.rounding_residual_uu` 的季内变化必须被 `log.rounding` 逐条解释 | SimCore | 每季末 | P0 |
| INV-006 | 一切乘法过 `IntMath.mul` 的显式溢出前置检查（release 也执行）；**一切「先乘后除」过 `mul_div_floor`**。最大余数法的入口断言取充要条件 `\|total\| · max_i \|w_i\| ≤ INT64_MAX`（§13.5） | SimCore | 每次乘法 | P0 |
| INV-007 | `\|金额\| ≤ AMOUNT_MAX`（**4e15**），`\|数量\| ≤ QTY_MAX`（1e12），`price ∈ [PRICE_MIN, PRICE_MAX]`（**[4e8, 2.5e9]**） | SimCore | 每次写入 | P0 |
| INV-008 | 一切集合遍历先取键并按稳定 ID／下标升序；禁止 `for k in dict` | 静态 | 构建 | P0 |
| INV-009 | 随机流隔离：任一流的抽样次数变化，不改变其它流的任何取值 | 测试 | `test_u_rng_isolation` | P0 |
| INV-010 | 抽样与 ID 可复算：`draw = f(root_seed, stream, q, index)`；运行期 ID 只来自单调计数器 | SimCore + 静态 | 每次抽样 | P0 |
| INV-011 | 每次抽样写一条 `log.rng`；同季 `log.rng` 条数 == `Σ_stream Δdraw_count` | SimCore | 每季末 | P0 |
| INV-012 | 八步严格单向推进，不回退不跳步；`state.time.q` 只在 S08 末 `+1`，无其它写入路径 | SimCore + 静态 | 每步 | P0 |
| INV-013 | 每步只写其可写子集白名单；越界写入即 `E_WRITE_OUT_OF_SCOPE` | SimCore（调试全开／发布抽样） + 静态 | 每步 | P0 |
| INV-014 | 同 `build_id` + 同 `content_hash` + 同 `root_seed` + 同命令流 ⇒ 每季 `state_hash` 逐位相同；调试构建每季重算全部 `derived.*` 并比对 | 测试 + SimCore | 每季末 | P0 |

### 14.2 账本与货币闭合

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-015 | 每笔 `txn` 的有符号过账行之和为 0；每行 `amount != 0`，两端账户不同 | SimCore | 每次过账 | P0 |
| INV-016 | 所有 `cash` 科目 ≥ 0；不足时走 `ARREARS` 或 `REJECT`，**永不先扣成负数再想办法** | SimCore | 每次过账后 | P0 |
| INV-017 | 每季 `Σ 全部主体 Δcash == 0` | SimCore | 每季末 | P0 |
| INV-018 | 全经济现金总量恒定 `== scenario.total_cash_uu`（首版不模拟商业银行与货币创造） | SimCore | 每季末 | P0 |
| INV-019 | `Σ recv == Σ pay` | SimCore | 每季末 | P0 |
| INV-020 | 逐主体资产负债恒等式：`cash + Σinv + wip + capital + housing + recv + bondhold + deposit_claim − pay − debt − deposit_liab == nw` | SimCore | 每季末 | P0 |
| INV-021 | `Δnw` 被本季损益类流量完全解释（净值不得自己动） | SimCore | 每季末 | P0 |
| INV-022 | SimCore 内不存在直接赋值修改 `cash` / `inv` / `capital` / `debt` 的 API；全部变动经 `post()` | 静态 | 构建 | P0 |
| INV-023 | 初值经一组 `q = −1` 的开账分录生成（对手方 `agent.opening`），使 INV-015 从第 0 秒起成立 | 加载 | 载入 | P0 |
| INV-024 | `Σ group.deposit_uu == invpool.deposit_liab == invpool.cash + invpool.bondhold` | SimCore | 每季末 | P0 |
| INV-025 | `Σ (invpool.bondhold + row.bondhold) == derived.gov.debt_uu` | SimCore | 每季末 | P0 |
| INV-026 | 外部世界是显式账户；不存在无对手方的对外收支 | SimCore + 静态 | 每次过账 | P0 |

### 14.3 政府财政与债券

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-027 | `cash_end == cash_start + 收入 + 新增借款 − 基本支出 − 利息 − 还本`，残差恰为 0 | SimCore | S06 末 | P0 |
| INV-028 | `debt_end == debt_start + 新增借款 − 还本 − 确认减记` | SimCore | S06 末 | P0 |
| INV-029 | 新增借款不出现在收入构成中；新增借款与还本不进入任何 GDP 口径（GDP 函数输入白名单不含此二者） | 静态 + SimCore | 构建 / S06 | P0 |
| INV-030 | `arrears_end == arrears_start + 新增欠付 − 清偿欠付`；且 `arrears == Σ arrears_by_payee ≥ 0` | SimCore | 每季末 | P0 |
| INV-031 | `tax_receivable_end == start + (应计税 − 实收税) − 追征 − 核销` | SimCore | S06 末 | P0 |
| INV-032 | `committed_memo` 只由「新签合同 +」「履约付款 −」「取消 −」变动；**取消不退还已实际支付的钱** | SimCore | 每季末 | P0 |
| INV-033 | `reserved_memo ≤ cash`，且季末归零（预留要么执行要么释放） | SimCore | S02/S04/季末 | P0 |
| INV-034 | 融资不超对手方能力：国内 ≤ `min(credit_limit_domestic, invpool.cash)`；外部 ≤ `credit_limit_uu − credit_used_uu`。**额度是增量额度：存量外债不占用 `credit_used_uu`，还本也不释放额度**（R-CREDIT-01，§8.4） | SimCore | S02 | P0 |
| INV-035 | `derived.gov.debt_uu == Σ active bond.principal_outstanding_uu` | SimCore | S02 末、S06 末 | P0 |
| INV-036 | 利息逐批次计算：`interest = mul_div_floor(outstanding, coupon_ppm_per_q, PPM)`（**旧写法 `idiv_floor(outstanding × coupon, 1e6)` 在新刻度下裸乘溢出 43 倍，已作废**）；`coupon_ppm_per_q` 发行后被写入即 FAULT | SimCore + 静态 | S02 | P0 |
| INV-037 | `Σ_{q'≥q} scheduled_principal(b, q') == outstanding`；`level_principal` 的分期表由最大余数法预生成，和 == 面值 | SimCore | S02 | P0 |
| INV-038 | 新发批次 `coupon ≥ market_rate_ppm(q)`，且 `market_rate_ppm` 对 `derived.fiscal.debt_service_ratio_ppm` 单调不减；**不允许自动展期** | SimCore + 测试 | S02 / `ADV-02` | P0 |
| INV-039 | `payment_priority` 是 8 类支出的全排列，且实际支付顺序与之一致 | 加载 + SimCore | 载入 / S02,S04 | P0 |
| INV-040 | 无法支付第 1 档连续 `param.default_grace_q` 季 ⇒ `termination_reason = fiscal_restructuring_failed`；不得静默展期 | SimCore | S02 | P1 |
| INV-041 | 票息余数累加器长期不漂移（120 季累计误差 ≤ 1 μU/批次）。**新刻度下 1 μU 是旧刻度的千分之一，本上界因此自动收紧 1 000 倍，不放宽** | 测试 | `test_x_coupon_drift` | P1 |
| INV-042 | `Σ season_factor_ppm == 1 000 000`；年度额按季拆分用最大余数法，四季合计精确等于年计划 | 加载 + SimCore | 载入 / S02 | P0 |

### 14.4 生产、库存与资产

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-043 | `output_actual == min(激活的候选约束)`，且 `≤ output_plan`、`≤ capacity_active` | SimCore | S05 | P0 |
| INV-044 | 系数为 0 的约束**不产生候选值**（`continue` / `SENTINEL`）；**禁止除零，也禁止用 `max(c,1)` 代替** | SimCore + 静态 | S05 / 构建 | P0 |
| INV-045 | `slack[binding] == 0`，其余 `slack == 候选值 − q_actual ≥ 0`；并列时按 `plan<capacity<labor<energy<materials` 固定序取最小序号 | SimCore | S05 | P0 |
| INV-046 | 投入与用工由 `q_actual` 用 `idiv_ceil` 反算，且 `≤ 可用量`（整数引理，见 12 号文件 §3.4）。**「先乘后除」的 ceil 写成 `−mul_div_floor(−q_actual, coeff, Q_SCALE)`（§13 M7）；取整方向仍是 ceil** | SimCore | S05 | P0 |
| INV-047 | 库存恒等式（逐 cell 逐品种）：`期末 == 期初 + 生产 + 购入 − 售出 − 生产耗用 − 损耗` | SimCore | S05 末 | P0 |
| INV-048 | 任何库存字段每次写入后 `≥ 0`；不足时走配给／降产，**不得无提示负库存** | SimCore | 每次写入 | P0 |
| INV-049 | `content.storable == 0` 的部门（energy、services）期末库存恒为 0 | SimCore | S05 末 | P0 |
| INV-050 | 可库存中间投入**只来自期初库存**；本季购入补的是下季可用库存（同季不得使用本季产出） | SimCore + 测试 | S05 / `test_u_no_same_quarter_chain` | P0 |
| INV-051 | 电力当期使用；未用作废记 `energy_unused_uqs`，不入任何库存；`Σ 配给 ≤ min(能源可交付量, 电网容量)` | SimCore | S05 | P0 |
| INV-052 | 能源部门的自用电先从本部门产出净出；内容包必须满足 `a(energy→energy) < 1 000 000` | SimCore + 加载 | S05 / 载入 | P0 |
| INV-053 | 损耗显式登记并计入中间消耗；**不允许用「盘点差异」吸收** | SimCore | S05/S06 | P0 |
| INV-054 | `capacity_active` 的增量写入点全局唯一（S01 的 `pending → active`）；完工事件只能写 `pending` | 静态 + SimCore | 构建 / S01,S07 | P0 |
| INV-055 | 折旧减资产账面值与产能；维护欠账只降本季可用率，**不减资产** | SimCore | S06/S07 | P1 |
| INV-056 | 产能轨与价值轨用同一折旧率；载入期与投运瞬间 `\|capacity − mul_ppm(capital_value_uu, capacity_per_capital_uu_ppm)\| ≤ 1 μQ_s`。**`capital_value_uu` 可达 `AMOUNT_MAX`，此处裸乘溢出，必须走 `mul_ppm` → `mul_div_floor`；`capacity_per_capital_uu_ppm` 的值已随 R-SCALE-01 ÷1 000（§4.5）** | 加载 + SimCore | 载入 / S07 | P1 |
| INV-057 | 排放只累积 `emissions_stock` 与 `env_exposure_ppm`，**首版不反馈到生产约束** | 静态 | 构建 | P1 |
| INV-058 | 施工同时受 `construction_capacity_uqs`（推进速度）与 `construction_slots_total`（并发数）双重约束 | SimCore | S02/S05 | P1 |

### 14.5 市场与价格

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-059 | 市场对账：`Σ 成交 + Σ 未满足 == Σ 需求`；`Σ 成交 ≤ 供给`；卖方库存减少量 == `Σ 成交` | SimCore | S05 末 | P0 |
| INV-060 | 配给：`Σ alloc == min(可供, Σ 需求)`，且 `alloc_i ≤ requested_i` | SimCore | 每次配给 | P0 |
| INV-061 | `flow.market.rationing_rule` 与实际发生的路径一致（充足 ⇒ `none`） | SimCore | S05 末 | P1 |
| INV-062 | 买方付款额 `== mul_div_floor(成交量_uqs, 价格_uu_per_qs, Q_SCALE)`（**旧写法 `idiv_floor(成交量 × 价格, 1e6)` 在新刻度下裸乘溢出 271 倍，已作废**），跨区另加 `logistics_cost_ppm`；金额与实物各自双边入账 | SimCore | S05 | P0 |
| INV-063 | 居民本季可花的钱 = 已实际收到的工资 + 转移 + 赡养净额 + 可动用存量；**未收到的预计收入不可支配** | SimCore + 测试 | S05 / `test_s_no_phantom_income` | P0 |
| INV-064 | 未成交需求写 `unmet_demand`，未实现消费写 `unmet_consumption`；**不允许静默消失，也不允许当作已消费** | SimCore | S05 末 | P0 |
| INV-065 | 价格只在 S07 写 `pending`，S08 末一次性 swap；S05 的任何函数不得写 `price.*` | 静态 + SimCore | 构建 / S05 | P0 |
| INV-066 | `price ∈ [mul_ppm(base, price_floor_ppm), mul_ppm(base, price_ceil_ppm)]` | SimCore | S07 | P0 |
| INV-067 | `\|price_next − price_cur\| ≤ mul_ppm(price_cur, price_step_max_ppm)` | SimCore | S07 | P0 |
| INV-068 | 缺口恒为 0 时价格序列严格不变（取整偏置不累积） | 测试 | `test_u_price_fixpoint` | P0 |
| INV-069 | 每次 `clamp` 写 `log.clamp` 并计数；压力测试中 `clamp_budget_used_count > param.price_clamp_budget_count` 即判失败 | SimCore + 测试 | S07 / `test_x_price_stable` | P1 |
| INV-070 | 工资率同样是「S07 写 pending、S08 swap、有界平滑」，不在季内出清 | SimCore + 静态 | S07 | P0 |

### 14.6 人口、劳动、教育、迁移、住房

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-071 | 全国人口守恒：`Σ pop(q) == Σ pop(q−1) + Σ 出生 − Σ 死亡`；**死亡是唯一净流出，出生是唯一净流入** | SimCore | S07 末 | P0 |
| INV-072 | 逐组来源去向：`pop_g == pop_g_prev + 出生 − 死亡 + 成年入 − 成年出 + 技能入 − 技能出 + 迁入 − 迁出` | SimCore | S07 末 | P0 |
| INV-073 | 迁移双边：`migrate_out[a][b] == migrate_in[b][a]`，且 `Σ 迁入 == Σ 迁出` | SimCore | S07 末 | P0 |
| INV-074 | 年龄有向：成年只能来自低一档；`age ∈ {minor, elder}` ⇒ `participation_ppm == 0` 且 `employed == 0` | SimCore + 加载 | S07 / 载入 | P0 |
| INV-075 | `labor_force_g == mul_div_floor(pop_g, participation_ppm_g, PPM)`（仅 working 组）；`unemployed == labor_force − employed ≥ 0`；`unemployment_ppm == mul_div_floor(Σ unemployed, PPM, Σ labor_force)`。（人口口径本身不溢出，裕度 384 307×；改写只为 INV-002 的「先乘后除唯一入口」统一，取整方向不变） | SimCore | S03 | P0 |
| INV-076 | 逐地区逐技能 `Σ employed ≤ Σ labor_force` | SimCore | S03 末 | P0 |
| INV-077 | 群组侧就业与 cell／pubserv 侧就业是同一事实的两个索引视图，逐（地区，技能）精确相等 | SimCore + 加载 | S03 末 / 载入 | P0 |
| INV-078 | 首版不允许技能向下替代；错配只表现为 `bound_labor` 降低 | 静态 | 构建 | P1 |
| INV-079 | `Σ 各组工资收入 == Σ 各 cell 工资总额`；支付前 `cell.cash ≥ wage_bill`，**首版不允许欠薪** | SimCore | S04 | P0 |
| INV-080 | `employment_persons` 只由 S03（市场决定）与 S07（人口流出配对）写；S07 的减少量必须精确等于对应群组的流出就业人数 | SimCore + 静态 | S03/S07 | P0 |
| INV-081 | 新增培训席位 `≤ teachers_persons × param.student_teacher_ratio − 在读席位`；**拨款当季不得产生任何 `skill_in`** | SimCore + 测试 | S07 / `ADV-03` | P0 |
| INV-082 | 技能升档只来自结业队列，`skill_out` 与 `skill_in` 等量配对，滞后 `≥ param.training_lag_q` | SimCore | S07 末 | P0 |
| INV-083 | `Σ_g housing_units_occupied ≤ region.housing_stock_units ≤ region.housing_capacity_units` | SimCore | S07 末 | P0 |
| INV-084 | 被住房或迁移成本挡回的人数写 `migrate_rejected_persons`；容量不得「自动增长」 | SimCore + 测试 | S07 / `ADV-04` | P0 |
| INV-085 | 组间赡养转移双边：`Σ support_in == Σ support_out`，默认区内发生 | SimCore | S04 | P0 |
| INV-086 | `disposable == 工资 + 财产 + 转移 + 赡养入 − 赡养出 − 个税`；`savings == disposable − 消费 − 住房支出`；且 `Δcash + Δdeposit == savings`（逐组逐季精确） | SimCore | S06 末 | P0 |

### 14.7 项目与政策

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-087 | **付款不制造进度**：`construction_progress` 的增量只由实际投入的施工服务量决定，与 `paid_uu` 无函数依赖 | 静态 + 测试 | 构建 / `test_s_p04_pay_no_progress` | P0 |
| INV-088 | 施工进度增量 `= mul_div_floor(实投施工量_uqs, PPM, required_construction_uqs)`，实投量受本季 `construction_capacity` 与已占用量约束 | SimCore | S05 | P0 |
| INV-089 | 交付进度增量只由实际到货量决定，到货量 `≤ world.delivery_capacity_uqs` | SimCore | S05 | P0 |
| INV-090 | 完工充要条件：`delivery == 1e6 且 construction == 1e6 且 配套条件满足`；任一未满足**不得投运** | SimCore + 测试 | S07 / `test_s_p04_no_early_commission` | P0 |
| INV-091 | 完工写 `capacity_pending`，下一季 S01 转 `capacity_active`，`commissioned_q == 完工季 + 1` | SimCore + 测试 | S01/S07 / `test_s_commission_lag` | P0 |
| INV-092 | `Σ_line paid_uu ≤ Σ_q Σ_line spend_plan_uu`；`Σ spend_plan == total_cost`；付款只增 `wip` 与承包方现金 | SimCore + 加载 | S04 / 载入 | P0 |
| INV-093 | 取消：`committed_memo` 减未付部分，`paid_uu` **不回退**，现金不增加；`residual_value` 与 `cancel_penalty` 均入账 | SimCore | S02 | P0 |
| INV-094 | `Σ_{project ∈ r} queue_slot_held ≤ region.construction_slots_total`；超出者 `suspended(congestion)`，**不是静默排队** | SimCore | S02/S07 | P0 |
| INV-095 | 任何政策效应函数在 `q < effective_from_q` 或 `enabled == 0` 时返回零效应 | SimCore + 静态 | 每步 | P0 |
| INV-096 | `policy.budget_spent ≤ policy.budget_committed`；超预留必须重新审核 | SimCore | S04 | P0 |
| INV-097 | 补助幂等：`claim_key = hash(policy_id, beneficiary_id, q, qualifying_event_id)`，同键至多一条、至多付一次；关停再开启不补发历史季 | SimCore + 测试 | S04 / `ADV-01` | P0 |
| INV-098 | `q < cooldown_until_q` ⇒ 开关命令 `REJECT`；`toggle_count` 单调递增，每次开关产生一次性行政成本；`effective_from_q` 单调不回溯 | SimCore | S02 | P0 |
| INV-099 | 政策定义九字段齐全，`failure_paths` 非空且每条 `test_id` 在测试注册表中真实存在 | 加载 + 测试 | 载入 | P0 |
| INV-100 | `enabled == 0 且玩家可见` ⇒ `blocked_reason != none` 且本地化表存在对应条目 | SimCore + 测试 | S02 / `test_u_blocked_reason_text` | P1 |

### 14.8 公共服务与外部世界

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-101 | 非市场产出按成本计价：`output == 工资 + 中间消耗 + 折旧`；其增加值 = `工资 + 折旧`；全额计入政府最终消费，**不重复计算** | SimCore | S06 | P0 |
| INV-102 | 运行费欠拨只降 `availability_ppm`；`capacity_active`、`grid_capacity`、`housing_stock` 在此路径下**不得被写**（不得用写 0 表达停运） | SimCore + 静态 | S07 | P0 |
| INV-103 | `delivered ≤ mul_ppm(capacity_active, availability_ppm)`；未获服务人数写 `queue_persons`；`state.group.service_access_ppm ∈ [0, 1 000 000]` 且**各组可不同**，其基年人口加权值存入只读的 `content.group.base_service_access_ppm[]`，**不存在「加权值恒为 1 000 000」的约束**（R-ACCESS-01，§6.3） | SimCore | S05 | P1 |
| INV-104 | `imports_uqs[s] ≤ world.delivery_capacity_uqs[s]`，且进口支出受买方现金与外部信用额度双重约束 | SimCore + 测试 | S05 / `test_s_import_cap` | P0 |
| INV-105 | `fx_rate_ppm` 恒为 1 000 000，任何写入即 FAULT | 静态 + SimCore | 构建 | P0 |
| INV-106 | `current_account(q) == current_account(q−1) + 出口 − 进口 − 对外利息 + 对外净借款` | SimCore | S06 末 | P0 |
| INV-107 | `derived.world.external_debt_uu == Σ (holder == row) bond.principal_outstanding_uu` | SimCore | S06 末 | P0 |
| INV-108 | 冲击只写 `world.*` 白名单字段；**不得直接写国内账户、产能、库存或人口** | 加载 + 静态 | 载入 / 构建 | P0 |
| INV-109 | 每次冲击抽样写 `shock_log`；S01 先查 `shock_log` 再抽样，已有记录则复用且不推进计数器 | SimCore + 测试 | S01 / `ADV-06` | P0 |
| INV-110 | `Δ net_foreign_position == −(经常账户 + 金融账户)`，残差恒为 0 | SimCore | S06 末 | P0 |

### 14.9 国民核算

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-111 | `value_added == gross_output − intermediate`（逐 cell / 逐 pubserv） | SimCore | S06 | P0 |
| INV-112 | `gdp_production == Σ value_added + Σ pubserv.output`；**禁止用 `Σ 销售额` 求和** | SimCore + 测试 | S06 / `test_u_gdp_no_double` | P0 |
| INV-113 | 补助只增加企业现金与净值，不进 `gross_output`，不进任何 GDP 口径 | SimCore + 静态 | S06 | P0 |
| INV-114 | 每条账本行的三个分类码完备且互斥；按 `kind` 反查白名单，应分类却为 `none` 即 FAULT | SimCore + 测试 | S06 / `test_u_gdp_class_coverage` | P0 |
| INV-115 | `gdp_expenditure == gdp_production + price_variance_total`，残差恰为 0 | SimCore | S06 | P0 |
| INV-116 | `gdp_income == gdp_production`（营业盈余按残差定义），并通过 §9.4 覆盖性检验 | SimCore | S06 | P0 |
| INV-117 | 实际 GDP 用基年价重新核算总产出与中间投入；**禁止用名义 GDP 除以任何价格指数**（实际 GDP 函数不得引用 `consumer_index_ppm`） | 静态 + SimCore | 构建 / S06 | P0 |
| INV-118 | 无命令跑满基年四季：`Σ_{q=0..3} gdp_production_uu == 100 000 000 000 μU`（= 100 U），**容差 0** | 测试 | `test_s_base_year_gdp` | P0 |
| INV-119 | `price_variance_total` 可逐笔追溯到入库交易，每笔的 `1 000 × qty_uqs − paid_uu` 可复算（`1 000` = `BASE_PRICE / Q_SCALE`，§2.3；**R-SCALE-01 前该系数是 1**） | SimCore | S06 | P0 |
| INV-120 | 不存在「精确基尼系数」字段；收入分位为近似量，展示必须标注「未模拟组内差异」 | 静态 | 构建 | P1 |

### 14.10 政治与社会

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-121 | 生活 / 预期 / 信任三者分开存储、分开更新、分开展示；SimCore 内禁止合成单一「满意度」字段 | 静态 | 构建 | P0 |
| INV-122 | `trust_ppm` 的更新式中不存在 `transfer_income` 通道；恢复速度 < 下降速度（`trust_recover_ppm < trust_drop_ppm`） | 静态 + 测试 | 构建 / `test_s_trust_asymmetry` | P0 |
| INV-123 | `support_ppm` 的每次变动都有来源分解记录（生活／预期／信任各自贡献） | SimCore | S08 | P1 |
| INV-124 | `support_national_ppm` 只由群组 `support_ppm` 按人口加权（最大余数法）得出，且**必须同时保留逐组分布** | SimCore + 静态 | S08 | P0 |
| INV-125 | 票（`support`）、组织影响力（`bloc.org_power`）、行政能力（`admin_capacity`）三者由三个不同函数计算，互不引用对方的量 | 静态 | 构建 | P0 |
| INV-126 | 席位转换是纯函数 `seat_rule(support_national_ppm, seats_total)`，整数、最大余数法、`0 ≤ seats_gov ≤ seats_total` | SimCore + 测试 | S08 | P0 |
| INV-127 | 选举只在 `q ∈ {15, 31}`；预算审查在 `q ≡ 3 (mod 4)` | SimCore | S02/S08 | P0 |
| INV-128 | 终局条件式中不含任何 GDP 项（经济下滑本身不是失败）；`run_terminated == true` 后任何 `advance_quarter` 返回 `REJECT` 且状态哈希不变 | 静态 + SimCore | 构建 / S08 | P0 |
| INV-129 | 集团成员规模由群组人口映射得出；允许重叠成员，但必须以「加权人数」口径展示并标注 | SimCore | S08 | P1 |
| INV-130 | 事件 `effects.target` 只能是 `{expectation_ppm, trust_ppm, support_ppm, org_power_ppm, stance_ppm, admin_capacity_ppm}`；**事件不得直接写现金、库存、产能、人口，首版事件没有任何账本效应** | 加载 + 静态 | 载入 / 构建 | P0 |

### 14.11 存档、重放、日志与版本

| 编号 | 内容 | 层 | 时点 | 级 |
|---|---|---|---|---|
| INV-131 | 存档含全部跨季状态 + `root_seed` + 6 个计数器 + 完整命令流（含被拒命令） | SimCore | 存档 | P0 |
| INV-132 | 读档复算 `state_hash` 并与档内值比对，不符即 `E_SAVE_CORRUPT` 拒绝载入；**不做尽力修复**。载入后立即跑一遍全部 P0 不变量 | 加载 | 载入 | P0 |
| INV-133 | `save → load → advance` 与 `advance` 的 `state_hash` 逐位相同；`log.rng` 完全一致 | 测试 | `ADV-06` | P0 |
| INV-134 | `content_hash` 或 `param_set_version` 不符 ⇒ 进入**只读检视模式**（可看不可推进）；`build_id` 不符 ⇒ 可继续游玩但置 `replay_unreliable` 并禁用重放验证 | 加载 | 载入 | P0 |
| INV-135 | `schema_version` 高于当前支持上限 ⇒ 拒绝载入，不猜测 | 加载 | 载入 | P0 |
| INV-136 | 迁移是有序纯函数链，逐版递增不跳版；不得发明数据；每版有黄金存档回归 | 测试 | `test_r_migrate` | P0 |
| INV-137 | 被拒命令仍入档并记原因码；命令被拒时状态哈希完全不变 | SimCore + 测试 | CMD / `test_u_reject_pure` | P0 |
| INV-138 | 命令不得携带任何直接状态值（`set_cash` / `set_gdp` / `set_support` 之类字段一律拒绝） | 加载 + 静态 | 载入 / 构建 | P0 |
| INV-139 | 每条状态数值变化都存在至少一条日志条目可解释之 | 测试 | `test_r_trace` | P1 |
| INV-140 | `log.explanations.kind ∈ {accounted, inferred, projected}` 三类分离；`projected` 条目禁止回写任何状态 | 静态 | 构建 | P0 |

### 14.12 剧本硬约束（载入期，容差一律 0）

| 编号 | 内容 | 层 | 级 |
|---|---|---|---|
| INV-141 | `Σ 人口 == 24 000 000`；北原 9 000 000 / 中州 7 000 000 / 海岬 5 000 000 / 西岭 3 000 000 | 加载 | P0 |
| INV-142 | 36 个群组齐全、ID 无重复、覆盖 4×3×3 全组合（允许空组） | 加载 | P0 |
| INV-143 | 反算失业率 ∈ [79 500, 80 500] ppm；**剧本 schema 中不存在失业率输入字段** | 加载 + 静态 | P0 |
| INV-144 | `Σ bond.principal_outstanding_uu == 50 000 000 000`（= 50 U；六个批次 8 + 7 + 10 + 10 + 9 + 6，单位 10⁹ μU） | 加载 | P0 |
| INV-145 | `gov.cash_uu == 2 000 000 000`（= 2 U） | 加载 | P0 |
| INV-146 | 年收入计划 20 000 000 000；年支出计划（含利息、不含还本）22 000 000 000；赤字 2 000 000 000（= 20 U / 22 U / 2 U） | 加载 | P0 |
| INV-147 | 支出计划中的利息项 == 基年四季逐批次票息之和（防止债务与利息各写各的） | 加载 | P0 |
| INV-148 | 基年全部门 `price == base_price == 1 000 000 000` | 加载 | P0 |
| INV-149 | 基期人口加权的 `consumption_index_ppm` 与 `derived.living.public_service_index_ppm` 均 == 1 000 000（**不含 `state.group.service_access_ppm`**，R-ACCESS-01）；全文与 UI 无「国际排名」字样 | 加载 + 静态 | P0 |
| INV-150 | IO 表每列和 < 1 000 000（增加值为正）；`storable[energy] == 0`、`storable[services] == 0`；`a(energy→energy) < 1 000 000`；邻接矩阵对称无自环 | 加载 | P0 |
| INV-151 | 群组侧就业与 cell 侧就业在同一（地区, 技能）口径下完全一致（故意冗余，交叉校验） | 加载 | P0 |
| INV-152 | 每个数值参数有一张九字段齐全的身份证卡；SimCore 内无魔数（白名单仅 `0, 1, −1` 与 §0.5 维度常量）；声称 `observed` 却无对应数据文件即失败 | 加载 + 静态 | P0 |

---

## 15 裁定记录

| # | 冲突点 | 各方主张 | 裁定 | 理由 |
|---|---|---|---|---|
| R-01 | 字段命名大小写 | A/B：`_uU` `_uQs`；C：`_uu` `_uqs` | **C** | 已锁定决策要求 JSON 键名与代码标识符英文 snake_case；`_uU` 违反 |
| R-02 | 生产的权威粒度 | A：16 个 firm；B：16 cell（财务也在 cell）；C：物理 16 cell + 财务 4 部门 | **16 cell，物理与财务同体** | 地区约束必须落到生产上（B/C 共识）；C 的拆分制造跨区调货的现金归属缝隙（C 自认 OQ-02） |
| R-03 | ID 段序 | A：`firm.<sector>.<region>`；B/C：region 在前 | **region 在前** | 与已锁定的 `group.<region>.<age>.<skill>` 同一读法 |
| R-04 | `q` 的写入者 | A/B：S01 递增（需首季例外）；C：S07 | **S08 末递增**，结算期间 `q` 恒定 | 无首季例外；八步读到的 `q` 语义一致；单一写入点可静态检查 |
| R-05 | 选举与审查的季度 | A/B：`q ∈ {16,32}`；C：`q ∈ {15,31}` | **C** | `q` 从 0 起，第 16 季 = `q=15`。A/B 是差一错误 |
| R-06 | 完工→供能的落点 | A：S01 快照 `capital_effective`；B：S01 转 pending；C：S07 末 swap | **S07 只写 pending，S01 转 active** | 合并 A 的「唯一写入点」与 B/C 的「可断言 pending 字段」；C 的方案依赖隐含步骤顺序，将来插步即静默失效 |
| R-07 | 利息与还本在哪一步 | A：S06；B/C：S02 | **S02** | 计划书 §13 第 02 步明写「处理到期债务」 |
| R-08 | 票息取整余数 | A：floor 丢弃；B/C：累加器结转 | **累加器结转，且只此一处适用** | 票息是形成持续债权债务的计提，丢弃会系统性少付；限定一处避免累加器泛滥 |
| R-09 | 折旧在哪一步 | A：S06 算 / S07 落账（自认 OQ-19）；B/C：S07 | **S06 算并落账** | 折旧是经营结果的费用项，计划书 §13 第 06 步即「经营结果」；消除跨步暂存 |
| R-10 | 随机数实现 | A：未排除引擎 RNG；B：计数器式 splitmix64；C：自研 xoshiro256\*\* 演进状态 | **B（计数器式）+ 拒绝采样去偏** | 流之间结构性独立；存档只需种子与计数器；可从任意季重算任意抽样；避免 C 自认的「自研 PRNG 静默偏斜」风险 |
| R-11 | 抽样映射偏差 | B、C 均登记为待决 | **拒绝采样，直接消除** | 代价是极小的期望重抽次数，收益是删掉一个待决问题 |
| R-12 | 溢出上限 | A：单笔 1e15（会溢出）；B：AMOUNT 9e12 / QTY 3e12（仅 3× 裕度） | **AMOUNT_MAX 4e15 / QTY_MAX 1e12**（R-SCALE-01 后；旧值 4e12） | `AMOUNT_MAX` 随 `U_SCALE` 同步 ×1 000，相对基年 GDP 仍是 4 万倍；货币侧裸乘因此全部越界，改由 `mul_div_floor` 降阶，最紧处裕度反升到 2 305×（§13） |
| R-13 | GDP 三法一致 | A：分类法，残差恒 0；B/C：只做生产法 | **生产法为权威口径 + 分类法做支出／收入分解 + 价差调节项** | A 的「残差恒 0」在基年价计价下不成立（§9.3 推导）；保留分类法的覆盖性检验价值，把不成立的等式改成成立的等式 |
| R-14 | 库存计价 | A：基年价恒定；B/C：未明确 | **A（基年价恒定，`inv` 的 μU 值 == 1 000 × μQ_s 值）** | 使数量账与价值账永不脱钩、无需成本流假设；R-SCALE-01 后换算系数由 1 变为 1 000，因整除而仍无取整余数，结论不变；代价（价差项）已由 R-13 显式对账 |
| R-15 | 价格边界与步长 | A：25%–400%，±4%/±3%；B：40%–250%，±3%；C：25%–400%，±6% | **40%–250%，对称 ±3%，并强制 clamp 预算** | 取最紧护栏；用「夹逼计数超预算即测试失败」防止护栏变成掩盖 |
| R-16 | 价格是否分地区 | A：市场量带地区维；B/C：全国按部门 | **全国按部门（4 个）** | 计划书未要求地区价；4 个价格使「只在一处更新一次」可静态检查 |
| R-17 | 工资欠付 | A/C：不允许（S03 现金闸）；B：允许 S04 二次裁员 | **不允许；employment 只由 S03 与 S07 写** | B 自认 Q-SIM-07 破坏单一写者；双写者是后续违规的口子 |
| R-18 | 电力分配在哪一步 | A：S05（能源先产，按实际分配）；B/C：S04（按计划分配） | **S05，按能源部门实际产量分配** | 消除 B 自认的 Q-SIM-02「计划与实际错位」整类风险；能源部门在 S05 内先结算，顺序可测 |
| R-19 | 能源自用 | 三稿均未处理 `a(energy→energy) > 0` 的自指 | **能源部门跳过能源约束，自用量从产出净出；加载期要求 `a(e→e) < 1e6`** | 唯一能在整数下闭合且不引入迭代的写法 |
| R-20 | 技能替代 | A：允许向下替代；B：分档配给；C：禁止 | **禁止（C）** | 替代矩阵是三稿中唯一无计划书依据的自创机制，且会让错配失去可观察性 |
| R-21 | 资本双轨一致性 | B：允许漂移；C：要求永远同源 | **同一折旧率 + 载入与投运瞬间一致性检查 + 漂移诊断** | 整数 floor 下「永远同源」不可实现；只在可实现处强制 |
| R-22 | 施工能力的表达 | A：μQ 施工量；B：剧本产能；C：整数槽位 | **μQ 施工量（推进速度）+ 槽位（并发数）并存** | 两条约束对应两种可测的失败形态，缺一则「施工拥堵」只测得出一种 |
| R-23 | 事件能否动钱 | A：允许带 payer/payee 的 `ledger_effects`；B/C：禁止 | **首版事件无任何账本效应** | A 自己的 OQ-25 也建议留空；花钱必须走政策或项目，这是 §13 的结构性执行点 |
| R-24 | 存档形态 | A：单文件；B：目录（manifest/state/commands.jsonl/checkpoints）；C：单文件含全量命令流 | **B 的目录 + C 的全量命令流 + A 的载入后跑 P0** | 自动保存 O(1)；逐季 checkpoint 支持二分定位；全量命令流支持 `commands_only` 交叉验证 |
| R-25 | `content_hash` 不符的行为 | A：拒绝推进，只读；B：三选一，默认只读；C：只读 | **只读检视模式，首版无「继续游玩」选项** | 最保守；避免静默串味。放宽须由命令行开关且在存档留痕 |
| R-26 | 断言在发布构建 | A/C：用 `assert`；B：用显式 `if + Fault` | **资金／物资／人口类一律显式 `if + Fault`** | Godot 的 `assert()` 在 release 被剥离；靠它守账等于没守 |
| R-27 | 组间赡养转移 | 仅 A 提出 | **采纳 A** | 未成年与老年组的消费能力必须有来源；否则是隐性补贴 |
| R-28 | 公共服务的位置 | A：4 个 pubserv 主体；B：cell 上打标记；C：region 级容量 | **4 个 `pubserv.<region>` 主体（services 子账户），无自有现金** | 计划书 §03 明写「公共服务为服务部门子账户」；无现金简化支付路径而不损失口径 |
| R-29 | 季节系数口径 | A：四季和 = 4 000 000；B/C：四季和 = 1 000 000 | **1 000 000（份额）** | 可直接喂给 `split_largest_remainder`，四季合计精确等于年额 |
| R-30 | 税率提高的税基反应 | A/B：只有征收能力；C：征收能力 + 税基侵蚀 | **两者并用（C）** | 计划书 §17 的「提高税率后税收是否绕过实际税基」要求非线性反应，只有征收能力做不到 |

---

## 16 R-SCALE-01 同步记录

本节记录本轮按 `docs/18_rulings.md` 的 **R-SCALE-01**、**R-ACCESS-01**、**R-CREDIT-01** 对本文件所做的**全部**改动。
逐处列出，**没有「其余类推」**。INV 编号一个未增、一个未删、一个未重排。

### 16.1 R-SCALE-01（货币刻度 1 U = 10⁹ μU）

| 小节 | 改动 | 旧 → 新 |
|---|---|---|
| §0.1 记数单位表 | `μU` 行定义 | `1 U = 1 000 000 μU`；`基年全年名义 GDP = 100 000 000 μU` → `1 U = 1 000 000 000 μU`；`100 000 000 000 μU`；并补记 `基年季度名义 GDP = 25 000 000 000 μU` |
| §0.1 记数单位表 | `μU/Q_s` 行 | `基年全部门价格 = 1 000 000` → `1 000 000 000` |
| §0.1 | **新增**「货币刻度」裁定块 | 列出改动常量（`U_SCALE`、`BASE_PRICE`、`BASE_YEAR_GDP_UU`、`AMOUNT_MAX`、`PRICE_MIN/MAX`）与不动常量（`Q_SCALE`、`PPM`、`QTY_MAX`），并前置声明两条全局后果 |
| §0.9 铁律 1 | **新增**入口约束 | 先乘后除一律 `mul_div_floor`；ceil 侧写 `−mul_div_floor(−a, b, c)`；禁止 `mul` 后 `idiv_floor` |
| §0.9 计提行 | 余数求法 | 追加：禁止 `mul(a,b) % c`，改用 `(r·b) mod c` |
| §0.10 对照表 | **逐条复核并新增第四列** | 13 条原条目**取整方向无一改变**；其中 6 条（数量×价格、税额、利息、折旧、投入消耗、产量上限）的**算法形态**改为 `mul_div_floor`；另新增 2 条人均／每套条目 |
| §2.2 科目表 | `inv.<sector>` 单位注 | `恒等于 μQ_s 数值` → `恒等于 1 000 × μQ_s 数值` |
| §2.3 库存计价 | 计价价格 | `1 000 000 μU/Q_s` → `1 000 000 000 μU/Q_s` |
| §2.3 | **新增**换算常量 | `BASE_VALUE_PER_UQS = BASE_PRICE / Q_SCALE = 1 000`（整除，无余数） |
| §2.3 | 价差定义 | `price_variance = qty_uqs − value_uu` → `= 1 000 × qty_uqs − paid_uu` |
| §2.3 | **新增**同步警示块 | 说明这是全次迁移最易漏改处：错了不触发任何溢出／区间检查，只会让 INV-115 在一个「看起来合理」的数上失败 |
| §3.1 | `state.gov.cash_uu` 初值 | `剧本 = 2 000 000` → `2 000 000 000（= 2 U）` |
| §3.1 | `credit_limit_domestic_memo_uu` 中文名 | 补注「**增量额度**」 |
| §4.5 | `capacity_per_capital_uu_ppm` 说明 + **新增**注块 | 登记「分母带 μU 的系数必须 ÷1 000」，值为 `[200, 180, 55, 160]`，并写明这是全契约唯一反向走的系数、迁移器够不到 |
| §4.5 R-21 裁定 | 一致性检查式 | `capital_value × coeff / 1e6` → `mul_ppm(capital_value_uu, coeff)` |
| §9.1 | 价格区间与初值 | `[400 000, 2 500 000]` → `[400 000 000, 2 500 000 000]`；`剧本 = 1 000 000` → `1 000 000 000`；`恒 1 000 000` → `恒 1 000 000 000` |
| §9.1 价格裁定 | 边界与步长表述 | 边界改新刻度值并注明 `= 基年价的 [40%, 250%]`；步长由「±30 000」改为「`price_step_max_ppm = 30 000 ppm`，对称 ±3%（在基年价上 = ±30 000 000 μU/Q_s）」 |
| §9.3 | 三法推导块 | 价差项 `Σ (qty_uqs − value_uu)` → `Σ (mul_div_floor(qty_uqs, base_price, Q_SCALE) − paid_uu)` = `Σ (1 000 × qty_uqs − paid_uu)` |
| §13 | **整节重写** | 见 §16.2 |
| §14.1 | INV-002 | 除法入口清单加入 `mul_div_floor` / `mul_ppm_2`；新增「出现 `idiv_floor(mul(a,b),c)` 形态即构建失败」 |
| §14.1 | INV-004 | 追加 M6 的余数求法 |
| §14.1 | INV-006 | 追加「一切先乘后除过 `mul_div_floor`」与最大余数法入口断言的充要形式 |
| §14.1 | INV-007 | 补上新常量数值 `4e15` / `1e12` / `[4e8, 2.5e9]` |
| §14.3 | INV-036 | `idiv_floor(outstanding × coupon, 1e6)` → `mul_div_floor(outstanding, coupon_ppm_per_q, PPM)`，并注明旧写法溢出 43 倍 |
| §14.3 | INV-041 | 注明 1 μU 上界在新刻度下自动收紧 1 000 倍 |
| §14.4 | INV-046 | 追加 ceil 的不溢出写法 `−mul_div_floor(−q_actual, coeff, Q_SCALE)` |
| §14.4 | INV-056 | 一致性检查式改 `mul_ppm(...)`，并注明系数已 ÷1 000 |
| §14.5 | INV-062 | `idiv_floor(成交量 × 价格, 1e6)` → `mul_div_floor(成交量_uqs, 价格_uu_per_qs, Q_SCALE)`，注明旧写法溢出 271 倍 |
| §14.6 | INV-075 | 两式改 `mul_div_floor`（本处不溢出，改写只为统一入口） |
| §14.7 | INV-088 | 改 `mul_div_floor(实投施工量_uqs, PPM, required_construction_uqs)` |
| §14.9 | INV-118 | `100 000 000 μU` → `100 000 000 000 μU（= 100 U）` |
| §14.9 | INV-119 | 可复算量 `qty − value` → `1 000 × qty_uqs − paid_uu` |
| §14.12 | INV-144 | `50 000 000` → `50 000 000 000`（并列出六批次构成） |
| §14.12 | INV-145 | `2 000 000` → `2 000 000 000` |
| §14.12 | INV-146 | `20 000 000 / 22 000 000 / 2 000 000` → `20 000 000 000 / 22 000 000 000 / 2 000 000 000` |
| §14.12 | INV-148 | `1 000 000` → `1 000 000 000` |
| §15 | R-12 | 裁定值 `AMOUNT_MAX 4e12` → `4e15`，理由改写为「上限不再是防溢出的主要手段」 |
| §15 | R-14 | 补「`inv` 的 μU 值 == 1 000 × μQ_s 值」，说明换算系数由 1 变 1 000 但仍整除、结论不变 |

**确认未改（刻度无关，逐项核对过）**：`Q_SCALE`（1 000 000 μQ_s/Q_s）、`PPM`（1 000 000）、`QTY_MAX`（1e12）、
全部 `_ppm` 字段区间（含 `0..1 000 000`、`0..2 000 000`、`0..3 000 000`、`−1 000 000..1 000 000`）、
`fx_rate_ppm == 1 000 000`（INV-105）、`Σ season_factor_ppm == 1 000 000`（INV-042）、
`a(energy→energy) < 1 000 000` 与 IO 表列和 < 1 000 000（INV-052 / INV-150）、
`Σ 人口 == 24 000 000` 与四地区分解（INV-141）、失业率区间 `[79 500, 80 500]` ppm（INV-143）、
进度与完工判据的 `1e6`（INV-090）、R-15 的百分比表述、R-29 的季节系数份额口径。

### 16.2 §13 的重算结果（本轮最实质的一处）

1. **两处契约上界真的溢出**：`mul(AMOUNT_MAX, PPM) = 4e21`（超 int64 约 434 倍）、
   `mul(QTY_MAX, PRICE_MAX) = 2.5e21`（约 271 倍）。溢出幅度是两三位数倍，不存在「调小上限糊过去」的解。
2. **`mul_div_floor(a, b, c)` 成为唯一合法的先乘后除入口**，并在 §13.2 给出完整证明：
   由 `a = q·c + r`（`0 ≤ r < c`）得 `floor(a·b/c) = q·b + floor(r·b/c)`，**恒等而非近似**；
   中间量不超过 `max(|真值| + |b|, c·|b|)`。同时写明它的**适用边界**——`c` 小的时候它不降阶，
   那种情形下真值本身就装不下，报溢出才是正确行为。
3. **全部乘法裕度逐条重算**（§13.3 十行表）。货币侧走 `mul_div_floor` 后最紧处 2 305×；
   全表最紧仍是与货币无关的 `qty × Q_SCALE` 的 9.2×，与旧刻度逐位相同。
4. **两组上界互相自洽**：`QTY_MAX × PRICE_MAX / Q_SCALE = 2.5e15 ≤ AMOUNT_MAX = 4e15`，
   不存在「数量与价格都合法、金额必然违反 INV-007」的死角；旧刻度同款检算比例一模一样。
5. **新增 M6（计提余数）与 M7（向上取整）两条缩放规则**，M1/M3 改写，M0/M4/M5 保留。
6. **§13.5 记录本轮唯一一处真冲突**：最大余数法的入口断言旧表述 `|total| ≤ INT64_MAX / Σweights`
   在新刻度下会**拒绝基年第一次付息**（`total = 317 500 000 μU` vs 上界 `214 497 024 μU`），
   而实际乘法裕度还有 3.76×。裁定改为充要条件 `|total| · max_i |w_i| ≤ INT64_MAX`，
   并逐条论证「这是把充分条件换成充要条件，不是放宽护栏」。
   **`sim/jw_math.gd::split_lr_into` 尚未同步，改之前基年 S06 会误报 `INT_OVERFLOW`。**

### 16.3 R-ACCESS-01

| 小节 | 改动 |
|---|---|
| §6.3 | `state.group.service_access_ppm[]` 行补注「**各组可以不同**」 |
| §6.3 | **新增** `content.group.base_service_access_ppm[]`（长度 3，C 类，LOAD 写，此后只读） |
| §6.3 民生基线口径 | 把「服务可及性」从加权恒等式中**删除**，改为点名 `consumption_index_ppm` 与 `derived.living.public_service_index_ppm` |
| §6.3 | **新增**裁定块：说明区间与恒等式互斥（联立只剩「36 组全取 1 000 000」这一个解，等于抹平开局服务不平等）、`base_service_access_ppm` 的用途与它**不进 `content_hash`、不进 `state_hash`** 的理由 |
| §14.8 | INV-103 追加区间与「不存在加权恒等式」的表述 |
| §14.12 | INV-149 点名两个指数，并显式排除 `service_access_ppm` |

### 16.4 R-CREDIT-01

| 小节 | 改动 |
|---|---|
| §8.4 | `state.world.credit_limit_uu` 中文名加「**增量额度**」；`credit_used_uu` 加「**只计本局新借**」、初值注「开局存量外债不计入」 |
| §8.4 | `derived.world.external_debt_uu` 中文名加「**存量，不占用额度**」 |
| §8.4 | **新增**裁定块：写明理由（存量外债的约束已由还本付息现金流表达，再占额度是重复计价，且会制造「还得起却借不到」这种无法追溯的拒绝）、可用额度唯一公式、还本**不释放**额度、冲击只压上限不追缴、国内侧为何不需要对称的存量计数器 |
| §3.1 | `credit_limit_domestic_memo_uu` 中文名加「**增量额度**」 |
| §14.3 | INV-034 追加增量额度表述 |

### 16.5 已知的跨文件遗留（本轮无权改，交对应负责人）

1. `sim/jw_math.gd::split_lr_into` 的入口断言仍是 `Σweights` 版 —— 见 §13.5，**会误报基年票息分配**。
2. `sim/jw_units.gd` 中 `U_SCALE` 上方的文档注释仍写「`## 1 U = 1 000 000 μU`」，常量值本身已正确。
3. `docs/12_simulation_contract.md` 仍写「基年价计价的量其 μU 数值恒等于 μQ 数值（10 号文件 §2.3）」——
   新刻度下该系数是 1 000，须按本文件 §2.3 同步。
4. `tools/validate_content.py` 的提示文案仍写「AMOUNT_MAX = 4e12」（常量值本身已是 4e15）。
5. `content/scenarios/chengwan/assertions.json`、`scenario.json`、`cells_init.json`、`io_table.json` 的
   `_note_*` 正文里仍有大量旧刻度数字（如「六个批次 8000000 + … = 50000000」「合计 20 000 000 μU」）。
6. `content/scenarios/chengwan/population_init.json` 的 `_note_zh` 与参数卡仍援引已被 R-ACCESS-01 删除的
   `V-POP-07` 服务可及性加权恒等式，并据此把 36 组钉死在 1 000 000；
   开局服务不平等现在**可以**直接写进 `service_access_ppm`，是否迁移需内容层裁定。

---

*本文件为唯一权威版本。任何与之冲突的草案内容一律作废。*
