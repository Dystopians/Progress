# 11 数据协议（唯一权威版）

> 对应计划书 §12「数据协议：尽早固定」、§14「每个参数都带一张身份证」、§16 T03/T04/T08。
> 本文件定义 **`content/` 内容包**与**存档**的全部外部可见数据形态。
> 变量语义以 `10_variable_dictionary.md` 为准；结算过程以 `12_simulation_contract.md` 为准。
> 三份文档的单位、ID、整数规则完全自洽；任一处冲突以本三份为一体、以最严格者为准并立即修订全部三份。
>
> 立场（综合三份草案后的统一表述）：
> **schema 本身就是第一道测试；数据文件是账本的初始分录，不是配置表。**
> 凡能用 schema 排除的错误不留给运行期；schema 排除不掉的（如「8% 失业率必须反算得出」）一律转成载入期断言。
> **任何不能被校验器证明「账能对上」的剧本一律拒绝加载**，而不是加载后靠运行时补救。

---

## 1 总原则

1. **内容包是只读数据，不是脚本。** 只有 JSON，不允许内嵌表达式、不允许 GDScript 回调、不存在表达式求值器
   （事件触发只有六种比较运算）。计划书 §12「不得隐藏不可追溯的脚本副作用」在结构上由此保证。
2. **一切外部数值以整数进入。** JSON 中禁止小数点、指数记号与负零。
   解析后立即断言 `typeof(v) == TYPE_INT`（Godot 的 `JSON.parse_string` 对带小数点的数返回 `float`，一旦出现小数已丢精度）。
3. **所有 ID 在加载期解析成 int 下标**，存入 `IdRegistry`；SimCore 运行期不再见到字符串。
   下标顺序由 `10_variable_dictionary.md` §0.5 的**枚举表**决定，**不随文件中出现顺序变化**。
4. **校验分层，任一层失败即拒绝加载**：文件格式 → schema → 必填 → 类型 → 区间 → 单文件语义
   → 跨文件引用 → 剧本硬约束（会计对账）。**不自动修正、不填默认值兜底。**
5. **展示文案与数据分离。** `label_zh` / `desc_zh` / `*_note_*` 只供 Presentation 读取；
   SimCore 的加载器不读它们，`content_hash` 也不包含它们（§6.4）。改一句中文不会让老存档失效。

---

## 2 文件布局

```
content/
  scenarios/chengwan/
    scenario.json            # Scenario 根文件，引用下列各文件
    io_table.json            # IOTable（技术系数）
    regions.json             # RegionInit
    population_init.json     # PopulationInit（36 群组）
    cells_init.json          # CellInit（16 生产单元，物理 + 财务初值）
    pubserv_init.json        # PubservInit（4 个公共服务单元）
    government_init.json     # GovernmentInit（含债券存量批次、投资池、外部世界）
    politics_init.json       # PoliticsInit
    assertions.json          # 载入期冗余断言（§5.11）
  policies/policy_P01.json .. policy_P12.json      # 12 个，缺一不可
  events/event_E01.json  .. event_E12.json         # 12 个，缺一不可
  shocks/shock_S01.json  .. shock_S03.json         #  3 个，缺一不可
  parameters/params_core.json                      # ParameterCard 集合（手写，事实来源）
  parameters/registry.json                         # ParameterRegistry（**生成产物**，见 §5.16）
  schemas/*.schema.json                            # 本文件各类型的机读版本
  id_aliases.json                                  # 旧 ID → 新 ID，仅读档路径生效
  tombstones.json                                  # 已删除实体的墓碑（ID 永不复用）
```

存档：`user://saves/<slot>/`（目录结构见 §6）。

---

## 3 JSON 方言限制（比标准 JSON 更严）

| 规则 | 理由 | 错误码 |
|---|---|---|
| 不允许浮点字面量（`1.5`、`1e3`、`.5`、`-0`） | int64 定点纪律 | `E_FLOAT_IN_CONTENT` |
| 整数绝对值 ≤ 2^53（JSON 互操作安全区） | 防止解析器静默丢精度；`AMOUNT_MAX = 4e15 < 9.007e15`（裁定 R-SCALE-01 后仍成立，但裕度只剩 2.25 倍，不得再抬高 `AMOUNT_MAX`） | `E_INT_RANGE` |
| 不允许用 `null` 表示「未填」，必须显式给值或省略可选键 | `null` 与 0 的混淆是最常见的账目缺陷 | `E_NULL_NOT_ALLOWED` |
| 对象键必须是 schema 已声明的键（`additionalProperties: false`） | 拼错字段名会被静默忽略 | `E_UNKNOWN_FIELD` |
| 键名英文 `snake_case`；展示文案值用简体中文 | 已锁定的工程决策 | `E_KEY_NAMING` |
| UTF-8 无 BOM、LF 换行、末尾单换行 | 内容哈希稳定 | `E_FILE_FORMAT` |
| 顶层必须有 `schema_kind`（常量）与 `schema_version`（整数 ≥ 1） | 迁移链的唯一依据 | `E_SCHEMA_HEADER` |

**大整数的可读性**：JSON 不支持数字分隔符。**不允许**在数值里写下划线，也**不允许**用字符串形式的
`"50_000_000_000"`（草案 A 的提议被否决：它给解析器开了一个「字符串也能当数」的口子，而这个口子的第一个
受害者就是 `is_integer` 检查）。裁定 R-SCALE-01 把 1 U 从 10⁶ μU 改成 10⁹ μU 之后，金额字面量普遍多出三位，
这条纪律只会更重要，不会更宽松。取而代之：可在同级写注释键 `"_note_<field>": "50 U"`，
schema 允许该键但不参与任何逻辑；测试 `test_u_note_consistency` 解析 `_note_` 中的「N U」并断言与数值一致，
防止注释与数值漂移。

---

## 4 ID 命名规则（机器可检查）

```
id_pattern    = ^[a-z][a-z0-9_]*(\.[a-zA-Z0-9_]+)*$        # 段内小写下划线；策略/事件/冲击段允许大写
region_id     = ^region\.(beiyuan|zhongzhou|haijia|xiling)$
sector_id     = ^sector\.(agri|manu|energy|services)$
cell_id       = ^cell\.(beiyuan|zhongzhou|haijia|xiling)\.(agri|manu|energy|services)$
pubserv_id    = ^pubserv\.(beiyuan|zhongzhou|haijia|xiling)$
group_id      = ^group\.(beiyuan|zhongzhou|haijia|xiling)\.(minor|working|elder)\.(low|mid|high)$
policy_id     = ^policy\.P(0[1-9]|1[0-2])$
event_id      = ^event\.E(0[1-9]|1[0-2])$
shock_id      = ^shock\.S0[1-3]$
param_id      = ^param\.[a-z][a-z0-9_]*$
bloc_id       = ^bloc\.(agri_coop|business|labor_public)$
bond_id       = ^bond\.q(-?[0-9]{1,3})_[0-9]{2}$           # 开局存量批次 issue_q 为负
project_id    = ^project\.P[0-9]{2}_(-?[0-9]{1,3})_[0-9]{3}$
agent_id      = ^agent\.(gov|invpool|row|opening)$
              | ^agent\.cell\.[a-z]+\.[a-z]+$
              | ^agent\.pubserv\.[a-z]+$
              | ^agent\.group\.[a-z]+\.[a-z]+\.[a-z]+$
account_id    = ^account\.<agent_id 去掉前缀 agent\.>\.(cash|wip|capital|housing|recv|bondhold|deposit_claim|pay|debt|deposit_liab)$
              | ^account\.<...>\.inv\.(agri|manu|energy|services)$
scenario_id   = ^scenario\.[a-z][a-z0-9_]*$
paramset_id   = ^paramset\.[a-z][a-z0-9_]*$
```

规则：

1. ID 一经进入任何已发布存档即**永不复用、永不改名**。改名 = 新增 ID + `id_aliases.json` 登记；
   删除 = `tombstones.json` 留墓碑。别名只在读档路径生效；新内容文件中出现别名侧 ID 即 `E_ALIAS_IN_CONTENT`。
2. 运行期生成的 ID（债券批次、项目）**只来自单调计数器** `state.meta.entity_seq`，
   禁止时间戳、指针地址、哈希（INV-010）。
3. 枚举值同样受正则约束，禁止自由字符串。
4. 加载器构建全局 ID 表，重复 ID 直接拒绝（`E_DUP_ID`）。
5. 保留字 `me` / `null` / `true` / `false` 不可作为段名。

---

## 5 各类型 schema

记号：`!` 必填，`?` 可选，`[]` 数组，`{k:v}` 映射。机读版本放在 `content/schemas/`。

**允许的 `schema_kind`（闭集合；出现其它值即 `E_SCHEMA_HEADER`）**

| `schema_kind` | 定义于 | 来源 |
|---|---|---|
| `scenario` | §5.4 | 手写 |
| `io_table` | §5.5 | 手写 |
| `regions` | §5.6 | 手写 |
| `population_init` | §5.7 | 手写 |
| `cells_init` | §5.8 | 手写 |
| `pubserv_init` | §5.8 | 手写 |
| `government_init` | §5.9 | 手写 |
| `politics_init` | §5.10 | 手写 |
| `assertions` | §5.11 | 手写 |
| `policy_definition` | §5.12 | 手写 |
| `event_template` | §5.13 | 手写 |
| `shock_definition` | §5.14 | 手写 |
| `parameter_set` | §5.15 | 手写 |
| `parameter_registry` | §5.16 | **生成产物**（`tools/build_param_registry.py`，不手工编辑） |

> **裁定 R-SCHEMA-01 的落点在两处，缺一不可**：`parameter_registry` 既要进本表（否则 `E_SCHEMA_HEADER`），
> 也要进 §2 的文件布局（否则 `E_CONTENT_LAYOUT`）。只补一处的话文件仍然进不来。

### 5.1 整数编码对照

> **刻度以 `sim/jw_units.gd` 为唯一事实来源**（裁定 R-SCALE-01：`U_SCALE = 1 000 000 000`，
> `Q_SCALE = PPM = 1 000 000`）。本表是它的内容层投影，两者不符时改本表，不改引擎常量。

| 概念 | 键后缀 | 编码 | 例 |
|---|---|---|---|
| 金额 | `_uu` | 1 U = 1 000 000 000 μU | 50 U → `50000000000` |
| 数量 | `_uqs` | 1 Q_s = 1 000 000 μQ_s | 3.5 Q_s → `3500000` |
| 价格 | `_uu_per_qs` | 基年 = 1 000 000 000 | `1000000000` |
| 产能 | `_uqs_per_q` | μQ_s/季 | `8000000` |
| 投入系数 | `_uqs_per_qs` | μQ_from 每 1 Q_to 产出 | `120000` |
| 用工系数 | `_persons_per_qs` | 人 每 1 Q_s 产出 | `40000` |
| 比率 | `_ppm` | 1 = 1 000 000 | 8% → `80000` |
| 人口 | `_persons` | 整数人 | `9000000` |
| 件数 | `_units` | 整数件 | `1600000` |
| 时间 | `_q` | 季度索引，q=0 为基年第 1 季 | 第 8 季 → `7` |
| 位掩码 | `_mask` | 整数位或 | `5`（地区 0 与 2） |

> **R-SCALE-01 只动货币一列**：`_uu`、`_uu_per_qs`、`_uu_per_person_q`、`_uu_per_unit_q`
> 这些分子带 μU 的后缀整体 ×1000；`_uqs`、`_uqs_per_q`、`_uqs_per_qs`、`_persons_per_qs`、`_ppm`、
> `_persons`、`_units`、`_q`、`_count`、`_mask`、`_uqe` 一律**不变**（实物与比率与货币刻度无关）。
> `_ppmuu`（余数累加器，单位 μU·ppm）也**不变**：它的取值恒在 `[0, 999 999]`，由 `PPM` 定界而非由 μU 定界，
> 满 1 000 000 就结转成 1 μU（§5.2 的「计提」行）——刻度变细只让它更频繁地满仓，不改变它的上界。
> **唯一的反向例外**：分母带 μU 的系数方向相反——`capacity_per_capital_uu_ppm` 的单位是 μQ_s 每 μU 资本，
> μU 变细 1000 倍 ⇒ 该系数 **÷1000**（R-SCALE-01 连带要求 2）。凡新增「每 μU」口径的系数，
> 都必须在本处登记方向，不得靠读者推断。

### 5.2 取整与余数的协议层规则

SimCore 只允许通过以下六个函数做除法与分配（`mul` 是乘法的唯一入口，不计在内）；**静态检查禁止裸 `/` 与 `%`**
（GDScript 的 `/` 对整数向零截断，`%` 取被除数符号，两者都不是我们要的语义）。

> **参考实现与真实实现的对应**：下面这段是契约层的规范，真实实现是 `sim/jw_math.gd`（`class_name JWMath`），
> 算术逐字一致，只有函数名按 `docs/17_api_skeleton.md` §1.1 的映射表改写：
> `IntMath.idiv_floor` → `JWMath.floor_div`、`IntMath.idiv_ceil` → `JWMath.ceil_div`、
> `IntMath.split_largest_remainder` → `JWMath.split_lr_into`（热路径）／`JWMath.split_lr`（冷路径）；
> `mul` / `mul_div_floor` / `mul_ppm` / `mul_ppm_2` 两边同名。常量在 `sim/jw_units.gd`（`class_name JWUnits`）。
> 这条映射登记在 docs/17 的 `IR-01`，是**已知的命名分歧**，不是实现跑偏；改任何一侧都必须同时改另一侧。

```gdscript
class_name IntMath

const U_SCALE:    int = 1_000_000_000              # 裁定 R-SCALE-01：1 U = 10⁹ μU
const Q_SCALE:    int = 1_000_000                  # 1 Q_s = 10⁶ μQ_s（不随货币刻度变化）
const PPM:        int = 1_000_000
const BASE_PRICE: int = 1_000_000_000              # 基年价 μU/Q_s，== U_SCALE（INV-148）
const AMOUNT_MAX: int = 4_000_000_000_000_000      # 4×10¹⁵ μU == 4×10⁶ U
const QTY_MAX:    int = 1_000_000_000_000
const PRICE_MIN:  int =   400_000_000              # 基年价的 0.4 倍
const PRICE_MAX:  int = 2_500_000_000              # 基年价的 2.5 倍
const INT64_MAX:  int = 9_223_372_036_854_775_807
const INT64_MIN:  int = -9_223_372_036_854_775_807 - 1   # 写成算式：其正值不是合法 int64 字面量

# 溢出守卫：debug 与 release 都执行（Godot 的 assert 在 release 被剥离，故用显式 if）。
# INT64_MIN 没有正的绝对值，是一切「取反 / 取绝对值」的溢出奇点，必须先挡掉再谈裕度。
static func mul(a: int, b: int) -> int:
    if a == 0 or b == 0:
        return 0
    if a == INT64_MIN or b == INT64_MIN:
        Fault.raise(Fault.INT_OVERFLOW)
        return 0
    var aa: int = a if a >= 0 else -a
    var ab: int = b if b >= 0 else -b
    # rounding: floor, reason=aa > floor(INT64_MAX/ab) 等价于 aa*ab > INT64_MAX，是精确判据不是近似
    if aa > idiv_floor(INT64_MAX, ab):
        Fault.raise(Fault.INT_OVERFLOW)          # 不做饱和截断
        return 0
    return a * b

# 1) 向下取整除法（对负数也向 −∞）
static func idiv_floor(a: int, b: int) -> int:
    if b == 0:
        Fault.raise(Fault.DIV_ZERO)
        return 0
    if a == INT64_MIN and b == -1:               # 真值是 INT64_MAX + 1，int64 装不下
        Fault.raise(Fault.INT_OVERFLOW)
        return 0
    var q: int = a / b                            # GDScript: 向零截断
    if (a % b != 0) and ((a < 0) != (b < 0)):
        q -= 1
    return q

# 2) 向上取整除法（用于「投入消耗」「用工人数」等不得少算的场合）
static func idiv_ceil(a: int, b: int) -> int:
    if a == INT64_MIN:                            # -a 溢出；不做饱和截断，交调用方走失败路径
        Fault.raise(Fault.INT_OVERFLOW)
        return 0
    return -idiv_floor(-a, b)

# 3) 无溢出的 floor(a * b / c)（c > 0）—— 唯一合法的「先乘后除」入口（裁定 R-SCALE-01 连带要求 1）。
#    设 a = q*c + r 且 0 <= r < c（idiv_floor 语义保证），则 floor(a*b/c) == q*b + floor(r*b/c)，
#    因为 q*b 已是整数。中间量最大只到 max(|q*b|, |r*b|)，而不是 |a*b|。
static func mul_div_floor(a: int, b: int, c: int) -> int:
    if c <= 0:
        Fault.raise(Fault.DIV_ZERO)
        return 0
    # rounding: floor, reason=R-SCALE-01，先拆商与余数，避免 a*b 的中间溢出
    var q: int = idiv_floor(a, c)
    var r: int = a - mul(q, c)
    var hi: int = mul(q, b)
    var lo: int = idiv_floor(mul(r, b), c)
    if lo > 0 and hi > INT64_MAX - lo:
        Fault.raise(Fault.INT_OVERFLOW)
        return 0
    if lo < 0 and hi < INT64_MIN - lo:
        Fault.raise(Fault.INT_OVERFLOW)
        return 0
    return hi + lo

# 4) ppm 缩放（单次）—— 必须走 mul_div_floor，不得写成 idiv_floor(mul(x, p), PPM)
static func mul_ppm(x: int, p: int) -> int:
    # rounding: floor, reason=M1，换算只取整一次，少给优于凭空多给
    return mul_div_floor(x, p, PPM)

# 5) 两个 ppm 合并后只取整一次（禁止 mul_ppm(mul_ppm(x,p1),p2) 的双重取整）
static func mul_ppm_2(x: int, p1: int, p2: int) -> int:
    # rounding: floor, reason=M2，先把两个系数合成一个 ppm
    var p: int = idiv_floor(mul(p1, p2), PPM)
    # rounding: floor, reason=M1，合成系数对 x 的唯一一次取整
    return mul_div_floor(x, p, PPM)

# 6) 最大余数法：把 total 按 weights 拆分，保证 Σ result == total
static func split_largest_remainder(total: int, weights: PackedInt64Array,
                                    tiebreak_keys: PackedInt64Array) -> PackedInt64Array:
    # 前置：total >= 0；∀ w >= 0；W = Σ w；n <= 256
    # W == 0 时返回全 0，并把 total 记入调用方指定的余数登记账（显式，不丢失）
    # 入口溢出守卫（R-SCALE-01 之后是硬性的，不再是形式）：
    #     if total > idiv_floor(INT64_MAX, W): Fault.raise(Fault.INT_OVERFLOW)
    #     —— 因为 total * w_i <= total * W，逐项判定退化成这一次判定
    # base_i = idiv_floor(mul(total, w_i), W)
    # rem_i  = total * w_i - base_i * W
    # r = total - Σ base_i                    （0 <= r < n）
    # 把 1 单位依次加给 rem_i 最大的 r 个；rem_i 并列时按 tiebreak_keys 升序（下标即稳定 ID 序）
    # 后置断言：Σ result == total              （INV-003）
```

**为什么 `mul_div_floor` 是强制的，而不是一种优化**（裁定 R-SCALE-01 连带要求 1）

新刻度下，契约上界处的裸乘**真的溢出 int64**，不是理论风险：

| 表达式 | 真值 | int64 能否装下 |
|---|---|---|
| `mul(AMOUNT_MAX, PPM)` | 4×10²¹ | **否**（INT64_MAX ≈ 9.22×10¹⁸） |
| `mul(QTY_MAX, PRICE_MAX)` | 2.5×10²¹ | **否** |

也就是说「金额 × 1 ppm」与「数量上界 × 价格上界」这两件最平常的事，在旧写法 `idiv_floor(mul(x, p), PPM)`
下会在上界处登记 `INT_OVERFLOW` 并返回 0——一笔钱会静默变成 0。
`mul_div_floor` 的结果与 `floor(a·b/c)` 的数学真值**精确相等**（不是近似、不是饱和截断），中间量不溢出。
测试 `test_scaled_ceilings_require_mul_div_floor` 把这条钉死：它先证明裸乘在契约上界处确实登记
`INT_OVERFLOW`，再证明 `mul_div_floor` 在同样输入上给出精确值且不报故障。

**三类除法的归属（与 10 号文件 §0.9 完全一致，不得另立）**

| 类别 | 判据 | 取整 | 余数去向 | 首版适用范围 |
|---|---|---|---|---|
| **拆分** | 把一笔**已存在**的金额／数量分给 n 个去向 | 最大余数法 | 无余数 | 工资到组、支出到收款方、配给、年度拆季、等额本金、支持度加权 |
| **计提** | 对**存量**按率计提并形成**持续债权债务** | floor + 余数累加器 | `*_remainder_ppmuu`，满 1 000 000 结转 1 μU | **仅债券票息** |
| **换算** | 数量×价格、税基×税率、折旧、一切 ppm 缩放 | floor（或按保守方向 ceil） | 写 `log.rounding` 备查，**不产生债权债务** | 其余全部 |

**每个调用点必须写注释** `# rounding: floor|ceil|lr, reason=...`；
测试 `test_u_rounding_sites` 扫描全部调用点，缺注释即失败（INV-002）。

**「四舍五入」在本项目中不存在。**

### 5.3 账本交易类型码（`log.ledger.kind`）与三重分类白名单

`kind` 是闭集合；新增 `kind` 必须同时在下表登记三重分类，否则 `E_LEDGER_KIND_UNCLASSIFIED`（INV-114）。

| code | kind | prod_class | exp_class | inc_class |
|---|---|---|---|---|
| 1 | `wage_payment` 企业付工资 | none | none | `compensation` |
| 2 | `public_wage_payment` 政府付公共部门工资 | `va_nonmarket` | `G` | `compensation` |
| 3 | `household_consumption` 居民消费 | `sale_final` | `C` | none |
| 4 | `gov_procurement` 政府采购 | `sale_final` | `G` | none |
| 5 | `intermediate_purchase` 企业购入投入 | `sale_intermediate` | none | none |
| 6 | `inventory_change` 存货变动（基年价） | `inv_change` | `dINV` | none |
| 7 | `capital_purchase` 资本品购入 | `sale_final` | `I` | none |
| 8 | `export` 出口 | `sale_final` | `X` | none |
| 9 | `import` 进口 | none | `M`（负号） | none |
| 10 | `income_tax` 个人所得税 | none | none | none |
| 11 | `profit_tax` 企业利润税 | none | none | none |
| 12 | `subsidy` 企业补助 | none | none | none |
| 13 | `transfer` 法定转移支付 | none | none | none |
| 14 | `household_support` 组间赡养转移 | none | none | none |
| 15 | `bond_issue` 新增借款 | none | none | none |
| 16 | `bond_principal` 还本 | none | none | none |
| 17 | `bond_interest` 利息 | none | none | none |
| 18 | `property_income` 财产收入分配 | none | none | none |
| 19 | `project_payment` 项目履约付款 | none | `I` | none |
| 20 | `service_opex` 服务运行费 | `va_nonmarket` | `G` | none |
| 21 | `depreciation` 折旧（非现金） | none | none | `consumption_of_fixed_capital` |
| 22 | `operating_surplus` 营业盈余结转（非现金） | none | none | `gross_operating_surplus` |
| 23 | `price_variance` 采购价差（非现金） | none | none | none |
| 24 | `opening_balance` 开账分录（q = −1） | none | none | none |
| 25 | `migration_cost` 迁移成本（再分配类，docs/18 R-MIGRATE-01；原 `sale_final` / `C`） | none | none | none |
| 26 | `policy_toggle_cost` 政策开关行政成本 | `va_nonmarket` | `G` | none |
| 27 | `cancel_penalty` 合同赔偿 | none | none | none |
| 28 | `writeoff` 债务减记 | none | none | none |

> `kind ∈ {10..18, 27, 28}` 在三种口径下**全部为 none**：借款不是收入、还本不是 GDP、
> 补助不重复计入最终产出、税与转移是再分配（INV-029、INV-113）。

### 5.4 `Scenario`（根文件）

```jsonc
{
  "schema_kind": "scenario",
  "schema_version": 1,
  "scenario_id": "scenario.chengwan",
  "label_zh": "澄湾共和国",
  "reference_year": 0,                        // 虚构剧本用 0，仅供文案与参数卡对账
  "unit_declaration": {                       // 全为常量，存在的唯一目的是让错误剧本在载入时就死掉
    "money_micro_per_unit": 1000000000,       // == JWUnits.U_SCALE（裁定 R-SCALE-01）
    "quantity_micro_per_qs": 1000000,         // == JWUnits.Q_SCALE，不随货币刻度变化
    "ppm_scale": 1000000,                     // == JWUnits.PPM，不随货币刻度变化
    "base_price_uu_per_qs": 1000000000        // == JWUnits.BASE_PRICE
  },
  "horizon_q": 40,                            // ∈ {40, 120}；压力测试用 120
  "param_set_ref": "paramset.baseline",
  "param_set_version": 1,
  "root_seed": 0,                             // 0 = 运行时注入（玩家或测试夹具指定）
  "includes": {
    "io_table":         "io_table.json",
    "regions":          "regions.json",
    "population_init":  "population_init.json",
    "cells_init":       "cells_init.json",
    "pubserv_init":     "pubserv_init.json",
    "government_init":  "government_init.json",
    "politics_init":    "politics_init.json",
    "assertions":       "assertions.json"
  },
  "enabled_policies": ["policy.P01", "…"],    // 首版 12 项全列
  "enabled_events":   ["event.E01", "…"],
  "enabled_shocks":   ["shock.S01", "shock.S02", "shock.S03"],
  "season_factor_ppm": {                      // 每条数组 4 项，Σ 必须 == 1000000
    "gov_receipts":  [250000, 250000, 250000, 250000],
    "gov_primary":   [250000, 250000, 250000, 250000],
    "agri_output":   [175000, 275000, 350000, 200000]
  },
  "prices_init": {
    "sector_uu_per_qs": [1000000000, 1000000000, 1000000000, 1000000000],
    "base_uu_per_qs":   [1000000000, 1000000000, 1000000000, 1000000000],
    "wage_uu_per_person_q": [0, 0, 0],        // 必填，由剧本作者给出，> 0
    "housing_rent_uu_per_unit_q": [0, 0, 0, 0]
  },
  "world_init": {
    "fx_rate_ppm": 1000000,                   // const
    "export_demand_ppm":    [1000000, 1000000, 1000000, 1000000],
    "import_price_ppm":     [1000000, 1000000, 1000000, 1000000],
    "delivery_capacity_uqs":[0, 4000000, 2000000, 0],
    "credit_limit_uu": 15000000000,
    "sovereign_rate_ppm_per_q": 10000,        // 必须 == param.market_rate_base_ppm，见下
    "cash_uu": 15000000000                    // agent.row 的初始现金（INV-018 需要）
  },
  "mandate_goals": ["industry", "livelihood", "fiscal"],
  "total_cash_uu": 0,                         // 全经济现金总量；载入时由各主体初值求和校验（INV-018）
  "notes_zh": "数字为测试起点，不是现实国家数据或已跑出的结果。"
}
```

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `unit_declaration.money_micro_per_unit` | int | ✔ | == `JWUnits.U_SCALE` == 1 000 000 000，否则 `E_UNIT_MISMATCH` |
| `unit_declaration.quantity_micro_per_qs` / `ppm_scale` | int | ✔ | == 1 000 000（`Q_SCALE` / `PPM`，不随 R-SCALE-01 变化） |
| `unit_declaration.base_price_uu_per_qs` | int | ✔ | == `JWUnits.BASE_PRICE` == 1 000 000 000 |
| `horizon_q` | int | ✔ | ∈ {40, 120} |
| `root_seed` | int | ✔ | int64 全域；0 表示运行时注入 |
| `season_factor_ppm[*]` | int[4] | ✔ | 每条 Σ == 1 000 000（INV-042） |
| `prices_init.sector_uu_per_qs` / `base_uu_per_qs` | int[4] | ✔ | 每项 == 1 000 000 000（INV-148） |
| `prices_init.wage_uu_per_person_q` | int[3] | ✔ | 每项 > 0 |
| `world_init.fx_rate_ppm` | int | ✔ | == 1 000 000（INV-105） |
| `world_init.sovereign_rate_ppm_per_q` | int | ✔ | ∈ [0, 100 000]，且 == `param.market_rate_base_ppm`（见下） |
| `total_cash_uu` | int | ✔ | 必须等于各主体 `cash_uu` 初值之和（INV-018） |

> **`world_init.sovereign_rate_ppm_per_q` 为什么取 10 000**：它不是自由参数。12 号文件 §1.1 的 01.7
> 每季都用 `clamp(param.market_rate_base_ppm + mul_ppm(eff_ppm[S03], param.rate_sensitivity_ppm), 0, 100_000)`
> 重算这个字段，而 q=0 开局无冲击 ⇒ `eff_ppm[S03] == 0` ⇒ 首次重算结果恒等于 `param.market_rate_base_ppm`。
> 本字段只在 q=0 的 S01 之前有效，此后每季被覆盖。若初值与 `param.market_rate_base_ppm`（§5.15 = 10 000）
> 不等，玩家会在「存档载入瞬间的利率」与「第一季的利率」之间看到一次无法解释的跳变，而报告层没有任何
> 事件可以解释它。**两者必须一起改。** 本契约此前在此处写 12 500、在 §5.15 写 10 000，是同一个数的两处
> 不同写法，已按 §5.15 统一为 10 000（旧值 12 500 与 §5.9 中 `bond.q-4_01` 的 `coupon_ppm_per_q` 同值，
> 属巧合，两者无推导关系）。

> **压力测试的 120 季不改剧本文件**：由命令行参数 `--horizon 120` 覆盖，并在存档中记录实际值（OQ-210）。

### 5.5 `IOTable`

```jsonc
{
  "schema_kind": "io_table",
  "schema_version": 1,
  "sectors": ["sector.agri", "sector.manu", "sector.energy", "sector.services"],   // 顺序固定
  "io_coeff_uqs_per_qs": {          // 生产 1 Q_s 的「列部门」需要多少 μQ 的「行部门」产品
    "sector.agri":     { "sector.agri":  80000, "sector.manu": 120000, "sector.energy":  60000, "sector.services":  90000 },
    "sector.manu":     { "sector.agri": 150000, "sector.manu": 250000, "sector.energy": 180000, "sector.services": 140000 },
    "sector.energy":   { "sector.agri":      0, "sector.manu": 200000, "sector.energy":  50000, "sector.services":  80000 },
    "sector.services": { "sector.agri":  30000, "sector.manu":  90000, "sector.energy":  70000, "sector.services": 110000 }
  },
  "labor_coeff_persons_per_qs": {   // 按 (部门, 技能)；0 表示该档不需要 -> 跳过该约束
    "*": {
      "sector.agri":     { "low": 140000, "mid":  20000, "high":   2000 },
      "sector.manu":     { "low":  40000, "mid":  60000, "high":  10000 },
      "sector.energy":   { "low":   5000, "mid":  12000, "high":   6000 },
      "sector.services": { "low":  60000, "mid":  70000, "high":  25000 }
    },
    "cell.beiyuan.agri": { "low": 165000, "mid": 18000, "high": 1500 }        // 单格覆盖
  },
  "energy_coeff_uqs_per_qs":       [30000, 150000, 20000, 50000],
  "spoilage_ppm":                  [20000, 2000, 0, 0],
  "depreciation_ppm_per_q":        [10000, 15000, 12000, 8000],
  "capacity_per_capital_uu_ppm":   [600, 500, 300, 700],        // μQ_s/季 每 μU 资本，见下
  "emission_ppm":                  [20000, 90000, 500000, 15000],
  "storable":                      [1, 1, 0, 0]        // energy 与 services 必须为 0
}
```

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-IO-01 | `io_coeff` 每**列**和 < 1 000 000（否则中间投入吃光总产出，增加值必为负） | `E_IO_COLSUM` |
| V-IO-02 | `storable[energy] == 0` 且 `storable[services] == 0`（计划书 §06「电力当期使用，不跨季储存」） | `E_IO_STORABLE` |
| V-IO-03 | `io_coeff[energy][energy] < 1 000 000`（能源自用不得吞掉自身产出，见 12 号 §3.5） | `E_IO_ENERGY_SELF` |
| V-IO-04 | 全部系数 ≥ 0；`== 0` 是合法值（表示跳过该约束），不是错误 | `E_IO_NEGATIVE` |
| V-IO-05 | Leontief 可行性整数近似：以单位最终需求做 30 轮整数迭代，累计投入增量收敛到 < 1 μQ | `E_IO_NOT_CONVERGENT` |
| V-IO-06 | `labor_coeff` 展开后，每个 (cell, skill) 要么 `== 0` 要么 `≥ 1`；至少一档 > 0 | `E_IO_LABOR` |
| V-IO-07 | `capacity_per_capital_uu_ppm[s] > 0` | `E_IO_CAPACITY_COEFF` |
| V-IO-08 | `energy_coeff_uqs_per_qs[s] == io_coeff_uqs_per_qs[sector.energy][s]`（**故意冗余，交叉校验**；运行期只用 IO 表那一份） | `E_IO_ENERGY_COEFF` |

覆盖语法：键 `"*"` 是默认值，`"cell.<region>.<sector>"` 覆盖单格。**加载期展开成定长数组，运行期不再有 map。**

> **诚实登记**：V-IO-05 用整数幂和近似，不是精确特征值计算；目的只是拦住「投入比产出还多」这类明显错配的表，
> 不宣称数学严谨。（采纳草案 A 的自我声明。）

> **`capacity_per_capital_uu_ppm` 是 R-SCALE-01 下唯一方向相反的系数**：它的单位是 μQ_s/季 **每 μU 资本**，
> μU 变细 1000 倍 ⇒ 同一条物理关系对应的系数必须 **÷1000**，不是 ×1000。本表示例由旧刻度的
> `[600000, 500000, 300000, 700000]` 整除得到 `[600, 500, 300, 700]`（四个值均能整除，无精度损失）。
> **遗留登记**：该系数在新刻度下的整数粒度只剩约 0.2%～1.8%（即改动 1 个 ppm 就是 1/600 … 1/55 的相对变化）。
> 若基年校准需要更细的控制，应提出契约修订（改为「每 10³ μU」口径并**改名**，按 §6.7 的 M-6：
> 口径变更必须改名换 ID），**不得私自另立第二套比率刻度**。

### 5.6 `RegionInit`

```jsonc
{
  "schema_kind": "regions",
  "schema_version": 1,
  "regions": [
    {
      "region_id": "region.haijia",
      "label_zh": "海岬",
      "population_persons": 5000000,                       // 冗余值，与群组求和交叉校验
      "adjacency": ["region.zhongzhou", "region.xiling"],  // 必须对称、无自环
      "logistics_cost_ppm": { "region.beiyuan": 120000, "region.zhongzhou": 30000,
                              "region.xiling": 80000, "region.haijia": 0 },
      "migration_cost_uu":  { "region.beiyuan": 400000, "region.zhongzhou": 250000,
                              "region.xiling": 350000, "region.haijia": 0 },   // μU/人
      "housing_capacity_units": 1700000,
      "housing_stock_units":    1600000,
      "grid_capacity_uqs_per_q": 4200000,
      "port_capacity_uqs_per_q": 3000000,                  // 内陆为 0
      "irrigation_index_ppm": 400000,
      "construction_slots_total": 2,                       // 1..8
      "area_index": 1000000,                               // 相对面积指数，用于人口密度折算（> 0）
      "emissions_stock_uqe": 1800000,
      "env_exposure_ppm": 180000
    }
  ]
}
```

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-REG-01 | 恰好 4 条，ID 齐全无重复 | `E_REGION_SET` |
| V-REG-02 | 邻接对称、对角为 0；`logistics_cost` / `migration_cost` 对其它 3 区完备，自身为 0 | `E_REGION_ADJ` |
| V-REG-03 | `housing_stock_units ≤ housing_capacity_units` | `E_HOUSE_CAP` |
| V-REG-04 | `1 ≤ construction_slots_total ≤ 8`（施工拥堵失败路径可测的前提） | `E_REGION_SLOTS` |
| V-REG-05 | 地区人口 == 群组按地区求和（北原 9e6 / 中州 7e6 / 海岬 5e6 / 西岭 3e6） | `E_POP_REGION` |

### 5.7 `PopulationInit`

```jsonc
{
  "schema_kind": "population_init",
  "schema_version": 1,
  "groups": [
    {
      "group_id": "group.beiyuan.working.low",
      "population_persons": 2600000,
      "participation_ppm": 720000,                 // 非 working 组必须为 0
      "employed_persons": { "sector.agri": 1300000, "sector.manu": 90000,
                            "sector.energy": 20000, "sector.services": 280000,
                            "pubserv": 40000 },    // 仅 working 组可非空
      "cash_uu": 900000000,
      "deposit_uu": 300000000,
      "housing_units_occupied": 640000,
      "support_out_weight_ppm": 380000,            // 组间赡养转出权重；仅 working 组可非零
      "service_access_ppm": { "health": 620000, "education": 700000, "utility": 850000 },
      "consumption_index_ppm": 1000000,
      "living_index_ppm": 1000000,
      "base_per_capita_real_income_uu": 0,         // 基年人均实际可支配收入基准；> 0，之后只读
      "expectation_ppm": 1000000,
      "trust_ppm": 600000,
      "support_ppm": 520000,
      "bloc_affiliation_ppm": [600000, 100000, 250000]   // 允许 Σ > 1e6（成员可同属多个网络）
    }
    // …共 36 条，允许 population_persons == 0 的空组，但 36 条必须齐全
  ],
  "demography_rates": {
    "birth_ppm_per_q":     { "region.beiyuan": 2600, "region.zhongzhou": 2100,
                             "region.haijia": 2200, "region.xiling": 2400 },
    "death_ppm_per_q":     { "minor": 60, "working": 180, "elder": 6200 },
    "age_out_ppm_per_q":   { "minor": 12500, "working": 5400 },
    "birth_target_skill":  "low"                   // 新生儿落入 group.<r>.minor.low
  }
}
```

**失业率的反算链（不可绕过）**

```
labor_force_g  = idiv_floor(population_persons_g * participation_ppm_g, 1_000_000)   # 仅 working 组
employed_g     = Σ_sector employed_persons[sector] + employed_persons["pubserv"]
unemployed_g   = labor_force_g - employed_g                    # 必须 >= 0
unemployment_ppm = idiv_floor(Σ_g unemployed_g * 1_000_000, Σ_g labor_force_g)
```

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-POP-01 | 恰好 36 条，ID 覆盖 4×3×3 全组合且无重复 | `E_GROUP_SET` |
| V-POP-02 | 全国求和 == 24 000 000；分地区 == 9/7/5/3 百万 | `E_POP_TOTAL` |
| V-POP-03 | `age != working` ⇒ `participation_ppm == 0` 且 `employed_persons` 全 0 且 `support_out_weight_ppm == 0` | `E_POP_AGE_ROLE` |
| V-POP-04 | 逐组 `employed_g ≤ labor_force_g` | `E_POP_EMP` |
| V-POP-05 | **反算**失业率 ∈ [79 500, 80 500] ppm | `E_POP_UNEMP` |
| V-POP-06 | 逐地区 `Σ housing_units_occupied ≤ region.housing_stock_units` | `E_HOUSE_OVER` |
| V-POP-07 | 人口加权的 `consumption_index_ppm` 与 `living_index_ppm` 均 == 1 000 000（**不含服务可及性**，见下） | `E_INDEX_BASE` |
| V-POP-07b | 逐组逐种类 `service_access_ppm ∈ [0, 1 000 000]`；载入期算出人口加权均值登记为只读的 `base_service_access_ppm[3]`，且**每一种类都必须 > 0** | `E_INDEX_BASE` |
| V-POP-08 | 群组侧就业按 (地区, 部门, 技能) 汇总 == `cells_init` / `pubserv_init` 侧的在岗人数（故意冗余，交叉校验） | `E_EMPLOY_MISMATCH` |

> **schema 中不存在 `unemployment_ppm` 字段。** 8% 只能反算，再与 `assertions.json` 的冗余校验值比对。
> 这样「手写失业率」在**语法层面**就不可能（采纳草案 C 的做法）。

**`service_access_ppm` 为什么退出 V-POP-07**（裁定 R-ACCESS-01，覆盖本契约原文）

10 号文件 §6.3 给 `state.group.service_access_ppm` 的区间是 `0…1 000 000`；本契约原先的 V-POP-07 又要求它的
人口加权值 `== 1 000 000`。两条联立的唯一解是 **36 组全取 1 000 000**——于是 §5.7 示例里的
`{health: 620000, education: 700000, utility: 850000}` 在载入期必然失败，而且**开局的服务可及性不平等被彻底抹平**，
与计划书 §08「保留受益和受损的分布」直接冲突。这不是数据填错，是两条校验互斥。

裁定：**删除加权恒等式**。`service_access_ppm` 就是「相对自身基准的可及率」，区间 `0…1 000 000` 保留，
各组可以不同，剧本必须有开局不平等。取而代之的是登记，不是断言：

```
# 载入期计算一次，之后只读；SimCore 运行期任何写入即 FAULT
base_service_access_ppm[kind]
    = idiv_floor(Σ_g mul(population_persons_g, service_access_ppm[g][kind]),
                 max(Σ_g population_persons_g, 1))        # kind ∈ {health, education, utility}
```

- 它是**派生常量，不是输入字段**：`population_init.json` 的 schema 里**不存在** `base_service_access_ppm` 键，
  写了即 `E_UNKNOWN_FIELD`。理由与失业率完全相同——能手写的冗余量迟早会与它的算据漂移。
- 它是 `content.*`（内容常量）而非 `state.*`：**不进 `state_hash`**（§6.4 的排除集合），
  也不需要单独进 `content_hash`——它由 `population_init.json` 完全决定，而那份文件已经进了 `content_hash`。
  换句话说：内容包一改，它自动跟着变；内容包不改，它逐位可复现。
- 用途**唯一**：作后续季度的相对比较基准。`derived.living.public_service_index_ppm` 按它归一化，
  于是基年值恒等于 1 000 000——**INV-149 由此继续成立**，代价不是抹平群组差异，而是换了归一化的分母。
- 三个种类各自 `> 0` 是硬约束：它是除数（见上式的 `max(…, 1)` 只是防崩，不是允许 0），
  某一种类全国全组皆 0 会让该维度的指数在整局内恒为满分或恒为 0，属于剧本缺陷而非合法取值。
- 加权用人口而非组数：空组（`population_persons == 0`）自然不参与，不需要特例。

### 5.8 `CellInit` 与 `PubservInit`

```jsonc
// cells_init.json
{
  "schema_kind": "cells_init",
  "schema_version": 1,
  "cells": [
    {
      "cell_id": "cell.haijia.manu",
      "cash_uu": 3000000000,
      "capacity_active_uqs_per_q": 5000000,
      "capital_value_uu": 10000000000,        // V-CELL-03: 10e9 × 500 / 1e6 == 5e6，精确相等
      "inventory_output_uqs": 600000,
      "inventory_input_uqs": { "sector.agri": 200000, "sector.manu": 400000, "sector.services": 100000 },
      "employment_persons": { "low": 300000, "mid": 450000, "high": 75000 },
      "loss_carryforward_uu": 0,
      "equity_share_ppm": { "group.haijia.working.mid": 400000, "…": 600000 }   // Σ == 1000000
    }
    // …16 条（允许全 0 的空 cell）
  ]
}

// pubserv_init.json
{
  "schema_kind": "pubserv_init",
  "schema_version": 1,
  "units": [
    {
      "pubserv_id": "pubserv.zhongzhou",
      "capacity_active_uqs_per_q": 2600000,
      "capital_value_uu": 9000000000,
      "availability_ppm": 1000000,
      "employment_persons": { "low": 40000, "mid": 90000, "high": 60000 },
      "teachers_persons": 42000,
      "health_staff_persons": 31000,
      "service_capacity_split_ppm": { "health": 400000, "education": 400000, "utility": 200000 }
    }
    // …4 条
  ]
}
```

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-CELL-01 | 恰好 16 条 cell / 4 条 pubserv，ID 齐全无重复 | `E_CELL_SET` |
| V-CELL-02 | `inventory_input_uqs` 不得出现 `sector.energy` 或 `sector.services`（不可库存） | `E_ENERGY_INVENTORY` |
| V-CELL-03 | `\|capacity_active − mul_ppm(capital_value, capacity_per_capital_uu_ppm)\| ≤ 1`（防止「凭空产能」，计划书 §16 人工评审要点） | `E_CAPACITY_INCONSISTENT` |
| V-CELL-04 | `equity_share_ppm` 各项和 == 1 000 000，且键必须是真实群组 | `E_EQUITY_SHARE` |
| V-CELL-05 | `service_capacity_split_ppm` 各项和 == 1 000 000 | `E_SERVICE_SPLIT` |
| V-CELL-06 | 全部 `cash_uu ≥ 0`，全部数量 ≤ `QTY_MAX`，全部金额 ≤ `AMOUNT_MAX` | `E_RANGE` |

### 5.9 `GovernmentInit`

```jsonc
{
  "schema_kind": "government_init",
  "schema_version": 1,
  "gov": {
    "cash_uu": 2000000000,                         // 2 U
    "arrears_uu": 0,
    "tax_receivable_uu": 0,
    "wip_uu": 0,
    "capital_uu": 18000000000,
    "housing_uu": 4000000000,
    "tax_capacity_ppm": 780000,
    "credit_limit_domestic_uu": 8000000000,
    "service_opex_committed_uu": 120000000
  },
  "annual_plan": {
    "receipts_uu": 20000000000,                    // 全年收入 20 U
    "expenditure_incl_interest_uu": 22000000000,   // 全年支出 22 U（含利息，不含还本）
    "deficit_uu": 2000000000,                      // 2 U
    "receipt_lines_uu":    { "income_tax": 11000000000, "profit_tax": 7000000000,
                             "other": 2000000000 },
    "expenditure_lines_uu": { "public_wages": 9000000000, "statutory_transfers": 4000000000,
                              "procurement": 4200000000, "project_contracts": 2000000000,
                              "service_opex": 0, "subsidies": 0, "discretionary": 688000000,
                              "interest": 2112000000 }   // 逐批次复算，见下表
  },
  "payment_priority": ["debt_service", "public_wages", "statutory_transfers", "service_opex",
                       "project_contracts", "procurement", "subsidies", "discretionary"],
  "bonds": [
    { "bond_id": "bond.q-12_01", "issue_q": -12, "principal_initial_uu": 20000000000,
      "principal_outstanding_uu": 20000000000, "coupon_ppm_per_q": 9000,
      "maturity_q": 20, "amortization": "bullet", "holder": "invpool" },
    { "bond_id": "bond.q-8_01",  "issue_q": -8,  "principal_initial_uu": 18000000000,
      "principal_outstanding_uu": 18000000000, "coupon_ppm_per_q": 11000,
      "maturity_q": 28, "amortization": "bullet", "holder": "row" },
    { "bond_id": "bond.q-4_01",  "issue_q": -4,  "principal_initial_uu": 12000000000,
      "principal_outstanding_uu": 12000000000, "coupon_ppm_per_q": 12500,
      "maturity_q": 36, "amortization": "bullet", "holder": "invpool" }
  ],
  "invpool": { "cash_uu": 9000000000 }
}
```

**本示例的 V-FIN-05 复算（逐批次、按 12 号文件 §2 的 02.3）**

| 批次 | 未偿本金 μU | `coupon_ppm_per_q` | 单季利息 μU | 基年四季 μU |
|---|---|---|---|---|
| `bond.q-12_01` | 20 000 000 000 | 9 000 | 180 000 000 | 720 000 000 |
| `bond.q-8_01` | 18 000 000 000 | 11 000 | 198 000 000 | 792 000 000 |
| `bond.q-4_01` | 12 000 000 000 | 12 500 | 150 000 000 | 600 000 000 |
| **合计** | **50 000 000 000**（V-FIN-02） | — | 528 000 000 | **2 112 000 000** |

三笔都取 `bullet`，因此基年四季内 `principal_outstanding_uu` 不变，四季利息相等，整除无余数
（`interest_remainder_ppmuu` 全程为 0）。`expenditure_lines_uu.interest` 因此**必须**写 2 112 000 000，
`discretionary` 吸收差额 688 000 000，四季合计与 V-FIN-03 / V-FIN-04 同时成立。

> **为什么示例三笔都改成 `bullet`**：`amortization` 的取值集合仍是 `{bullet, level_principal}`（V-FIN-07 不变）。
> 但开局存量批次若取 `level_principal`，`principal_outstanding_uu` 就必须等于「面值减去 q=0 之前已摊还的期数」，
> 而「issue_q 到 q=0 之间已摊还几期」这条约定 12 号文件 §2 的 02.4 并未写死（`amort_schedule` 只说按等权重预生成）。
> 契约示例不负责替 T03 发明这条约定，所以改用 `bullet`——它的 `outstanding == initial` 在语义上自洽，
> 于是整个示例可以被 V-FIN-02 / 03 / 04 / 05 逐条复算。开局批次要不要用 `level_principal`，
> 连同「已摊还期数」的约定一起，留给 T03 与 12 号文件的修订。

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-FIN-01 | `gov.cash_uu == 2 000 000 000`（2 U，计划书 §05 锁定值） | `E_CASH_INIT` |
| V-FIN-02 | `Σ bonds[].principal_outstanding_uu == 50 000 000 000`（50 U） | `E_DEBT_TOTAL` |
| V-FIN-03 | `expenditure_incl_interest_uu − receipts_uu == deficit_uu == 2 000 000 000`（2 U） | `E_FIN_YEARPLAN` |
| V-FIN-04 | `Σ receipt_lines == receipts_uu`；`Σ expenditure_lines == expenditure_incl_interest_uu` | `E_FIN_LINES` |
| V-FIN-05 | `expenditure_lines.interest` == 基年四季按逐批次 `coupon_ppm_per_q` 算出的票息之和（**防止债务与利息各写各的**） | `E_FIN_INTEREST` |
| V-FIN-06 | `payment_priority` 是 8 类支出的**全排列**（缺项即行为未定义、不可测） | `E_PRIORITY_INCOMPLETE` |
| V-FIN-07 | 每笔债券 `maturity_q > issue_q`；`coupon_ppm_per_q ∈ [0, 100 000]`；`holder ∈ {invpool, row}` | `E_BOND_FIELD` |
| V-FIN-08 | `invpool.cash_uu ≥ annual_plan.deficit_uu`（基线年赤字必须有对手方买得起，见 OQ-201） | `E_INVPOOL_TOO_SMALL` |
| V-FIN-09 | `Σ group.deposit_uu == invpool.cash_uu + Σ (holder==invpool) principal_outstanding_uu` | `E_DEPOSIT_MISMATCH` |

> **开局债务批次结构是 `design_assumption` 占位。** 计划书 §05 只锁定「合计 50 U」与「必须拆分期限与债权人」；
> 上表的三笔是本契约给出的占位示例，由 T03 剧本任务最终确定。不可变的只有合计与「必须拆分」。
> 占位不等于可以不配平：示例本身必须能被 V-FIN-02..05 逐条复算（见上表），否则它教给剧本作者的就是
> 「这些数各写各的也没关系」。

### 5.10 `PoliticsInit`

```jsonc
{
  "schema_kind": "politics_init",
  "schema_version": 1,
  "seats_total": 101,                       // 必须为奇数
  "seats_gov": 56,
  "next_election_q": 15,                    // ∈ {15, 31}
  "next_budget_review_q": 3,                // q ≡ 3 (mod 4)
  "admin_capacity_ppm": 600000,
  "legal_authority_mask": 7,
  "blocs": [
    { "bloc_id": "bloc.agri_coop",    "org_power_ppm": 300000, "resource_uu": 400000000,
      "veto_domains": ["land_reform"] },
    { "bloc_id": "bloc.business",     "org_power_ppm": 400000, "resource_uu": 900000000,
      "veto_domains": ["tax_law"] },
    { "bloc_id": "bloc.labor_public", "org_power_ppm": 350000, "resource_uu": 500000000,
      "veto_domains": ["public_employment"] }
  ],
  "stance_ppm": { "bloc.business": { "policy.P04": 250000, "…": 0 } }
}
```

校验：`V-POL-01` 恰好 3 个集团；`V-POL-02` `seats_total` 为奇数且 `0 ≤ seats_gov ≤ seats_total`；
`V-POL-03` `next_election_q ∈ {15, 31}`、`next_budget_review_q ≡ 3 (mod 4)`（INV-127）。

### 5.11 `Assertions`（载入期冗余断言）

```jsonc
{
  "schema_kind": "assertions",
  "schema_version": 1,
  "checks": [
    { "id": "assert.total_population", "at": "load",
      "expr": "sum(group.*.population_persons)", "expect": 24000000, "tolerance": 0 },
    { "id": "assert.region_population", "at": "load",
      "expr": "sum_by_region(group.*.population_persons)",
      "expect": [9000000, 7000000, 5000000, 3000000], "tolerance": 0 },
    { "id": "assert.unemployment", "at": "load",
      "expr": "derived.labor.unemployment_ppm", "expect": 80000, "tolerance": 500 },
    { "id": "assert.gov_debt", "at": "load",
      "expr": "derived.gov.debt_uu", "expect": 50000000000, "tolerance": 0 },
    { "id": "assert.gov_cash", "at": "load",
      "expr": "state.gov.cash_uu", "expect": 2000000000, "tolerance": 0 },
    { "id": "assert.annual_deficit", "at": "load",
      "expr": "annual_plan.expenditure_incl_interest_uu - annual_plan.receipts_uu",
      "expect": 2000000000, "tolerance": 0 },
    { "id": "assert.base_prices", "at": "load",
      "expr": "state.price.sector_uu_per_qs",
      "expect": [1000000000,1000000000,1000000000,1000000000], "tolerance": 0 },
    { "id": "assert.living_index", "at": "load",
      "expr": "derived.living.consumption_index_ppm", "expect": 1000000, "tolerance": 0 },
    { "id": "assert.base_service_access", "at": "load",
      "expr": "content.pop.base_service_access_ppm",
      "expect": [620000, 700000, 850000], "tolerance": 0 },   // [health, education, utility]

    { "id": "assert.interest_in_spend", "at": "load",
      "expr": "annual_plan.expenditure_lines_uu.interest", "expect": "sum_q(0..3, bond_coupon_total_uu)", "tolerance": 0 },
    { "id": "assert.base_year_gdp", "at": "q_end:3",
      "expr": "sum_q(0..3, derived.gdp.production_uu)", "expect": 100000000000, "tolerance": 0 },
    { "id": "assert.cash_total", "at": "load",
      "expr": "sum(all_agents.cash_uu)", "expect": "scenario.total_cash_uu", "tolerance": 0 }
  ]
}
```

- `at ∈ load | q_end:<n>`。
- **`tolerance` 只允许为 0，唯一的例外是 `assert.unemployment` 的 500 ppm**
  （因为 8% 是一个被四舍五入过的目标值，而就业分配是整数；计划书 §05 给的是「8%」而非精确 ppm）。
  任何其它非零容差即 `E_ASSERT_TOLERANCE`。
- `assert.base_service_access` 的 `expect` 是**剧本特有值**，不是计划书锁定值：剧本作者按 36 组人口加权
  自行算出 `[health, education, utility]` 三个数并填入，载入器用 §5.7 的公式重算后必须**逐位相等**。
  上面的三个数只是与 §5.7 单组示例同量级的写法示范，换剧本必须重算（裁定 R-ACCESS-01）。
- `expr` 使用一个极小的**只读**表达式语言（`sum`、`sum_by_region`、`sum_q`、字段路径、整数四则），
  解释器本身有单元测试（`test_u_assert_expr`）；`expr` 中禁止调用任何会写状态的函数。
- **`assertions` 是断言，不是输入。** SimCore 绝不从这里读任何值（INV-143）。

> **裁定**：草案 C 要求 `tolerance` 一律为 0，并自己登记了风险「剧本作者调参时会频繁撞墙，
> 将来可能为省事放宽」。本契约的处理是：把**唯一可放宽的一条写死在协议里**（失业率 500 ppm），
> 其余一律 0，并让「出现第二个非零容差」本身成为一个校验错误。这样放宽必须改协议，不能偷偷改数据。

### 5.12 `PolicyDefinition`

```jsonc
{
  "schema_kind": "policy_definition",
  "schema_version": 1,
  "policy_id": "policy.P04",
  "label_zh": "电网可靠性升级",
  "problem_statement_zh": "制造企业受可用供电能力限制。",
  "kind": "project",                                   // rate | transfer | subsidy | project | capacity | admin
  "legal_authority": {
    "authority_bit": 2,
    "requires_budget_review": true,
    "requires_bloc_support": ["bloc.business"],
    "min_seats_ppm": 500000
  },
  "player_params": [
    { "key": "region_mask",    "type": "mask", "valid_range": [1, 15], "default": 4 },
    { "key": "scale_ppm",      "type": "ppm",  "valid_range": [250000, 2000000], "default": 1000000 },
    { "key": "funding_source", "type": "enum", "values": ["cash", "bond", "reallocation"], "default": "bond" }
  ],
  "cost": {
    "one_off_uu": 4000000000,                          // 4 U
    "per_quarter_uu": 500000000,
    "planned_quarters": 8,
    "spend_lines_uu_per_q": { "import_equipment": 200000000, "domestic_material": 100000000,
                              "construction_service": 200000000 },
    "opex_per_q_uu": 20000000,
    "required_construction_uqs": 3200000,              // μQ_services，不随货币刻度变化
    "required_equipment_uqs": 1600000                  // μQ_manu，同上
  },
  "preconditions": [
    { "kind": "construction_slot",  "region_ref": "param:region_mask", "slots": 1 },
    { "kind": "budget_reservation", "amount_ref": "cost.per_quarter_uu" },
    { "kind": "legal_authority",    "bit": 2 }
  ],
  "lag": { "enact_to_effect_q": 1, "min_feedback_q": 4, "max_feedback_q": 8, "commission_delay_q": 1 },
  "effect": {
    "kind": "capacity_delta",
    "target": "state.region.grid_capacity_pending_uqs_per_q",
    "capacity_delta_uqs_per_q": 10000000,
    "capacity_unit_ref": "sector.energy",
    "unit_note_zh": "单位必须与部门用电系数一致（μQ_energy/季）。"
  },
  "exit_rule": {
    "delivered_assets": "retain",
    "unfinished_work": "register_residual",
    "compensation_rule": "remaining_contract_ppm",
    "compensation_ppm": 300000
  },
  "political_reaction": { "bloc.business": 250000, "bloc.labor_public": 80000, "bloc.agri_coop": -50000 },
  "failure_paths": [
    { "code": "financing",  "test_id": "T-S-P04-FAIL-FINANCING" },
    { "code": "delivery",   "test_id": "T-S-P04-FAIL-DELIVERY" },
    { "code": "congestion", "test_id": "T-S-P04-FAIL-CONGESTION" },
    { "code": "fuel",       "test_id": "T-S-P04-FAIL-FUEL" },
    { "code": "no_demand",  "test_id": "T-S-P04-FAIL-NODEMAND" }
  ],
  "acceptance_tests": ["T-S-P04-PAY-NO-PROGRESS", "T-S-P04-NO-EARLY-COMMISSION",
                       "T-S-P04-CONSTRAINT-ORDER", "T-S-P04-NO-DEMAND-NO-BONUS"],
  "mechanism_ids": ["mech.grid_capacity", "mech.project_queue", "mech.service_capacity"],
  "cooldown_q": 4,
  "toggle_cost_uu": 10000000,                          // == param.policy_toggle_cost_uu（§5.15）
  "ui_text_keys": { "blocked.authority": "policy.P04.blocked.authority" }
}
```

**九项必填（计划书 §09「没有这些字段的政策不进入可玩菜单」的机器版本）**：
`problem_statement_zh`、`legal_authority`、`cost`、`preconditions`、`lag`、`effect`、`exit_rule`、
`political_reaction`、`failure_paths`。

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-PD-01 | 12 个政策文件齐全，ID 连续 `P01..P12` | `E_POLICY_COUNT` |
| V-PD-02 | 九项必填字段齐全且非空 | `E_POLICY_FIELDS` |
| V-PD-03 | `per_quarter_uu × planned_quarters == one_off_uu`；`Σ spend_lines_uu_per_q == per_quarter_uu`（精确，**加载器不做归一化补偿**） | `E_POLICY_COST` |
| V-PD-04 | `lag.commission_delay_q ≥ 1`（INV-091） | `E_COMMISSION_LAG` |
| V-PD-05 | `effect.capacity_unit_ref` 指向真实部门，且单位与 `io_table` 的用电系数同口径 | `E_UNIT_MISMATCH` |
| V-PD-06 | `failure_paths` 非空，且**每项 `test_id` 在测试注册表中真实存在** | `E_POLICY_TEST_MISSING` |
| V-PD-07 | `acceptance_tests` 非空且同样存在 | `E_POLICY_TEST_MISSING` |
| V-PD-08 | `mechanism_ids` 非空，且每个 ID 在 `MechanismRegistry` 中已注册 | `E_MECH_UNKNOWN` |
| V-PD-09 | 每个 `player_params` 项有 `valid_range` 与 `default`，且 `default ∈ valid_range` | `E_PARAM_RANGE` |
| V-PD-10 | `effect.target` 在效果落点白名单内（见下） | `E_EFFECT_TARGET` |
| V-PD-11 | 一切产能／容量／设施类效果只能落在 `*_pending_*` 字段上；落在 `*_active_*` 或直接的容量字段上即失败（INV-091 的加载期防线） | `E_EFFECT_TARGET` |

> **写不出失败测试的政策，进不了内容包**（V-PD-06）。这是计划书 §09 的机器版本，采纳自草案 C。
> **机制注册表**（`mech.*` 是 SimCore 里已实现的函数表）堵住计划书 §09 的「伪深度」：政策只能引用已有机制并给参数，
> 不能自带逻辑；两个政策的 `mechanism_ids` 与参数完全相同时 `tools/check_policy_dup.gd` 报警告。

**效果落点白名单**（`effect.target` 只能取这些；其余一律 `E_EFFECT_TARGET`）：

```
state.region.grid_capacity_pending_uqs_per_q
state.region.housing_pending_units
state.region.irrigation_index_pending_ppm
state.region.port_capacity_pending_uqs_per_q
state.cell.capacity_pending_uqs_per_q
state.pubserv.capacity_pending_uqs_per_q
state.pubserv.teachers_persons | health_staff_persons
state.policy.params_ppm | params_uu            （税率、替代率、席位等）
state.gov.tax_capacity_ppm
state.politics.admin_capacity_ppm
state.group.education_cohort_persons
```

### 5.13 `EventTemplate`

```jsonc
{
  "schema_kind": "event_template",
  "schema_version": 1,
  "event_id": "event.E07",
  "label_zh": "海岬限电投诉集中出现",
  "trigger": {
    "all_of": [
      { "metric": "derived.region.electricity_availability_ppm", "scope": "region.haijia",
        "op": "lt", "value": 850000 },
      { "metric": "flow.cell.binding_code", "scope": "cell.haijia.manu", "op": "eq", "value": 3 },
      { "metric": "state.time.q", "op": "gte", "value": 2 }
    ],
    "probability_ppm": 600000,
    "rng_stream": "rng.event",
    "cooldown_q": 6,
    "max_occurrences": 3
  },
  "effects": [
    { "target": "state.group.trust_ppm", "scope": "region.haijia", "delta_ppm": -40000 },
    { "target": "state.bloc.org_power_ppm", "scope": "bloc.business", "delta_ppm": 20000 }
  ],
  "evidence_refs": ["derived.region.electricity_availability_ppm", "flow.cell.binding_code"],
  "report_template_id": "tpl.event.grid_complaint",
  "kind": "inferred"
}
```

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-EV-01 | 12 个事件文件齐全 | `E_EVENT_COUNT` |
| V-EV-02 | `trigger.*.metric` 必须是 10 号文件中真实存在的稳定 ID | `E_METRIC_UNKNOWN` |
| V-EV-03 | `op ∈ {lt, le, eq, ne, ge, gt}` —— **没有表达式求值器，只有比较** | `E_EVENT_OP` |
| V-EV-04 | `rng_stream == "rng.event"`（不得借用 `rng.shock`） | `E_EVENT_STREAM` |
| V-EV-05 | `effects[].target` ∈ **事件可写白名单**（见下），且只能是 `delta_ppm` | `E_EVENT_TARGET` |
| V-EV-06 | **首版不存在 `ledger_effects` 字段**；出现即 `E_EVENT_LEDGER` | `E_EVENT_LEDGER` |
| V-EV-07 | `max_occurrences ≥ 1`；`cooldown_q ≥ 0`；`probability_ppm ∈ [0, 1 000 000]` | `E_EVENT_FIELD` |
| V-EV-08 | `evidence_refs` 非空（计划书 §13「每条变化附带实体 ID」） | `E_EVENT_EVIDENCE` |

**事件可写白名单（唯一）**：
`state.group.expectation_ppm`、`state.group.trust_ppm`、`state.group.support_ppm`、
`state.bloc.org_power_ppm`、`state.bloc.stance_ppm`、`state.politics.admin_capacity_ppm`。

> **事件不得直接写现金、库存、产能、人口、GDP。要花钱必须通过一条政策或项目。**
> 这是计划书 §13「禁止后处理补丁」在内容层的结构性执行点（INV-130）。
> 草案 A 曾允许带 `payer`/`payee` 的双边 `ledger_effects`，但 A 自己的待决登记也建议首版留空；
> 本契约裁定**从 schema 里删掉这个字段**——留着它，迟早会有人用。

### 5.14 `ShockDefinition`

```jsonc
{
  "schema_kind": "shock_definition",
  "schema_version": 1,
  "shock_id": "shock.S01",
  "label_zh": "出口需求变化",
  "channel": "export_demand",                 // export_demand | import_price | external_credit
  "targets": ["sector.agri", "sector.manu", "sector.energy", "sector.services"],
  "target_weights_ppm": [100000, 600000, 50000, 250000],      // Σ == 1000000
  "arrival": { "hazard_ppm_per_q": 40000, "earliest_q": 2, "min_gap_q": 6, "max_active": 1 },
  "magnitude_ppm": { "min": -350000, "max": 150000 },         // 闭区间，整数均匀（拒绝采样）
  "duration_q":    { "min": 2, "max": 8 },
  "onset_profile": "step",                    // step | ramp_2q
  "decay_profile": "linear",                  // none | linear
  "rng_stream": "rng.shock",
  "log_fields": ["q", "magnitude_ppm", "duration_q", "draw_index", "raw_u64", "mapped_value"]
}
```

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-SH-01 | 3 个冲击文件齐全，`channel` 三者各一 | `E_SHOCK_COUNT` |
| V-SH-02 | `rng_stream == "rng.shock"` | `E_SHOCK_STREAM` |
| V-SH-03 | `Σ target_weights_ppm == 1 000 000` | `E_SHOCK_WEIGHTS` |
| V-SH-04 | **冲击只能写 `state.world.*` 白名单字段**，不得直接写国内账户、产能、库存或人口 | `E_SHOCK_SCOPE` |
| V-SH-05 | `log_fields` 必须含 `draw_index`、`raw_u64`、`mapped_value`（计划书 §07「每次抽样写入日志」，且可复核） | `E_SHOCK_LOG` |
| V-SH-06 | `magnitude_ppm.min ≤ max`；`duration_q.min ≥ 1` | `E_SHOCK_RANGE` |

**冲击可写白名单（唯一）**：`state.world.export_demand_ppm`、`state.world.import_price_ppm`、
`state.world.credit_limit_uu`、`state.world.sovereign_rate_ppm_per_q`、`state.world.delivery_capacity_uqs`。

### 5.15 `ParameterCard`（计划书 §14 参数身份证）

```jsonc
{
  "schema_kind": "parameter_set",
  "schema_version": 1,
  "param_set_id": "paramset.baseline",
  "param_set_version": 1,
  "cards": [
    {
      "parameter_id": "param.price_step_max_ppm",
      "value": 30000,
      "unit": "ppm",
      "source_type": "design_assumption",
      "source_ref": "计划书 §06「价格根据短缺和库存作有界、平滑的下一季调整」",
      "reference_year": 0,
      "definition": "单季价格相对上季的最大变动幅度（±3%）。",
      "valid_range": [5000, 100000],
      "confidence": "low",
      "calibration_note": "§18 出现宏观指标无原因振荡时，先减小此值，再动其它参数。"
    }
  ]
}
```

| 字段 | 必填 | 约束 |
|---|---|---|
| `parameter_id` | ✔ | `^param\.[a-z][a-z0-9_]*$`，全集唯一 |
| `value` | ✔ | 整数或整数数组；落在 `valid_range` 内 |
| `unit` | ✔ | 10 号文件 §0.1 的单位符号之一，或 `dimensionless` |
| `source_type` | ✔ | **只能是** `observed` / `literature` / `design_assumption` / `derived` |
| `source_ref` | ✔ | 非空。`observed`/`literature` 必须含可核验出处与下载日期 |
| `reference_year` | ✔ | `observed`/`literature` 必填真实年份；虚构剧本的 `design_assumption` 填 0（**不得把缺失当零年份**，0 是「虚构基年」的专用标记） |
| `definition` | ✔ | 非空简体中文，说明口径而非重复名字 |
| `valid_range` | ✔ | `[min, max]`，`min ≤ value ≤ max` |
| `confidence` | ✔ | `low` / `medium` / `high` |
| `calibration_note` | ✔ | 非空；至少写明「如何检验它」或「先调谁」 |

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-PC-01 | 九字段齐全，缺一即失败 | `E_PARAM_CARD` |
| V-PC-02 | `value ∈ valid_range` | `E_PARAM_RANGE` |
| V-PC-03 | `source_type == "observed"` 但 `source_ref` 无数据集名 + 下载日期，或 `docs/ref/` 下无对应数据文件 ⇒ 失败（**防止伪造观测**） | `E_FAKE_OBSERVED` |
| V-PC-04 | **首版内容包中 `observed` 条目数必须为 0**（计划书 §19：数据尚未导入）；出现即失败 | `E_FAKE_OBSERVED` |
| V-PC-05 | `derived` 类必须给 `derivation_expr` 并被复算验证 | `E_PARAM_DERIVE` |
| V-PC-06 | SimCore 中每个裸数字都有对应卡；白名单只有 `0, 1, -1, 1000000` 与 10 号文件 §0.5 的维度常量 | `E_PARAM_COVERAGE` |

> **参数卡的覆盖边界（裁定 R-PARAM-01：以本条为准，任务书与之冲突时任务书让步）**：
> ParameterCard 只覆盖 `param.*` 命名空间，即**行为系数与工程常量**。
> 剧本初值（人口、现金、债券、产能、库存、IO 系数、季节系数等）是**内容数据**，
> 由 §5.4–§5.10 的 `V-*` 校验器与 `assertions.json` 负责，**不需要也不允许**逐个建卡——
> 否则 T03 会退化成为两万个数字写身份证。两者的分界线是：
> **进 `content_hash` 且由剧本作者按剧情设定的 → 内容数据；由模型行为决定、需要校准的 → `param.*`。**
>
> G0 任务书「每个数值参数都必须带身份证」的正确落地方式**不是**给剧本初值建卡，
> 而是给剧本初值写 `_note_*` 登记来源（见下）。**只有 `param.*` 建正式卡片。**
> 这正是先定契约的意义：契约赢，不是因为它更宽松，而是因为它是先写的那一份。
>
> **一个例外**：IOTable 的技术系数（`content.io.*` 七组）虽是内容数据，但计划书 §06 明写
> 「初始技术系数与价格调整速度均为待校准假设」。因此它们**整表共用一张集合级参数卡** `param.io_table_set`：
> 九字段齐全，`value` 记该表规范化哈希的前 16 位十进制截断，`source_type = design_assumption`，
> `calibration_note` 必须写明校准计划。逐个系数**不建卡**，但整表的来源与置信度必须被登记。
> 校验 `V-PC-07`：`param.io_table_set.value` 与实际 IOTable 的哈希前缀不符即 `E_PARAM_STALE`
> ——这保证「改了系数却忘了更新校准说明」会被当场发现。

> **裁定**：草案 A 允许 `observed` 占比 ≤ 10% 只报警不阻断；草案 C 要求首版 `observed` 数必须为 0。
> 取 C：计划书 §19 明确写着「本计划尚未导入数据」，此刻出现任何 `observed` 只可能是伪造。

#### 5.15.1 剧本初值的 `_note_*` 登记（R-PARAM-01 的另一半）

剧本初值不建卡，但**不等于不登记来源**。每一个「作者自己定下来的数」都要在**同级**写一个 `_note_<field>`
注释键；数组或整块结构可以写在父级的 `_note_<block>` 上，一块一条，不必逐元素。
`_note_*` 是自由文本或自由对象（§3 允许该键，schema 不校验其内部形状），不进加载器、不进 `content_hash`（§6.4）。
**推荐结构（四段，缺一段就说明这个数还没想清楚）**：

```jsonc
{
  "cash_uu": 2000000000,
  "_note_cash_uu": {
    "source_zh":      "计划书 §05「国库现金 2 U」——锁定值，不是本剧本的自由选择",
    "derivation_zh":  "2 U × U_SCALE(1e9) = 2000000000 μU；与 V-FIN-01、assert.gov_cash 同源",
    "conservatism_zh": "此处不适用：锁定值，没有自由度可保守",
    "calibration_todo": 0
  }
}
```

| 段 | 键名 | 必须回答的问题 | 写不出来时怎么办 |
|---|---|---|---|
| 来源 | `source_zh` | 这个数从哪来？（计划书条款 / 另一份文档 / 另一个字段 / 作者设定） | 写「作者设定」并说明剧情理由，**不允许留空或写「暂定」** |
| 推导式 | `derivation_zh` | 从来源到这个数的算式，含单位换算 | 若无推导（纯设定值）写「无推导：直接设定」，不要编一个 |
| 保守性理由 | `conservatism_zh` | 为什么是往「更难 / 更紧」的方向拍的？（计划书 §00「凡未写清之处取最保守选择」） | 若不是保守方向，写清为什么可以不保守 |
| 待校准标记 | `calibration_todo` | `0` = 已定稿；`1` = 等基年求解器／重拟合回来再定 | 拿不准一律填 `1`，**宁可多标也不要漏标** |

规则：

1. **`calibration_todo` 用整数 `0` / `1`，不用布尔**：本内容包里一切可统计的量都是整数（§1.2），
   而且它将来可能扩成分级（`2 = 等外部数据`之类），布尔扩不了。工具按 `_note_*` 子树扫描它，
   统计「还有多少个数没定稿」，这是 T03 的完成度指标，不是装饰。
2. 只登记**作者定下来的数**。由其它字段推导且已有 `V-*` 校验器保证的冗余值（例如
   `region.population_persons` 与群组求和）写一条 `_note_` 指向那条校验器即可，不重复推导。
3. `_note_*` 里的数字**同样受 R-SCALE-01 约束**：正文里写「2000000 μU」而字段是 `2000000000`，
   等于把旧刻度留在文档里骗下一个人。测试 `test_u_note_consistency`（§3）解析 `_note_` 中的「N U」
   并与数值比对，是这条的机器版本；`_note_` 里的其它自由文本目前只能靠人工与本条纪律。
4. **`_note_*` 永远不是事实来源。** SimCore 不读它，校验器不从它取期望值（期望值只能来自
   `assertions.json`）。它的读者是人和离线工具。

#### 5.15.2 首版必备参数最小集

全部 `design_assumption`，每张卡九字段齐全：

| parameter_id | 含义 | 单位 | 首版取值 |
|---|---|---|---|
| `param.amount_max_uu` / `param.qty_max_uqs` | 溢出硬上限 | μU / μQ_s | **4e15** / 1e12 |
| `param.price_floor_ppm` / `param.price_ceil_ppm` | 价格上下限（相对基年价） | ppm | 400000 / 2500000 |
| `param.price_step_max_ppm` | 单季价格变动上限 | ppm | 30000 |
| `param.price_gap_gain_ppm` | 价格对供需缺口的响应 | ppm | 200000 |
| `param.price_cover_gain_ppm` | 价格对库存偏离的响应 | ppm | 100000 |
| `param.gap_cap_ppm` | 缺口计入上限 | ppm | 500000 |
| `param.price_clamp_budget_count` | 压测允许的夹逼次数预算 | 次 | 240 |
| `param.wage_gain_ppm` / `param.wage_step_max_ppm` | 工资响应与步长 | ppm | 150000 / 20000 |
| `param.demand_smooth_ppm` | 计划产量对滞后需求的平滑 | ppm | 400000 |
| `param.inventory_target_ppm` | 目标库存覆盖比例 | ppm | 500000 |
| `param.hiring_friction_ppm` / `param.firing_friction_ppm` | 单季招／裁上限比例 | ppm | 100000 / 60000 |
| `param.wage_cash_share_ppm` | 企业可用于工资的现金比例 | ppm | 800000 |
| `param.construction_share_cap_ppm` | 服务产出可用于施工的上限比例 | ppm | 300000 |
| `param.uu_to_construction_uqs_ppm` | 施工服务金额→数量换算 | ppm | **1000** ⚠ |
| `param.training_lag_q` / `param.student_teacher_ratio` | 培训周期／师生比 | 季 / 人 | 4 / 25 |
| `param.migration_threshold_ppm` / `param.migration_max_share_ppm` | 迁移阈值／单季上限 | ppm | 120000 / 20000 |
| `param.migration_w_wage_ppm` / `param.migration_w_job_ppm` / `param.migration_w_service_ppm` | 迁移拉力三项权重（和 == 1e6） | ppm | 500000 / 300000 / 200000 |
| `param.migration_w_house_ppm` / `param.migration_w_env_ppm` | 迁移推力两项权重（和 == 1e6） | ppm | 700000 / 300000 |
| `param.emission_decay_ppm` / `param.env_exposure_gain_ppm` | 排放存量季度衰减／暴露指数增益 | ppm | 30000 / 200000 |
| `param.trust_streak_cap_q` | 连续兑现计入信任恢复的季数上限 | 季 | 8 |
| `param.bloc_care_gain_ppm` | 集团关心指标变化对立场的传导 | ppm | 300000 |
| `param.bloc_org_inertia_ppm` / `param.bloc_w_size_ppm` / `param.bloc_w_resource_ppm` | 组织力惯性与两项权重（三者和 == 1e6） | ppm | 700000 / 200000 / 100000 |
| `param.bloc_resource_ref_uu` | 组织力折算用的资源参照额 | μU | 2000000000 |
| `param.tax_recovery_ppm` | 应收欠税的季度追回比例 | ppm | 50000 |
| `param.persons_per_housing_unit` | 每套住房居住人数 | 人/套 | 3 |
| `param.market_rate_base_ppm` / `param.market_rate_slope_ppm` | 基准季度利率／偿债率斜率 | ppm | 10000 / 30000 |
| `param.coupon_min_ppm` / `param.coupon_max_ppm` | 票息上下限 | ppm | 2000 / 60000 |
| `param.household_bond_appetite_ppm` | 投资池可动用于认购的比例 | ppm | 600000 |
| `param.tax_evasion_slope_ppm` | 税率对税基侵蚀的斜率 | ppm | 250000 |
| `param.tax_base_rate_ppm` | 税基侵蚀的参照平均税率（低于它不产生侵蚀） | ppm | 150000 |
| `param.rate_sensitivity_ppm` | 外部融资收紧冲击对主权利率的传导系数 | ppm | 300000 |
| `param.wage_floor_uu` / `param.wage_ceil_uu` | 工资率硬上下限 | μU/人/季 | 50000000 / 20000000000 ⚠ |
| `param.living_weight_house_ppm` / `param.living_weight_service_ppm` | 生活指数中住房与服务的权重（与收入权重合计 1e6） | ppm | 250000 / 250000 |
| `param.no_confidence_q` | 留任资格丧失后的宽限季数 | 季 | 2 |
| `param.write_guard_sample_q` | 发布构建中重计算型不变量的抽季周期 | 季 | 8 |
| `param.dissave_ppm` | 居民单季可动用存量比例 | ppm | 50000 |
| `param.mpc_ppm` | 边际消费倾向 | ppm | 750000 |
| `param.engel_weight_ppm[4]` | 消费的分产品权重 | ppm | Σ = 1e6 |
| `param.payout_ratio_ppm` | 企业利润分配比例 | ppm | 300000 |
| `param.invest_propensity_ppm` | 扩产意愿系数 | ppm | 200000 |
| `param.opex_starve_decay_ppm` / `param.opex_recover_ppm` | 断供降效／恢复速度 | ppm | 150000 / 50000 |
| `param.maintenance_backlog_gain_ppm` / `param.maintenance_backlog_recover_ppm` / `param.maintenance_backlog_max_ppm` | 维护欠账三参数 | ppm | 200000 / 100000 / 400000 |
| `param.trust_drop_ppm` / `param.trust_recover_ppm` | 信任下降／恢复速度（必须 recover < drop） | ppm | 80000 / 20000 |
| `param.expectation_inertia_ppm` | 预期惯性 | ppm | 700000 |
| `param.support_weight_ppm[3]` | 生活／预期／信任的支持度权重 | ppm | Σ = 1e6 |
| `param.default_grace_q` | 无法偿债的宽限季数 | 季 | 2 |
| `param.policy_toggle_cost_uu` | 政策开关一次性行政成本 | μU | 10000000 |
| `param.log_capacity_rows` | 单季日志预分配行数 | 行 | 8192 |
| `param.bond_batch_cap` | 债券批次上限 | 批 | 512 |
| `param.commitment_horizon_q` | 承诺表滚动窗口 | 季 | 16 |
| `param.edu_pipeline_slots` | 培训队列最大在训季数 | 季 | 8 |
| `param.rng_salt[6]` | 6 条随机流的盐值（属 schema，发布后不得更改） | int64 | 常量表 |

**本表在 R-SCALE-01 下的三条改动规则**（逐项核对过，不是「其余类推」）：

1. `unit` 以 `μU` 开头者，取值 ×1000：`param.amount_max_uu`（4e12 → **4e15**）、
   `param.bloc_resource_ref_uu`（2000000 → **2000000000**）、
   `param.policy_toggle_cost_uu`（10000 → **10000000**，与 §5.12 的 `toggle_cost_uu` 同值）、
   `param.wage_floor_uu` / `param.wage_ceil_uu`（50000 / 20000000 → **50000000 / 20000000000**）。
2. **分母带 μU 的 ppm 系数方向相反，取值 ÷1000**：`param.uu_to_construction_uqs_ppm`
   （1000000 → **1000**）。理由与 `capacity_per_capital_uu_ppm`（§5.5）完全相同：
   基年价下 1 Q_s = 10⁹ μU 而 1 Q_s = 10⁶ μQ_s，故 1 μU 对应 10⁻³ μQ_s，即 1000 ppm。
   R-SCALE-01 的连带要求 2 只点名了 `capacity_per_capital_uu_ppm`，**本参数是同一类的第二个**，
   在此一并登记；今后凡新增「每 μU」口径的系数，一律回到 §5.1 末尾那条登记方向。
3. `ppm` / `季` / `人` / `次` / `行` / `批` / `μQ_s` 为单位者**一律不动**。特别是
   `param.price_floor_ppm` / `param.price_ceil_ppm`（400000 / 2500000）是**相对基年价的比率**，
   与 §5.2 的绝对界 `PRICE_MIN` / `PRICE_MAX`（4e8 / 2.5e9 μU/Q_s）是同一约束的两种写法：
   `PRICE_MIN == mul_ppm(BASE_PRICE, price_floor_ppm)`，`PRICE_MAX == mul_ppm(BASE_PRICE, price_ceil_ppm)`。
   两边必须同时改，改一边即 `E_UNIT_MISMATCH`。

> **⚠ 标记 = 刻度已迁移但量级尚未重新标定**，`calibration_todo` 必须填 `1`：
> - `param.wage_floor_uu` / `param.wage_ceil_uu`：新刻度下的人均季度劳动报酬约 1 360 μU（R-SCALE-01），
>   而机械迁移后的下限是 5×10⁷ μU——**下限比真实工资高约四个数量级，一上来就会夹住每一个工资率**。
>   旧刻度下同样离谱（5×10⁴ vs 1.4 μU），也就是说这两张卡从来没有对着工资量级标定过，
>   不是这次迁移弄坏的。**在基年重拟合给出工资轨之前，不得把它们当作有效的硬界使用**；
>   谁先用到谁负责先标定，并在卡上写清检验方式。
> - `param.uu_to_construction_uqs_ppm`：1000 是基年价下的中性换算值（1 μU ↔ 10⁻³ μQ_services）。
>   内容层的实测比值并不一致：P07 与 P08 恰好是 1000 ppm，P04 是 2000 ppm，P06 约 600 ppm。
>   这说明各政策的「钱→施工量」里混进了各自的材料与管理占比，本参数到底是**中性换算**
>   还是**含占比的换算**必须先定义清楚再标定，否则它会同时扮演两个角色。

### 5.16 `ParameterRegistry`（**生成产物**，裁定 R-SCHEMA-01）

```jsonc
{
  "schema_kind": "parameter_registry",
  "schema_version": 1,
  "generated": 1,                                  // 恒为 1：本文件不是手写的
  "_note_generated": "由 tools/build_param_registry.py 生成……",
  "tool": "tools/build_param_registry.py",
  "tool_version": 1,
  "summary": { "files_scanned": 19, "card_count": 162, "error_count": 5, "…": 0 },
  "stats":   { "by_source_type": [], "by_confidence": [], "by_file": [] },
  "files_scanned": ["…"],
  "files_skipped": ["…"],
  "contract_min_set_missing": ["param.amount_max_uu", "…"],   // 对照 §5.15.2 的必备集
  "near_miss_cards": [],                           // 带身份证字段却缺 parameter_id 的对象
  "findings": [],                                  // PR-* 级别的问题清单
  "cards": [
    { "parameter_id": "param.price_step_max_ppm", "value": 30000, "…": 0,
      "_origin_file": "scenarios/chengwan/…json", "_origin_pointer": "/parameter_cards/cards/3" }
  ]
}
```

**它是什么，不是什么**

| 是 | 不是 |
|---|---|
| `content/` 下全部参数身份证的**只读索引** | 任何参数的事实来源 |
| 离线工具与人工评审的入口（配 `docs/14_parameter_registry.md` 人读版） | 加载器读取的内容文件 |
| 可被删掉后重新生成的派生物 | 可手工编辑的数据 |

| 校验 ID | 内容 | 错误码 |
|---|---|---|
| V-PR-01 | `schema_kind == "parameter_registry"` 且 `generated == 1` | `E_SCHEMA_HEADER` |
| V-PR-02 | **与源文件一致**：重跑 `tools/build_param_registry.py` 的输出与磁盘上这份**逐字节相等**（工具以 UTF-8 无 BOM、LF、`indent=2`、`ensure_ascii=False`、末尾单换行写出，输出是确定性的） | `E_PARAM_REGISTRY_STALE` |
| V-PR-03 | 每张 `cards[]` 的 `_origin_file` / `_origin_pointer` 指向真实存在的文件与位置 | `E_NOT_FOUND` |
| V-PR-04 | **SimCore 与加载器不得读取本文件**；把它当 `parameter_set` 加载即 `E_SCHEMA_HEADER` | `E_SCHEMA_HEADER` |

> **校验器检查它「是否与源文件一致」，而不是检查它的内容本身。**
> 这是 R-SCHEMA-01 的要点，也是它与 `params_core.json`（§5.15，手写、事实来源）的唯一分界：
> 对生成产物做内容校验，是在给同一份数据写第二套真理，而两套真理迟早会打架——
> 要么改源文件后重新生成，要么承认源文件错了。**任何「直接改 registry.json 让它变绿」的做法都是伪造。**
>
> **不进 `content_hash`**（§6.4 的排除集合已含 `_note_*`，本文件整份另行排除）：
> 它是索引，不是内容；把它算进哈希会让「重跑一次生成器」变成存档不兼容。
> 也因此它**不在** `scenario.includes` 里——加载器根本不知道它存在。

---

## 6 命令与存档

### 6.1 `Command`

命令是**玩家意图**，不是状态变更；它是重放的唯一输入（除 `root_seed` 与内容包之外）。
序列化格式为 **JSON Lines**（每行一条，追加写），文件 `<save>/commands.jsonl`。
选 JSONL 而非单个 JSON 数组：可 O(1) 追加写、单行损坏只丢一条。

```jsonc
{"command_id":137,"issued_q":5,"kind":"policy_enact","args":{"policy_id":"policy.P04","region_mask":4,"scale_ppm":1000000,"funding_source":"bond"},"client_build_id":"godot-4.7.2-stable/jingwei-0.1.0"}
{"command_id":138,"issued_q":5,"kind":"advance_quarter","args":{}}
```

| code | kind | args | 主要校验 | 失败 |
|---|---|---|---|---|
| 1 | `policy_enact` | `policy_id`, 各 `player_params` | 权限、冷却、前置条件、资金来源已声明 | `REJECT(code)` |
| 2 | `policy_set_params` | `policy_id`, `params` | 每项在 `valid_range` 内、在允许修改的窗口内 | `REJECT(E_PARAM_RANGE)` |
| 3 | `policy_repeal` | `policy_id` | 冷却、退出规则可执行 | `REJECT` |
| 4 | `project_launch` | `policy_id`, `region_id`, `scale_ppm`, `funding_source` | 施工槽位、资金来源 | `REJECT(E_NO_SLOT / E_NO_FUNDING)` |
| 5 | `project_cancel` | `project_id` | 存在且未完工 | `REJECT(E_NOT_FOUND)` |
| 6 | `project_defer` | `project_id`, `quarters` | 在建、不在延期中；次数 ≤ `param.max_defer_count`，累计季数 ≤ `param.max_defer_quarters`（docs/18 R-DEFER-01） | `REJECT(E_PRECONDITION)` |
| 7 | `budget_reallocate` | `from_line`, `to_line`, `amount_uu` | 源额度充足 | `REJECT(E_BUDGET_INSUFFICIENT)` |
| 8 | `issue_bond` | `amount_uu`, `tenor_q`, `holder` | 对手方额度；**玩家不能设利率** | `REJECT(E_CREDIT_LIMIT)` |
| 9 | `debt_restructure` | `bond_id`, `mode` | 必须登记债权人损失（`recognized_writeoffs`） | `REJECT` |
| 10 | `set_payment_priority` | `order[]` | 8 类的全排列 | `REJECT(E_PRIORITY_INCOMPLETE)` |
| 11 | `set_standing_rule` | `rule`, `value` | 计划书 §04「低风险维护预先设定」 | `REJECT` |
| 12 | `select_mandate_goal` | `goal` | 仅 `q == 0` 可用 | `REJECT` |
| 99 | `advance_quarter` | — | 未终止；`phase == idle`；**每季恰好一条且为该季最后一条** | `REJECT(E_RUN_TERMINATED)` |

**规则**

1. `(issued_q, command_id)` 是全序主键；`command_id` 单调递增，不跳号。
   **被拒命令也消耗序号**（保证命令流是提交序的忠实记录）。
2. **被拒命令仍写入命令流**，并记 `accepted: 0` 与 `reject_code`。理由：重放必须复现「玩家试过但被挡住」
   这一事实，否则同一命令流在不同版本下可能被接受，导致分歧（INV-137）。
3. 拒绝必须带机器可读原因码 + 可本地化文案 key，且**状态哈希完全不变**（`test_u_reject_pure`）。
4. 命令**只写 `state.policy.pending_params` 与命令日志**，绝不直接改账；一切生效发生在 S02（INV-138）。
5. 命令**不得携带任何直接状态值**。含 `set_cash` / `set_gdp` / `set_support` 之类字段即 `E_DIRECT_STATE_WRITE`。
6. 命令流**不得包含结算结果**。命令只有意图，结果由 SimCore 推导。
7. 命令日志与冲击日志**分开存储**（计划书 §12「多写一句新闻不改变经济抽样」）。

### 6.2 存档目录结构

```
user://saves/<slot>/
  manifest.json        # 版本、哈希、指纹、目录
  state.json           # 权威状态（大数组以 base64 编码）
  commands.jsonl       # 命令流（自开局起全量，追加写）
  checkpoints.jsonl    # 每季一行：{q, state_hash, step_hash[8]}，用于重放分歧二分
  shock_log.jsonl      # 冲击抽样记录（与命令流分离）
  log/q0000.bin        # 可选：各季日志列式二进制（可丢弃，不影响重放）
```

**工程理由**：命令流可追加写（自动保存 O(1)，单次 < 1 KB），大状态只在手动存档或每 N 季写一次，
日志可独立清理。自动保存（计划书 §03 要求）= 追加 `commands.jsonl` + 追加 `checkpoints.jsonl` 尾行。

> **裁定**：草案 A/C 用单文件、草案 B 用目录。取 B 的目录结构 + C 的「全量命令流必须保留」
> + A 的「载入后立即跑 P0 不变量」。三者合并后，任何存档都能被「从 q=0 重跑」交叉验证（INV-133）。

### 6.3 `manifest.json`

```jsonc
{
  "schema_kind": "save_manifest",
  "schema_version": 1,
  "created_utc": "2026-09-12T00:00:00Z",
  "build_id": "godot-4.7.2-stable.official.ed1daf0bf/jingwei-0.1.0",
  "scenario_id": "scenario.chengwan",
  "scenario_hash": "<sha256 hex 64>",
  "content_hash":  "<sha256 hex 64>",
  "param_set_version": 1,
  "root_seed": 1234567890123,
  "horizon_q": 40,
  "q": 17,
  "state_hash": "<sha256 hex 64>",
  "command_count": 63,
  "command_log_hash": "<sha256 hex 64>",
  "draw_count": [12, 40, 68, 210, 17, 0],
  "replay_mode": "state+commands"
}
```

| 字段 | 作用 |
|---|---|
| `schema_version` | **整数、单调递增**。迁移的唯一依据。不用语义化版本号——迁移链需要全序 |
| `build_id` | 重放确定性只在同一构建下承诺（计划书 §12[8]）。不同则置 `replay_unreliable` 并禁用重放验证，但**仍允许继续游玩** |
| `content_hash` | 不同则进入**只读检视模式**（可看不可推进） |
| `scenario_hash` | 单独列出，便于定位到底是剧本改了还是政策改了 |
| `state_hash` | 反序列化后立即重算比对；不符即 `E_SAVE_CORRUPT`，**拒绝加载，不做尽力修复** |
| `draw_count` | 6 条随机流的抽样计数。**因为抽样是计数器式的，这 6 个数 + `root_seed` 就是完整的随机流状态** |
| `replay_mode` | `state+commands`（默认，快）或 `commands_only`（从 q=0 重算，用于验证） |

### 6.4 `state.json` 的编码与哈希规范化

```jsonc
{
  "schema_version": 1,
  "scalars": { "state.gov.cash_uu": 1840000000, "state.time.q": 17 },
  "arrays":  { "state.cell.inventory_output_uqs": { "n": 16, "enc": "b64le64", "data": "AAAA…==" } },
  "soa":     { "bond":    { "n": 7, "ids": ["bond.q-12_01"], "cols": { "issue_q": {…} } },
               "project": { "n": 3, "ids": ["project.P04_5_001"], "cols": {…} } }
}
```

- `enc: "b64le64"` = `PackedInt64Array.to_byte_array()` 的 Base64（小端、每元素 8 字节）。
  **必须有单元测试 `test_u_packed_int64_byte_layout` 断言这个布局**，因为我们把它写进了协议。
- **不用 `var_to_bytes()`**：其二进制布局是引擎内部表示，跨版本不承诺。
- 标量用可读 JSON（便于人工排错）；只有大数组走 Base64（体积与解析速度）。
- 估算：约 1 200 个 int64 元素 ≈ 9.6 KB 原始 ≈ 13 KB Base64；整份存档 < 150 KB。

**规范化编码（`CanonicalEncoder`，`content_hash` / `state_hash` 共用）**

1. 条目按**稳定 ID 的字节序升序**排列，不用文件顺序、不用 Dictionary 迭代序。
2. 每条：`uint16 len(id)` + id 的 UTF-8 + `uint8 type_tag` + 值。
3. 整数标量：int64 小端 8 字节。整数数组：`uint32 n` + n×8 字节小端。
4. 字符串（仅 SoA 的 `ids[]`）：`uint32 len` + UTF-8。
5. **排除集合**：`state.meta.state_hash_prev`、全部 `log.*`、全部 `derived.*`、
   一切 `label_zh` / `desc_zh` / `report_template_id` / `_note_*` / `created_utc` / `client_build_id`。
6. `content_hash` 的输入是全部内容包 JSON 按**相对路径升序**，每个文件先解析后做同样的规范化再拼接
   （不哈希原始字节，这样格式化改动不影响哈希）。
   **例外：生成产物整份排除。** 目前只有 `parameters/registry.json`（§5.16）。
   理由：它是由同一批源文件算出来的索引，算进哈希等于把同一份数据数两遍，
   而且「重跑一次生成器」会平白让全部老存档进只读检视模式（§6.6）。
   排除名单是闭集合，新增生成产物必须同时改 §2、§5 的 `schema_kind` 表与本条，三处缺一即拒绝加载。

### 6.5 重放协议

| 模式 | 输入 | 用途 |
|---|---|---|
| `commands_only` | `root_seed` + 剧本 + 内容包 + `commands.jsonl` | **权威重放**，CI 用此模式 |
| `state+commands` | 上面 + `state.json` 快照 | 正常读档；快照只是加速，必须可被 `commands_only` 复现 |

`tools/replay_verify.gd`：

1. 从 q=0 用 `commands_only` 重跑到存档的 `q`。
2. 逐季比对 `checkpoints.jsonl` 的 `state_hash`。
3. 第一个不匹配的季即分歧点，输出该季的 8 个 `step_hash`，定位到步骤。
4. 若 8 个步骤哈希都一致而季末不一致 ⇒ 存在步骤之外的写入 ⇒ 违反「写者唯一」约定，直接报架构缺陷。

**独立随机流的重放保证**：抽样是 `f(root_seed, salt[stream], q, draw_index)`，
`rng.event` 的 `draw_index` 增减完全不影响 `rng.shock` 的任何取值。新增一个事件模板不会改变经济结果。
代价是必须保证 `draw_index` 在同一流内的递增顺序确定 —— 由「遍历顺序 = 下标升序」保证（INV-008）。

### 6.6 读档流程（顺序固定）

```
解析 manifest → schema_version 检查（高于上限 ⇒ 拒绝，INV-135）
  → 迁移链（逐版递增，不跳版）
  → 解析 state.json / commands.jsonl / checkpoints.jsonl / shock_log.jsonl
  → 重算 state_hash 并比对（不符 ⇒ E_SAVE_CORRUPT，拒绝，INV-132）
  → content_hash / param_set_version 比对（不符 ⇒ 只读检视模式，INV-134）
  → build_id 比对（不符 ⇒ replay_unreliable = true，禁用重放验证，允许继续游玩）
  → 立即跑一遍全部 P0 不变量（INV-015..021, 027, 028, 035, 047, 071, 083 …）
  → 任一失败即拒绝加载。坏档必须当场发现，不能等到第 30 季才暴露。
```

### 6.7 版本迁移

**三条互相独立的版本线**，不合并：

| 版本号 | 覆盖范围 | 变更触发 |
|---|---|---|
| `save.schema_version` | 状态形状 | 数组长度、下标顺序、单位、盐值、新增必填状态字段 |
| `content.schema_version` | 内容包形状 | 内容包字段增删改 |
| `param_set_version` | 参数取值集合 | 参数值变化（不是结构变化） |

| 规则 | 内容 |
|---|---|
| M-1 | `save.schema_version > CURRENT` ⇒ 拒绝加载，提示「存档来自更新的版本」。不尝试向下兼容 |
| M-2 | `< CURRENT` ⇒ 依次执行迁移函数升到当前版本。每个迁移是 `Dictionary → Dictionary` 的**纯函数**，不碰磁盘，**不允许跳版** |
| M-3 | 迁移后重算 `state_hash` 写回，并保留 `migrated_from`（原版本 + 原哈希）便于追溯 |
| M-4 | 每次升版本必须在 `tests/fixtures/saves/v<N>/` 存一份黄金存档，回归测试跑「v1 → 当前」全链 |
| M-5 | **缺失字段禁止用 0 填充**，除非该字段语义上就是「无」。需要真实缺省值时必须从同版本剧本的对应字段推导，并断言迁移后所有不变量仍成立 |
| M-6 | 字段语义变更（单位、口径）**必须改名换 ID**，不得复用旧名 |
| M-7 | 部门／地区／群组集合变化 ⇒ 旧档不可迁移，明确拒绝并说明原因 |
| M-8 | 内容包不做迁移。`content_hash` 不符即只读检视（§6.6），**不允许静默继续** |
| M-9 | 参数包升级不改状态形状但会改变结果；重放时必须用同版本参数包，否则同样进只读检视 |

### 6.8 存档安全边界

存档**不加密、不签名**（单机离线，计划书 §18 无遥测、无在线依赖）。
哈希只用于**检测损坏与内容漂移，不用于防作弊**。玩家改自己的存档不是本项目要防的威胁模型。

---

## 7 加载流水线与错误码

```
枚举 content/ 下全部 *.json → 与 §2 布局比对（不在布局内即 E_CONTENT_LAYOUT）
  → 剔除生成产物（§5.16 的 parameters/registry.json：它由工具校验，不进加载器、不进 content_hash）
  → 读取文件 → 文件格式（UTF-8/LF/BOM） → JSON 解析 → 方言限制（无浮点/无 null/无未知键）
  → schema 校验 → ID 唯一性与正则 → 单文件语义校验（V-IO-*, V-REG-*, V-POP-*, V-CELL-*,
    V-FIN-*, V-POL-*, V-PD-*, V-EV-*, V-SH-*, V-PC-*）
  → 登记 base_service_access_ppm[3]（§5.7，由群组值人口加权算出，之后只读）
  → 跨文件引用解析（悬空引用即失败）
  → 剧本硬约束与会计对账（INV-141..152）
  → 构建初始账本：把全部初值写成 q = −1 的开账分录（对手方 agent.opening）
  → 跑一遍 P0 不变量 → 就绪
```

> **关键取舍：初值也要过账本。** Scenario 的初始现金、库存、资本、债务不是直接赋值，
> 而是由一组 `kind = opening_balance` 的开账分录生成。开账完成后 `agent.opening` 的现金恒为 0，
> 只持有净值平衡项，之后永不参与任何交易。
> 好处：**「每笔交易借贷相等」从第 0 秒起成立，初始化不是恒等式的例外**（INV-023，采纳自草案 A）。

### 7.1 校验器 ↔ 不变量映射（供覆盖率工具消费）

`10_variable_dictionary.md` §14 的每条「层 = 加载」的不变量，必须由至少一个 `V-*` 校验器落地。
下表是双向映射；`tests/tools/invariant_coverage.gd` 读它，任一侧出现孤儿即 CI 失败。

| 不变量 | 由哪些校验器落地 |
|---|---|
| INV-002（禁止裸 `/` 与 `%`；每个取整调用点有 `rounding` 注释） | §5.2 的函数白名单 + `test_u_rounding_sites` |
| INV-006 / INV-007（溢出守卫与上下界） | §5.2 的 `mul` / `mul_div_floor` 溢出前置检查 + `test_scaled_ceilings_require_mul_div_floor`（R-SCALE-01） |
| INV-023（初值过账本） | 加载流水线的「构建初始账本」阶段 + `T-U-OPENING-BALANCE` |
| INV-024（存款与投资池配平） | V-FIN-09 |
| INV-042（季节系数） | Scenario 字段约束 `Σ season_factor_ppm == 1e6` |
| INV-052（能源自用 < 1） | V-IO-03 |
| INV-056（产能与资本一致性） | V-CELL-03（系数按 R-SCALE-01 ÷1000 后重算，见 §5.5） |
| INV-074（未成年与老年不就业） | V-POP-03 |
| INV-091（下季供能） | V-PD-04、V-PD-11 |
| INV-092（分季计划合计 == 合同总额） | V-PD-03 |
| INV-099（政策九字段 + 失败路径有测试） | V-PD-01、V-PD-02、V-PD-06、V-PD-07、V-PD-08 |
| INV-108（冲击写入范围） | V-SH-04 |
| INV-122（信任恢复慢于下降） | ParameterCard 交叉校验 `trust_recover_ppm < trust_drop_ppm` |
| INV-127（选举与审查季度） | V-POL-03 |
| INV-130（事件写入范围） | V-EV-05、V-EV-06 |
| INV-131（存档完整性） | `manifest` 字段必填 + `T-R-SAVE-EQUIV-REPLAY` |
| INV-132 / INV-134 / INV-135 | §6.6 读档流程的三步比对 |
| INV-136（迁移链） | M-1..M-9 + `T-R-MIGRATE` |
| INV-138（命令不带状态值） | 命令 schema 的 `additionalProperties: false` + `E_DIRECT_STATE_WRITE` |
| INV-141 | V-REG-05、V-POP-02 |
| INV-142 | V-POP-01 |
| INV-143 | V-POP-05 + PopulationInit 无失业率字段（schema 层） |
| INV-144 | V-FIN-02 |
| INV-145 | V-FIN-01 |
| INV-146 | V-FIN-03、V-FIN-04 |
| INV-147 | V-FIN-05 |
| INV-148 | Scenario `prices_init` 字段约束（每项 == 1 000 000 000，R-SCALE-01）+ `unit_declaration` 的 `E_UNIT_MISMATCH` |
| INV-149 | V-POP-07（**只剩消费指数与生活指数**）+ V-POP-07b（`base_service_access_ppm` 登记，R-ACCESS-01）+ 静态文案检查 |
| INV-150 | V-IO-01、V-IO-02、V-IO-03、V-REG-02 |
| INV-151 | V-POP-08 |
| INV-152 | V-PC-01..V-PC-07 + V-PR-01..V-PR-04（登记表与源文件一致，R-SCHEMA-01） |

**本轮（R-SCALE-01 / R-PARAM-01 / R-SCHEMA-01 / R-ACCESS-01）对本表的增删**

| 动作 | 校验器 | 说明 |
|---|---|---|
| **删** | V-POP-07 的「服务可及性人口加权 == 1 000 000」分支 | R-ACCESS-01：与 10 号 §6.3 的区间联立后唯一解是 36 组全 1e6，会抹平开局不平等 |
| **增** | V-POP-07b | 登记 `base_service_access_ppm[3]`，逐种类 > 0；`population_init` 中不得出现该键 |
| **增** | V-PR-01 … V-PR-04 | `parameter_registry` 的头部、与源文件逐字节一致、`_origin_*` 可解析、不得被加载器读取 |
| **增** | `unit_declaration.money_micro_per_unit` 单列检查 | 原表把四个常量并作一行「与引擎常量逐字相等」，R-SCALE-01 之后四者不再同值（1e9 / 1e6 / 1e6 / 1e9），必须逐个比对 |
| **改** | V-FIN-01 / 02 / 03、V-CELL-03、INV-148 的目标值 | 全部按 1 U = 10⁹ μU 重写；V-CELL-03 的系数方向相反（÷1000） |
| **不变** | V-POP-01..06、V-POP-08、V-IO-*、V-POL-*、V-PD-*、V-EV-*、V-SH-* | 这些检查只涉及人口、数量、比率与结构，与货币刻度无关 |

**错误码表**（全部为加载期拒绝，前缀 `E_`）

```
# 文件与方言
E_FILE_FORMAT  E_SCHEMA_HEADER  E_FLOAT_IN_CONTENT  E_INT_RANGE  E_NULL_NOT_ALLOWED
E_UNKNOWN_FIELD  E_KEY_NAMING  E_DUP_ID  E_ID_FORMAT  E_ALIAS_IN_CONTENT  E_UNIT_MISMATCH
E_CONTENT_LAYOUT                       # 文件不在 §2 的固定布局内（新增文件必须先改 §2）
# 剧本硬约束
E_POP_TOTAL  E_POP_REGION  E_GROUP_SET  E_POP_AGE_ROLE  E_POP_EMP  E_POP_UNEMP
E_EMPLOY_MISMATCH  E_HOUSE_CAP  E_HOUSE_OVER  E_INDEX_BASE
E_CASH_INIT  E_DEBT_TOTAL  E_FIN_YEARPLAN  E_FIN_LINES  E_FIN_INTEREST
E_PRIORITY_INCOMPLETE  E_BOND_FIELD  E_INVPOOL_TOO_SMALL  E_DEPOSIT_MISMATCH
E_GDP_INIT  E_BALANCE_INIT  E_CASH_TOTAL  E_ASSERT_TOLERANCE
# 结构与内容
E_REGION_SET  E_REGION_ADJ  E_REGION_SLOTS  E_CELL_SET  E_ENERGY_INVENTORY
E_CAPACITY_INCONSISTENT  E_EQUITY_SHARE  E_SERVICE_SPLIT  E_RANGE
E_IO_COLSUM  E_IO_STORABLE  E_IO_ENERGY_SELF  E_IO_NEGATIVE  E_IO_NOT_CONVERGENT  E_IO_ENERGY_COEFF
E_IO_LABOR  E_IO_CAPACITY_COEFF
E_POLICY_COUNT  E_POLICY_FIELDS  E_POLICY_COST  E_COMMISSION_LAG  E_POLICY_TEST_MISSING
E_MECH_UNKNOWN  E_PARAM_RANGE  E_EFFECT_TARGET
E_EVENT_COUNT  E_METRIC_UNKNOWN  E_EVENT_OP  E_EVENT_STREAM  E_EVENT_TARGET  E_EVENT_LEDGER
E_EVENT_FIELD  E_EVENT_EVIDENCE
E_SHOCK_COUNT  E_SHOCK_STREAM  E_SHOCK_WEIGHTS  E_SHOCK_SCOPE  E_SHOCK_LOG  E_SHOCK_RANGE
E_PARAM_CARD  E_FAKE_OBSERVED  E_PARAM_DERIVE  E_PARAM_COVERAGE  E_PARAM_STALE
E_PARAM_REGISTRY_STALE                 # §5.16 V-PR-02：registry.json 与源文件不一致（重新生成，不要手改）
E_LEDGER_KIND_UNCLASSIFIED
# 命令与存档
E_RUN_TERMINATED  E_PHASE_BUSY  E_UNKNOWN_POLICY  E_POLICY_COOLDOWN  E_AUTHORITY
E_SEATS_SHORT  E_BLOC_VETO  E_BUDGET_INSUFFICIENT  E_NO_FUNDING  E_CREDIT_LIMIT  E_NO_SLOT
E_PRECONDITION  E_ALREADY_ENACTED  E_NOT_FOUND  E_DIRECT_STATE_WRITE
E_SAVE_CORRUPT  E_SAVE_VERSION_TOO_NEW  E_MIGRATION_MISSING
```

`FAULT` 级错误码（程序缺陷，非玩家可触发）定义在 `12_simulation_contract.md` §8。

---

## 8 内容包与测试分层的对应

| 数据对象 | unit `T-U-*` | replay `T-R-*` | scenario `T-S-*` | stress `T-X-*` |
|---|---|---|---|---|
| Scenario / 各 Init | schema、assertions、就业两处交叉对账 | — | 开局四季基线 | 120 季不崩 |
| IOTable | 系数非负、收敛性、零系数跳过、能源自用 | — | 瓶颈切换可解释 | — |
| PolicyDefinition | 九项必填、`failure_paths` 的 `test_id` 存在 | — | 每政策 ≥1 成功链 + ≥1 失败链 | 12 政策同时开启 |
| EventTemplate | 白名单字段、metric 存在、无 `ledger_effects` | 事件抽样可复现 | 触发链路 | 事件刷屏上限 |
| ShockDefinition | 抽样映射整数化与去偏 | 冲击可复现 | 组合冲击可解释 | 100 种子 |
| ParameterCard | 九字段齐全、无魔数、`observed` 数为 0 | — | 敏感性三档 | — |
| ParameterRegistry | 与源文件逐字节一致（V-PR-02）、`_origin_*` 可解析、不被加载器读取 | — | — | — |
| Command | 拒绝纯净性、无副作用 | 命令流重放 | 恶意玩家序列 `ADV-01..06` | 长命令流 |
| Save | schema 校验、字节布局 | 往返、迁移、重载不重抽 | — | 每季自动存档不拖慢 |

---

## 9 裁定记录（数据协议部分）

| # | 冲突点 | 各方主张 | 裁定 | 理由 |
|---|---|---|---|---|
| D-01 | 大整数可读性 | A：允许 `"50_000_000"` 字符串形式；B/C：不允许 | **不允许，改用 `_note_` 注释键 + 一致性测试** | 字符串形式给 `is_integer` 检查开了口子；注释键既可读又不进逻辑 |
| D-02 | `assertions` 的容差 | A：无此段；B：有但未限制；C：一律 0 | **一律 0，唯一例外：失业率 500 ppm，写死在协议里** | C 自认「将来会被偷偷放宽」；把唯一例外写进协议，放宽就必须改协议 |
| D-03 | 事件的账本效应 | A：允许双边 `ledger_effects`；B/C：禁止 | **schema 里删掉该字段** | 留着它迟早会被用；花钱必须走政策或项目 |
| D-04 | `observed` 参数的占比 | A：>10% 只警告；C：必须为 0 | **必须为 0** | 计划书 §19 明写数据尚未导入，此刻的 `observed` 只可能是伪造 |
| D-05 | 存档形态 | A/C：单文件；B：目录 | **目录 + 全量命令流 + 载入后跑 P0** | 自动保存 O(1)；逐季 checkpoint 支持二分；全量命令流支持 `commands_only` 交叉验证 |
| D-06 | `content_hash` 不符 | A：只读；B：三选一默认只读；C：只读 | **只读检视，首版无「继续游玩」选项** | 最保守；放宽须命令行开关且在存档留痕 |
| D-07 | `build_id` 不符 | A：标记不可靠仍可玩；B：警告并禁用重放验证；C：并入确定性承诺 | **可继续游玩 + `replay_unreliable` + 禁用重放验证** | 我们的 RNG 与引擎无关，风险低于草案预期；但 int64 语义仍与引擎相关，标记必须保留 |
| D-08 | 版本号形态 | A：`param_set` 用 semver；B/C：单调整数 | **全部单调整数** | 迁移链需要全序；semver 的比较规则在迁移里是负担 |
| D-09 | 命令被拒后是否消耗序号 | B：消耗；A/C：未明确 | **消耗** | `(q, seq)` 必须是提交序的忠实记录，否则重放会因序号复用而分歧 |
| D-10 | 债券批次结构 | A 给出占位三笔；B/C 未给 | **采用 A 的占位，明标 `design_assumption`，由 T03 定稿** | 不可变的只有「合计 50 U」与「必须拆分期限与债权人」 |
| D-11 | 投资池初值是否受约束 | A 登记为 OQ-01；B/C 未处理 | **加载期强制 `invpool.cash ≥ 年赤字`（V-FIN-08）** | 现金总量恒定下，融资必须有对手方；否则基年即触发融资危机 |
| D-12 | 存档是否防篡改 | B/C：不加密不签名 | **不加密不签名** | 单机离线，改自己的存档不在威胁模型内 |

---

## 10 R-SCALE-01 同步记录

本节记录本契约按 `docs/18_rulings.md` 的 **R-SCALE-01 / R-PARAM-01 / R-SCHEMA-01 / R-ACCESS-01**
所做的全部改动，**逐处列出**，以便任何人能反查「这个数为什么是现在这个样子」。
18 号文件的优先级高于本文件；本节只是执行记录，不是新的裁定。

### 10.1 货币刻度 1 U = 10⁹ μU（R-SCALE-01）

**原则**：分子带 μU 的量 ×1000；分母带 μU 的系数 ÷1000；实物、比率、人数、件数、季度一概不动。

| § | 位置 | 旧值 | 新值 |
|---|---|---|---|
| §3 | JSON 方言表「整数安全区」行 | `AMOUNT_MAX = 4e12` | `4e15`（裕度降到 2.25 倍，已写明不得再抬高） |
| §3 | 被否决的字符串写法示例 | `"50_000_000"` | `"50_000_000_000"` |
| §5.1 | 金额编码行 | 1 U = 10⁶ μU；50 U → `50000000` | 1 U = 10⁹ μU；50 U → `50000000000` |
| §5.1 | 价格编码行 | 基年 = `1000000` | 基年 = `1000000000` |
| §5.1 | 表末 | （无） | **新增**：逐后缀登记「哪些 ×1000、哪些不动、哪一个 ÷1000」 |
| §5.2 | 常量块 | `AMOUNT_MAX 4e12`、`PRICE_MIN 4e5`、`PRICE_MAX 2.5e6` | `4e15`、`4e8`、`2.5e9`；并**新增** `U_SCALE` / `Q_SCALE` / `BASE_PRICE` / `INT64_MIN` |
| §5.2 | `mul` | 单行溢出判据 | 与 `sim/jw_math.gd` 对齐：先挡 `INT64_MIN`，再用 `idiv_floor(INT64_MAX, absi(b))` 作精确判据 |
| §5.2 | `idiv_floor` / `idiv_ceil` | 无边界守卫 | 补 `DIV_ZERO`、`INT64_MIN / -1`、`-INT64_MIN` 三处显式守卫 |
| §5.2 | — | （不存在） | **新增 `mul_div_floor(a, b, c)`**，并给出「为什么它是强制的」的溢出对照表 |
| §5.2 | `mul_ppm` / `mul_ppm_2` | `idiv_floor(mul(x, p), PPM)` | 改为走 `mul_div_floor`，与真实实现逐字一致 |
| §5.2 | `split_largest_remainder` | 注释「M0 保证不溢出」 | 写出真实的入口守卫 `total > idiv_floor(INT64_MAX, W)` |
| §5.4 | `unit_declaration` | 四个常量同为 `1000000` | `money_micro_per_unit` 与 `base_price_uu_per_qs` 改 `1000000000`；另两个不变；字段表由一行拆成三行 |
| §5.4 | `prices_init.sector/base_uu_per_qs` | `[1000000]×4` | `[1000000000]×4`（INV-148 目标值同步） |
| §5.4 | `world_init.credit_limit_uu` / `cash_uu` | `15000000` | `15000000000` |
| §5.5 | `capacity_per_capital_uu_ppm` | `[600000, 500000, 300000, 700000]` | `[600, 500, 300, 700]`（**÷1000**，方向相反）+ 粒度遗留说明 |
| §5.6 | `migration_cost_uu` | `{400, 250, 350, 0}` | `{400000, 250000, 350000, 0}` |
| §5.7 | 群组 `cash_uu` / `deposit_uu` | `900000` / `300000` | `900000000` / `300000000` |
| §5.8 | cell `cash_uu` | `3000000` | `3000000000` |
| §5.8 | cell `capital_value_uu` | `20000000` | `10000000000`（**同时重新配平**：V-CELL-03 要求 `mul_ppm(capital, 500) == 5 000 000`） |
| §5.8 | pubserv `capital_value_uu` | `9000000` | `9000000000` |
| §5.9 | `gov.*` 六项金额 | `2000000` / `18000000` / `4000000` / `8000000` / `120000` | 各 ×1000 |
| §5.9 | `annual_plan` 全部金额与两组分项 | 20/22/2 U 及各行 | 各 ×1000，三条会计恒等式重新验过（20e9 = 11e9+7e9+2e9；22e9 = 各行之和；22e9−20e9 = 2e9） |
| §5.9 | `bonds[]` 三笔本金 | `20000000` / `18000000` / `12000000` | 各 ×1000，合计仍 50 U（V-FIN-02） |
| §5.9 | `bonds[].amortization` | 两笔 `level_principal` | 三笔均 `bullet`（理由见 §5.9 正文：开局批次的已摊还期数尚无约定） |
| §5.9 | `expenditure_lines_uu.interest` | `2800000`（与三笔票息对不上） | `2112000000`，**逐批次复算**；差额 688 000 000 记入 `discretionary`，V-FIN-05 由此真正成立 |
| §5.9 | `invpool.cash_uu` | `9000000` | `9000000000` |
| §5.9 | V-FIN-01 / 02 / 03 的目标值 | 2e6 / 5e7 / 2e6 | 2e9 / 5e10 / 2e9 |
| §5.10 | 三个集团 `resource_uu` | `400000` / `900000` / `500000` | 各 ×1000 |
| §5.11 | `assert.gov_debt` / `gov_cash` / `annual_deficit` / `base_prices` / `base_year_gdp` | 5e7 / 2e6 / 2e6 / `[1e6]×4` / 1e8 | 5e10 / 2e9 / 2e9 / `[1e9]×4` / 1e11 |
| §5.12 | `cost.*` 五项与 `toggle_cost_uu` | 4e6 / 5e5 / {2e5,1e5,2e5} / 2e4 / 1e4 | 各 ×1000；V-PD-03 重新验过（5e8 × 8 == 4e9；2e8+1e8+2e8 == 5e8） |
| §5.15 | `param.amount_max_uu` | 4e12 | 4e15 |
| §5.15 | `param.bloc_resource_ref_uu` | 2000000 | 2000000000 |
| §5.15 | `param.policy_toggle_cost_uu` | 10000 | 10000000 |
| §5.15 | `param.wage_floor_uu` / `param.wage_ceil_uu` | 50000 / 20000000 | 50000000 / 20000000000，**标 ⚠ 待标定**（量级从来没对着工资标过） |
| §5.15 | `param.uu_to_construction_uqs_ppm` | 1000000 | **1000（÷1000）**，标 ⚠ 待标定；这是「分母带 μU」的第二个系数，R-SCALE-01 原文未点名，本次一并登记 |
| §6.4 | `state.json` 示例 `state.gov.cash_uu` | `1840000` | `1840000000` |

**明确不动的**（逐项确认过，不是漏改）：`Q_SCALE` / `PPM` / `QTY_MAX`；全部 `_uqs*`、`_persons*`、
`_units`、`_q`、`_count`、`_mask`、`_uqe`、`_ppm` 字段；`param.price_floor_ppm` / `price_ceil_ppm`
（相对基年价的比率）；全部 `coupon_ppm_per_q`（含 §5.9 中恰好等于 12500 的那一笔，与 §5.4 的利率无关）；
`season_factor_ppm`、`equity_share_ppm`、`service_capacity_split_ppm`、`target_weights_ppm` 的
「Σ == 1 000 000」；`_ppmuu` 余数累加器的 `[0, 999 999]` 上界。

### 10.2 参数身份证的适用范围（R-PARAM-01）

- §5.15 的「覆盖边界」改写为裁定口径：**只有 `param.*` 建卡**，任务书与契约冲突时契约胜。
- **新增 §5.15.1**：剧本初值用 `_note_*` 登记来源，给出四段推荐结构
  （`source_zh` / `derivation_zh` / `conservatism_zh` / `calibration_todo`）与四条使用规则。
- 原「首版必备参数最小集」下沉为 **§5.15.2**，编号变化不改内容。

### 10.3 `parameter_registry` 是合法类型（R-SCHEMA-01）

- §2 文件布局新增 `parameters/registry.json`，并标注生成产物。
- §5 新增**允许的 `schema_kind` 闭集合表**，`parameter_registry` 列为唯一的生成产物。
- **新增 §5.16**：登记表的形状、「是什么／不是什么」对照、V-PR-01..04。
  核心是 **V-PR-02 检查它与源文件逐字节一致，而不是检查它的内容**。
- §6.4 `content_hash` 新增「生成产物整份排除」条款；§7 加载流水线新增「枚举 → 与 §2 布局比对 → 剔除生成产物」两步。
- 错误码表新增 `E_CONTENT_LAYOUT`（文件不在 §2 布局内）与 `E_PARAM_REGISTRY_STALE`（V-PR-02 失败）。

### 10.4 `service_access_ppm` 的区间与恒等式二选一（R-ACCESS-01）

- **V-POP-07 删除**「服务可及性人口加权 == 1 000 000」这一分支，只保留消费指数与生活指数两项。
- **新增 V-POP-07b**：逐组逐种类区间 `[0, 1 000 000]`；载入期按人口加权算出
  `base_service_access_ppm[3]` 并登记为只读常量；三个种类各自必须 > 0。
- §5.7 新增该常量的计算式与五条纪律（不是输入字段、属 `content.*`、用途唯一、> 0 是硬约束、按人口加权）。
- §5.11 的 `assertions.json` 示例新增 `assert.base_service_access`，并写明它的 `expect`
  是剧本特有值而非计划书锁定值。
- §7.1 的 INV-149 映射改为「V-POP-07（只剩两项）+ V-POP-07b + 静态文案检查」——
  **INV-149 没有被放宽**：`derived.living.public_service_index_ppm` 改为按 `base_service_access_ppm`
  归一化，基年值仍恒等于 1 000 000，换的是分母，不是标准。

### 10.5 本节未处理、留给其它文件或后续任务的

1. **`docs/10` §0.1 仍写「1 U = 1 000 000 μU」**，`docs/12` 与 `docs/16` 的正文中也有旧刻度数字。
   本轮只同步本文件；三份文档的单位必须自洽（见本文件开头的立场声明），需要同批次一并改完才算收口。
2. **剧本文件 `scenario.json` 的 `unit_declaration.money_micro_per_unit` 仍是 `1000000`**：
   迁移器的规则是「键名含 `uu` 词元者 ×1000」，这个键名里没有 `uu`，因而被漏掉。
   按本文件 §5.4 它必须是 `1000000000`，否则 `E_UNIT_MISMATCH`。
3. **`tools/validate_content.py` 的 `MICRO` 仍同时充当「ppm 基数」与「价格基数」**：
   `expect_ud` 与 `prices_init` 的比对仍按 `1000000` 判定，会把已经正确的新刻度剧本判错。
   本文件是裁判，不因校验器未同步而改口径。
4. **`world.json` 与 `assertions.json` 尚未进入 §2 的文件布局**：前者是 R-CREDIT-01 明确要求存在的文件，
   后者 §2 已列但内容层尚未落地。二者都会触发 `E_CONTENT_LAYOUT`，需要单独裁定后再改 §2。
5. **⚠ 两项参数的量级未重新标定**（§5.15.2 已标）：`param.wage_floor_uu` / `param.wage_ceil_uu`、
   `param.uu_to_construction_uqs_ppm`。刻度对了不等于数对了。

---

*本文件为唯一权威版本。任何与之冲突的草案内容一律作废。*
