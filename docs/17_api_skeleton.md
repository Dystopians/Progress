# 17 API 骨架（唯一权威接口面）

> **本文件是 20+ 名实现者并行工作的唯一接口契约。**
> 它覆盖 `docs/15_module_map.md` 列出的全部 34 个文件（`sim/` 27 个 + `systems/` 5 个 + `application/` 2 个），
> 给出每个文件的 `class_name`、`extends`、全部成员变量、全部方法签名与调用方向。
>
> **语义来源不在本文件。** 公式见 `docs/12_simulation_contract.md`，变量语义与不变量见 `docs/10_variable_dictionary.md`，
> 数据形态见 `docs/11_data_contract.md`，待决取法见 `docs/13_open_questions.md`。
> 本文件只回答一个问题：**这些语义应该落在哪个类的哪个方法上，谁调谁。**
>
> **冻结规则**：签名一经本文件发布，实现者不得改动。确需改动 → 登记为接口变更请求（§8），
> 由骨架负责人一人统一改，改完递增顶部的 `skeleton_revision`。
>
> `skeleton_revision: 1` · 对应 `save.schema_version: 1` · 引擎 Godot 4.7.2-stable

---

## 0 阅读顺序

| 你要做什么 | 先读本文件的 |
|---|---|
| 实现某个 `sim/` 文件 | §1 全局约定 → §2 稠密下标 → §3 分层与调用方向 → §4 中你那一节 |
| 实现 `systems/turn_runner.gd` | §1 → §3 → §5 八步调用序列（逐行） → §4.29 |
| 实现存档／重放 | §6 序列化、哈希与随机流状态接口 |
| 写测试 | §2 + §4 的方法文档注释（前置／后置／不变量／失败返回） |
| 分工排期 | §7 文件 → 负责模块 → 依赖总表 |
| 发现接口不够用 | §8 接口变更流程与已登记缺口 |

---

## 1 全局约定（所有文件必须遵守）

### 1.1 命名

- **全部 `class_name` 以 `JW` 前缀**（与既有 `JWTest` 一致）。理由：`Account`、`Ledger`、`Capital`、
  `Politics` 这类裸名字与将来的引擎类型有冲突风险，而 `class_name` 冲突在 Godot 里是**全局**的、
  会在无关文件里报错。前缀是一次性成本，冲突是持续成本。
- 文件路径沿用 `docs/15_module_map.md` 的原样（`sim/ledger/account.gd` → `class_name JWAccount`）。
- **方法命名与 `docs/11_data_contract.md` §5.2 的对照（实现者必须照此写）**：

| 契约文档里的写法 | 本骨架的唯一实现名 | 所在类 |
|---|---|---|
| `IntMath.mul(a, b)` | `JWMath.mul(a, b)` | `JWMath` |
| `IntMath.idiv_floor(a, b)` | `JWMath.floor_div(a, b)` | `JWMath` |
| `IntMath.idiv_ceil(a, b)` | `JWMath.ceil_div(a, b)` | `JWMath` |
| `IntMath.mul_ppm(x, p)` | `JWMath.mul_ppm(x, p)` | `JWMath` |
| `IntMath.mul_ppm_2(x, p1, p2)` | `JWMath.mul_ppm_2(x, p1, p2)` | `JWMath` |
| `IntMath.split_largest_remainder(...)` | `JWMath.split_lr_into(...)`（热路径）／`JWMath.split_lr(...)`（冷路径） | `JWMath` |
| `Fault.raise(code)` | `JWResult.raise_fault(code, a, b)` | `JWResult` |
| `CanonicalEncoder` | `JWSimState.canon_*()` 静态族 | `JWSimState` |
| `IdRegistry` | `JWIds` | `JWIds` |
| `WriteGuard.begin/end` | `JWTurnRunner._guard_begin/_guard_end` | `JWTurnRunner` |
| `StateView` | `JWGame.StateView`（内部类） | `JWGame` |
| `MechanismRegistry` | `JWPolicyDef.MECHANISM_IDS` + `JWPolicyDef.mechanism_index()` | `JWPolicyDef` |

  这只是**命名**的统一，不是语义变更；四则运算的定义、取整方向、余数归属一律以 11 号文件 §5.2 为准。
  已登记为接口变更请求 `IR-01`（见 §8）：若 11 号文件后续统一改名，只需改本表一处。

### 1.2 `extends`

- `sim/**`：一律 `extends RefCounted`。**禁止 `Node` / `Control` / `Resource`，也不用 `Object`**
  （`Object` 需要手动 `free()`，而 SimCore 的对象生命周期跟随 `JWSimState`；`RefCounted` 自动）。
- `systems/**`、`application/**`：一律 `extends RefCounted`。这两层也不进场景树；
  宿主（UI 场景或测试运行器）持有 `JWGame` 的引用即可。
- 全部声明**带类型**，缩进 **Tab**；`project.godot` 已把 untyped 声明警告设为错误级。

### 1.3 返回值约定（冷热两条路，不混用）

| 路径 | 何时 | 返回类型 | 约定 |
|---|---|---|---|
| **热路径**（S01…S08 结算内的一切） | 每季调用 | `-> int` | `0 == JWResult.OK`；非 0 即故障码，**调用方必须立即向上返回**，不得吞掉 |
| **冷路径**（加载、存档、命令提交、重放校验） | 每局若干次 | `-> JWResult` | 对象形态 `{ok, code, detail_a, detail_b, detail_key}` |
| **查询**（纯读、不可失败） | 任意 | `-> int` / `-> PackedInt64Array` | 越界即 `JWResult.raise_fault(INDEX_OUT_OF_RANGE)` 并返回 0 |

- **业务性短缺不是故障**：钱不够、货不够、人不够、队列满 → 返回 `OK`，
  同时登记欠付／延期／取消／配给／未满足需求并写日志（`docs/12` §0.6 的 `ARREARS` 语义）。
  只有恒等式破裂与工程性错误才返回非 0。
- **禁止静默改账**：任何返回 `OK` 的方法都不得留下未登记的差额。

### 1.4 热路径纪律（`docs/12` §14 性能预算的前提）

1. 结算期间**不 `new` 任何对象、不建 `Dictionary`、不拼 `String`**。
2. 一切中间结果写入**预分配 scratch 数组**；scratch 由 `JWTurnRunner` 在构造期 `resize()` 一次，
   每步入口 `fill(0)`。
3. 分配类计算一律 `*_into(..., out: PackedInt64Array)` 形态，由调用方提供输出缓冲。
   返回新数组的版本只允许出现在冷路径与测试里（静态检查禁止 `JWMath.split_lr` 出现在 `sim/**` 的结算调用点）。
4. 状态一律稠密 `PackedInt64Array` + 整数下标；运行期不出现 `String`，不出现 `Dictionary` 键查找。
   `JWIds` 的字符串映射只在 `LOAD` 期可用，`freeze()` 之后调用即 `Fault.PHASE_VIOLATION`。

### 1.5 写入者标注（INV-013 的实现前提）

每个成员变量表都有「写入者」列，取值与 `docs/10` §0.7 完全一致：
`LOAD` / `MIG` / `CMD` / `S01`…`S08` / `DERIVED`。

- 一个字段出现两个结算步作为写入者时，本文件在该字段行后写明「为什么同一季两次写入不会互相放大」。
- `JWTurnRunner._guard_begin(step)` 在进入每步前对**不属于该步可写子集**的子系统取 `subsystem_hash`，
  `_guard_end(step)` 退出时比对；不等即 `Fault.WRITE_OUT_OF_SCOPE`。
  可写子集就是 `docs/12` 每一步的「可写子集」行，在本文件 §5 里逐步落成 `JWUnits.WRITABLE_SUBSYS[step]` 位掩码。

### 1.6 状态块协议（StateBlock Protocol）

**每一个持有状态的 SimCore 类**都实现下面这组方法，签名逐字相同。
这使「遍历流量注册表整表清零」（`docs/12` §01.3）、「规范化哈希」（`docs/10` §11）、
「存档序列化」（`docs/11` §6.4）、「WriteGuard 子系统哈希」全部变成**对一个注册表的遍历**，
而不是对字段名做字符串匹配。

```gdscript
## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = PackedInt64Array([...])

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = PackedStringArray([...])
const STATE_SCALAR_IDS: PackedStringArray = PackedStringArray([...])
const FLOW_ARRAY_IDS: PackedStringArray = PackedStringArray([...])
const FLOW_SCALAR_IDS: PackedStringArray = PackedStringArray([...])

func allocate() -> void                                  ## LOAD 期一次性 resize 到 §2 的契约长度
func state_array(i: int) -> PackedInt64Array             ## 只读取用（返回引用，调用方不得写）
func set_state_array(i: int, v: PackedInt64Array) -> int ## 仅 LOAD / MIG
func state_scalar(i: int) -> int
func set_state_scalar(i: int, v: int) -> int             ## 仅 LOAD / MIG
func flow_array(i: int) -> PackedInt64Array
func flow_scalar(i: int) -> int
func reset_flows() -> void                               ## 仅 S01；全部 FLOW_* 归零
func flow_abs_sum() -> int                               ## S01 清零后的自检，非 0 即 FLOW_NOT_RESET
```

- 数组下标与 `STATE_ARRAY_IDS` 的下标一一对应；**顺序是 schema 的一部分**，重排即破坏性变更（INV-136）。
- `set_state_*` 的静态检查：调用点必须位于 `systems/content_loader.gd` 或 `systems/saves.gd`。
- `reset_flows()` 的静态检查：调用点必须位于 `systems/turn_runner.gd` 的 `_step_s01` 内。

### 1.7 日志通道协议

持有日志的类（`JWLedger`、`JWRngStreams`、`JWTreasury`、`JWCommands`、`JWPricing`、`JWDiagnostics`、`JWShocks`）
额外实现：

```gdscript
func log_reset_quarter() -> void   ## 每季 S01 重置本季游标（日志不进 state_hash）
func log_row_count() -> int        ## 本季已写行数，供 INV-011 / INV-139 对账
func log_capacity() -> int         ## 当前容量；写满时按 1.5 倍扩容并写一条告警行
```

**日志只有整数。** 展示文案由 Presentation 用 `cause` / `kind` 码查模板表生成（`docs/10` §2.5）。

### 1.8 方法文档注释模板（强制）

```gdscript
## <一句话：这个方法做什么>
## 步骤：S05 §5.3（结算合同章节号）
## 前置：<调用前必须成立的条件>
## 后置：<调用后保证成立的条件>
## 不变量：INV-043, INV-044, INV-045
## 失败：<返回什么错误码 / 登记什么欠付 / 拒绝什么>
func solve_output(...) -> int:
```

六行齐全才算完成。缺「不变量」或「失败」两行的方法一律打回。
本文件 §4 对每个方法给出的正是这六行的内容。

---

## 2 稠密下标与维度常量（契约的一部分，不得重排）

全部落在 `JWUnits`（维度与枚举）与 `JWIds`（索引函数与主体／科目布局）。
**任何改动都是 schema 破坏性变更**：必须升 `save.schema_version` 并写迁移函数（INV-136）。

### 2.1 维度常量（`JWUnits`）

```gdscript
const R: int = 4            # region: 0 beiyuan 1 zhongzhou 2 haijia 3 xiling
const S: int = 4            # sector: 0 agri 1 manu 2 energy 3 services
const A: int = 3            # age:    0 minor 1 working 2 elder
const K: int = 3            # skill:  0 low 1 mid 2 high
const CELL: int = 16            # R * S
const GROUP: int = 36           # R * A * K
const PUBSERV: int = 4          # == R
const IO_N: int = 16            # S * S
const INV_N: int = 64           # CELL * S
const EMP_N: int = 48           # CELL * K
const OD_N: int = 16            # R * R
const GROUP_EMP_N: int = 180    # GROUP * 5   （4 部门 + pubserv）
const GROUP_SVC_N: int = 108    # GROUP * SERVICE_KIND
const GROUP_PROD_N: int = 144   # GROUP * S
const EDU_SLOT: int = 8         # 结业队列槽位数
const EDU_N: int = 288          # GROUP * EDU_SLOT
const PUBSERV_EMP_N: int = 12   # PUBSERV * K
const PUBSERV_QUEUE_N: int = 12 # PUBSERV * SERVICE_KIND
const SERVICE_KIND: int = 3     # 0 health 1 education 2 utility
const POLICY_N: int = 12
const POLICY_PARAM_N: int = 48  # POLICY_N * 4
const EVENT_N: int = 12
const SHOCK_N: int = 3
const BLOC_N: int = 3           # 0 agri_coop 1 business 2 labor_public
const STANCE_N: int = 36        # BLOC_N * POLICY_N
const AFFIL_N: int = 108        # GROUP * BLOC_N
const RNG_STREAM_N: int = 6
const PAY_LINE_N: int = 8       # 支付优先级 8 档
const BUYER_CLASS_N: int = 5    # 0 居民 1 公共服务 2 政府采购 3 企业投入 4 出口
const MARKET_N: int = 20        # S * BUYER_CLASS_N
const OPEX_N: int = 12          # R * SERVICE_KIND
const QUANTILE_N: int = 5
const AGENT_N: int = 60
const ACCOUNT_CODE_N: int = 15
const ACCOUNT_N: int = 900      # AGENT_N * ACCOUNT_CODE_N
const BOND_CAP0: int = 512      # 债券 SoA 初始容量（param.bond_batch_cap 的编译期上限）
const PROJECT_CAP0: int = 64    # 项目 SoA 初始容量
const MIGRATION_CAP: int = 256  # 稀疏迁移流每季上限行数
const LOG_CAP0: int = 8192      # param.log_capacity_rows 的初值
```

### 2.2 索引函数（`JWIds`，全部 `static`、O(1)、无分支）

```gdscript
static func idx_cell(r: int, s: int) -> int             # r * 4 + s           0..15
static func idx_group(r: int, a: int, k: int) -> int    # r * 9 + a * 3 + k   0..35
static func idx_io(s_from: int, s_to: int) -> int       # s_from * 4 + s_to   0..15
static func idx_inv(cell: int, s_in: int) -> int        # cell * 4 + s_in     0..63
static func idx_emp(cell: int, k: int) -> int           # cell * 3 + k        0..47
static func idx_od(r_from: int, r_to: int) -> int       # r_from * 4 + r_to   0..15
static func idx_group_emp(g: int, slot: int) -> int     # g * 5 + slot        0..179（slot==4 为 pubserv）
static func idx_group_svc(g: int, kind: int) -> int     # g * 3 + kind        0..107
static func idx_group_prod(g: int, s: int) -> int       # g * 4 + s           0..143
static func idx_edu(g: int, slot: int) -> int           # g * 8 + slot        0..287
static func idx_pubserv_emp(r: int, k: int) -> int      # r * 3 + k           0..11
static func idx_pubserv_queue(r: int, kind: int) -> int # r * 3 + kind        0..11
static func idx_market(s: int, buyer: int) -> int       # s * 5 + buyer       0..19
static func idx_policy_param(p: int, j: int) -> int     # p * 4 + j           0..47
static func idx_stance(b: int, p: int) -> int           # b * 12 + p          0..35
static func idx_affil(g: int, b: int) -> int            # g * 3 + b           0..107
static func idx_opex(r: int, kind: int) -> int          # r * 3 + kind        0..11
static func idx_account(agent: int, code: int) -> int   # agent * 15 + code   0..899

# 反解（报告与写日志时用；结算算式里不用）
static func region_of_cell(cell: int) -> int
static func sector_of_cell(cell: int) -> int
static func region_of_group(g: int) -> int
static func age_of_group(g: int) -> int
static func skill_of_group(g: int) -> int
```

### 2.3 主体（agent）下标布局 —— 60 个，加载期枚举，运行期不新建

```
 0            agent.gov
 1 .. 16      agent.cell.<region>.<sector>        == 1 + idx_cell(r, s)
17 .. 20      agent.pubserv.<region>              == 17 + r
21 .. 56      agent.group.<region>.<age>.<skill>  == 21 + idx_group(r, a, k)
57            agent.invpool
58            agent.row
59            agent.opening
```

```gdscript
const AGENT_GOV: int = 0
const AGENT_CELL_BASE: int = 1
const AGENT_PUBSERV_BASE: int = 17
const AGENT_GROUP_BASE: int = 21
const AGENT_INVPOOL: int = 57
const AGENT_ROW: int = 58
const AGENT_OPENING: int = 59

static func agent_of_cell(cell: int) -> int      # AGENT_CELL_BASE + cell
static func agent_of_pubserv(r: int) -> int      # AGENT_PUBSERV_BASE + r
static func agent_of_group(g: int) -> int        # AGENT_GROUP_BASE + g
static func cell_of_agent(a: int) -> int         # 非 cell 主体返回 -1
static func group_of_agent(a: int) -> int        # 非 group 主体返回 -1
```

**现金主体口径（`docs/10` §2.1 与 OQ-217 的合并，必须写进注释）**

```gdscript
const AGENT_CASH_ACCOUNTS: int = 56   # 全部主体减去 4 个 pubserv（pubserv 无自有现金，其支付由 gov 执行）
const AGENT_CASH_ACTIVE: int  = 55    # docs/10 §2.1 的「持有现金的主体共 55 个」口径：
                                      # 不含 agent.opening —— 其 cash 科目存在但开账后恒为 0（OQ-217）
```

INV-018（`Σ cash == scenario.total_cash_uu`）对 **56 个** cash 科目求和。
`agent.opening.cash` 恒为 0，不影响结果，但必须参与求和 —— 否则「恒为 0」这件事就没人检查了。
`T-U-OPENING-BALANCE` 断言 `accounts.cash_of(AGENT_OPENING) == 0`。

### 2.4 科目（account code）下标布局 —— 15 个

```
 0 cash            1 inv.agri        2 inv.manu       3 inv.energy     4 inv.services
 5 wip             6 capital         7 housing        8 recv           9 bondhold
10 deposit_claim  11 pay            12 debt          13 deposit_liab  14 nw
```

```gdscript
const ACC_CASH: int = 0
const ACC_INV_BASE: int = 1          # ACC_INV_BASE + sector
const ACC_WIP: int = 5
const ACC_CAPITAL: int = 6
const ACC_HOUSING: int = 7
const ACC_RECV: int = 8
const ACC_BONDHOLD: int = 9
const ACC_DEPOSIT_CLAIM: int = 10
const ACC_PAY: int = 11
const ACC_DEBT: int = 12
const ACC_DEPOSIT_LIAB: int = 13
const ACC_NW: int = 14
```

**方向约定**：资产科目（0..10）余额为正表示资产，负债科目（11..13）余额为正表示负债，
`nw` 是平衡项，由 `JWLedger` 在每次 `post()` 内同步维护，**不是独立可写字段**（`docs/10` §2.2）。
过账行的 `delta_uu` 一律「资产增 +、负债增 −」（`docs/10` §2.5），
`JWLedger._apply()` 负责把这个符号约定翻译成上面的余额约定，**这是全系统唯一一处做该翻译的地方**。

### 2.5 子系统（`subsystem_hash` 与 WriteGuard 的粒度，`docs/10` §11 的 15 个）

```gdscript
const SUBSYS_META: int = 0      const SUBSYS_TIME: int = 1      const SUBSYS_GOV: int = 2
const SUBSYS_BOND: int = 3      const SUBSYS_CELL: int = 4      const SUBSYS_PUBSERV: int = 5
const SUBSYS_GROUP: int = 6     const SUBSYS_REGION: int = 7    const SUBSYS_PROJECT: int = 8
const SUBSYS_POLICY: int = 9    const SUBSYS_POLITICS: int = 10 const SUBSYS_WORLD: int = 11
const SUBSYS_PRICE: int = 12    const SUBSYS_MARKET: int = 13   const SUBSYS_RNG: int = 14
const SUBSYS_N: int = 15
```

一个类可以持有多个子系统的数据（例如 `JWCapital` 同时持有 `SUBSYS_CELL` 的产能与 `SUBSYS_REGION` 的设施）；
`STATE_ARRAY_SUBSYS` 逐数组登记归属。**账户余额（`JWAccount`）按主体归属映射到子系统**：
`gov → SUBSYS_GOV`，`cell → SUBSYS_CELL`，`group → SUBSYS_GROUP`，`invpool/row/opening → SUBSYS_GOV`
（它们的余额只在 S02/S06 随政府与居民一起变动，归到 GOV 不会削弱 WriteGuard 的分辨力）。

### 2.6 数值参数 `param.*` 的运行期形态（`docs/14_parameter_registry.md` 的落点）

**不新增文件。** 全部 `param.<snake_name>` 在加载期被折成一个稠密整数数组：

```gdscript
# JWUnits 内。枚举名 == 参数卡 ID 去掉 `param.` 前缀后大写；
# 顺序 == 参数卡 ID 的字典序（数组型参数按下标占连续槽位）。
# 清单来自 content/parameters/registry.json 的 contract_min_set（72 项），
# 其中 param.rng_salt 不进本数组（它是 content.rng.salt[6]，由 JWRngStreams 持有）。
enum Param {
    AMOUNT_MAX_UU = 0, BLOC_CARE_GAIN_PPM = 1, BLOC_ORG_INERTIA_PPM = 2,
    BLOC_RESOURCE_REF_UU = 3, BLOC_W_RESOURCE_PPM = 4, BLOC_W_SIZE_PPM = 5,
    BOND_BATCH_CAP = 6, COMMITMENT_HORIZON_Q = 7, CONSTRUCTION_SHARE_CAP_PPM = 8,
    COUPON_MAX_PPM = 9, COUPON_MIN_PPM = 10, DEFAULT_GRACE_Q = 11,
    DEMAND_SMOOTH_PPM = 12, DISSAVE_PPM = 13, EDU_PIPELINE_SLOTS = 14,
    EMISSION_DECAY_PPM = 15, ENGEL_WEIGHT_PPM_0 = 16, ENGEL_WEIGHT_PPM_1 = 17,
    ENGEL_WEIGHT_PPM_2 = 18, ENGEL_WEIGHT_PPM_3 = 19, ENV_EXPOSURE_GAIN_PPM = 20,
    EXPECTATION_INERTIA_PPM = 21, FIRING_FRICTION_PPM = 22, GAP_CAP_PPM = 23,
    HIRING_FRICTION_PPM = 24, HOUSEHOLD_BOND_APPETITE_PPM = 25, INVENTORY_TARGET_PPM = 26,
    INVEST_PROPENSITY_PPM = 27, LIVING_WEIGHT_HOUSE_PPM = 28, LIVING_WEIGHT_SERVICE_PPM = 29,
    LOG_CAPACITY_ROWS = 30, MAINTENANCE_BACKLOG_GAIN_PPM = 31, MAINTENANCE_BACKLOG_MAX_PPM = 32,
    MAINTENANCE_BACKLOG_RECOVER_PPM = 33, MARKET_RATE_BASE_PPM = 34, MARKET_RATE_SLOPE_PPM = 35,
    MIGRATION_MAX_SHARE_PPM = 36, MIGRATION_THRESHOLD_PPM = 37, MIGRATION_W_ENV_PPM = 38,
    MIGRATION_W_HOUSE_PPM = 39, MIGRATION_W_JOB_PPM = 40, MIGRATION_W_SERVICE_PPM = 41,
    MIGRATION_W_WAGE_PPM = 42, MPC_PPM = 43, NO_CONFIDENCE_Q = 44,
    OPEX_RECOVER_PPM = 45, OPEX_STARVE_DECAY_PPM = 46, PAYOUT_RATIO_PPM = 47,
    PERSONS_PER_HOUSING_UNIT = 48, POLICY_TOGGLE_COST_UU = 49, PRICE_CEIL_PPM = 50,
    PRICE_CLAMP_BUDGET_COUNT = 51, PRICE_COVER_GAIN_PPM = 52, PRICE_FLOOR_PPM = 53,
    PRICE_GAP_GAIN_PPM = 54, PRICE_STEP_MAX_PPM = 55, QTY_MAX_UQS = 56,
    RATE_SENSITIVITY_PPM = 57, STUDENT_TEACHER_RATIO = 58, SUPPORT_WEIGHT_PPM_0 = 59,
    SUPPORT_WEIGHT_PPM_1 = 60, SUPPORT_WEIGHT_PPM_2 = 61, TAX_BASE_RATE_PPM = 62,
    TAX_EVASION_SLOPE_PPM = 63, TAX_RECOVERY_PPM = 64, TRAINING_LAG_Q = 65,
    TRUST_DROP_PPM = 66, TRUST_RECOVER_PPM = 67, TRUST_STREAK_CAP_Q = 68,
    UU_TO_CONSTRUCTION_UQS_PPM = 69, WAGE_CASH_SHARE_PPM = 70, WAGE_CEIL_UU = 71,
    WAGE_FLOOR_UU = 72, WAGE_GAIN_PPM = 73, WAGE_STEP_MAX_PPM = 74,
    WRITE_GUARD_SAMPLE_Q = 75,
}
const PARAM_N: int = 76
```

- 运行期一律 `params[JWUnits.Param.XXX]`，**`sim/**` 内不出现裸数字字面量**
  （白名单仅 `0, 1, -1, 1_000_000` 与 §2.1 的维度常量，INV-152，`check_param_coverage.gd` 检查）。
- 该数组由 `JWSimState.params` 持有，以 `PackedInt64Array` 形参传进各域方法
  —— 域类因此**不需要认识 `JWSimState`**（§3.1 规则 R-B）。
- 枚举顺序即数组下标顺序，是 `param_set_version` 的一部分；**新增参数只能追加在末尾**
  （追加不改动已有下标，因此不需要升 `save.schema_version`；插入或重排则需要）。
- `AMOUNT_MAX_UU` 与 `QTY_MAX_UQS` 与代码常量 `JWUnits.AMOUNT_MAX` / `QTY_MAX` **重复登记**：
  加载期必须逐字相等（不等即 `Load.UNIT_MISMATCH`）。故意冗余，防止参数包与代码各说各的。
- 加载期交叉校验（例：`TRUST_RECOVER_PPM < TRUST_DROP_PPM`，INV-122；
  三项 `SUPPORT_WEIGHT_PPM` 之和 == 1 000 000；四项 `ENGEL_WEIGHT_PPM` 之和 == 1 000 000；
  三项迁移权重与两项 `LIVING_WEIGHT` + `SUPPORT_WEIGHT_PPM_0` 的口径一致性）
  由 `JWContentLoader.validate_params()` 执行。
- **当前 `registry.json` 的 `contract_min_set_missing == 72`**：这 72 项参数卡尚未在内容包里写出来。
  骨架先把**下标布局**定死，内容作者按本表逐项补卡；补齐前 `JWContentLoader.load_all()` 必然失败
  （`Load.PARAM_COVERAGE`），这是预期行为，不是缺陷。

---

## 3 分层、所有权与调用方向（无环证明）

### 3.1 三条结构性规则

**R-A（数据所有权唯一）**：每个稳定 ID 只有**一个**类持有它的数组。
别的类要读它，调那个类的只读方法；要写它，调那个类的领域方法。
「一个文件一个负责人」因此等价于「一个字段一个负责人」。

**R-B（SimCore 域类不认识 `JWSimState`）**：`sim/**` 里除 `sim/state/sim_state.gd` 自己以外，
**任何类都不得引用 `JWSimState`**。跨域数据一律以**显式形参**传入（传对象引用或 `PackedInt64Array`）。
这条规则是本骨架无环的根本原因：`JWSimState` 单向依赖全部域类，域类之间只按 §3.2 的秩单向依赖。
静态检查：在**剥离注释后的代码行**上（与 `tools/layer_check.py` 同一约定：去掉行内 `#` 之后的内容、
整行跳过 `##` 文档注释），`sim/**` 除 `sim/state/sim_state.gd` 外不得出现标识符 `JWSimState`。
注释里提及类名（例如「LOAD 期由 `JWSimState` 装配」）不算引用 —— 注释不产生依赖边；
按字面 `grep` 整个文件会把这类说明也判成违规，那是检查式写错了，不是代码写错了。

**R-C（派生量不进结算路径）**：`derived.*` 由**其所有者以纯函数形式**提供
（例如 `JWPopulation.labor_force(g)`、`JWBondBook.debt_outstanding()`）。
`JWDiagnostics` 只做汇总、快照与 INV-014 的一致性比对，**任何 S01…S08 的结算路径都不得调用 `JWDiagnostics`**。
静态检查：`sim/**`（除 `report/diagnostics.gd` 与 `state/sim_state.gd`）与 `systems/turn_runner.gd`
的结算段不出现 `JWDiagnostics`。
`state/sim_state.gd` 的豁免只限**持有声明**那一行（`var diag: JWDiagnostics`）——
§3.2 要求秩 10 的 `JWSimState` 持有全部域类，本行是该要求的实现，不是结算路径调用。
唯一例外：S08 末 `JWTurnRunner` 调 `JWDiagnostics.snapshot_and_verify(...)`，它只读不写状态；
该方法按规则 R-B 逐个接收域类形参，**不接收 `JWSimState`**（秩 9 不得引用秩 10）。

### 3.2 依赖秩（只能依赖**严格更低**的秩；同秩之间不得互相引用）

| 秩 | 文件 | 类 | 允许引用 |
|---|---|---|---|
| 0 | `sim/jw_units.gd` | `JWUnits` | — |
| 0 | `sim/jw_result.gd` | `JWResult` | — |
| 1 | `sim/jw_math.gd` | `JWMath` | 0 |
| 1 | `sim/jw_ids.gd` | `JWIds` | 0 |
| 2 | `sim/state/rng_streams.gd` | `JWRngStreams` | 0,1 |
| 2 | `sim/ledger/account.gd` | `JWAccount` | 0,1 |
| 2 | `sim/sectors/io_table.gd` | `JWIoTable` | 0,1 |
| 2 | `sim/policy/policy_def.gd` | `JWPolicyDef` | 0,1 |
| 2 | `sim/sectors/pricing.gd` | `JWPricing` | 0,1 |
| 3 | `sim/ledger/ledger.gd` | `JWLedger` | 0,1,2 |
| 4 | `sim/ledger/bond_book.gd` | `JWBondBook` | ≤3 |
| 4 | `sim/sectors/capital.gd` | `JWCapital` | ≤3 |
| 4 | `sim/population/population.gd` | `JWPopulation` | ≤3 |
| 4 | `sim/world/world_market.gd` | `JWWorldMarket` | ≤3 |
| 5 | `sim/ledger/treasury.gd` | `JWTreasury` | ≤4 |
| 5 | `sim/population/labor_market.gd` | `JWLaborMarket` | ≤4 |
| 5 | `sim/world/shocks.gd` | `JWShocks` | ≤4 |
| 6 | `sim/sectors/inventory.gd` | `JWInventory` | ≤5 |
| 6 | `sim/projects/project_queue.gd` | `JWProjectQueue` | ≤5 |
| 6 | `sim/population/migration.gd` | `JWMigration` | ≤5 |
| 6 | `sim/politics/politics.gd` | `JWPolitics` | ≤5 |
| 7 | `sim/sectors/sector_model.gd` | `JWSectorModel` | ≤6 |
| 8 | `sim/projects/asset_commissioning.gd` | `JWAssetCommissioning` | ≤7 |
| 8 | `sim/policy/policy_engine.gd` | `JWPolicyEngine` | ≤7 |
| 8 | `sim/politics/interest_groups.gd` | `JWInterestGroups` | ≤7 |
| 9 | `sim/report/diagnostics.gd` | `JWDiagnostics` | ≤8（只读） |
| 10 | `sim/state/sim_state.gd` | `JWSimState` | ≤9（持有全部域类） |
| A0 | `systems/commands.gd` | `JWCommands` | ≤1，`JWPolicyDef` |
| A1 | `systems/content_loader.gd` | `JWContentLoader` | ≤10, A0 |
| A2 | `systems/event_engine.gd` | `JWEventEngine` | ≤10 |
| A3 | `systems/turn_runner.gd` | `JWTurnRunner` | ≤10, A0, A2 |
| A4 | `systems/saves.gd` | `JWSaves` | ≤10, A0, A1 |
| A5 | `application/replay.gd` | `JWReplay` | ≤10, A0..A4 |
| A6 | `application/game.gd` | `JWGame` | ≤10, A0..A5 |

**无环证明**：上表是一个全序（秩严格递增），每条允许边都从高秩指向低秩，
因此依赖图是有向无环的（DAG）。同秩文件之间不存在任何引用 —— 这一点由静态检查逐对验证。

### 3.3 四条容易画成环、本骨架已改掉的边（必须记住）

| 看起来需要的边 | 为什么会成环 | 本骨架的改法 |
|---|---|---|
| `JWPopulation → JWLaborMarket`（S07 人口流出要扣就业） | `JWLaborMarket` 已依赖 `JWPopulation`（秩 5 → 4） | `JWTurnRunner` 先从 `JWPopulation.outflow_persons()` 取流出量，再调 `JWLaborMarket.release_for_outflow(...)`。**S07 对 `employment_persons` 的写只在这一个函数里**（INV-080） |
| `JWWorldMarket → JWInventory`（出口要减库存） | `JWInventory` 已依赖 `JWWorldMarket`（秩 5 → 4） | 出口是买方类 4，交易由 `JWInventory` 统一撮合与过账；`JWWorldMarket` 只提供额度并接收 `record_export()` 回写 |
| `JWPolitics → JWInterestGroups`（支持度想看集团） | 也违反 INV-125 | **结构上禁止**：票、组织影响力、行政能力由三个类分别计算，互不引用（静态检查） |
| `JWTreasury → JWSectorModel`（S06 算利润税） | 会形成 5 → 7 的反向边 | `JWTurnRunner` 先从 `JWSectorModel` 取 `taxable_by_cell` 数组，再传给 `JWTreasury.collect_profit_tax()` |
| `JWLaborMarket → JWTreasury`（S04 付公共工资） | 两者同秩 5，同秩禁止互引 | `JWTurnRunner` 取 `labor.public_wage_due_into()` → `treasury.pay_line()` → `labor.record_public_wage_paid()` |
| `JWProjectQueue → JWSectorModel`（S05 要服务产量折施工能力） | 会形成 6 → 7 的反向边 | `JWTurnRunner` 把 `output_actual_uqs` 数组传进 `project_queue.advance_progress()` |
| 任意域类 `→ JWDiagnostics`（想取 `derived.*`） | `JWDiagnostics` 秩 9，读所有人 | 派生量由所有者提供纯函数（R-C）；`JWDiagnostics` 只汇总 |

**统一改法**：凡是会形成反向边或同秩边的地方，一律把**对象依赖降级成数组形参**，
由 `JWTurnRunner` 做中转。代价是 `JWTurnRunner` 的方法参数变长；
收益是依赖图恒为 DAG，且每一步的输入在签名里一眼可见（正是 §1.5 可写子集纪律想要的）。

### 3.4 层边界（计划书 §12 的可执行形式）

- `sim/**` 不出现 `Node` / `Control` / `SceneTree` / `get_tree()` / `tr(` / `res://ui/` / `float` /
  浮点字面量 / `randf`（`tools/layer_check.py` 机器检查）。
- `systems/**`、`application/**` 也不得出现 `float`（INV-001 覆盖两层）。
- `ui/**` 只能拿 `JWGame.StateView`，且 `StateView` 的每个数组访问器都 `duplicate()` 后返回；
  `ui/**` 出现 `JWLedger` / `JWSimState` 的写方法即违规。
- SimCore 的状态写接口一律以 `_` 开头的只有一类：`JWAccount._apply_delta()`（只许 `JWLedger` 调）。
  其余领域方法是公开的，因为它们本身就带着不变量检查 —— 把检查放在门里，比把门锁上更可靠。

---

## 4 文件逐一

> 表格列：**稳定 ID** = `docs/10` 的 ID；**类** = S 存量 / F 流量 / C 内容 / L 日志；
> **写入者** = `docs/10` §0.7 的代号。长度省略时为标量。

### 4.1 `sim/jw_units.gd` · `class_name JWUnits extends RefCounted`

**职责**：单位常量、维度常量、全部枚举。**没有任何逻辑，没有任何状态。**
所有人都依赖它，所以它不能依赖任何人。

#### 常量

| 名称 | 值 | 含义 |
|---|---|---|
| `U_SCALE` | `1_000_000` | 1 U = 1 000 000 μU |
| `Q_SCALE` | `1_000_000` | 1 Q_s = 1 000 000 μQ_s |
| `PPM` | `1_000_000` | 比率基数 |
| `BASE_PRICE` | `1_000_000` | 基年价格（μU/Q_s），`content.price.base_uu_per_qs` 的唯一合法值（INV-148） |
| `FX_RATE_PPM` | `1_000_000` | 汇率恒定（INV-105），任何写入即 FAULT |
| `BASE_YEAR_GDP_UU` | `100_000_000` | 基年全年名义 GDP（INV-118 的目标值） |
| `AMOUNT_MAX` | `4_000_000_000_000` | 金额上限（INV-007） |
| `QTY_MAX` | `1_000_000_000_000` | 数量上限（INV-007） |
| `PRICE_MIN` / `PRICE_MAX` | `400_000` / `2_500_000` | 价格绝对边界（INV-066） |
| `INT64_MAX` | `9_223_372_036_854_775_807` | 溢出守卫用 |
| `SENTINEL` | `== QTY_MAX` | 「该约束不适用」的哨兵（`docs/12` §5.3，INV-044） |
| §2.1 的全部维度常量 | — | 稠密下标布局，重排即破坏性变更 |

#### 枚举（全部 `int`，值即稠密下标，**不得重排**）

```gdscript
enum Region   { BEIYUAN = 0, ZHONGZHOU = 1, HAIJIA = 2, XILING = 3 }
enum Sector   { AGRI = 0, MANU = 1, ENERGY = 2, SERVICES = 3 }
enum Age      { MINOR = 0, WORKING = 1, ELDER = 2 }
enum Skill    { LOW = 0, MID = 1, HIGH = 2 }
enum ServiceKind { HEALTH = 0, EDUCATION = 1, UTILITY = 2 }
enum Phase    { IDLE = 0, S01 = 1, S02 = 2, S03 = 3, S04 = 4, S05 = 5, S06 = 6, S07 = 7, S08 = 8 }
enum Binding  { PLAN = 0, CAPACITY = 1, LABOR = 2, ENERGY = 3, MATERIALS = 4 }
enum BuyerClass { HOUSEHOLD = 0, PUBSERV = 1, GOV_PROCUREMENT = 2, FIRM_INPUT = 3, EXPORT = 4 }
enum PayLine  { DEBT_SERVICE = 0, PUBLIC_WAGES = 1, STATUTORY_TRANSFERS = 2, SERVICE_OPEX = 3,
                PROJECT_CONTRACTS = 4, PROCUREMENT = 5, SUBSIDIES = 6, DISCRETIONARY = 7 }
enum RngStream { SHOCK = 0, EVENT = 1, DEMOGRAPHY = 2, MARKET = 3, POLITICS = 4, RESERVED = 5 }
enum Rationing { NONE = 0, PRIORITY = 1, PROPORTIONAL = 2 }
enum ProjectStatus { PLANNED = 0, IN_PROGRESS = 1, SUSPENDED = 2, COMPLETED = 3,
                     COMMISSIONED = 4, CANCELLED = 5 }
enum SuspendReason { NONE = 0, FINANCING = 1, DELIVERY = 2, CONGESTION = 3, FUEL = 4, NO_DEMAND = 5 }
enum BlockedReason { NONE = 0, AUTHORITY = 1, BUDGET = 2, COOLDOWN = 3, PRECONDITION = 4,
                     QUEUE = 5, EXITED = 6 }
enum BondStatus { ACTIVE = 0, MATURED = 1, DEFAULTED = 2, RESTRUCTURED = 3, WRITTEN_OFF = 4 }
enum Amortization { BULLET = 0, LEVEL_PRINCIPAL = 1 }
enum Holder { INVPOOL = 0, ROW = 1 }
enum MandateGoal { INDUSTRY = 0, LIVELIHOOD = 1, FISCAL = 2 }
enum MandateStatus { OK = 0, AT_RISK = 1, LOST = 2 }
enum Termination { NONE = 0, HORIZON = 1, LOST_ELECTION = 2, LOST_CONFIDENCE = 3,
                   FISCAL_RESTRUCTURING_FAILED = 4 }
enum ExplainKind { ACCOUNTED = 0, INFERRED = 1, PROJECTED = 2 }
enum Bloc { AGRI_COOP = 0, BUSINESS = 1, LABOR_PUBLIC = 2 }

## 账本交易类型码，逐字对应 docs/11 §5.3 的 28 项，值不得改（进日志、进存档）
enum Kind { WAGE_PAYMENT = 1, PUBLIC_WAGE_PAYMENT = 2, HOUSEHOLD_CONSUMPTION = 3,
            GOV_PROCUREMENT = 4, INTERMEDIATE_PURCHASE = 5, INVENTORY_CHANGE = 6,
            CAPITAL_PURCHASE = 7, EXPORT = 8, IMPORT = 9, INCOME_TAX = 10, PROFIT_TAX = 11,
            SUBSIDY = 12, TRANSFER = 13, HOUSEHOLD_SUPPORT = 14, BOND_ISSUE = 15,
            BOND_PRINCIPAL = 16, BOND_INTEREST = 17, PROPERTY_INCOME = 18, PROJECT_PAYMENT = 19,
            SERVICE_OPEX = 20, DEPRECIATION = 21, OPERATING_SURPLUS = 22, PRICE_VARIANCE = 23,
            OPENING_BALANCE = 24, MIGRATION_COST = 25, POLICY_TOGGLE_COST = 26,
            CANCEL_PENALTY = 27, WRITEOFF = 28 }
enum ProdClass { NONE = 0, SALE_FINAL = 1, SALE_INTERMEDIATE = 2, INV_CHANGE = 3, VA_NONMARKET = 4 }
enum ExpClass  { NONE = 0, C = 1, G = 2, I = 3, DINV = 4, X = 5, M = 6 }
enum IncClass  { NONE = 0, COMPENSATION = 1, GROSS_OPERATING_SURPLUS = 2,
                 CONSUMPTION_OF_FIXED_CAPITAL = 3 }
```

#### 静态表

```gdscript
## kind → 三重分类（docs/11 §5.3）。下标 = Kind 值，长度 29（0 号占位不使用）。
## INV-114 的「按 kind 反查白名单」就是查这三张表；未登记的 kind 即 LEDGER_KIND_UNCLASSIFIED。
const KIND_PROD_CLASS: PackedInt64Array
const KIND_EXP_CLASS:  PackedInt64Array
const KIND_INC_CLASS:  PackedInt64Array
## kind 是否属于「三口径全 none 的再分配类」（10..18, 27, 28），供 INV-029 / INV-113 静态断言。
const KIND_IS_REDISTRIBUTION: PackedInt64Array

## 每步允许写入的子系统位掩码，下标 = Phase 值（docs/12 每步「可写子集」行的机器化）。
## JWTurnRunner._guard_begin/_guard_end 用它判 WRITE_OUT_OF_SCOPE。
const WRITABLE_SUBSYS: PackedInt64Array
```

#### 方法

```gdscript
## 校验一个 kind 是否已在三张分类表中登记。
## 步骤：加载期一次 + 每次 post() 一次（O(1) 查表）
## 前置：kind ∈ [1, 28]
## 后置：返回 true 表示三张表都有登记（可为 NONE，但必须是显式登记的 NONE）
## 不变量：INV-114
## 失败：越界或未登记返回 false，调用方转 Fault.LEDGER_KIND_UNCLASSIFIED
static func kind_is_classified(kind: int) -> bool
```

---

### 4.2 `sim/jw_result.gd` · `class_name JWResult extends RefCounted`

**职责**：全系统唯一的错误码定义与故障登记点。**禁止任何别的文件自定义错误码。**
它不依赖任何文件（连 `JWUnits` 都不依赖），因为 `JWMath` 要在溢出时调它。

#### 常量与枚举

```gdscript
const OK: int = 0

## 故障码，逐字对应 docs/12 §9 的 Fault 枚举，数值不得改（进故障包与测试断言）
enum Fault {
    OK = 0, RUN_ENDED = 1,
    FLOW_NOT_RESET = 10, WRITE_OUT_OF_SCOPE = 11, PHASE_VIOLATION = 12, RNG_LOG_MISMATCH = 13,
    NEGATIVE_CASH = 20, BOND_MISMATCH = 21, LEDGER_IMBALANCE = 22, SPLIT_MISMATCH = 23,
    CASH_TOTAL_CHANGED = 24, BALANCE_SHEET_BROKEN = 25,
    NEGATIVE_INVENTORY = 30, UNBOUNDED_PRODUCTION = 31, ENERGY_STORED = 32,
    DOUBLE_ALLOCATION = 33, STOCK_IDENTITY = 34,
    POPULATION_NOT_CONSERVED = 40, MIGRATION_UNPAIRED = 41, EMPLOYMENT_OVERFLOW = 42,
    HOUSING_OVERFLOW = 43, WAGE_UNFUNDED = 44,
    GDP_CLASS_MISSING = 50, GDP_CLASS_DUPLICATE = 51, LEDGER_KIND_UNCLASSIFIED = 52,
    GDP_IDENTITY = 53,
    SUPPORT_UNEXPLAINED = 60, METRIC_UNKNOWN = 61,
    INT_OVERFLOW = 90, DIV_ZERO = 91, INDEX_OUT_OF_RANGE = 92, FLOAT_IN_STATE = 93,
}

## 命令与加载期拒绝码，逐字对应 docs/11 §7 的 E_* 表（此处按用途分两组，值连续，不得改）
enum Reject {
    NONE = 0,
    RUN_TERMINATED = 1000, PHASE_BUSY = 1001, UNKNOWN_POLICY = 1002, POLICY_COOLDOWN = 1003,
    AUTHORITY = 1004, SEATS_SHORT = 1005, BLOC_VETO = 1006, BUDGET_INSUFFICIENT = 1007,
    NO_FUNDING = 1008, CREDIT_LIMIT = 1009, NO_SLOT = 1010, PRECONDITION = 1011,
    ALREADY_ENACTED = 1012, NOT_FOUND = 1013, DIRECT_STATE_WRITE = 1014,
    PARAM_RANGE = 1015, PRIORITY_INCOMPLETE = 1016, OVERPAY = 1017, COMMAND_ORDER = 1018,
}
enum Load {
    NONE = 0,
    FILE_FORMAT = 2000, SCHEMA_HEADER = 2001, FLOAT_IN_CONTENT = 2002, INT_RANGE = 2003,
    NULL_NOT_ALLOWED = 2004, UNKNOWN_FIELD = 2005, KEY_NAMING = 2006, DUP_ID = 2007,
    ID_FORMAT = 2008, ALIAS_IN_CONTENT = 2009, UNIT_MISMATCH = 2010,
    POP_TOTAL = 2100, POP_REGION = 2101, GROUP_SET = 2102, POP_AGE_ROLE = 2103, POP_EMP = 2104,
    POP_UNEMP = 2105, EMPLOY_MISMATCH = 2106, HOUSE_CAP = 2107, HOUSE_OVER = 2108,
    INDEX_BASE = 2109,
    CASH_INIT = 2200, DEBT_TOTAL = 2201, FIN_YEARPLAN = 2202, FIN_LINES = 2203,
    FIN_INTEREST = 2204, BOND_FIELD = 2205, INVPOOL_TOO_SMALL = 2206, DEPOSIT_MISMATCH = 2207,
    GDP_INIT = 2208, BALANCE_INIT = 2209, CASH_TOTAL = 2210, ASSERT_TOLERANCE = 2211,
    REGION_SET = 2300, REGION_ADJ = 2301, REGION_SLOTS = 2302, CELL_SET = 2303,
    ENERGY_INVENTORY = 2304, CAPACITY_INCONSISTENT = 2305, EQUITY_SHARE = 2306,
    SERVICE_SPLIT = 2307, RANGE = 2308,
    IO_COLSUM = 2400, IO_STORABLE = 2401, IO_ENERGY_SELF = 2402, IO_NEGATIVE = 2403,
    IO_NOT_CONVERGENT = 2404, IO_ENERGY_COEFF = 2405, IO_LABOR = 2406, IO_CAPACITY_COEFF = 2407,
    POLICY_COUNT = 2500, POLICY_FIELDS = 2501, POLICY_COST = 2502, COMMISSION_LAG = 2503,
    POLICY_TEST_MISSING = 2504, MECH_UNKNOWN = 2505, EFFECT_TARGET = 2506,
    EVENT_COUNT = 2600, METRIC_UNKNOWN = 2601, EVENT_OP = 2602, EVENT_STREAM = 2603,
    EVENT_TARGET = 2604, EVENT_LEDGER = 2605, EVENT_FIELD = 2606, EVENT_EVIDENCE = 2607,
    SHOCK_COUNT = 2700, SHOCK_STREAM = 2701, SHOCK_WEIGHTS = 2702, SHOCK_SCOPE = 2703,
    SHOCK_LOG = 2704, SHOCK_RANGE = 2705,
    PARAM_CARD = 2800, FAKE_OBSERVED = 2801, PARAM_DERIVE = 2802, PARAM_COVERAGE = 2803,
    PARAM_STALE = 2804,
    SAVE_CORRUPT = 2900, SAVE_VERSION_TOO_NEW = 2901, MIGRATION_MISSING = 2902,
}
```

#### 成员变量（冷路径对象形态）

| 成员 | 类型 | 初值 | 含义 |
|---|---|---|---|
| `ok` | `bool` | `true` | 是否成功 |
| `code` | `int` | `0` | `Fault` / `Reject` / `Load` 之一 |
| `detail_a` | `int` | `0` | 上下文整数 1（实体下标、期望值） |
| `detail_b` | `int` | `0` | 上下文整数 2（实际值、残差） |
| `detail_key` | `int` | `0` | 本地化文案键的整数码（**不存字符串**，由 Presentation 查表） |

#### 静态故障登记（热路径用，无对象分配）

| 成员 | 类型 | 初值 | 含义 |
|---|---|---|---|
| `_pending_code` | `static var int` | `0` | 本季第一次故障的码；后续故障不覆盖它 |
| `_pending_step` | `static var int` | `0` | 故障发生的步骤（`JWUnits.Phase`） |
| `_pending_a` / `_pending_b` | `static var int` | `0` | 现场整数 |
| `_current_step` | `static var int` | `0` | 由 `JWTurnRunner` 每步入口设置，供 `raise_fault` 自动带上步骤 |

#### 方法

```gdscript
## 登记一次故障并返回故障码，供调用方直接 `return JWResult.raise_fault(...)`。
## 步骤：任意（热路径）
## 前置：code != 0
## 后置：_pending_* 被写（仅第一次），返回值 == code
## 不变量：INV-006, INV-007（溢出与越界经由本函数落地）；docs/12 §9 的「不回滚到看起来正常的状态」
## 失败：本身不失败；它就是失败的登记点
static func raise_fault(code: int, detail_a: int = 0, detail_b: int = 0) -> int

## 查询本季是否已有未处理故障（WriteGuard 与 TurnRunner 用）。
## 步骤：每步末
## 前置：无
## 后置：不改状态
## 不变量：INV-012（有故障即中止推进）
## 失败：无
static func has_pending() -> bool
static func pending_code() -> int
static func pending_step() -> int

## 清空故障登记，只允许在开始新的一局或导出故障包之后调用。
## 步骤：LOAD / 故障包导出后
## 前置：调用方已经把故障包写盘
## 后置：_pending_* 归零
## 不变量：docs/12 §9「不得自动修正」——本函数不修状态，只清登记
## 失败：无
static func clear_pending() -> void

## 设置当前步骤号，使 raise_fault 自动带上步骤（避免每个调用点手写步骤）。
## 步骤：S01..S08 入口
## 前置：step ∈ JWUnits.Phase
## 后置：_current_step == step
## 不变量：INV-012
## 失败：无
static func set_step(step: int) -> void

## 冷路径构造器。
## 步骤：加载 / 命令 / 存档
## 前置：无
## 后置：返回一个新对象；**禁止在结算期调用**（静态检查：sim/** 的结算路径不得出现 make_* ）
## 不变量：§1.4 热路径不分配
## 失败：无
static func make_ok() -> JWResult
static func make_err(code: int, a: int = 0, b: int = 0, key: int = 0) -> JWResult
```

---

### 4.3 `sim/jw_math.gd` · `class_name JWMath extends RefCounted`

**职责**：整数定点算术的唯一实现。**`sim/**` 与 `systems/**` 内禁止裸 `/` 与 `%`**（INV-002），
一切除法、缩放、拆分只能经本类。

#### 成员（静态 scratch，避免热路径分配）

| 成员 | 类型 | 长度 | 含义 |
|---|---|---|---|
| `_split_base` | `static var PackedInt64Array` | `SPLIT_MAX_N = 256` | 最大余数法的整除部分缓冲 |
| `_split_rem` | `static var PackedInt64Array` | `SPLIT_MAX_N` | 余数缓冲 |
| `_split_order` | `static var PackedInt64Array` | `SPLIT_MAX_N` | 排序下标缓冲（决胜键 + 余数） |

`SPLIT_MAX_N = 256` 覆盖首版全部拆分场景（最大是 36 群组 / 64 库存项 / 60 收款方）；
超长即 `Fault.INDEX_OUT_OF_RANGE`，**不允许动态扩容**（扩容会在热路径分配）。

#### 方法

```gdscript
## 带显式溢出前置检查的乘法。release 构建也执行（Godot 的 assert 会被剥离）。
## 步骤：全部（一切乘法的唯一入口）
## 前置：无
## 后置：返回 a*b；溢出时已登记 INT_OVERFLOW 并返回 0
## 不变量：INV-006（M0 规则）
## 失败：`JWResult.raise_fault(Fault.INT_OVERFLOW, a, b)`，返回 0；**不做饱和截断**
static func mul(a: int, b: int) -> int

## 向下取整除法（对负数也向 −∞）。GDScript 的 `/` 向零截断，不是我们要的语义。
## 步骤：全部
## 前置：b != 0
## 后置：返回 floor(a/b)
## 不变量：INV-002；docs/10 §0.9 铁律一（不存在四舍五入）
## 失败：b == 0 → `raise_fault(Fault.DIV_ZERO)` 返回 0
static func floor_div(a: int, b: int) -> int

## 向上取整除法。用于「投入消耗」「用工人数」等不得少算的场合。
## 步骤：S03 §3.2/§3.5、S05 §5.2/§5.4
## 前置：b != 0
## 后置：返回 ceil(a/b) == -floor_div(-a, b)
## 不变量：INV-046（ceil 反算不透支的整数引理，见 docs/12 §5.4）
## 失败：同 floor_div
static func ceil_div(a: int, b: int) -> int

## ppm 缩放（单次取整）。
## 步骤：全部
## 前置：|x| <= AMOUNT_MAX 或 QTY_MAX（由调用方保证并断言）
## 后置：返回 floor_div(mul(x, p), PPM)
## 不变量：INV-005（换算余数写 log.rounding，不产生债权债务）；M1
## 失败：溢出转 mul 的失败路径
static func mul_ppm(x: int, p: int) -> int

## 两个 ppm 先合并再缩放，**只取整一次**。禁止 mul_ppm(mul_ppm(x,p1),p2)。
## 步骤：S03 §3.6、S07 §7.9 等
## 前置：同上
## 后置：返回 floor_div(mul(x, floor_div(mul(p1,p2), PPM)), PPM)
## 不变量：M2（禁止连乘两个 ppm）
## 失败：同 mul
static func mul_ppm_2(x: int, p1: int, p2: int) -> int

## 最大余数法拆分（热路径版本，写入调用方提供的 out）。
## 步骤：全部拆分场景（工资到组、支出到收款方、配给、年度拆季、等额本金、加权汇总）
## 前置：total >= 0；∀w >= 0；weights.size() == tiebreak.size() == out.size() <= SPLIT_MAX_N
## 后置：Σ out == total 精确成立；W == 0 时 out 全 0 并返回 residual = total 给调用方登记
## 不变量：INV-003（后置断言），INV-060（配给），INV-124（加权）
## 失败：长度越界 → INDEX_OUT_OF_RANGE；后置断言不成立 → SPLIT_MISMATCH（最严重的一类缺陷，立即停）
static func split_lr_into(total: int, weights: PackedInt64Array,
                          tiebreak: PackedInt64Array, out: PackedInt64Array) -> int

## 冷路径包装：返回一个新数组。**禁止出现在结算路径**（静态检查）。
## 步骤：加载期、测试
## 前置：同 split_lr_into
## 后置：同 split_lr_into
## 不变量：INV-003
## 失败：同 split_lr_into；失败时返回空数组
static func split_lr(total: int, weights: PackedInt64Array,
                     tiebreak: PackedInt64Array) -> PackedInt64Array

## 整数夹逼。**每个调用点必须由调用方自己写 log.clamp**（本函数不写日志，
## 因为它不知道字段码）。只允许出现在 docs/10 §0.8 登记为「有界平滑」的位置。
## 步骤：S03 摩擦、S05 进度、S07 价格与人口、S08 主观量
## 前置：lo <= hi
## 后置：返回 min(max(v, lo), hi)
## 不变量：INV-069（夹逼必须计数并写日志——由调用方负责）
## 失败：lo > hi → INDEX_OUT_OF_RANGE 返回 lo
static func clamp_i(v: int, lo: int, hi: int) -> int

## 绝对值、求和、上下界检查（写入前的护栏，INV-007）。
## 步骤：全部
## 前置：无
## 后置：check_* 越界时已登记故障
## 不变量：INV-007
## 失败：越界 → raise_fault(Fault.INT_OVERFLOW)，返回原值以便调用方继续走失败路径
static func absi(a: int) -> int
static func sum(a: PackedInt64Array) -> int
static func sum_abs(a: PackedInt64Array) -> int
static func check_amount(x: int) -> int
static func check_qty(x: int) -> int
static func check_price(p: int) -> int
```

---

### 4.4 `sim/jw_ids.gd` · `class_name JWIds extends RefCounted`

**职责**：稳定 ID 字符串 ↔ 稠密整数下标的双向映射（**只在 `LOAD` 期可用**），
以及 §2.2–§2.4 的全部索引函数（运行期只用这些）。

#### 成员变量

| 成员 | 类型 | 初值 | 类 | 含义 | 写入者 |
|---|---|---|---|---|---|
| `_id_to_index` | `Dictionary` | `{}` | — | `"<kind>:<id>" → int`，**加载期专用** | LOAD |
| `_index_to_id` | `Array[PackedStringArray]` | 按 kind 预分配 | — | 反查，用于写故障包与报告 | LOAD |
| `_frozen` | `bool` | `false` | — | `freeze()` 后禁止再解析字符串 | LOAD |

`IdKind` 枚举：`REGION, SECTOR, CELL, PUBSERV, GROUP, POLICY, EVENT, SHOCK, BOND, PROJECT, BLOC, AGENT, ACCOUNT, PARAM, MECHANISM`。

#### 方法

```gdscript
## 登记一个稳定 ID 与它的稠密下标。
## 步骤：LOAD
## 前置：!_frozen；id 匹配 docs/10 §0.4 的正则；同 kind 内 id 不重复
## 后置：resolve(kind, id) == index 且 id_of(kind, index) == id
## 不变量：INV-010（运行期 ID 只来自单调计数器，本函数不生成 ID，只登记）
## 失败：重复 → Load.DUP_ID；格式不符 → Load.ID_FORMAT；已冻结 → Fault.PHASE_VIOLATION
func register(kind: int, id: String, index: int) -> JWResult

## 字符串 ID → 稠密下标。**结算期调用即故障**。
## 步骤：LOAD
## 前置：!_frozen
## 后置：不改状态
## 不变量：docs/10 §0.6（运行期不使用 Dictionary 键查找）
## 失败：未登记 → 返回 -1；已冻结 → raise_fault(PHASE_VIOLATION) 返回 -1
func resolve(kind: int, id: String) -> int

## 稠密下标 → 字符串 ID。只用于故障包、存档 SoA 的 ids[]、报告模板取键。
## 步骤：LOAD / 存档 / 故障包（不在热路径）
## 前置：index 在该 kind 的范围内
## 后置：不改状态
## 不变量：INV-010
## 失败：越界返回空串并登记 INDEX_OUT_OF_RANGE
func id_of(kind: int, index: int) -> String

## 冻结映射表。加载流水线的最后一步调用；此后 SimCore 进入「零字符串」状态。
## 步骤：LOAD 末
## 前置：全部 kind 的登记数量等于 §2.1 的维度常量（CELL==16、GROUP==36…）
## 后置：_frozen == true
## 不变量：INV-142（群组齐全）、docs/10 §0.6
## 失败：数量不符 → Load.GROUP_SET / Load.CELL_SET / Load.REGION_SET
func freeze() -> JWResult

## §2.2–§2.4 的全部 static 索引函数（签名见 §2，此处不重复）。
## 步骤：全部
## 前置：各参数在其维度范围内
## 后置：返回稠密下标；**无分支、无除法**
## 不变量：docs/10 §0.5（下标布局是契约的一部分）
## 失败：debug 构建断言范围；release 构建越界由数组访问自身报 INDEX_OUT_OF_RANGE
```

**运行期生成 ID 的唯一路径**（INV-010）：`state.meta.entity_seq` 单调递增，
由 `JWSimState.next_entity_seq()` 提供；`JWBondBook` / `JWProjectQueue` 用它生成
`bond.q<qqq>_<nn>` 与 `project.<policy_code>_<issue_q>_<nnn>`，**禁止时间戳、指针、哈希**。

---

### 4.5 `sim/state/rng_streams.gd` · `class_name JWRngStreams extends RefCounted`

**职责**：计数器式确定性抽样（`docs/12` §0.4）。6 条流**结构性独立**：
任一流多抽一次，其它流的取值完全不变（INV-009）。持有 `log.rng`。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.rng.root_seed` | `root_seed` | `int` | — | 0 | S | uint64 位型 | LOAD |
| `state.rng.draw_count[]` | `draw_count` | `PackedInt64Array` | 6 | 全 0 | S | 计数 | S01,S03,S07,S08 |
| `content.rng.salt[]` | `salt` | `PackedInt64Array` | 6 | 内容包常量 | C | int64 | LOAD |
| `log.rng.stream[]` | `log_stream` | `PackedInt64Array` | `LOG_CAP0` | — | L | — | S01,S03,S07,S08 |
| `log.rng.draw_index[]` | `log_draw_index` | `PackedInt64Array` | `LOG_CAP0` | — | L | — | 同上 |
| `log.rng.purpose[]` | `log_purpose` | `PackedInt64Array` | `LOG_CAP0` | — | L | — | 同上 |
| `log.rng.raw_u64[]` | `log_raw` | `PackedInt64Array` | `LOG_CAP0` | — | L | — | 同上 |
| `log.rng.mapped[]` | `log_mapped` | `PackedInt64Array` | `LOG_CAP0` | — | L | — | 同上 |
| — | `_log_cursor` | `int` | — | 0 | L | — | 同上 |
| — | `_q` | `int` | — | 0 | — | 当季索引，由 `begin_quarter()` 写入 | S01 |

**`salt` 一经发布不得更改**（否则全部存档重放失效，INV-136）。
`root_seed` + 6 个 `draw_count` 就是**完整的随机流状态**（`docs/11` §6.3），存档不存内部状态。

#### 方法

```gdscript
## splitmix64。纯 int64 环绕算术；右移必须逻辑右移（(x >> n) & mask），
## 因为 GDScript 的 >> 对负数是算术右移。必须有已知测试向量的单元测试。
## 步骤：全部抽样的底座
## 前置：无
## 后置：同一 x 恒返回同一值；与引擎 RNG 无关
## 不变量：INV-010（抽样可复算）
## 失败：无（纯函数）
static func splitmix64(x: int) -> int

## 原始抽样：f(root_seed, salt[stream], q, index)。不推进计数器、不写日志。
## 步骤：全部；也是重放二分定位时「从任意季重算任意一次抽样」的入口
## 前置：stream ∈ [0,5]
## 后置：无副作用
## 不变量：INV-009（流隔离）、INV-010
## 失败：stream 越界 → INDEX_OUT_OF_RANGE 返回 0
func draw_raw(stream: int, q: int, index: int) -> int

## 无偏的 [0, n) 均匀整数：拒绝采样消除取模偏差。
## 步骤：S01 冲击、S03/S05 市场、S07 人口、S08 事件与政治
## 前置：n > 0；stream ∈ [0,5]
## 后置：draw_count[stream] 推进（含被拒的那次）；每次抽样写一条 log.rng（含被拒的那次）
## 不变量：INV-009, INV-010, INV-011（log.rng 条数 == Σ Δdraw_count）
## 失败：n <= 0 → DIV_ZERO 返回 0
func draw_below(stream: int, n: int, purpose: int) -> int

## [0, 1_000_000) 的 ppm 抽样；[lo, hi] 闭区间抽样。
## 步骤：同上
## 前置：lo <= hi
## 后置：同 draw_below
## 不变量：INV-009, INV-010, INV-011
## 失败：lo > hi → INDEX_OUT_OF_RANGE 返回 lo
func draw_ppm(stream: int, purpose: int) -> int
func draw_range(stream: int, lo: int, hi: int, purpose: int) -> int

## 设定本季 q（抽样公式里的 q 项）。只由 S01 调用一次。
## 步骤：S01
## 前置：q >= 0
## 后置：_q == q；日志游标重置
## 不变量：INV-011
## 失败：无
func begin_quarter(q: int) -> void

## 本季各流的抽样增量（供 INV-011 对账）。
## 步骤：每季末
## 前置：无
## 后置：不改状态
## 不变量：INV-011
## 失败：无
func draws_this_quarter() -> int
func draw_count_of(stream: int) -> int

## §1.6 状态块协议 + §1.7 日志通道协议的全部方法（签名见 §1.6/§1.7）。
## STATE_ARRAY_IDS = ["state.rng.draw_count"]；STATE_SCALAR_IDS = ["state.rng.root_seed"]
## FLOW_* 均为空（随机流没有流量）。log.rng 不进 state_hash。
```

---

### 4.6 `sim/ledger/account.gd` · `class_name JWAccount extends RefCounted`

**职责**：60 个主体 × 15 个科目 = 900 个余额的稠密表（`docs/10` §2.1/§2.2）。
**它是全系统唯一持有 `cash` / `inv` / `capital` / `debt` 数值的地方**，
因此 `docs/10` 里的 `state.gov.cash_uu`、`state.cell.cash_uu[]`、`state.group.cash_uu[]`、
`state.invpool.cash_uu` 都不是独立字段，而是本表的视图：

```
state.gov.cash_uu          == balance[idx_account(AGENT_GOV, ACC_CASH)]
state.cell.cash_uu[i]      == balance[idx_account(agent_of_cell(i), ACC_CASH)]
state.group.cash_uu[g]     == balance[idx_account(agent_of_group(g), ACC_CASH)]
state.group.deposit_uu[g]  == balance[idx_account(agent_of_group(g), ACC_DEPOSIT_CLAIM)]
state.invpool.cash_uu      == balance[idx_account(AGENT_INVPOOL, ACC_CASH)]
state.invpool.bondhold_uu  == balance[idx_account(AGENT_INVPOOL, ACC_BONDHOLD)]
state.invpool.deposit_liab_uu == balance[idx_account(AGENT_INVPOOL, ACC_DEPOSIT_LIAB)]
state.cell.inventory_* 的**价值腿** == balance[idx_account(agent_of_cell(i), ACC_INV_BASE + s)]
```

这样「绕开 `post()` 改现金」在结构上就不可能：改现金必须改本表，而本表的写入口只有一个 `_apply_delta()`，
静态检查要求其调用点只出现在 `sim/ledger/ledger.gd`（INV-022）。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `account.<agent>.<code>` | `balance` | `PackedInt64Array` | 900 | 0 | S | μU | S02..S07（全部经 `JWLedger.post()`） |
| — | `_cash_total_cached` | `int` | — | 0 | — | μU，INV-018 的缓存 | 同上 |
| — | `_owner_guard` | `int` | — | 0 | — | 非 0 表示当前在 `JWLedger` 的过账事务内 | `JWLedger` |

#### 方法

```gdscript
## 唯一的余额写入口。**只允许 sim/ledger/ledger.gd 调用**（静态检查 INV-022）。
## 步骤：S02..S07（由 post() 间接触发）
## 前置：_owner_guard != 0（必须在一次 post() 事务内）；account 在 [0, 900)
## 后置：balance[account] += delta；若为资产科目且结果 < 0 → 不写、返回 NEGATIVE_CASH 供整笔回滚
## 不变量：INV-016（cash >= 0，永不先扣成负数）、INV-007（幅度上限）
## 失败：现金为负 → Fault.NEGATIVE_CASH（**不改任何余额**）；越界 → INDEX_OUT_OF_RANGE
func _apply_delta(account: int, delta: int) -> int

## 开始／结束一次过账事务。post() 用它做「整笔回滚」。
## 步骤：S02..S07
## 前置：begin 时 _owner_guard == 0
## 后置：commit 后余额生效；rollback 后余额与 begin 前逐位相同
## 不变量：INV-015（一笔 txn 要么全成立要么全不成立）
## 失败：嵌套 begin → Fault.PHASE_VIOLATION
func begin_txn() -> int
func commit_txn() -> int
func rollback_txn() -> int

## 只读访问器（全系统读余额的唯一方式）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：—
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func get_balance(account: int) -> int
func cash_of(agent: int) -> int
func inv_of(agent: int, sector: int) -> int
func net_worth_of(agent: int) -> int

## 逐主体资产负债恒等式检查。
## 步骤：S06 §6.9、季末、载入后
## 前置：无
## 后置：不改状态
## 不变量：INV-020（cash+Σinv+wip+capital+housing+recv+bondhold+deposit_claim
##          −pay−debt−deposit_liab == nw）
## 失败：任一主体不成立 → Fault.BALANCE_SHEET_BROKEN，detail_a = 主体下标，detail_b = 残差
func check_balance_sheet() -> int

## 全经济现金总量与现金变动闭合。
## 步骤：S06 §6.9、季末
## 前置：quarter_start_cash_total 由 S01 记下
## 后置：不改状态
## 不变量：INV-017（Σ Δcash == 0）、INV-018（Σ cash == scenario.total_cash_uu）
## 失败：Fault.CASH_TOTAL_CHANGED，detail_b = 实际总量 − 期望总量
func total_cash() -> int
func check_cash_closure(expected_total: int, start_total: int) -> int

## Σ recv == Σ pay。
## 步骤：季末
## 前置：无
## 后置：不改状态
## 不变量：INV-019
## 失败：Fault.LEDGER_IMBALANCE
func check_receivable_payable() -> int

## §1.6 状态块协议全部方法。
## STATE_ARRAY_IDS = ["account.balance"]（900 元素，子系统按 §2.5 的主体映射逐元素归属）
## FLOW_* 为空。
```

---

### 4.7 `sim/sectors/io_table.gd` · `class_name JWIoTable extends RefCounted`

**职责**：投入产出与技术系数（`docs/10` §4.5）。**内容包只读**，`LOAD` 后永不改写。

#### 成员变量（全部 `content.*`，类 = C，写入者 = LOAD）

| 稳定 ID | 成员 | 类型 | 长度 | 单位 |
|---|---|---|---|---|
| `content.io.io_coeff_uqs_per_qs[]` | `io_coeff` | `PackedInt64Array` | 16 | μQ_from / Q_to |
| `content.io.labor_coeff_persons_per_qs[]` | `labor_coeff` | `PackedInt64Array` | 48（按 `idx_emp(cell,k)`） | 人 / Q_s |
| `content.io.energy_coeff_uqs_per_qs[]` | `energy_coeff` | `PackedInt64Array` | 16（按 cell） | μQ_energy / Q_s，**IO 表能源行的冗余副本** |
| `content.io.spoilage_ppm[]` | `spoilage_ppm` | `PackedInt64Array` | 4 | ppm/季 |
| `content.io.depreciation_ppm_per_q[]` | `depreciation_ppm` | `PackedInt64Array` | 4 | ppm/季（产能轨与价值轨同率） |
| `content.io.capacity_per_capital_uu_ppm[]` | `capacity_per_capital_ppm` | `PackedInt64Array` | 4 | μQ_s/季 每 μU，**只在投运时用一次** |
| `content.io.emission_ppm[]` | `emission_ppm` | `PackedInt64Array` | 4 | ppm |
| `content.storable[]` | `storable` | `PackedInt64Array` | 4 | 0/1，energy 与 services 必须为 0 |

#### 方法

```gdscript
## 系数读取。**系数为 0 表示「该约束不适用」，调用方必须 continue，
## 禁止除零，也禁止用 max(c,1) 代替**（INV-044）。
## 步骤：S03 §3.2/§3.5、S05 §5.3/§5.4、S06 §6.1
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-044
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func io(s_from: int, s_to: int) -> int
func labor(cell: int, k: int) -> int
func energy(cell: int) -> int
func spoilage(s: int) -> int
func depreciation(s: int) -> int
func capacity_per_capital(s: int) -> int
func emission(s: int) -> int
func is_storable(s: int) -> bool

## 加载期校验（V-IO-01..08 的落点）。
## 步骤：LOAD
## 前置：全部数组已填充
## 后置：不改状态
## 不变量：INV-150（每列和 < 1e6、storable[energy]==0、storable[services]==0、a(energy→energy)<1e6）、
##          INV-052（能源自用收敛）、V-IO-08（energy_coeff 与 io_coeff 的冗余一致）
## 失败：Load.IO_COLSUM / IO_STORABLE / IO_ENERGY_SELF / IO_NEGATIVE / IO_ENERGY_COEFF / IO_LABOR
func validate() -> JWResult

## §1.6 状态块协议：本类**只实现 allocate() 与 set_state_array()**，
## 其余协议方法返回空 —— 内容包不进 state_hash（进 content_hash，由 JWContentLoader 负责）。
```

---

### 4.8 `sim/policy/policy_def.gd` · `class_name JWPolicyDef extends RefCounted`

**职责**：12 项政策定义的**运行时表示**（`docs/11` §5.12），以及机制注册表（`MechanismRegistry`）。
内容包只读。**政策不能自带逻辑**：它只能引用已注册机制并给参数（计划书 §09 的「伪深度」防线）。

#### 成员变量（SoA，长度 12，类 = C，写入者 = LOAD）

| 稳定 ID | 成员 | 类型 | 长度 | 含义 |
|---|---|---|---|---|
| `content.policy.kind[]` | `kind` | `PackedInt64Array` | 12 | rate/transfer/subsidy/project/capacity/admin |
| `content.policy.authority_bit[]` | `authority_bit` | `PackedInt64Array` | 12 | 法定权限位 |
| `content.policy.min_seats_ppm[]` | `min_seats_ppm` | `PackedInt64Array` | 12 | 最低席位比例 |
| `content.policy.requires_bloc_mask[]` | `requires_bloc_mask` | `PackedInt64Array` | 12 | 需要哪些集团不否决 |
| `content.policy.requires_budget_review[]` | `requires_budget_review` | `PackedInt64Array` | 12 | 0/1 |
| `content.policy.cost_one_off_uu[]` | `cost_one_off_uu` | `PackedInt64Array` | 12 | μU |
| `content.policy.cost_per_quarter_uu[]` | `cost_per_quarter_uu` | `PackedInt64Array` | 12 | μU |
| `content.policy.planned_quarters[]` | `planned_quarters` | `PackedInt64Array` | 12 | 季 |
| `content.policy.spend_line_uu[]` | `spend_line_uu` | `PackedInt64Array` | 36（12×3：进口设备/国产材料/施工服务） | μU/季 |
| `content.policy.opex_per_q_uu[]` | `opex_per_q_uu` | `PackedInt64Array` | 12 | μU/季 |
| `content.policy.required_construction_uqs[]` | `required_construction_uqs` | `PackedInt64Array` | 12 | μQ_services |
| `content.policy.required_equipment_uqs[]` | `required_equipment_uqs` | `PackedInt64Array` | 12 | μQ_manu |
| `content.policy.lag_enact_to_effect_q[]` | `lag_enact_to_effect_q` | `PackedInt64Array` | 12 | 季 |
| `content.policy.commission_delay_q[]` | `commission_delay_q` | `PackedInt64Array` | 12 | 季，`>= 1`（INV-091） |
| `content.policy.effect_kind[]` | `effect_kind` | `PackedInt64Array` | 12 | 效果种类码 |
| `content.policy.effect_target[]` | `effect_target` | `PackedInt64Array` | 12 | **效果落点码**（白名单内，V-PD-10/11） |
| `content.policy.effect_magnitude[]` | `effect_magnitude` | `PackedInt64Array` | 12 | 按 `effect_kind` 解释（μQ/季 或 ppm 或 μU） |
| `content.policy.param_min_ppm[]` / `param_max_ppm[]` / `param_default[]` | 同名 | `PackedInt64Array` | 48 | 玩家参数的 `valid_range` 与默认值 |
| `content.policy.cooldown_q[]` | `cooldown_q` | `PackedInt64Array` | 12 | 季 |
| `content.policy.toggle_cost_uu[]` | `toggle_cost_uu` | `PackedInt64Array` | 12 | μU |
| `content.policy.exit_compensation_ppm[]` | `exit_compensation_ppm` | `PackedInt64Array` | 12 | ppm |
| `content.policy.political_reaction[]` | `political_reaction` | `PackedInt64Array` | 36（12×3 集团） | ppm |
| `content.policy.mechanism_mask[]` | `mechanism_mask` | `PackedInt64Array` | 12 | 引用的机制位掩码 |

#### 常量

```gdscript
## 效果落点白名单（docs/11 §5.12），下标即 effect_target 码。
## **一切产能／容量／设施类效果只能落在 *_pending_* 上**（V-PD-11 / INV-091）。
const EFFECT_TARGETS: PackedStringArray = PackedStringArray([
    "state.region.grid_capacity_pending_uqs_per_q",
    "state.region.housing_pending_units",
    "state.region.irrigation_index_pending_ppm",
    "state.region.port_capacity_pending_uqs_per_q",
    "state.cell.capacity_pending_uqs_per_q",
    "state.pubserv.capacity_pending_uqs_per_q",
    "state.pubserv.teachers_persons",
    "state.pubserv.health_staff_persons",
    "state.policy.params_ppm",
    "state.policy.params_uu",
    "state.gov.tax_capacity_ppm",
    "state.politics.admin_capacity_ppm",
    "state.group.education_cohort_persons",
])

## 机制注册表：SimCore 里已实现的机制 ID，内容包的 mechanism_ids 必须全部命中（V-PD-08）。
const MECHANISM_IDS: PackedStringArray = PackedStringArray([
    "mech.grid_capacity", "mech.project_queue", "mech.service_capacity", "mech.tax_rate",
    "mech.transfer_payment", "mech.investment_subsidy", "mech.training_seats",
    "mech.housing_stock", "mech.irrigation_index", "mech.port_capacity",
    "mech.tax_capacity", "mech.admin_capacity",
])
```

#### 方法

```gdscript
## 机制 ID → 位序号。内容包加载时用来把 mechanism_ids 折成 mechanism_mask。
## 步骤：LOAD
## 前置：!JWIds.frozen（可用字符串）
## 后置：不改状态
## 不变量：INV-099（政策只能引用已注册机制）
## 失败：未注册 → 返回 -1，调用方转 Load.MECH_UNKNOWN
static func mechanism_index(mech_id: String) -> int

## 效果落点 → 白名单码。
## 步骤：LOAD
## 前置：同上
## 后置：不改状态
## 不变量：INV-091（V-PD-11：只能落在 *_pending_*）
## 失败：不在白名单 → 返回 -1，调用方转 Load.EFFECT_TARGET
static func effect_target_code(target_id: String) -> int

## 读取访问器（结算期只用这些，全是整数下标）。
## 步骤：S02（资格与成本）、S04（转移与补助）、S05（项目）、S07（效果落点）
## 前置：p ∈ [0,12)
## 后置：不改状态
## 不变量：INV-095（效应函数在未生效时返回零效应——判定在 JWPolicyEngine，本类只给数据）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func cost_per_quarter(p: int) -> int
func spend_line(p: int, line: int) -> int
func param_range(p: int, j: int) -> Vector2i    ## 返回 (min, max)；Vector2i 是整数对，不含 float
func effect_target_of(p: int) -> int
func political_reaction_of(p: int, b: int) -> int

## 加载期九项必填与成本一致性校验。
## 步骤：LOAD
## 前置：12 个 JSON 已解析
## 后置：不改状态
## 不变量：INV-099；V-PD-01..11
## 失败：Load.POLICY_COUNT / POLICY_FIELDS / POLICY_COST / COMMISSION_LAG /
##       POLICY_TEST_MISSING / MECH_UNKNOWN / PARAM_RANGE / EFFECT_TARGET
func validate() -> JWResult

## §1.6 状态块协议：同 JWIoTable，只实现 allocate() 与 set_state_array()（内容包不进 state_hash）。
```

---

### 4.9 `sim/sectors/pricing.gd` · `class_name JWPricing extends RefCounted`

**职责**：价格、工资率、住房使用成本的**有界平滑调整**。
结构性保证：**S07 只写 `pending`，S08 末一次性 swap，S05 内价格全程是常量**（INV-065/070）。
持有 `log.clamp` 与夹逼预算计数。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.price.sector_uu_per_qs[]` | `price` | `PackedInt64Array` | 4 | 1 000 000 | S | μU/Q_s | **仅 S08（swap）** |
| `state.price.pending_uu_per_qs[]` | `price_pending` | `PackedInt64Array` | 4 | = price | S | μU/Q_s | **仅 S07** |
| `content.price.base_uu_per_qs[]` | `base_price` | `PackedInt64Array` | 4 | 1 000 000 | C | μU/Q_s | LOAD |
| `state.price.wage_uu_per_person_q[]` | `wage` | `PackedInt64Array` | 3 | 剧本 | S | μU/人/季 | **仅 S08（swap）** |
| `state.price.wage_pending_uu_per_person_q[]` | `wage_pending` | `PackedInt64Array` | 3 | = wage | S | μU/人/季 | **仅 S07** |
| `state.price.housing_rent_uu_per_unit_q[]` | `housing_rent` | `PackedInt64Array` | 4 | 剧本 | S | μU/套/季 | S07 |
| `flow.price.gap_ppm[]` | `gap_ppm` | `PackedInt64Array` | 4 | 0 | F | ppm | S07 |
| `state.price.clamp_budget_used_count` | `clamp_used` | `int` | — | 0 | S | 计数 | S07 |
| `log.clamp.*` | `log_field` / `log_raw` / `log_clamped` / `log_bound` | `PackedInt64Array` ×4 | `LOG_CAP0` | — | L | — | S03,S07,S08 |

> **两个写入者为什么不互相放大**：`price` 的唯一写入点是 S08 的 `swap_pending()`，
> `price_pending` 的唯一写入点是 S07 的 `update_prices()`。同一季内二者读写不重叠：
> S05 读 `price`（常量），S07 写 `price_pending`，S08 把后者拷进前者。回路在数据流上被切断。

#### 方法

```gdscript
## 读取本季生效价格 / 工资 / 租金。S05 全程只读，不得写。
## 步骤：S03（招工预算）、S05（成交）、S06（税基）、S08（消费价格指数）
## 前置：s ∈ [0,4)，k ∈ [0,3)
## 后置：不改状态
## 不变量：INV-065（S05 的任何函数不得写 price.*）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func price_of(s: int) -> int
func wage_of(k: int) -> int
func rent_of(r: int) -> int
func base_price_of(s: int) -> int

## 居民消费价格指数（派生，纯函数；实际 GDP 函数禁止引用它，INV-117）。
## 步骤：S06/S08 读
## 前置：consumption_weight 为各产品消费量权重（由 JWPopulation 传入）
## 后置：不改状态
## 不变量：INV-117（静态检查：实际 GDP 计算不得出现本函数）
## 失败：权重全 0 → 返回 1_000_000（基年）
func consumer_index_ppm(consumption_weight_uqs: PackedInt64Array) -> int

## S07 §7.3：按供需缺口与库存偏离更新下季价格，写 pending。
## 步骤：S07 §7.3
## 前置：supply/demand/inventory/inventory_target 为本季已结算的实际值；price_pending 尚未被本季写过
## 后置：price_pending[s] ∈ [floor, ceil]，|price_pending − price| <= step_max；每次夹逼写 log.clamp 并计数
## 不变量：INV-065, INV-066, INV-067, INV-068, INV-069
## 失败：不产生业务失败；越界参数 → INDEX_OUT_OF_RANGE
func update_prices(supply_uqs: PackedInt64Array, demand_uqs: PackedInt64Array,
                   inventory_uqs: PackedInt64Array, inventory_target_uqs: PackedInt64Array,
                   storable: PackedInt64Array, params: PackedInt64Array) -> int

## S07 §7.3 末：工资率同法（空缺 vs 失业），写 wage_pending。
## 步骤：S07 §7.3
## 前置：vacancies/unemployed/labor_force 来自 S03 的实际结果
## 后置：wage_pending[k] ∈ [wage_floor, wage_ceil]，步长受 wage_step_max_ppm 约束
## 不变量：INV-070（不在季内出清）、INV-069（夹逼计数）
## 失败：labor_force == 0 → gap 记 0，不除零
func update_wages(vacancies_persons: int, unemployed_persons: int,
                  labor_force_persons: int, params: PackedInt64Array) -> int

## S07：住房季度使用成本（按占用率）。
## 步骤：S07 §7.3
## 前置：occupied/capacity 来自 S07 的人口结果
## 后置：housing_rent[r] > 0
## 不变量：INV-083（住房恒等式由 JWCapital/JWPopulation 保证，本函数只定价）
## 失败：capacity == 0 → 保持原值，写 log.clamp
func update_housing_rent(occupied_units: PackedInt64Array, capacity_units: PackedInt64Array,
                         params: PackedInt64Array) -> int

## S08 收尾：价格与工资的唯一切换点。
## 步骤：S08 §8.7
## 前置：phase == S08；本季 S07 已写过 pending
## 后置：price == price_pending 且 wage == wage_pending（逐位）
## 不变量：INV-065, INV-070
## 失败：phase 不对 → Fault.PHASE_VIOLATION
func swap_pending() -> int

## 夹逼登记（供其它类复用同一条日志通道）。
## 步骤：S03, S07, S08
## 前置：field_code 已在文案表登记
## 后置：log.clamp 多一行；若 bound 实际生效则 clamp_used += 1
## 不变量：INV-069（压测中 clamp_used > param.price_clamp_budget_count 即判失败）
## 失败：日志满 → 1.5 倍扩容并写告警行，不失败
func log_clamp(field_code: int, raw: int, clamped: int, bound: int) -> void

## §1.6 状态块协议 + §1.7 日志协议全部方法。
## STATE_ARRAY_IDS = ["state.price.sector_uu_per_qs", "state.price.pending_uu_per_qs",
##                    "state.price.wage_uu_per_person_q", "state.price.wage_pending_uu_per_person_q",
##                    "state.price.housing_rent_uu_per_unit_q"]
## STATE_SCALAR_IDS = ["state.price.clamp_budget_used_count"]
## FLOW_ARRAY_IDS   = ["flow.price.gap_ppm"]
```

---

### 4.10 `sim/ledger/ledger.gd` · `class_name JWLedger extends RefCounted`

**职责**：**全系统唯一的过账入口**（`docs/12` §0.2）。一次 `post()` 产生一笔 `txn`，
含 ≥ 2 条有符号过账行；持有 `log.ledger`、`log.physical`、`log.rounding`。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 写入者 |
|---|---|---|---|---|---|---|
| — | `_accounts` | `JWAccount` | — | 构造注入 | — | LOAD |
| `state.meta.txn_seq` | `txn_seq` | `int` | — | 0 | S | S02..S07 |
| `log.ledger.txn_id[]` | `l_txn` | `PackedInt64Array` | `LOG_CAP0` | — | L | S02..S06 |
| `log.ledger.q[]` | `l_q` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.step[]` | `l_step` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.kind[]` | `l_kind` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.account[]` | `l_account` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.delta_uu[]` | `l_delta` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.qty_uqs[]` | `l_qty` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.product[]` | `l_product` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.cause[]` | `l_cause` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.entity_ref[]` | `l_entity` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.prod_class[]` | `l_prod` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.exp_class[]` | `l_exp` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.ledger.inc_class[]` | `l_inc` | `PackedInt64Array` | 同 | — | L | 同 |
| `log.physical.*` | `p_from`/`p_to`/`p_product`/`p_qty`/`p_cause`/`p_step` | `PackedInt64Array` ×6 | `LOG_CAP0` | — | L | S04,S05 |
| `log.rounding.*` | `r_site`/`r_total`/`r_parts`/`r_residual` | `PackedInt64Array` ×4 | `LOG_CAP0` | — | L | 各步 |
| — | `_step` | `int` | — | 0 | — | 当前步骤，由 TurnRunner 设 | S01..S08 |
| — | `_q` | `int` | — | 0 | — | 当季 | S01 |

#### 方法

```gdscript
## 唯一的过账入口。一次调用产生一笔 txn，含 >= 2 条有符号行。
## 步骤：S02..S07（S01/S08 不过账）
## 前置：amount_uu >= 0；payer_account != payee_account；kind 已在三分类表登记；
##       方向由 payer → payee 决定
## 后置：两端余额已更新且都 >= 0（资产科目）；log.ledger 增 2 行；行之和为 0；
##       有实物时同 txn_id 写一条 log.physical
## 不变量：INV-015（行和为 0、amount != 0、两端不同）、INV-016（现金不为负）、
##          INV-022（唯一入口）、INV-026（对外必有 agent.row 对手方）、INV-114（三分类码完备）
## 失败：现金不足 → **整笔回滚**并返回 Fault.NEGATIVE_CASH（调用方决定转欠付／缩规模／延期）；
##       kind 未分类 → Fault.LEDGER_KIND_UNCLASSIFIED；金额为负 → Fault.LEDGER_IMBALANCE
func post(kind: int, payer_account: int, payee_account: int, amount_uu: int,
          qty_uqs: int, product: int, cause: int, entity_ref: int) -> int

## 多腿过账（一次交易涉及 3 条以上行，例如「现金 + 库存 + 价差」）。
## 步骤：S05（成交入库）、S06（折旧、营业盈余结转、价差）
## 前置：legs_account 与 legs_delta 等长且 Σ legs_delta == 0；至少 2 行；每行 delta != 0
## 后置：全部行原子生效或全部不生效
## 不变量：INV-015, INV-016, INV-020, INV-114
## 失败：行和不为 0 → Fault.LEDGER_IMBALANCE；任一现金为负 → 整笔回滚 + NEGATIVE_CASH
func post_multi(kind: int, legs_account: PackedInt64Array, legs_delta: PackedInt64Array,
                qty_uqs: int, product: int, cause: int, entity_ref: int) -> int

## 非现金分录（折旧、价差、营业盈余结转、开账）：资产/净值两腿，不动现金。
## 步骤：S06 §6.1/§6.6、LOAD（开账）
## 前置：kind ∈ {DEPRECIATION, OPERATING_SURPLUS, PRICE_VARIANCE, OPENING_BALANCE, WRITEOFF}
## 后置：cash 科目不被触碰（静态断言）；nw 同步调整
## 不变量：INV-021（Δnw 被损益流量完全解释）、INV-017（现金不变）
## 失败：kind 不在白名单 → Fault.LEDGER_KIND_UNCLASSIFIED
func post_noncash(kind: int, agent: int, asset_code: int, delta_uu: int,
                  cause: int, entity_ref: int) -> int

## 开账分录（q = −1，对手方 agent.opening）。
## 步骤：LOAD
## 前置：尚未开始任何季度结算
## 后置：全部初值经分录生成；agent.opening 的 **cash 恒为 0**（OQ-217：现金腿与自身 nw 配平，
##       不经 opening 的现金科目）；开账后 Σ cash == scenario.total_cash_uu
## 不变量：INV-023（初值过账本）、INV-015、INV-018
## 失败：Load.BALANCE_INIT / Load.CASH_TOTAL
func post_opening(agent: int, code: int, amount_uu: int) -> int

## 物资流水（与资金行共享 txn_id）。
## 步骤：S04（项目物资）、S05（生产与交易）
## 前置：qty_uqs != 0；from/to 是库存位置码（可为 -1 表示无）
## 后置：log.physical 增一行
## 不变量：INV-047（库存恒等式的可追溯性）、INV-139
## 失败：日志满 → 扩容并写告警，不失败
func log_physical(from_loc: int, to_loc: int, product: int, qty_uqs: int, cause: int) -> void

## 取整余数登记（换算类，不产生债权债务）。
## 步骤：各步
## 前置：site_code 已登记
## 后置：log.rounding 增一行
## 不变量：INV-005（季末 gov.rounding_residual 的变化必须被本日志逐条解释）
## 失败：无
func log_rounding(site_code: int, total: int, parts: int, residual: int) -> void

## GDP 三口径的分类汇总（唯一数据源是本季账本行的三个分类码）。
## 步骤：S06 §6.4
## 前置：本季全部分录已写入
## 后置：out_prod/out_exp/out_inc 被填满；不改任何状态
## 不变量：INV-112（禁止用 Σ 销售额求和）、INV-114（完备性与互斥性）、INV-115、INV-116
## 失败：应分类却为 none → Fault.GDP_CLASS_MISSING（detail_a = 行号）；
##       同口径计入两类 → Fault.GDP_CLASS_DUPLICATE；kind 未登记 → LEDGER_KIND_UNCLASSIFIED
func aggregate_classes(out_prod: PackedInt64Array, out_exp: PackedInt64Array,
                       out_inc: PackedInt64Array) -> int

## 设置当前 q 与步骤（供日志行填充）；只由 TurnRunner 调用。
## 步骤：S01..S08 入口
## 前置：step ∈ JWUnits.Phase
## 后置：后续日志行带上正确的 q 与 step
## 不变量：INV-012
## 失败：无
func set_context(q: int, step: int) -> void

## §1.6 状态块协议 + §1.7 日志协议全部方法。
## STATE_SCALAR_IDS = ["state.meta.txn_seq"]；三条日志均不进 state_hash。
```

---

### 4.11 `sim/ledger/bond_book.gd` · `class_name JWBondBook extends RefCounted`

**职责**：债券批次 SoA（`docs/10` §3.3）。**只增不删**：结清批次改状态位，下标永久稳定。
**逐批次计息**，禁止「求和后乘平均利率」（INV-036）。

#### 成员变量（SoA，容量 `BOND_CAP0`，实际长度 `count`）

| 稳定 ID | 成员 | 类型 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|
| `state.bond.id[]` | `id` | `PackedStringArray` | — | S | `bond.q<qqq>_<nn>` | LOAD, S02 |
| `state.bond.issue_q[]` | `issue_q` | `PackedInt64Array` | — | S | 季（开局存量债为负） | LOAD, S02 |
| `state.bond.principal_initial_uu[]` | `principal_initial` | `PackedInt64Array` | — | S | μU | LOAD, S02 |
| `state.bond.principal_outstanding_uu[]` | `principal_outstanding` | `PackedInt64Array` | — | S | μU | S02 |
| `state.bond.coupon_ppm_per_q[]` | `coupon_ppm` | `PackedInt64Array` | — | S | ppm/季 | **仅发行时** |
| `state.bond.maturity_q[]` | `maturity_q` | `PackedInt64Array` | — | S | 季 | LOAD, S02 |
| `state.bond.amortization[]` | `amortization` | `PackedInt64Array` | — | S | 枚举 | LOAD, S02 |
| `state.bond.holder[]` | `holder` | `PackedInt64Array` | — | S | 枚举 | LOAD, S02 |
| `state.bond.status[]` | `status` | `PackedInt64Array` | `ACTIVE` | S | 枚举 | S02 |
| `state.bond.accrued_unpaid_interest_uu[]` | `accrued_unpaid` | `PackedInt64Array` | 0 | S | μU | S02 |
| `state.bond.interest_remainder_ppmuu[]` | `interest_remainder` | `PackedInt64Array` | 0 | S | μU·ppm，0..999 999 | S02 |
| `state.bond.writeoff_uu[]` | `writeoff` | `PackedInt64Array` | 0 | S | μU | S02 |
| `state.bond.amort_schedule[]` | `amort_schedule` | `PackedInt64Array` | — | S | μU，按 `batch*HORIZON_MAX + q` 稀疏存 | 发行时预生成 |
| `flow.bond.interest_due_uu[]` | `interest_due` | `PackedInt64Array` | 0 | F | μU | S02 |
| `flow.bond.principal_due_uu[]` | `principal_due` | `PackedInt64Array` | 0 | F | μU | S02 |
| — | `count` | `int` | 0 | S | 批次数 | LOAD, S02 |

#### 方法

```gdscript
## 逐批次计提本季应付利息，余数进累加器满 1e6 结转 1 μU。
## 步骤：S02 §2.3
## 前置：status == ACTIVE 且 principal_outstanding > 0；coupon_ppm 发行后未被改写
## 后置：flow.bond.interest_due_uu 被填满；interest_remainder ∈ [0, 999_999]
## 不变量：INV-036（逐批次 floor 计提）、INV-004（余数累加器）、INV-041（120 季漂移 ≤ 1 μU/批次）
## 失败：coupon_ppm 被改写过 → Fault.BOND_MISMATCH；不产生业务失败（计提不需要现金）
func accrue_interest(q: int) -> int

## 计算本季应还本金：bullet 到期一次还清；level_principal 查预生成的分期表。
## 步骤：S02 §2.4
## 前置：amort_schedule 在发行时已由 split_lr 预生成，Σ == 面值
## 后置：flow.bond.principal_due_uu 被填满
## 不变量：INV-037（Σ_{q'>=q} scheduled == outstanding）
## 失败：分期表和不等于面值 → Fault.BOND_MISMATCH
func schedule_principal(q: int) -> int

## 发行一个新批次（票息由规则给出，玩家不能设）。
## 步骤：S02 §2.6
## 前置：coupon_ppm >= market_rate_ppm(q)；holder 额度已由调用方（JWTreasury）核过；
##       count < params[BOND_BATCH_CAP]
## 后置：新批次写入 SoA 末尾；amort_schedule 预生成；调用方负责 post(kind=BOND_ISSUE)
## 不变量：INV-034（融资不超对手方能力）、INV-037、INV-038（不允许自动展期）、INV-010（ID 来自 entity_seq）
## 失败：超批次上限 → 返回 -1 并由调用方 REJECT(Reject.CREDIT_LIMIT)；
##       **不自动合并批次**（合并会破坏 INV-036 的「旧债不重定价」）
func issue(entity_seq: int, q: int, principal_uu: int, coupon_ppm_per_q: int,
           maturity_q: int, amortization: int, holder: int) -> int

## 登记一次还本（由 JWTreasury 在 post 成功后调用）。
## 步骤：S02 §2.5
## 前置：amount <= principal_outstanding[b]
## 后置：principal_outstanding 减少；归 0 则 status = MATURED
## 不变量：INV-028, INV-035
## 失败：超额 → Fault.BOND_MISMATCH
func apply_principal_payment(b: int, amount_uu: int) -> int

## 登记一次利息欠付（违约）。
## 步骤：S02 §2.5
## 前置：本季该批次的 interest_due 未足额支付
## 后置：accrued_unpaid += 未付额；status = DEFAULTED
## 不变量：INV-030（欠付登记）、INV-038/INV-040（不得自动展期）
## 失败：不失败——这是业务性短缺（ARREARS 语义）
func register_interest_arrears(b: int, unpaid_uu: int) -> int

## 重组（延期 / 减记 / 违约），只能由玩家命令 debt_restructure 触发。
## 步骤：S02（受理命令后）
## 前置：mode ∈ {defer, writedown, default}；必须登记债权人损失
## 后置：writeoff 增加、status = RESTRUCTURED/WRITTEN_OFF；调用方 post(kind=WRITEOFF)
## 不变量：INV-028（debt_end == start + 借款 − 还本 − 确认减记）
## 失败：模式非法 → Reject.NOT_FOUND；**不允许静默展期**
func restructure(b: int, mode: int, q: int) -> int

## 未偿本金合计（derived.gov.debt_uu 的唯一来源，纯函数）。
## 步骤：S02 末、S06 末、报告
## 前置：无
## 后置：不改状态
## 不变量：INV-035（debt == Σ active outstanding）、INV-107（外债 == Σ holder==row）
## 失败：无
func debt_outstanding() -> int
func debt_outstanding_of_holder(holder: int) -> int

## 未来四季到期本金 + 利息（财政页必须展示，derived.fiscal.next4q_debt_service_uu）。
## 步骤：S02 §2.6（算 dsr）、S06（报告）
## 前置：q >= 0
## 后置：不改状态
## 不变量：INV-038（dsr 单调性的输入）
## 失败：无
func debt_service_next4q(q: int) -> int

## §1.6 状态块协议全部方法。SoA 的 ids[] 在存档中单列（docs/11 §6.4 的 "soa" 段）。
```

---

### 4.12 `sim/ledger/treasury.gd` · `class_name JWTreasury extends RefCounted`

**职责**：国库现金流的**编排者**（`docs/10` §3.1/§3.2）：支付优先级、欠付、延期、
到期债务、新发债、税收入账、预算预留。持有 `log.arrears`。
**它自己不改余额**——一切资金移动仍走 `JWLedger.post()`。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.gov.arrears_uu` | `arrears` | `int` | — | 0 | S | μU | S02,S04,S06 |
| `state.gov.arrears_by_payee_uu[]` | `arrears_by_payee` | `PackedInt64Array` | 60 | 0 | S | μU | S02,S04,S06 |
| `state.gov.tax_receivable_uu` | `tax_receivable` | `int` | — | 0 | S | μU | S06 |
| `state.gov.committed_memo_uu` | `committed_memo` | `int` | — | 剧本 | memo | μU | S02,S04,S07 |
| `state.gov.reserved_memo_uu` | `reserved_memo` | `int` | — | 0 | memo | μU | S02,S04 |
| `state.gov.credit_limit_domestic_memo_uu` | `credit_limit_domestic` | `int` | — | 剧本 | memo | μU | S02 |
| `state.gov.service_opex_committed_uu` | `service_opex_committed` | `int` | — | 剧本 | S | μU/季 | S07 |
| `state.gov.tax_capacity_ppm` | `tax_capacity_ppm` | `int` | — | 剧本 | S | ppm | S07（P11） |
| `state.gov.tax_capacity_built_ppm` | `tax_capacity_built_ppm` | `int` | — | 剧本 | S | ppm | S07（P11） |
| `state.gov.payment_priority[]` | `payment_priority` | `PackedInt64Array` | 8 | 剧本 | S | 枚举全排列 | CMD→S02 |
| `state.gov.deferral_flag[]` | `deferral_flag` | `PackedInt64Array` | 8 | 0 | S | 0/1 | S02,S04 |
| `state.gov.rounding_residual_uu` | `rounding_residual` | `int` | — | 0 | S | μU | S02,S04,S05,S06 |
| `flow.gov.receipts_income_tax_uu` | `f_receipts_income_tax` | `int` | — | 0 | F | μU | S06 |
| `flow.gov.receipts_profit_tax_uu` | `f_receipts_profit_tax` | `int` | — | 0 | F | μU | S06 |
| `flow.gov.receipts_other_uu` | `f_receipts_other` | `int` | — | 0 | F | μU | S05,S06 |
| `flow.gov.new_borrowing_uu` | `f_new_borrowing` | `int` | — | 0 | F | μU | S02 |
| `flow.gov.primary_paid_uu` | `f_primary_paid` | `int` | — | 0 | F | μU | S04,S05 |
| `flow.gov.interest_paid_uu` | `f_interest_paid` | `int` | — | 0 | F | μU | **仅 S02** |
| `flow.gov.principal_paid_uu` | `f_principal_paid` | `int` | — | 0 | F | μU | **仅 S02** |
| `flow.gov.recognized_writeoffs_uu` | `f_writeoffs` | `int` | — | 0 | F | μU | S02 |
| `flow.gov.pay_public_wages_uu` | `f_pay_public_wages` | `int` | — | 0 | F | μU | S04 |
| `flow.gov.pay_transfers_uu[]` | `f_pay_transfers` | `PackedInt64Array` | 36 | 0 | F | μU | S04 |
| `flow.gov.pay_subsidies_uu[]` | `f_pay_subsidies` | `PackedInt64Array` | 16 | 0 | F | μU | S04 |
| `flow.gov.pay_project_uu[]` | `f_pay_project` | `PackedInt64Array` | `PROJECT_CAP0` | 0 | F | μU | S04 |
| `flow.gov.pay_opex_uu[]` | `f_pay_opex` | `PackedInt64Array` | 12 | 0 | F | μU | S04 |
| `flow.gov.pay_procurement_uu` | `f_pay_procurement` | `int` | — | 0 | F | μU | S05 |
| `flow.gov.arrears_added_uu[]` | `f_arrears_added` | `PackedInt64Array` | 60 | 0 | F | μU | S02,S04,S06 |
| `flow.gov.arrears_cleared_uu[]` | `f_arrears_cleared` | `PackedInt64Array` | 60 | 0 | F | μU | S02,S04 |
| `flow.gov.nonmarket_output_uu[]` | `f_nonmarket_output` | `PackedInt64Array` | 4 | 0 | F | μU | S06 |
| `flow.gov.final_consumption_uu` | `f_final_consumption` | `int` | — | 0 | F | μU | S06 |
| `flow.gov.gross_capital_formation_uu` | `f_gross_capital_formation` | `int` | — | 0 | F | μU | S06 |
| `log.arrears.*` | `a_payee`/`a_amount`/`a_reason`/`a_step` | `PackedInt64Array` ×4 | `LOG_CAP0` | — | L | S02,S04,S06 |
| — | `_cash_at_quarter_start` | `int` | — | 0 | — | μU，INV-027 的基准 | S01 |
| — | `_default_streak_q` | `int` | — | 0 | S | 季，连续无法付第 1 档的季数 | S02 |

> **三个写入者（S02/S04/S06）为什么不互相放大**：`arrears` 与 `arrears_by_payee` 在三步中
> 只做**单调累加或清偿**，且每次变动都写 `flow.gov.arrears_added/cleared` 与 `log.arrears`；
> INV-030（`arrears_end == arrears_start + 新增 − 清偿`）在季末一次性验证，任何重复登记都会被它抓住。

#### 方法

```gdscript
## 记录季初现金基准，供 S06 §6.9 的 INV-027 终检。
## 步骤：S01
## 前置：phase == S01
## 后置：_cash_at_quarter_start == accounts.cash_of(AGENT_GOV)
## 不变量：INV-027
## 失败：无
func begin_quarter(accounts: JWAccount) -> void

## 预算预留（不是支付）：只减少可用额度，不产生任何现金移动。
## 步骤：S02 §2.2
## 前置：need_uu >= 0
## 后置：reserved_memo += need_uu 且 reserved_memo <= cash
## 不变量：INV-033（reserved_memo <= cash 且季末归零）
## 失败：可用额度不足 → 返回 Reject.BUDGET_INSUFFICIENT（**不写任何资金行**，
##       混记会让 INV-027 失衡）
func reserve(need_uu: int, accounts: JWAccount) -> int

## 释放本季未执行的预留（季末必须归零）。
## 步骤：S04 末
## 前置：无
## 后置：reserved_memo == 0
## 不变量：INV-033
## 失败：残留非零且无法解释 → Fault.LEDGER_IMBALANCE
func release_reservations() -> int

## S02 §2.5：按优先级支付到期利息与本金；短缺先显露。
## 步骤：S02 §2.5
## 前置：bonds.accrue_interest / schedule_principal 已跑完
## 后置：flow.gov.interest_paid / principal_paid 写入；未付部分登记 arrears 且批次转 DEFAULTED；
##       gov.cash 恒不为负
## 不变量：INV-016, INV-027, INV-028, INV-030, INV-035, INV-036, INV-037, INV-038, INV-039, INV-040
## 失败：现金将为负 → Fault.NEGATIVE_CASH；连续 params[DEFAULT_GRACE_Q] 季无法付第 1 档 →
##       返回信号让 S08 置 termination_reason = FISCAL_RESTRUCTURING_FAILED；**不得自动展期**
func pay_debt_service(bonds: JWBondBook, ledger: JWLedger, accounts: JWAccount,
                      q: int, params: PackedInt64Array) -> int

## S02 §2.6：按规则定价并发行新债（国内额度 + 外部额度两段）。
## 步骤：S02 §2.6
## 前置：need_uu > 0；市场利率由 dsr 与冲击共同决定；玩家不能设利率
## 后置：新批次入 SoA；post(kind=BOND_ISSUE) 完成；flow.gov.new_borrowing_uu 登记；
##       world.credit_used_uu 增加
## 不变量：INV-034（国内 ≤ min(credit_limit_domestic, invpool.cash × appetite)；
##          外部 ≤ credit_limit − credit_used）、INV-029（借款不进收入、不进 GDP）、INV-038
## 失败：额度不足 → 返回 Reject.CREDIT_LIMIT，差额回到 §2.5 的排序／延期／重组分支
func issue_debt(need_uu: int, bonds: JWBondBook, world: JWWorldMarket, ledger: JWLedger,
                accounts: JWAccount, q: int, entity_seq: int, params: PackedInt64Array) -> int

## S04 §4.2：按 8 档优先级在可用现金内支付一档。
## 步骤：S04 §4.2
## 前置：line ∈ PayLine；due_by_payee 与 payee_agent 等长；payment_priority 是 8 类的全排列
## 后置：按收款方 ID 升序用 split_lr 拆分实付额并逐笔 post()；不足部分登记 arrears 与 deferral_flag
## 不变量：INV-003（拆分精确）、INV-015、INV-016、INV-030、INV-039（实际顺序与优先级一致）
## 失败：拆分和不等于原额 → Fault.SPLIT_MISMATCH（最严重的一类，立即停）
func pay_line(line: int, payee_agent: PackedInt64Array, due_by_payee: PackedInt64Array,
              kind: int, ledger: JWLedger, accounts: JWAccount) -> int

## 登记一笔欠付（唯一入口；别处不得直接写 arrears）。
## 步骤：S02, S04, S06
## 前置：amount_uu > 0
## 后置：arrears 与 arrears_by_payee 同步增加；flow.arrears_added 与 log.arrears 各增一条
## 不变量：INV-030（arrears == Σ arrears_by_payee >= 0）
## 失败：无（这是业务性短缺的登记点，不是故障）
func add_arrears(payee_agent: int, amount_uu: int, reason_line: int) -> void

## 清偿历史欠付。
## 步骤：S02, S04
## 前置：amount_uu <= arrears_by_payee[payee]
## 后置：arrears 减少；flow.arrears_cleared 增加
## 不变量：INV-030
## 失败：超额清偿 → Fault.LEDGER_IMBALANCE
func clear_arrears(payee_agent: int, amount_uu: int, ledger: JWLedger, accounts: JWAccount) -> int

## S06 §6.5：个人所得税（含征收能力 P11 与税基侵蚀）。
## 步骤：S06 §6.5
## 前置：税基只来自**已过账的收入分录**（wage_income + property_income）；转移收入不计税（OQ-212）
## 后置：collected 入账；(liability − collected) 进 tax_receivable，差额显式登记不消失
## 不变量：INV-031（tax_receivable 恒等式）、ADV-05（税率 10%→60% 的非线性曲线）
## 失败：群组现金不足 → 按现金上限征收，差额进应收；**不得把群组现金打成负数**
func collect_income_tax(pop: JWPopulation, policy_params: PackedInt64Array,
                        ledger: JWLedger, accounts: JWAccount, params: PackedInt64Array) -> int

## S06 §6.6：企业利润税（利润与现金严格分开）。
## 步骤：S06 §6.6
## 前置：taxable_by_cell 已由 JWSectorModel 算出（利润扣结转亏损后）并由 TurnRunner 传入
##       —— 不直接引用 JWSectorModel，避免同秩依赖（§3.2）
## 后置：paid = min(tax, cell.cash)；差额进 tax_receivable（**不是核销**）
## 不变量：INV-031、INV-116（营业盈余按残差定义）
## 失败：现金不足不是故障；应收登记缺失才是 → Fault.LEDGER_IMBALANCE
func collect_profit_tax(taxable_by_cell: PackedInt64Array, policy_params: PackedInt64Array,
                        ledger: JWLedger, accounts: JWAccount, params: PackedInt64Array) -> int

## S06 §6.9：政府口径的恒等式终检。
## 步骤：S06 §6.9
## 前置：本季全部分录已写
## 后置：不改状态
## 不变量：INV-027（现金恒等式残差恰为 0）、INV-028（债务恒等式）、INV-035（debt == Σ outstanding）
## 失败：Fault.LEDGER_IMBALANCE / Fault.BOND_MISMATCH，导出故障包，**不得自动修正**
func check_fiscal_identities(bonds: JWBondBook, accounts: JWAccount) -> int

## §1.6 状态块协议 + §1.7 日志协议全部方法。
```

---

### 4.13 `sim/sectors/capital.gd` · `class_name JWCapital extends RefCounted`

**职责**：**全部「能力存量」的唯一持有者**：cell 产能与资本、pubserv 容量与可用率、
地区设施（电网 / 港口 / 灌溉 / 住房 / 施工槽位）、排放与环境存量。

把它们放在一个文件里的理由是纪律性的：`docs/12` §01.4 要求
**一切「完工后才生效的能力」都必须经 `*_pending_*` 缓冲且只在 S01 转入**（INV-054/091）。
这条规则只有在「全部 pending → active 的转移写在同一个函数里」时才可被静态检查。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.cell.capacity_active_uqs_per_q[]` | `cell_capacity_active` | `PackedInt64Array` | 16 | 剧本 | S | μQ_s/季 | **S01（转入）, S06（折旧）** |
| `state.cell.capacity_pending_uqs_per_q[]` | `cell_capacity_pending` | `PackedInt64Array` | 16 | 0 | S | μQ_s/季 | S07（完工写入）, S01（清零） |
| `state.cell.capital_value_uu[]` | `cell_capital_value` | `PackedInt64Array` | 16 | 剧本 | S | μU | S06（折旧）, S07（投运） |
| `state.cell.wip_uu[]` | `cell_wip` | `PackedInt64Array` | 16 | 0 | S | μU | S05, S07 |
| `state.cell.maintenance_backlog_ppm[]` | `cell_maint_backlog` | `PackedInt64Array` | 16 | 0 | S | ppm | S07 |
| `flow.cell.depreciation_uu[]` | `f_cell_dep_uu` | `PackedInt64Array` | 16 | 0 | F | μU | S06 |
| `flow.cell.depreciation_uqs_per_q[]` | `f_cell_dep_uqs` | `PackedInt64Array` | 16 | 0 | F | μQ_s/季 | S06 |
| `flow.cell.investment_uu[]` | `f_cell_investment` | `PackedInt64Array` | 16 | 0 | F | μU | S05 |
| `state.pubserv.capacity_active_uqs_per_q[]` | `pub_capacity_active` | `PackedInt64Array` | 4 | 剧本 | S | μQ_services/季 | S01, S06 |
| `state.pubserv.capacity_pending_uqs_per_q[]` | `pub_capacity_pending` | `PackedInt64Array` | 4 | 0 | S | 同 | S07, S01 |
| `state.pubserv.capital_value_uu[]` | `pub_capital_value` | `PackedInt64Array` | 4 | 剧本 | S | μU | S06, S07 |
| `state.pubserv.availability_ppm[]` | `pub_availability` | `PackedInt64Array` | 4 | 1 000 000 | S | ppm | S07 |
| `state.pubserv.teachers_persons[]` | `pub_teachers` | `PackedInt64Array` | 4 | 剧本 | S | 人 | S03, S07 |
| `state.pubserv.health_staff_persons[]` | `pub_health_staff` | `PackedInt64Array` | 4 | 剧本 | S | 人 | S03, S07 |
| `flow.pubserv.funding_ratio_ppm[]` | `f_pub_funding_ratio` | `PackedInt64Array` | 4 | 0 | F | ppm | S04 |
| `flow.pubserv.depreciation_uu[]` | `f_pub_dep_uu` | `PackedInt64Array` | 4 | 0 | F | μU | S06 |
| `flow.pubserv.output_uu[]` | `f_pub_output` | `PackedInt64Array` | 4 | 0 | F | μU | S06 |
| `state.region.grid_capacity_uqs_per_q[]` | `grid_capacity` | `PackedInt64Array` | 4 | 剧本 | S | μQ_energy/季 | S01, S06 |
| `state.region.grid_capacity_pending_uqs_per_q[]` | `grid_pending` | `PackedInt64Array` | 4 | 0 | S | 同 | S07, S01 |
| `state.region.housing_capacity_units[]` | `housing_capacity` | `PackedInt64Array` | 4 | 剧本 | S | 套 | S01, S07 |
| `state.region.housing_stock_units[]` | `housing_stock` | `PackedInt64Array` | 4 | 剧本 | S | 套 | S01, S07 |
| `state.region.housing_pending_units[]` | `housing_pending` | `PackedInt64Array` | 4 | 0 | S | 套 | S07, S01 |
| `state.region.irrigation_index_ppm[]` | `irrigation_index` | `PackedInt64Array` | 4 | 剧本 | S | ppm | **S01（转入）** |
| `state.region.irrigation_index_pending_ppm[]` | `irrigation_pending` | `PackedInt64Array` | 4 | 0 | S | ppm | S07, S01 |
| `state.region.port_capacity_uqs_per_q[]` | `port_capacity` | `PackedInt64Array` | 4 | 剧本 | S | μQ/季 | S01, S06 |
| `state.region.port_capacity_pending_uqs_per_q[]` | `port_pending` | `PackedInt64Array` | 4 | 0 | S | 同 | S07, S01 |
| `state.region.construction_slots_total[]` | `construction_slots` | `PackedInt64Array` | 4 | 剧本 1..8 | S | 槽 | S07 |
| `state.region.emissions_stock_uqe[]` | `emissions_stock` | `PackedInt64Array` | 4 | 剧本 | S | μQ_e | S07 |
| `state.region.env_exposure_ppm[]` | `env_exposure` | `PackedInt64Array` | 4 | 剧本 | S | ppm | S07 |
| `flow.region.emissions_uqe[]` | `f_emissions` | `PackedInt64Array` | 4 | 0 | F | μQ_e | S05 |
| `content.region.area_index[]` | `area_index` | `PackedInt64Array` | 4 | 剧本 | C | 指数 | LOAD |

> **S01 与 S06 为什么不互相放大**：S01 只做 `active += pending; pending = 0`（**唯一的增量写入点**），
> S06 只做 `active -= mul_ppm(active, dep_rate)`（唯一的减量写入点）。两者都在 S05 生产之外，
> 一个在生产前、一个在生产后，位置确定；`capacity_pending` 在 S01 之后到 S07 之前恒为 0，
> 任何中途写入都会被 S01 末的 `Σ pending == 0` 断言抓住。

#### 方法

```gdscript
## S01 §01.4：把全部待投运能力转入在用能力。**这是 capacity_active 的唯一增量写入点**。
## 步骤：S01 §01.4
## 前置：phase == S01；本季尚未做任何生产
## 后置：全部 *_active += *_pending 且全部 *_pending == 0；
##       irrigation_index 在 [0, 2_000_000] 内 clamp 并写 log.clamp
## 不变量：INV-054（增量写入点全局唯一）、INV-091（完工写 pending、下季转 active）
## 失败：转入后 Σ pending != 0 → Fault.STOCK_IDENTITY
func commit_pending() -> int

## S07：把一笔完工能力写入 pending（**禁止写 active**，V-PD-11 在加载期已拦截直写 active 的政策）。
## 步骤：S07 §7.1
## 前置：target_code ∈ JWPolicyDef.EFFECT_TARGETS 的 *_pending_* 子集；delta >= 0
## 后置：对应 *_pending 增加 delta；本季生产完全不受影响
## 不变量：INV-091、INV-054
## 失败：target 不在白名单 → Fault.WRITE_OUT_OF_SCOPE
func add_pending(target_code: int, slot: int, delta: int) -> int

## S06 §6.1：折旧（非现金分录，资产↓净值↓），产能轨与价值轨用同一折旧率。
## 步骤：S06 §6.1
## 前置：io.depreciation_ppm 已加载；本季生产已完成
## 后置：capital_value 与 capacity_active 同步减少；flow.cell.depreciation_* 写入；
##       调用方已 post_noncash(kind=DEPRECIATION)
## 不变量：INV-055（折旧减资产与产能；维护欠账不减资产）、INV-056（同一折旧率）、INV-020
## 失败：资产被折成负数 → Fault.BALANCE_SHEET_BROKEN
func depreciate(io: JWIoTable, ledger: JWLedger, accounts: JWAccount) -> int

## S04：登记本季运行费拨款到位率（决定 S07 的可用率）。
## 步骤：S04 §4.2 的 service_opex 档
## 前置：due > 0 时 ratio = floor_div(paid * 1e6, due)；due == 0 时 ratio = 1_000_000
## 后置：flow.pubserv.funding_ratio_ppm[r] ∈ [0, 1_000_000]
## 不变量：INV-102（拨款不足只降可用率）
## 失败：无
func set_funding_ratio(r: int, paid_uu: int, due_uu: int) -> int

## S07 §7.2：维护欠账与公共服务可用率。
## 步骤：S07 §7.2
## 前置：本季 funding_ratio 已写
## 后置：availability_ppm ∈ [0, 1_000_000]；maintenance_backlog ∈ [0, max]
## 不变量：INV-055、INV-102（**capacity_active、grid_capacity、housing_stock 在本路径下不得被写**，
##          不得用写 0 表达停运）
## 失败：本函数若触碰上述三个字段 → Fault.WRITE_OUT_OF_SCOPE（WriteGuard 会抓住）
func update_maintenance_and_availability(params: PackedInt64Array) -> int

## S06 §6.3：公共非市场产出（按成本计价 = 工资 + 中间消耗 + 折旧）。
## 工资来自 JWLaborMarket、中间消耗来自 JWInventory，均以**数组形参**传入（避免反向依赖）。
## 步骤：S06 §6.3
## 前置：本季 pubserv 的工资与中间消耗已确定；折旧已由 depreciate() 算出
## 后置：flow.pubserv.output_uu = wage + intermediate + depreciation；其增加值 = wage + depreciation；
##       全额计入政府最终消费
## 不变量：INV-101（**不走市场销售，不重复计算**）、INV-112
## 失败：无
func compute_nonmarket_output(pub_wage_bill_uu: PackedInt64Array,
                              pub_intermediate_uu: PackedInt64Array) -> int

## S05 §5.8：按实际产量累计本季排放流量。
## 步骤：S05 §5.8
## 前置：output_actual 已定
## 后置：flow.region.emissions_uqe 写入
## 不变量：INV-057（排放只累积，首版不反馈到生产约束——静态检查生产函数不引用 emissions）
## 失败：无
func accumulate_emissions(output_actual_uqs: PackedInt64Array, io: JWIoTable) -> int

## S07 §7.9：排放存量衰减与环境暴露指数。
## 步骤：S07 §7.9
## 前置：region_population 由 JWPopulation 传入
## 后置：emissions_stock >= 0；env_exposure ∈ [0, 3_000_000]
## 不变量：INV-057
## 失败：area_index == 0 → 用 max(area,1)，不除零
func update_environment(region_population: PackedInt64Array, params: PackedInt64Array) -> int

## S07：项目完工时把 wip 转成目标主体的 capital（由 JWAssetCommissioning 调用）。
## 步骤：S07 §7.1
## 前置：wip_part <= 该主体当前 wip
## 后置：capital_value += wip_part；wip -= wip_part；调用方已 post_noncash
## 不变量：INV-092（付款只增 wip 与承包方现金）、INV-020
## 失败：wip 不足 → Fault.BALANCE_SHEET_BROKEN
func capitalize_wip(target_agent: int, wip_part_uu: int, ledger: JWLedger, accounts: JWAccount) -> int

## 只读访问器（生产、迁移、项目、诊断都从这里取能力值）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-083（Σ occupied <= housing_stock <= housing_capacity，由调用方在 S07 断言）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func cell_capacity(cell: int) -> int
func pubserv_capacity(r: int) -> int
func availability(r: int) -> int
func grid(r: int) -> int
func housing_stock_of(r: int) -> int
func housing_capacity_of(r: int) -> int
func slots_total(r: int) -> int
func irrigation(r: int) -> int
func port(r: int) -> int

## 载入期与投运瞬间的产能／资本一致性检查（允许此后漂移，OQ-206）。
## 步骤：LOAD、S07 投运瞬间
## 前置：io.capacity_per_capital_ppm > 0
## 后置：不改状态
## 不变量：INV-056（|capacity − capital × coeff / 1e6| <= 1 μQ_s）
## 失败：Load.CAPACITY_INCONSISTENT（载入期）；S07 投运时不符 → Fault.STOCK_IDENTITY
func check_capacity_value_consistency(io: JWIoTable) -> int

## 漂移诊断（只报警不改数，OQ-206）。
## 步骤：S06 末（诊断用）
## 前置：无
## 后置：不改状态
## 不变量：—（这是诊断指标 derived.cell.capacity_value_drift_ppm 的来源）
## 失败：无
func capacity_value_drift_ppm(cell: int, io: JWIoTable) -> int

## §1.6 状态块协议全部方法。STATE_ARRAY_SUBSYS 中 cell_* 归 SUBSYS_CELL、
## pub_* 归 SUBSYS_PUBSERV、其余归 SUBSYS_REGION。
```

---

### 4.14 `sim/population/population.gd` · `class_name JWPopulation extends RefCounted`

**职责**：36 个群组的人口守恒、出生／死亡／成年／退休／技能队列，以及群组的收入、消费、
储蓄、住房与民生指数（`docs/10` §6）。
**不含**四个主观量（生活／预期／信任／支持）——那四个由 `JWPolitics` 持有（INV-121 的结构性落地）。
群组现金与存款余额在 `JWAccount`，本类只持有「非余额」的人口与流量字段。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.group.population_persons[]` | `population` | `PackedInt64Array` | 36 | 剧本 | S | 人 | S07 |
| `state.group.participation_ppm[]` | `participation_ppm` | `PackedInt64Array` | 36 | 剧本 | S | ppm（非 working 组必须 0） | S07 |
| `state.group.employed_persons[]` | `employed` | `PackedInt64Array` | 180 | 剧本 | S | 人 | **S03（由 JWLaborMarket 回写）, S07（流出配对）** |
| `state.group.education_cohort_persons[]` | `education_cohort` | `PackedInt64Array` | 288 | 0 | S | 人 | S07 |
| `state.group.housing_units_occupied[]` | `housing_occupied` | `PackedInt64Array` | 36 | 剧本 | S | 套 | S07 |
| `state.group.service_access_ppm[]` | `service_access` | `PackedInt64Array` | 108 | 剧本 | S | ppm | S07 |
| `state.group.consumption_index_ppm[]` | `consumption_index` | `PackedInt64Array` | 36 | 1 000 000 | S | ppm | S07 |
| `flow.group.births_persons[]` | `f_births` | `PackedInt64Array` | 36 | 0 | F | 人 | S07 |
| `flow.group.deaths_persons[]` | `f_deaths` | `PackedInt64Array` | 36 | 0 | F | 人 | S07 |
| `flow.group.age_in_persons[]` / `age_out_persons[]` | `f_age_in` / `f_age_out` | `PackedInt64Array` ×2 | 36 | 0 | F | 人 | S07 |
| `flow.group.skill_in_persons[]` / `skill_out_persons[]` | `f_skill_in` / `f_skill_out` | `PackedInt64Array` ×2 | 36 | 0 | F | 人 | S07 |
| `flow.group.migrate_rejected_persons[]` | `f_migrate_rejected` | `PackedInt64Array` | 36 | 0 | F | 人 | S07（由 JWMigration 写） |
| `flow.group.wage_income_uu[]` | `f_wage_income` | `PackedInt64Array` | 36 | 0 | F | μU | S04 |
| `flow.group.transfer_income_uu[]` | `f_transfer_income` | `PackedInt64Array` | 36 | 0 | F | μU | S04 |
| `flow.group.support_in_uu[]` / `support_out_uu[]` | `f_support_in` / `f_support_out` | `PackedInt64Array` ×2 | 36 | 0 | F | μU | S04 |
| `flow.group.property_income_uu[]` | `f_property_income` | `PackedInt64Array` | 36 | 0 | F | μU | S06 |
| `flow.group.income_tax_paid_uu[]` | `f_income_tax_paid` | `PackedInt64Array` | 36 | 0 | F | μU | S06 |
| `flow.group.consumption_uu[]` | `f_consumption` | `PackedInt64Array` | 36 | 0 | F | μU | S05 |
| `flow.group.consumption_by_product_uu[]` | `f_consumption_by_product_uu` | `PackedInt64Array` | 144 | 0 | F | μU | S05 |
| `flow.group.consumption_by_product_uqs[]` | `f_consumption_by_product_uqs` | `PackedInt64Array` | 144 | 0 | F | μQ_s | S05 |
| `flow.group.housing_cost_uu[]` | `f_housing_cost` | `PackedInt64Array` | 36 | 0 | F | μU | S05 |
| `flow.group.unmet_consumption_uu[]` | `f_unmet_consumption` | `PackedInt64Array` | 36 | 0 | F | μU | S05 |
| `flow.group.savings_uu[]` | `f_savings` | `PackedInt64Array` | 36 | 0 | F | μU（可为负） | S06 |
| `content.demography.*` | `birth_ppm` / `death_ppm` / `age_out_ppm` / `support_out_weight_ppm` | `PackedInt64Array` | 4 / 36 / 3 / 36 | 剧本 | C | ppm | LOAD |
| `content.base_per_capita_real_income_uu[]` | `base_real_income` | `PackedInt64Array` | 36 | 剧本 | C | μU | LOAD |
| `content.base_real_consumption_uqs[]` | `base_real_cons` | `PackedInt64Array` | 36 | 剧本 | C | μQ | LOAD |
| `content.base_delivered_service[]` | `base_delivered_service` | `PackedInt64Array` | 108 | 剧本 | C | μQ | LOAD |
| `content.cells_init.equity_share_ppm[]` | `equity_share_ppm` | `PackedInt64Array` | 576（16 cell × 36 组） | 剧本 | C | ppm | LOAD |
| — | `_population_prev` | `PackedInt64Array` | 36 | — | — | 人，S07 入口快照，供 INV-072 | S07 |

> **两个写入者（S03/S07）为什么不互相放大**：`employed` 在 S03 被**整表重写**为市场决定的结果，
> 在 S07 只被**减少**，且减少量必须精确等于该组的人口流出带走的就业人数（INV-080）。
> S07 的写发生在 `JWLaborMarket.release_for_outflow()` 内部并回写本表，
> 是全系统对 `employed` 的第二个也是最后一个写入点。

#### 方法

```gdscript
## 劳动力（纯函数，INV-075 的分母）。非 working 组恒返回 0。
## 步骤：S03 §3.4、S07 迁移
## 前置：participation_ppm[g] == 0 当 age != working
## 后置：不改状态
## 不变量：INV-074, INV-075
## 失败：无
func labor_force(g: int) -> int
func labor_force_region_skill(r: int, k: int) -> int
func employed_total(g: int) -> int
func region_population(r: int) -> int
func nation_population() -> int

## S04 §4.5：组间赡养转移（未成年与老年组的消费资金来源）。
## 步骤：S04 §4.5
## 前置：pool 来自 working 组上季可支配收入 × support_out_weight_ppm；默认只在同地区内发生（OQ-208）
## 后置：Σ support_in == Σ support_out 精确成立；逐笔 post(kind=HOUSEHOLD_SUPPORT)
## 不变量：INV-085、INV-003（按人口权重用 split_lr 拆分）
## 失败：拆分和不等 → Fault.SPLIT_MISMATCH；付出方现金不足 → 缩减该组付出额并记 log.rounding
func pay_household_support(ledger: JWLedger, accounts: JWAccount, params: PackedInt64Array) -> int

## S05 §5.6：本季消费预算（**不能花未收到的钱**）。
## 步骤：S05 §5.6（买方类 0）
## 前置：S04 的工资、转移、赡养已全部落账
## 后置：out_budget[g] <= accounts.cash_of(agent_of_group(g))；按恩格尔权重拆到 4 个产品
## 不变量：INV-063（未收到的预计收入不可支配）、INV-003
## 失败：无（预算为 0 是正常结果）
func consumption_budget_into(out_budget_by_product: PackedInt64Array, accounts: JWAccount,
                            params: PackedInt64Array) -> int

## S05：登记一笔已成交的居民消费（由 JWInventory 在撮合后回调）。
## 步骤：S05 §5.6
## 前置：value_uu 与 qty_uqs 同时 > 0；该笔已 post(kind=HOUSEHOLD_CONSUMPTION)
## 后置：f_consumption、f_consumption_by_product_* 同步增加
## 不变量：INV-062（付款额 == floor(量×价)）、INV-064（未成交部分写 unmet_consumption）
## 失败：无
func record_consumption(g: int, product: int, value_uu: int, qty_uqs: int) -> void
func record_unmet_consumption(g: int, value_uu: int) -> void
func record_housing_cost(g: int, value_uu: int) -> void

## S06 §6.7：企业分配与存款利息分回各组，再算可支配收入与储蓄。
## 步骤：S06 §6.7
## 前置：企业利润与利息收入已确定；equity_share_ppm 与 deposit 份额按最大余数法拆分
## 后置：Δcash[g] + Δdeposit[g] == savings[g] 逐组逐季精确成立
## 不变量：INV-086（可支配与储蓄的定义式）、INV-024（存款与投资池配平）、INV-003
## 失败：恒等式不成立 → Fault.LEDGER_IMBALANCE，detail_a = 组下标，detail_b = 残差
func settle_income_and_savings(distributable_by_cell: PackedInt64Array, interest_received_uu: int,
                               ledger: JWLedger, accounts: JWAccount,
                               params: PackedInt64Array) -> int

## 可支配收入（派生纯函数，S08 计算生活指数时用）。
## 步骤：S06 末、S08 §8.1
## 前置：本季 S06 已完成
## 后置：不改状态
## 不变量：INV-086
## 失败：无
func disposable_income(g: int) -> int

## S07 §7.4：人口更新（死亡 → 出生 → 成年 → 退休 → 技能 → 迁移 → 核对）。
## 本函数只做前五步；迁移由 JWMigration 在其后调用，核对由 check_conservation() 完成。
## 步骤：S07 §7.4
## 前置：_population_prev 已在本步入口快照
## 后置：每一步都是配对的转移；取整余数用 split_lr 分配到组
## 不变量：INV-071（死亡是唯一净流出、出生是唯一净流入）、INV-072（逐组来源去向齐全）、
##          INV-074（年龄有向）、INV-082（技能升档只来自结业队列且等量配对）
## 失败：Fault.POPULATION_NOT_CONSERVED
func update_demography(rng: JWRngStreams, params: PackedInt64Array) -> int

## S07 §7.6：教育队列（P05）。**拨款当季不得产生任何 skill_in**。
## 步骤：S07 §7.6
## 前置：max_seats = teachers × student_teacher_ratio；teachers == 0 ⇒ new_seats == 0
## 后置：新席位入 education_cohort[g][q + training_lag_q]；到期队列等量配对 skill_out/skill_in
## 不变量：INV-081（席位上限与「拨款当季无 skill_in」）、INV-082（滞后 >= training_lag_q）
## 失败：申请超上限 → 截到上限并写 log.clamp；不是故障（ADV-03 的防线）
## teachers_by_region == state.pubserv.teachers_persons[]（长 4，按 region），由 JWCapital 持有、
## 经 JWTurnRunner 以数组形参传入：本类与 JWCapital 同为秩 4，同秩之间不得互相引用（§3.2/§3.3）。
func update_education(teachers_by_region: PackedInt64Array, requested_seats: PackedInt64Array,
                      q: int, params: PackedInt64Array) -> int

## S07 §7.8：消费指数与服务可及性（相对基准，不是国际排名）。
## 步骤：S07 §7.8
## 前置：base_real_cons 与 base_delivered_service 在 q=0 由剧本固定，之后只读
## 后置：consumption_index 与 service_access 更新；全国指数按人口用最大余数法加权
## 不变量：INV-149（基期人口加权值 == 1 000 000；文案无「国际排名」字样）
## 失败：基准为 0 → 用 max(base,1)，不除零
func update_living_indices(delivered_to_group: PackedInt64Array) -> int

## S07：本季各组人口流出量（死亡 + 成年出 + 迁出），供 JWLaborMarket 做就业配对。
## 步骤：S07 §7.7（在 update_demography 与 JWMigration 之后）
## 前置：本季人口流动已全部完成
## 后置：out_flow 被填满；不改状态
## 不变量：INV-080（S07 对 employment 的减少量必须精确等于本函数的结果分摊）
## 失败：无
func outflow_persons_into(out_flow: PackedInt64Array) -> void

## S07：接收 JWLaborMarket 的就业扣减结果，回写群组侧 employed。
## 步骤：S07 §7.7
## 前置：cut[g][slot] 之和 == outflow 对应的 employed_share
## 后置：employed 减少；两侧口径仍逐（地区，技能）相等
## 不变量：INV-077, INV-080
## 失败：和不相等 → Fault.EMPLOYMENT_OVERFLOW
func apply_employment_cut(cut_by_group_slot: PackedInt64Array) -> int

## S07 末：人口守恒终检。
## 步骤：S07 §7.4 第 7 步
## 前置：本季全部人口流动已完成
## 后置：不改状态
## 不变量：INV-071, INV-072, INV-073（迁移双边由 JWMigration 保证并在此复核）
## 失败：Fault.POPULATION_NOT_CONSERVED，detail_a = 组下标，detail_b = 残差
func check_conservation(migrate_in: PackedInt64Array, migrate_out: PackedInt64Array) -> int

## §1.6 状态块协议全部方法（子系统 SUBSYS_GROUP）。
```

---

### 4.15 `sim/population/labor_market.gd` · `class_name JWLaborMarket extends RefCounted`

**职责**：就业匹配、技能错配、失业统计、工资支付。
**`employment_persons` 的唯一持有者**（cell 侧与 pubserv 侧），群组侧由 `JWPopulation` 保存同一事实的
另一个索引视图，两者逐（地区，技能）精确相等（INV-077，故意冗余，交叉校验）。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.cell.employment_persons[]` | `cell_employment` | `PackedInt64Array` | 48 | 剧本 | S | 人 | **S03, S07（仅流出配对）** |
| `state.pubserv.employment_persons[]` | `pub_employment` | `PackedInt64Array` | 12 | 剧本 | S | 人 | S03, S07 |
| `flow.cell.hires_persons[]` | `f_hires` | `PackedInt64Array` | 48 | 0 | F | 人 | S03 |
| `flow.cell.separations_persons[]` | `f_separations` | `PackedInt64Array` | 48 | 0 | F | 人 | S03, S07 |
| `flow.cell.wage_bill_uu[]` | `f_wage_bill` | `PackedInt64Array` | 16 | 0 | F | μU | S04 |
| `flow.pubserv.wage_bill_uu[]` | `f_pub_wage_bill` | `PackedInt64Array` | 4 | 0 | F | μU | S04 |
| — | `_unemployment_ppm` | `int` | — | 0 | D | ppm | S03 |
| — | `_vacancies_persons` | `int` | — | 0 | D | 人（S07 工资调整用） | S03 |
| — | `_prev_employment` | `PackedInt64Array` | 48 | — | — | S03 入口快照 | S03 |

#### 方法

```gdscript
## S03 §3.2：招工与裁员（两道硬闸 + 摩擦）。**employment 的第一个也是主要的写入点**。
## 步骤：S03 §3.2
## 前置：output_plan 已由 JWSectorModel 算出；本季价格与工资率已固定
## 后置：employment_k <= min(need_k, prev + alloc_k, affordable_k)；
##       同步回写 JWPopulation.employed；hires/separations 写入
## 不变量：INV-076（Σ employed <= Σ labor_force）、INV-077（两侧口径相等）、
##          INV-078（不允许技能替代）、INV-079（工资有资金来源，首版不允许欠薪）、INV-003
## 失败：Σ employed > pool → Fault.EMPLOYMENT_OVERFLOW；
##       现金不足 → 缩减到 affordable_k 并写 log.clamp（业务性短缺，不是故障）
func hire_and_fire(output_plan_uqs: PackedInt64Array, io: JWIoTable, pricing: JWPricing,
                   pop: JWPopulation, accounts: JWAccount, params: PackedInt64Array) -> int

## S03 §3.4：失业率（反算，不是参数）。
## 步骤：S03 §3.4
## 前置：hire_and_fire 已完成
## 后置：_unemployment_ppm = floor(unemployed × 1e6 / max(labor_force, 1))；q=0 时必须落在 [79500, 80500]
## 不变量：INV-075（分母是劳动力）、INV-143（剧本 schema 中不存在失业率输入字段）
## 失败：unemployed < 0 → Fault.EMPLOYMENT_OVERFLOW
func compute_unemployment(pop: JWPopulation) -> int
func unemployment_ppm() -> int
func unemployed_persons() -> int
func vacancies_persons() -> int

## S04 §4.1：企业付工资（**工资先于消费**）。
## 步骤：S04 §4.1
## 前置：wage_bill[i] <= cell.cash（由 S03 闸二保证）
## 后置：按各组在该 cell 的在岗人数用 split_lr 拆分并逐组 post(kind=WAGE_PAYMENT)；
##       Σ 各组工资收入 == Σ 各 cell 工资总额
## 不变量：INV-079、INV-003、INV-015、INV-016
## 失败：现金不足 → **Fault.WAGE_UNFUNDED**（说明 S03 有缺陷；**不在 S04 补救、不裁员**）
func pay_wages(pricing: JWPricing, pop: JWPopulation, ledger: JWLedger, accounts: JWAccount) -> int

## S04 §4.2：公共部门工资的应付额清单（收款方 = 群组主体）。
## **不直接调 JWTreasury**（同秩，§3.2）：由 JWTurnRunner 取清单 → treasury.pay_line() → 回写实付。
## 步骤：S04 §4.2 的 public_wages 档
## 前置：pub_employment 与 wage 已定
## 后置：out_payee_agent 与 out_due 等长且逐项对应；返回清单长度
## 不变量：INV-101（非市场产出按成本计价的工资腿）、INV-079
## 失败：无
func public_wage_due_into(out_payee_agent: PackedInt64Array, out_due: PackedInt64Array,
                          pricing: JWPricing, pop: JWPopulation) -> int

## S04 §4.2：回写实际支付结果（不足部分已由 treasury 登记 arrears）。
## 步骤：S04 §4.2
## 前置：paid_by_group 来自 treasury.pay_line 的拆分结果
## 后置：flow.pubserv.wage_bill_uu 与 flow.group.wage_income_uu 同步写入
## 不变量：INV-079、INV-101、INV-030
## 失败：Σ paid > Σ due → Fault.LEDGER_IMBALANCE
func record_public_wage_paid(paid_by_group: PackedInt64Array, pop: JWPopulation) -> int

## S07 §7.7：人口流出带走的就业扣减。**S07 对 employment 的写只允许出现在本函数内**。
## 步骤：S07 §7.7
## 前置：outflow 来自 JWPopulation.outflow_persons_into()
## 后置：Σ 扣减 == employed_share（按各 cell/pubserv 在该组在岗人数用 split_lr 拆分）；
##       结果回写 JWPopulation.apply_employment_cut()
## 不变量：INV-080（减少量精确等于人口流出带走的就业人数）、INV-077、INV-003
## 失败：和不相等 → Fault.EMPLOYMENT_OVERFLOW
func release_for_outflow(outflow_persons: PackedInt64Array, pop: JWPopulation,
                         out_cut_by_group_slot: PackedInt64Array) -> int

## 只读访问器。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-077
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func employment(cell: int, k: int) -> int
func pubserv_employment(r: int, k: int) -> int
func region_wage_index(pricing: JWPricing, r: int) -> int   ## 迁移的工资拉力输入

## 载入期与 S03 末的两侧口径交叉校验。
## 步骤：LOAD、S03 末
## 前置：两侧数组都已填充
## 后置：不改状态
## 不变量：INV-077、INV-151（故意冗余的交叉校验）
## 失败：Load.EMPLOY_MISMATCH（载入期）/ Fault.EMPLOYMENT_OVERFLOW（运行期）
func check_employment_views(pop: JWPopulation) -> int

## §1.6 状态块协议全部方法（cell_* 归 SUBSYS_CELL，pub_* 归 SUBSYS_PUBSERV）。
```

---

### 4.16 `sim/population/migration.gd` · `class_name JWMigration extends RefCounted`

**职责**：迁移的拉力／推力合成与**三道硬闸**（职位、住房、迁移成本），来源去向必须一致（INV-073）。
持有稀疏的迁移流列式记录。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `flow.group.migrate_flow_persons[]` | `m_from` / `m_to` / `m_persons` | `PackedInt64Array` ×3 | `MIGRATION_CAP` | 0 | F | 组下标／人 | S07 |
| — | `_row_count` | `int` | — | 0 | F | 本季行数 | S07 |
| — | `_in_by_group` / `_out_by_group` | `PackedInt64Array` ×2 | 36 | 0 | F | 人（INV-073 的对账缓冲） | S07 |
| `content.region.adjacency[]` | `adjacency` | `PackedInt64Array` | 16 | 剧本 | C | 0/1，对称无自环 | LOAD |
| `content.region.migration_cost_uu[]` | `migration_cost` | `PackedInt64Array` | 16 | 剧本 | C | μU/人 | LOAD |

#### 方法

```gdscript
## S07 §7.5：按邻接对遍历，合成净拉力，过三道硬闸，写配对的迁移流并支付迁移成本。
## 步骤：S07 §7.5
## 前置：本季 update_demography 已完成；只在邻接地区之间发生（OQ-208）；
##       遍历顺序按 (r_from, r_to) 下标升序（确定性）
## 后置：movers = min(intent, cap_jobs, cap_housing, cap_cost)；
##       被挡回人数写 migrate_rejected_persons；post(kind=MIGRATION_COST, group → cell.services[r_to])
## 不变量：INV-073（migrate_out[a][b] == migrate_in[b][a] 且 Σ 进 == Σ 出）、
##          INV-083（住房硬上限）、INV-084（被挡回必须显式登记，容量不得自动增长）
## 失败：进出不配对 → Fault.MIGRATION_UNPAIRED；住房被突破 → Fault.HOUSING_OVERFLOW
func run(pop: JWPopulation, labor: JWLaborMarket, capital: JWCapital, pricing: JWPricing,
         ledger: JWLedger, accounts: JWAccount, rng: JWRngStreams,
         params: PackedInt64Array) -> int

## 本季迁移的进出汇总（供 JWPopulation.check_conservation 复核）。
## 步骤：S07 §7.4 第 7 步
## 前置：run() 已完成
## 后置：不改状态
## 不变量：INV-073
## 失败：无
func in_by_group() -> PackedInt64Array
func out_by_group() -> PackedInt64Array

## 住房紧张度（迁移推力输入，也是 JWPricing 的租金输入）。
## 步骤：S07 §7.5 / §7.3
## 前置：capital 的住房存量与 pop 的占用量已更新
## 后置：不改状态；返回 [0, 1_000_000]
## 不变量：INV-083
## 失败：capacity == 0 → 返回 1_000_000（满）
func housing_stress_ppm(pop: JWPopulation, capital: JWCapital, r: int) -> int

## §1.6 状态块协议全部方法（全部为 FLOW_*，子系统 SUBSYS_GROUP）。
```

---

### 4.17 `sim/sectors/inventory.gd` · `class_name JWInventory extends RefCounted`

**职责**：库存恒等式 **与** 国内市场闭合。两者合在一个文件里的理由：
INV-047（`期末 == 期初 + 生产 + 购入 − 售出 − 耗用 − 损耗`）与
INV-059（`Σ 成交 + Σ 未满足 == Σ 需求`，且`卖方库存减少量 == Σ 成交`）
是同一笔账的两半；分开放会让「卖方库存减少量等于成交量」这条断言变成跨文件约定。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.cell.inventory_output_uqs[]` | `inv_output` | `PackedInt64Array` | 16 | 剧本 | S | μQ_s | S05 |
| `state.cell.inventory_input_uqs[]` | `inv_input` | `PackedInt64Array` | 64 | 剧本 | S | μQ_j | S05 |
| `flow.cell.consumed_input_uqs[]` | `f_consumed` | `PackedInt64Array` | 64 | 0 | F | μQ_j | S05 |
| `flow.cell.purchased_input_uqs[]` | `f_purchased` | `PackedInt64Array` | 64 | 0 | F | μQ_j | S05 |
| `flow.cell.sold_uqs[]` | `f_sold` | `PackedInt64Array` | 16 | 0 | F | μQ_s | S05 |
| `flow.cell.spoilage_uqs[]` | `f_spoilage_out` | `PackedInt64Array` | 16 | 0 | F | μQ_s | S05 |
| — | `f_spoilage_in` | `PackedInt64Array` | 64 | 0 | F | μQ_j | S05 |
| `flow.cell.unmet_demand_uqs[]` | `f_unmet_demand` | `PackedInt64Array` | 16 | 0 | F | μQ_s | S05 |
| `flow.cell.price_variance_uu[]` | `f_price_variance` | `PackedInt64Array` | 16 | 0 | F | μU（可正可负） | S05 |
| `flow.market.supply_uqs[]` | `m_supply` | `PackedInt64Array` | 4 | 0 | F | μQ_s | S05 |
| `flow.market.demand_uqs[]` | `m_demand` | `PackedInt64Array` | 20 | 0 | F | μQ_s | S05 |
| `flow.market.traded_uqs[]` | `m_traded` | `PackedInt64Array` | 20 | 0 | F | μQ_s | S05 |
| `flow.market.unmet_demand_uqs[]` | `m_unmet` | `PackedInt64Array` | 20 | 0 | F | μQ_s | S05 |
| `flow.market.rationing_rule[]` | `m_rule` | `PackedInt64Array` | 4 | 0 | F | 枚举 | S05 |
| `flow.market.inventory_target_uqs[]` | `m_inv_target` | `PackedInt64Array` | 16 | 0 | F | μQ_s | S03 |
| `flow.pubserv.delivered_uqs[]` | `f_pub_delivered` | `PackedInt64Array` | 4 | 0 | F | μQ_services | S05 |
| `flow.pubserv.intermediate_uu[]` | `f_pub_intermediate` | `PackedInt64Array` | 4 | 0 | F | μU | S05 |
| `state.pubserv.queue_persons[]` | `pub_queue` | `PackedInt64Array` | 12 | 0 | S | 人 | S05 |
| — | `_inv_output_start` / `_inv_input_start` | `PackedInt64Array` ×2 | 16 / 64 | — | — | S05 入口快照，供 INV-047 | S05 |
| `content.region.logistics_cost_ppm[]` | `logistics_cost_ppm` | `PackedInt64Array` | 16 | 剧本 | C | ppm | LOAD |

#### 方法

```gdscript
## S03 §3.1：登记本季目标库存（由 JWSectorModel 在制定计划时调用）。
## 步骤：S03 §3.1
## 前置：storable == 0 的部门目标恒为 0
## 后置：m_inv_target[cell] >= 0
## 不变量：INV-049（不可库存部门期末库存恒为 0）
## 失败：无
func set_inventory_target(cell: int, target_uqs: int) -> void

## S05 入口：快照期初库存，供步末的库存恒等式检查。
## 步骤：S05 §5.1 开始
## 前置：phase == S05
## 后置：_inv_*_start 与当前库存逐位相同
## 不变量：INV-047
## 失败：无
func begin_production() -> void

## S05 §5.4：从 q_actual 反算并扣减投入品（ceil，保证不透支）。
## 步骤：S05 §5.4
## 前置：q_actual <= floor(avail × 1e6 / a)（由 §5.3 的 bound_materials 保证）
## 后置：inv_input 减少 use；f_consumed 增加 use；inv_input >= 0
## 不变量：INV-046（整数引理 T-U-CEIL-SAFE）、INV-047、INV-048、INV-050（只用期初库存）
## 失败：use > avail → Fault.NEGATIVE_INVENTORY（说明 q_actual 推导有误），终止保留现场
func consume_inputs(cell: int, q_actual_uqs: int, io: JWIoTable) -> int

## S05 §5.4：成品入库（storable == 1）或直接进当期供给（storable == 0）。
## 步骤：S05 §5.4
## 前置：q_actual >= 0
## 后置：storable == 1 → inv_output += q_actual；storable == 0 → 期末库存恒为 0
## 不变量：INV-049（energy 与 services 期末库存恒为 0）、INV-047
## 失败：不可库存部门被写入库存 → Fault.ENERGY_STORED
func store_output(cell: int, q_actual_uqs: int, io: JWIoTable) -> int

## S05 §5.6：形成 5 类买方的需求（先全部算完再统一配给，避免先到先得的顺序依赖）。
## 步骤：S05 §5.6
## 前置：居民预算由 JWPopulation 提供；公共服务与政府采购按已预留预算换算；
##       出口按 world.export_demand 与 delivery_capacity 取小
## 后置：m_demand 被填满，买方类顺序固定 0..4
## 不变量：INV-059、INV-063
## 失败：无
func collect_demand(pop: JWPopulation, capital: JWCapital, treasury: JWTreasury,
                    world: JWWorldMarket, pricing: JWPricing, accounts: JWAccount,
                    params: PackedInt64Array) -> int

## S05 §5.6：两级配给（公开优先级 + 档内按需求量比例），两级都完全确定。
## 步骤：S05 §5.6
## 前置：m_supply 与 m_demand 已算完；rationing_priority 来自内容配置
## 后置：Σ alloc == min(可供, Σ 需求)，alloc_i <= requested_i；m_rule 记录实际走的路径
## 不变量：INV-060（配给精确）、INV-061（rationing_rule 与实际路径一致）、INV-003
## 失败：拆分和不等 → Fault.SPLIT_MISMATCH
func ration(ration_mode: int, rng: JWRngStreams) -> int

## S05 §5.6：成交过账（金额与实物各自双边入账；跨区加物流成本；入库方产生价差）。
## 步骤：S05 §5.6
## 前置：ration() 已完成
## 后置：卖方库存减少量精确等于 Σ traded；买方若入库则按基年价计值并记 price_variance；
##       未成交的居民预算留作现金（被迫储蓄）并记 unmet_consumption
## 不变量：INV-059、INV-062、INV-064、INV-015、INV-016、INV-119（价差逐笔可追溯）
## 失败：买方现金不足 → 成交量缩减并记未满足需求（**没有任何路径可以产生凭空的货**）
func execute_trades(pop: JWPopulation, capital: JWCapital, treasury: JWTreasury,
                    world: JWWorldMarket, pricing: JWPricing, ledger: JWLedger,
                    accounts: JWAccount) -> int

## S05 §5.7：公共服务交付与排队。
## 步骤：S05 §5.7
## 前置：availability_ppm 是上季 S07 的结果（本季只读）
## 后置：delivered <= mul_ppm(capacity_active, availability_ppm)；
##       未获服务人数按各组需求用最大余数法摊回 queue_persons
## 不变量：INV-103、INV-102（**不得降 capacity_active、不得删资产**）
## 失败：无（交付不足是业务结果）
func deliver_public_services(capital: JWCapital, pop: JWPopulation) -> int

## S05 §5.8：损耗与期末库存结转。
## 步骤：S05 §5.8
## 前置：全部交易已完成
## 后置：spoilage 显式登记并计入中间消耗；库存 >= 0
## 不变量：INV-053（不允许用「盘点差异」吸收）、INV-048
## 失败：库存为负 → Fault.NEGATIVE_INVENTORY
func apply_spoilage(io: JWIoTable) -> int

## S05 末：逐 cell 逐品种的库存恒等式检查。
## 步骤：S05 §5.8 末
## 前置：begin_production() 已在本步入口调用
## 后置：不改状态
## 不变量：INV-047（期末 == 期初 + 生产 + 购入 − 售出 − 耗用 − 损耗）、INV-059
## 失败：Fault.STOCK_IDENTITY，detail_a = idx_inv，detail_b = 残差
func check_stock_identity(output_actual_uqs: PackedInt64Array) -> int

## S06 §6.2 的数量口径输入（库存变动、耗用、损耗），供增加值与实际 GDP 计算。
## 步骤：S06 §6.2
## 前置：S05 已完成
## 后置：不改状态
## 不变量：INV-111、INV-117
## 失败：无
func d_inventory_output(cell: int) -> int
func d_inventory_input(cell: int) -> int
func used_total(cell: int) -> int
func spoilage_out(cell: int) -> int
func spoilage_in_total(cell: int) -> int
func price_variance(cell: int) -> int
func price_variance_total() -> int

## §1.6 状态块协议全部方法（inv_* 与 f_* 归 SUBSYS_CELL，m_* 归 SUBSYS_MARKET，
## pub_* 归 SUBSYS_PUBSERV）。
```

---

### 4.18 `sim/sectors/sector_model.gd` · `class_name JWSectorModel extends RefCounted`

**职责**：生产单元（cell）的**计划 → 五项约束 → 实际产量 → 经营结果**。
`Q_actual = min(Q_plan, Q_capacity, Q_labor, Q_energy, Q_materials)`，**系数为零跳过该约束**。
同时持有 cell 的 S06 经营结果流量（增加值、利润），因为它们是同一个实体的两面。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.cell.demand_expect_uqs[]` | `demand_expect` | `PackedInt64Array` | 16 | 剧本 | S | μQ_s | S03 |
| `flow.cell.output_plan_uqs[]` | `f_output_plan` | `PackedInt64Array` | 16 | 0 | F | μQ_s | S03 |
| `flow.cell.bound_plan_uqs[]` | `f_bound_plan` | `PackedInt64Array` | 16 | 0 | F | μQ_s | S05 |
| `flow.cell.bound_capacity_uqs[]` | `f_bound_capacity` | `PackedInt64Array` | 16 | 0 | F | μQ_s | S05 |
| `flow.cell.bound_labor_uqs[]` | `f_bound_labor` | `PackedInt64Array` | 16 | 0 | F | μQ_s 或 SENTINEL | S05 |
| `flow.cell.bound_energy_uqs[]` | `f_bound_energy` | `PackedInt64Array` | 16 | 0 | F | μQ_s 或 SENTINEL | S05 |
| `flow.cell.bound_materials_uqs[]` | `f_bound_materials` | `PackedInt64Array` | 16 | 0 | F | μQ_s 或 SENTINEL | S05 |
| `flow.cell.binding_code[]` | `f_binding_code` | `PackedInt64Array` | 16 | 0 | F | 枚举 Binding | S05 |
| `flow.cell.output_actual_uqs[]` | `f_output_actual` | `PackedInt64Array` | 16 | 0 | F | μQ_s | S05 |
| `flow.cell.energy_allocated_uqs[]` | `f_energy_allocated` | `PackedInt64Array` | 16 | 0 | F | μQ_energy | S05 |
| `flow.cell.energy_unused_uqs[]` | `f_energy_unused` | `PackedInt64Array` | 16 | 0 | F | μQ_energy | S05 |
| `flow.region.electricity_demand_uqs[]` | `f_elec_demand` | `PackedInt64Array` | 4 | 0 | F | μQ_energy | S03 |
| `flow.region.electricity_supply_uqs[]` | `f_elec_supply` | `PackedInt64Array` | 4 | 0 | F | μQ_energy | S05 |
| `flow.cell.invest_intent_uu[]` | `f_invest_intent` | `PackedInt64Array` | 16 | 0 | F | μU | S03 |
| `flow.cell.gross_output_uu[]` | `f_gross_output` | `PackedInt64Array` | 16 | 0 | F | μU | S06 |
| `flow.cell.intermediate_uu[]` | `f_intermediate` | `PackedInt64Array` | 16 | 0 | F | μU | S06 |
| `flow.cell.value_added_uu[]` | `f_value_added` | `PackedInt64Array` | 16 | 0 | F | μU（可为负） | S06 |
| `flow.cell.value_added_real_uu[]` | `f_value_added_real` | `PackedInt64Array` | 16 | 0 | F | μU（基年价） | S06 |
| `flow.cell.operating_surplus_uu[]` | `f_operating_surplus` | `PackedInt64Array` | 16 | 0 | F | μU（可为负） | S06 |
| `flow.cell.profit_pretax_uu[]` | `f_profit_pretax` | `PackedInt64Array` | 16 | 0 | F | μU（可为负） | S06 |
| `flow.cell.tax_profit_paid_uu[]` | `f_tax_profit_paid` | `PackedInt64Array` | 16 | 0 | F | μU | S06 |
| `flow.cell.distributed_uu[]` | `f_distributed` | `PackedInt64Array` | 16 | 0 | F | μU | S06 |
| `flow.cell.subsidy_received_uu[]` | `f_subsidy_received` | `PackedInt64Array` | 16 | 0 | F | μU | S04 |
| `state.cell.loss_carryforward_uu[]` | `loss_carryforward` | `PackedInt64Array` | 16 | 0 | S | μU | S06 |
| `log.constraint_diag.*` | `d_cell`/`d_cands`/`d_binding`/`d_slack` | `PackedInt64Array` ×4 | 16×5 | 0 | L | — | S05 |
| — | `_sales_rev` | `PackedInt64Array` | 16 | 0 | F | μU，S05 累计的销售额 | S05 |
| — | `_sold_qty` | `PackedInt64Array` | 16 | 0 | F | μQ_s，基年价口径 | S05 |

#### 方法

```gdscript
## S03 §3.1：滞后需求预期与计划产量（**不含本季信息**）。
## 步骤：S03 §3.1
## 前置：sold_prev 与 unmet_prev 是上季的实际值（用「成交 + 未满足」而不是产量）
## 后置：demand_expect 更新（跨季存量，存档必含）；output_plan >= 0；同时写 inventory 目标
## 不变量：INV-043（output_actual <= output_plan）
## 失败：无
func plan_output(sold_prev_uqs: PackedInt64Array, unmet_prev_uqs: PackedInt64Array,
                 inventory: JWInventory, io: JWIoTable, params: PackedInt64Array) -> int

## S03 §3.5：投入订单与电力需求（只登记订单，本步不分配任何资源）。
## 步骤：S03 §3.5
## 前置：output_plan 已算出；energy_coeff 与 io_coeff 的能源行在加载期已交叉校验（V-IO-08）
## 后置：flow.region.electricity_demand_uqs 写入（含居民用电）
## 不变量：INV-044（系数为 0 跳过）；材料与电力**不在 S03/S04 分配**（§4.2）
## 失败：无
func order_inputs(io: JWIoTable, pop: JWPopulation, params: PackedInt64Array) -> int

## S03 §3.6：扩产意愿（部门行为规则，不是 AI）。
## 步骤：S03 §3.6
## 前置：三项输入全部是**已实现的量**（上季瓶颈、上季利润、产能利用率）
## 后置：invest_intent >= 0；无任何外生加成项
## 不变量：静态检查——投资函数不得引用 expectation_ppm / trust_ppm / support_ppm
## 失败：capacity == 0 → util 记 0，不除零
func compute_invest_intent(capital: JWCapital, params: PackedInt64Array) -> int

## S05 §5.2：能源 cell 先结算，净出自用量，形成各地区可交付电力并配给。
## 步骤：S05 §5.1 第 1–2 步
## 前置：a(energy→energy) < 1_000_000（加载期已保证，INV-052）
## 后置：flow.region.electricity_supply = min(Σ deliver, grid_capacity)；超出电网的部分作废；
##       两级配给（生命线 → 生产用电），同档内按 split_lr
## 不变量：INV-051（电力当期使用、不入库存、Σ 配给 ≤ min(可交付, 电网)）、INV-052、INV-060
## 失败：电力被写入库存 → Fault.ENERGY_STORED；配给和不等 → Fault.SPLIT_MISMATCH
func settle_energy(capital: JWCapital, inventory: JWInventory, io: JWIoTable,
                   labor: JWLaborMarket, params: PackedInt64Array) -> int

## S05 §5.3：五项约束的整数换算与取最小（**本季 argmin 是报告「限制因素」的唯一数据源**）。
## 步骤：S05 §5.3
## 前置：能源 cell 跳过 bound_energy；系数为 0 的约束不产生候选值（continue / SENTINEL）
## 后置：output_actual == min(激活候选)；binding_code 为并列时序号最小者；
##       slack[binding] == 0，其余 slack >= 0；逐 cell 写 log.constraint_diag
## 不变量：INV-043, INV-044（禁止除零、禁止 max(c,1)）, INV-045（并列决胜固定序）
## 失败：五项全为 SENTINEL（理论不可能）→ Fault.UNBOUNDED_PRODUCTION
func solve_output(cell: int, capital: JWCapital, labor: JWLaborMarket,
                  inventory: JWInventory, io: JWIoTable) -> int

## S05 §5.1 第 3 步：12 个 agri/manu/services cell 的生产（互不使用对方本季产出）。
## 步骤：S05 §5.1
## 前置：能源已结算；本季购入补的是**下季**可用库存
## 后置：逐 cell 调 solve_output → inventory.consume_inputs → inventory.store_output
## 不变量：INV-050（同季不得使用本季产出，T-U-NO-SAME-QUARTER-CHAIN）、INV-046、INV-047
## 失败：透支库存 → Fault.NEGATIVE_INVENTORY
func settle_production(capital: JWCapital, labor: JWLaborMarket, inventory: JWInventory,
                       io: JWIoTable) -> int

## S05：登记一笔销售（由 JWInventory 在成交后回调），用于 S06 的总产出。
## 步骤：S05 §5.6
## 前置：value_uu 与 qty_uqs 同时 >= 0
## 后置：_sales_rev 与 _sold_qty 累加
## 不变量：INV-112（**禁止用 Σ 销售额直接当 GDP**；这里只是增加值公式的一个输入项）
## 失败：无
func record_sale(cell: int, value_uu: int, qty_uqs: int) -> void

## S06 §6.2：总产出、中间投入、增加值（名义与基年价两轨）。
## 步骤：S06 §6.2
## 前置：S05 已完成；损耗计入中间消耗（INV-053）
## 后置：value_added == gross_output − intermediate 逐 cell 成立；
##       value_added_real 全部用数量口径重算
## 不变量：INV-111、INV-053、INV-117（**禁止用名义值除以任何价格指数**，
##          静态检查本函数不引用 consumer_index_ppm）
## 失败：无（单个 cell 增加值允许为负，OQ-219）
func compute_value_added(inventory: JWInventory, io: JWIoTable) -> int

## S06 §6.6：税前利润与结转亏损（价差进经营结果）。
## 步骤：S06 §6.6
## 前置：折旧已由 JWCapital 算出并落账；价差来自 JWInventory
## 后置：operating_surplus = value_added − wage_bill（**按残差定义**，INV-116 因此是定义式）；
##       profit_pretax = value_added − wage_bill − depreciation + price_variance；
##       loss_carryforward 按 §6.6 的公式更新；out_taxable 供 JWTreasury 用
## 不变量：INV-116、INV-113（补助不进 gross_output、不进任何 GDP 口径）
## 失败：无
func compute_profit(labor: JWLaborMarket, capital: JWCapital, inventory: JWInventory,
                    out_taxable_by_cell: PackedInt64Array, params: PackedInt64Array) -> int

## S06 §6.7：可分配利润（扣税后按 payout_ratio），交给 JWPopulation 分回各组。
## 步骤：S06 §6.7
## 前置：compute_profit 与 collect_profit_tax 已完成
## 后置：out_distributable 被填满；f_distributed 写入
## 不变量：INV-086（财产收入是可支配收入的一项）
## 失败：无
func compute_distributable(out_distributable: PackedInt64Array, params: PackedInt64Array) -> int

## 只读访问器（诊断、政治、集团、报告都从这里取）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-045（binding_code 是报告的唯一数据源）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func output_actual(cell: int) -> int
func binding_code(cell: int) -> int
func bound_value(cell: int, which: int) -> int
func value_added(cell: int) -> int
func value_added_real(cell: int) -> int
func profit_pretax(cell: int) -> int
func output_actual_array() -> PackedInt64Array   ## 供 JWProjectQueue 折施工能力（数组形参，不反向依赖）

## §1.6 状态块协议全部方法（子系统 SUBSYS_CELL，电力两项归 SUBSYS_REGION）。
```

---

### 4.19 `sim/projects/project_queue.gd` · `class_name JWProjectQueue extends RefCounted`

**职责**：项目 SoA（只增不删）、施工能力分配、进度推进、按进度付款。
**付款不制造进度**（INV-087）：`construction_progress` 的形参表里**没有 `paid_uu`**（静态检查）。

#### 成员变量（SoA，容量 `PROJECT_CAP0`，实际长度 `count`）

| 稳定 ID | 成员 | 类型 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|
| `state.project.id[]` | `id` | `PackedStringArray` | S | — | S02 |
| `state.project.policy_idx[]` | `policy_idx` | `PackedInt64Array` | S | 0..11 | S02 |
| `state.project.region_idx[]` | `region_idx` | `PackedInt64Array` | S | 0..3 | S02 |
| `state.project.status[]` | `status` | `PackedInt64Array` | S | 枚举 | **S01（completed→commissioned）, S02, S04, S05, S07** |
| `state.project.total_cost_uu[]` | `total_cost` | `PackedInt64Array` | S | μU | S02 |
| `state.project.planned_quarters[]` | `planned_quarters` | `PackedInt64Array` | S | 季 | S02 |
| `state.project.spend_plan_uu[]` | `spend_plan` | `PackedInt64Array` | S | μU（按 `p*3+line`） | S02 |
| `state.project.paid_uu[]` | `paid` | `PackedInt64Array` | S | μU（按 `p*3+line`） | S04 |
| `state.project.delivery_progress_ppm[]` | `delivery_progress` | `PackedInt64Array` | S | ppm | S05 |
| `state.project.construction_progress_ppm[]` | `construction_progress` | `PackedInt64Array` | S | ppm | S05 |
| `state.project.required_construction_uqs[]` | `required_construction` | `PackedInt64Array` | S | μQ_services | S02 |
| `state.project.required_equipment_uqs[]` | `required_equipment` | `PackedInt64Array` | S | μQ_manu | S02 |
| `state.project.queue_slot_held[]` | `slot_held` | `PackedInt64Array` | S | 0/1 | S02, S07 |
| `state.project.capacity_effect_uqs_per_q[]` | `capacity_effect` | `PackedInt64Array` | S | μQ/季 | S02 |
| `state.project.capacity_target[]` | `capacity_target` | `PackedInt64Array` | S | 效果落点码 | S02 |
| `state.project.opex_per_q_uu[]` | `opex_per_q` | `PackedInt64Array` | S | μU | S02 |
| `state.project.commissioned_q[]` | `commissioned_q` | `PackedInt64Array` | S | 季，−1 未投运 | **S01** |
| `state.project.residual_value_uu[]` | `residual_value` | `PackedInt64Array` | S | μU | S02, S07 |
| `state.project.cancel_penalty_uu[]` | `cancel_penalty` | `PackedInt64Array` | S | μU | S02 |
| `state.project.suspension_reason[]` | `suspension_reason` | `PackedInt64Array` | S | 枚举 | S02, S04, S05 |
| `state.project.defer_count[]` | `defer_count` | `PackedInt64Array` | S | 次 | S02 |
| `state.project.defer_quarters_total[]` | `defer_q_total` | `PackedInt64Array` | S | 季 | S02 |
| `state.project.defer_until_q[]` | `defer_until_q` | `PackedInt64Array` | S | 季 | S02 |
| `state.project.defer_fee_uu[]` | `defer_fee` | `PackedInt64Array` | S | μU | S02 |
| `flow.region.construction_capacity_uqs[]` | `f_construction_capacity` | `PackedInt64Array` | F | μQ_services | **S05** |
| `flow.region.construction_used_uqs[]` | `f_construction_used` | `PackedInt64Array` | F | μQ_services | S05 |
| — | `count` | `int` | S | 项目数 | S02 |

> **status 的五个写入者为什么不互相放大**：五处各自只做**单向的状态跃迁**，
> 且跃迁图是无环的：`planned →(S02) in_progress →(S04/S05) suspended →(S02) in_progress
> →(S07) completed →(S01) commissioned`，`cancelled` 是 S02 的终态。
> `JWProjectQueue.set_status()` 是唯一的写入函数，内部用一张 5×6 的合法跃迁表拦截非法跃迁。

#### 方法

```gdscript
## S02 §2.7：新建项目，占用施工槽位，展开分季支出计划。
## 步骤：S02 §2.7
## 前置：region 有空槽（derived.slots_used < slots_total）；Σ spend_plan == total_cost（精确）
## 后置：新项目入 SoA，slot_held = 1，status = PLANNED；ID 来自 entity_seq
## 不变量：INV-092（Σ spend_plan == total_cost）、INV-094（Σ slot_held <= slots_total）、INV-010
## 失败：无空槽 → 返回 -1，调用方置 blocked_reason = QUEUE 并 REJECT(Reject.NO_SLOT)
func launch(entity_seq: int, policy_idx: int, region: int, defs: JWPolicyDef,
            capital: JWCapital, q: int) -> int

## S02 §2.7：取消项目。**已付不退、现金不增加**。
## 步骤：S02 §2.7
## 前置：项目存在且未完工
## 后置：committed_memo 减去剩余合同额；penalty 与 residual_value 均入账；释放槽位；
##       status = CANCELLED
## 不变量：INV-093（paid_uu 不回退）、INV-032（取消不退还已付的钱）、INV-094
## 失败：项目不存在 → Reject.NOT_FOUND
func cancel(p: int, defs: JWPolicyDef, treasury: JWTreasury, ledger: JWLedger,
            accounts: JWAccount, capital: JWCapital) -> int

## S04 §4.4：项目履约付款的应付清单（三条 spend_line 各有收款方）。
## **本步不写任何进度字段。**
## 步骤：S04 §4.4
## 前置：status == IN_PROGRESS
## 后置：out_payee 与 out_due 填好（进口设备 → agent.row，国产材料 → cell.manu，
##       施工服务 → cell.services）
## 不变量：INV-087（付款与进度无数据依赖）、INV-092
## 失败：无
func payment_due_into(out_project: PackedInt64Array, out_line: PackedInt64Array,
                      out_payee_agent: PackedInt64Array, out_due: PackedInt64Array, q: int) -> int

## S04 §4.4：回写实付，增 wip，资金不足转 suspended(financing)。
## 步骤：S04 §4.4
## 前置：paid <= 该分项剩余合同额
## 后置：paid_uu 增加；gov.wip_uu 增加；不足 → status = SUSPENDED, reason = FINANCING，已付不退
## 不变量：INV-087, INV-092（Σ paid <= Σ spend_plan）
## 失败：超付 → 拒绝该笔并记 Reject.OVERPAY 诊断（不是 Fault），项目转 SUSPENDED
func record_payment(p: int, line: int, paid_uu: int, treasury: JWTreasury) -> int

## S05 §5.5：从服务 cell 的**实际**产量折出本地区施工能力（不是由付款折出）。
## 步骤：S05 §5.5
## 前置：svc_output_uqs 由 JWTurnRunner 从 JWSectorModel 取来（数组形参，避免反向依赖）
## 后置：f_construction_capacity[r] = mul_ppm(svc_out, construction_share_cap_ppm)；
##       该份额从服务的市场可售量中扣除（由 JWInventory 在算 supply 时读本字段）
## 不变量：INV-088、INV-058（施工受能力与槽位双重约束）
## 失败：无
func compute_construction_capacity(svc_output_uqs: PackedInt64Array,
                                   params: PackedInt64Array) -> int

## S05 §5.5：推进施工进度与交付进度。**形参表中没有 paid_uu**（INV-087 的静态防线）。
## 步骤：S05 §5.5
## 前置：compute_construction_capacity 已完成；设备到货量受 world.delivery_capacity 约束
## 后置：Δconstruction = floor(grant × 1e6 / required_construction)；
##       Δdelivery = floor(delivered × 1e6 / required_equipment)；两者都 clamp 到 [0, 1e6]；
##       grant == 0 且 need > 0 → status = SUSPENDED, reason = CONGESTION
## 不变量：INV-087, INV-088, INV-089（交付只由实际到货量决定）
## 失败：required_* == 0 → Fault.DIV_ZERO（加载期 V-PD 已保证 > 0，此处是兜底）
func advance_progress(world: JWWorldMarket, ledger: JWLedger, accounts: JWAccount) -> int

## 状态跃迁的唯一写入函数（内部查合法跃迁表）。
## 步骤：S01, S02, S04, S05, S07
## 前置：(from, to) 在合法跃迁表内
## 后置：status[p] == to；不合法则不改并返回错误
## 不变量：INV-090（完工充要条件由 JWAssetCommissioning 判定，本函数只执行跃迁）
## 失败：非法跃迁 → Fault.PHASE_VIOLATION
func set_status(p: int, to: int, reason: int) -> int

## 只读访问器与队列统计。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-094
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func slots_used(r: int) -> int
func progress_ready(p: int) -> bool      ## delivery == 1e6 且 construction == 1e6
func status_of(p: int) -> int
func region_of(p: int) -> int
func committed_remaining(p: int) -> int

## §1.6 状态块协议全部方法（SUBSYS_PROJECT；两个 flow.region.* 归 SUBSYS_REGION）。
```

---

### 4.20 `sim/projects/asset_commissioning.gd` · `class_name JWAssetCommissioning extends RefCounted`

**职责**：完工判定、投运、未完工残值、合同赔偿。
它是「**当季完工，下季供能**」这条底座的判定端，`JWCapital.commit_pending()` 是执行端。

#### 成员变量

本类**不持有任何状态**（纯编排）。它只读写 `JWProjectQueue`、`JWCapital`、`JWTreasury` 的字段。
`STATE_ARRAY_IDS` 与 `FLOW_ARRAY_IDS` 均为空数组；`reset_flows()` 是空实现。
这样做的好处：完工逻辑没有自己的「私房状态」可以藏，全部后果都落在别人可被断言的字段上。

#### 方法

```gdscript
## S01 §01.4 末：把上季完工的项目标记为已投运。
## 步骤：S01 §01.4
## 前置：JWCapital.commit_pending() 已执行（能力已转 active）
## 后置：status: COMPLETED → COMMISSIONED；commissioned_q = 当前 q（== 完工季 + 1）
## 不变量：INV-091（commissioned_q == 完工季 + 1）；验收测试 T-S-COMMISSION-LAG
## 失败：非法跃迁 → Fault.PHASE_VIOLATION
func promote_completed(pq: JWProjectQueue, q: int) -> int

## S07 §7.1：完工判定（充要条件三项齐全才算完工）。
## 步骤：S07 §7.1
## 前置：delivery == 1e6 且 construction == 1e6 且**配套条件满足**
##       （OQ-245：运行费已纳入下季预算承诺，且目标主体人员不为零）
## 后置：status = COMPLETED；**只写 *_pending_***（`JWCapital.add_pending`）；
##       wip 转 capital；gov.service_opex_committed += opex_per_q；释放槽位
## 不变量：INV-090（任一未满足不得投运）、INV-091（只写 pending）、INV-054、INV-092、INV-102
## 失败：配套条件不满足 → 停在进度 100% 但不完工，写 blocked_reason（业务结果，不是故障）；
##       若本函数写到任何 *_active_* → Fault.WRITE_OUT_OF_SCOPE
func commission_ready(pq: JWProjectQueue, capital: JWCapital, treasury: JWTreasury,
                      labor: JWLaborMarket, ledger: JWLedger, accounts: JWAccount, q: int) -> int

## S02/S07：未完工残值登记（取消或长期中断时）。
## 步骤：S02 §2.7（取消）、S07（长期中断复核）
## 前置：项目未完工
## 后置：residual_value = 已形成的可回收部分；wip 中超出残值的部分确认为损失（政府净值减少）
## 不变量：INV-093（残值与赔偿均入账）、INV-020、INV-021
## 失败：残值 > 已付 → Fault.LEDGER_IMBALANCE
func register_residual(pq: JWProjectQueue, p: int, capital: JWCapital,
                       ledger: JWLedger, accounts: JWAccount) -> int

## S02：合同赔偿（取消时按剩余合同额的 compensation_ppm）。
## 步骤：S02 §2.7
## 前置：defs.exit_compensation_ppm 已加载
## 后置：post(kind=CANCEL_PENALTY, gov → 承包方)；committed_memo 减少
## 不变量：INV-032、INV-093
## 失败：现金不足 → 登记 arrears（业务性短缺），不是故障
func pay_cancel_penalty(pq: JWProjectQueue, p: int, defs: JWPolicyDef, treasury: JWTreasury,
                        ledger: JWLedger, accounts: JWAccount) -> int

## §1.6 状态块协议：全部方法返回空 / 空实现（本类无状态）。
```

---

### 4.21 `sim/policy/policy_engine.gd` · `class_name JWPolicyEngine extends RefCounted`

**职责**：政策的**资格 → 预算预留 → 生效 → 运行费 → 退出**全链路，以及补助的幂等台账。
持有 `state.policy.*` 的运行时状态。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.policy.enabled[]` | `enabled` | `PackedInt64Array` | 12 | 0 | S | 0/1 | S02 |
| `state.policy.enacted_q[]` | `enacted_q` | `PackedInt64Array` | 12 | −1 | S | 季 | S02 |
| `state.policy.effective_from_q[]` | `effective_from_q` | `PackedInt64Array` | 12 | −1 | S | 季 | S02 |
| `state.policy.params_ppm[]` | `params_ppm` | `PackedInt64Array` | 48 | 默认值 | S | ppm | S02 |
| `state.policy.params_uu[]` | `params_uu` | `PackedInt64Array` | 48 | 默认值 | S | μU | S02 |
| `state.policy.pending_params[]` | `pending_params` | `PackedInt64Array` | 48 | 同上 | S | 同上 | **CMD** |
| `state.policy.region_mask[]` | `region_mask` | `PackedInt64Array` | 12 | 0 | S | 位掩码 0..15 | S02 |
| `state.policy.budget_committed_uu[]` | `budget_committed` | `PackedInt64Array` | 12 | 0 | S | μU | S02 |
| `state.policy.budget_spent_uu[]` | `budget_spent` | `PackedInt64Array` | 12 | 0 | S | μU | S04 |
| `state.policy.toggle_count[]` | `toggle_count` | `PackedInt64Array` | 12 | 0 | S | 计数 | S02 |
| `state.policy.cooldown_until_q[]` | `cooldown_until_q` | `PackedInt64Array` | 12 | 0 | S | 季 | S02 |
| `state.policy.claim_ledger[]` | `claim_key` / `claim_amount` | `PackedInt64Array` ×2 | `CLAIM_CAP = 2048` | 0 | S | μU | S04 |
| `state.policy.exit_pending_q[]` | `exit_pending_q` | `PackedInt64Array` | 12 | −1 | S | 季 | S02 |
| `state.policy.opex_landed_uu[]` | `opex_landed` | `PackedInt64Array` | 12 | 0 | S | μU/季 | S02, S07 |
| — | `_blocked_reason` | `PackedInt64Array` | 12 | 0 | D | 枚举 | S02（每季重算） |
| — | `_claim_count` | `int` | — | 0 | S | 台账行数（**只增不减**） | S04 |

#### 方法

```gdscript
## S02 §2.1：命令受理的资格检查链（任一失败即 REJECT，命令仍入档）。
## 步骤：S02 §2.1
## 前置：命令已通过 S01 的格式校验
## 后置：通过 → enacted_q = q，effective_from_q = q + lag（**只能向前**），toggle_count += 1，
##       cooldown_until_q = q + cooldown_q，并 post(kind=POLICY_TOGGLE_COST)；
##       未通过 → 状态完全不变，写 log.rejections
## 不变量：INV-095, INV-098（冷却与单调不回溯）、INV-099、INV-100（blocked_reason != none）、INV-137
## 失败：Reject.AUTHORITY / SEATS_SHORT / BLOC_VETO / POLICY_COOLDOWN / PRECONDITION /
##       NO_SLOT / NO_FUNDING / BUDGET_INSUFFICIENT
func try_enact(p: int, defs: JWPolicyDef, politics: JWPolitics, treasury: JWTreasury,
               pq: JWProjectQueue, capital: JWCapital, ledger: JWLedger, accounts: JWAccount,
               q: int, params: PackedInt64Array) -> int

## S02：撤销政策（退出规则）。
## 步骤：S02 §2.1
## 前置：冷却已过；退出规则可执行
## 后置：enabled = 0；exit_pending_q 设置；已交付资产保留（`delivered_assets: retain`）
## 不变量：INV-098（toggle_count 单调递增，每次开关有真实成本）、INV-032
## 失败：Reject.POLICY_COOLDOWN
func try_repeal(p: int, defs: JWPolicyDef, treasury: JWTreasury, ledger: JWLedger,
                accounts: JWAccount, q: int) -> int

## S02：把玩家提交的 pending_params 落到 params（只在允许修改的窗口内）。
## 步骤：S02 §2.1
## 前置：每项在 valid_range 内（V-PD-09）
## 后置：params_ppm / params_uu 更新；pending_params 清回同值
## 不变量：INV-138（命令不得携带任何直接状态值）、INV-099
## 失败：Reject.PARAM_RANGE
func apply_pending_params(p: int, defs: JWPolicyDef, q: int) -> int

## **政策效应的统一闸门**：任何政策效应函数都必须先过这一关。
## 步骤：全部八步
## 前置：无
## 后置：q < effective_from_q 或 enabled == 0 → 返回 false（零效应）
## 不变量：INV-095（**这是它的唯一实现点**；静态检查：任何读 policy params 的地方
##          必须在同一函数内先调用本函数）
## 失败：无
func is_effective(p: int, q: int) -> bool
func effective_param_ppm(p: int, j: int, q: int) -> int   ## 未生效时恒返回 0

## S04 §4.2：法定转移（P03 等）的应付清单。
## 步骤：S04 §4.2 的 statutory_transfers 档
## 前置：eligible_persons 按 P03 的 eligibility/duration 判定
## 后置：out_due[g] = eligible × benefit_per_person；**不得少算人数装作没人符合资格**
## 不变量：INV-095、INV-003
## 失败：无（现金不足由 treasury 走部分支付 + 欠付）
func transfer_due_into(out_payee_agent: PackedInt64Array, out_due: PackedInt64Array,
                       pop: JWPopulation, labor: JWLaborMarket, defs: JWPolicyDef,
                       q: int, params: PackedInt64Array) -> int

## S04 §4.3：补助的幂等发放（恶意玩家测试 ADV-01 的主防线）。
## 步骤：S04 §4.3
## 前置：claim_key = hash64(policy_id, beneficiary_cell, q, qualifying_investment_id)；
##       前置是「**已发生的实际投资**」（上季 flow.cell.investment_uu > 0 且已付款），
##       不是「政策已开启」
## 后置：同键至多付一次；台账**只增不减**，政策退出也不清零；关停再开启不补发历史季
## 不变量：INV-097（幂等）、INV-096（budget_spent <= budget_committed）、INV-113（补助不进 GDP）
## 失败：重复申领 → 记 duplicate_claim_blocked 并跳过（不是故障）；
##       台账写满 → Fault.INDEX_OUT_OF_RANGE（`CLAIM_CAP` 由 40/120 季规模上界推出）
func pay_subsidy(p: int, cell: int, requested_uu: int, qualifying_event_id: int,
                 investment_prev_uu: int, defs: JWPolicyDef, treasury: JWTreasury,
                 ledger: JWLedger, accounts: JWAccount, q: int) -> int

## S07：把生效政策的效果落到白名单落点（**一切能力类只能落在 *_pending_***）。
## 步骤：S07 §7.1 之后
## 前置：is_effective(p, q) 为真
## 后置：按 effect_target 调 JWCapital.add_pending / JWTreasury.tax_capacity /
##       JWPolitics.admin_capacity / JWPopulation.education_cohort
## 不变量：INV-091、INV-095、V-PD-10/11
## 失败：落点不在白名单 → Fault.WRITE_OUT_OF_SCOPE
func apply_effects(defs: JWPolicyDef, capital: JWCapital, treasury: JWTreasury,
                   politics: JWPolitics, pop: JWPopulation, q: int) -> int

## 政策参数的只读导出（S06 的税率等要用；导出的是**引用**，调用方不得写）。
## 步骤：S06 §6.5/§6.6
## 前置：无
## 后置：不改状态
## 不变量：INV-095（调用方必须先调 is_effective 才能使用某项参数）
## 失败：无
func params_ppm_array() -> PackedInt64Array
func params_uu_array() -> PackedInt64Array

## 无法执行的原因码（政策页必须告诉玩家为什么不能执行）。
## 步骤：S02 末重算
## 前置：无
## 后置：enabled == 0 且玩家可见 ⇒ blocked_reason != NONE
## 不变量：INV-100（且本地化表必须存在对应条目，test_u_blocked_reason_text）
## 失败：无
func blocked_reason(p: int) -> int

## §1.6 状态块协议全部方法（SUBSYS_POLICY）。
```

---

### 4.22 `sim/world/world_market.gd` · `class_name JWWorldMarket extends RefCounted`

**职责**：外部世界（`agent.row` 的业务视图）：出口需求、进口交付能力、外部信用额度、固定汇率、
经常账户。首版**固定汇率、无外币债务、无估值变动**。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `content.world.fx_rate_ppm` | `FX_RATE_PPM`（`const`） | `int` | — | 1 000 000 | C | ppm | **无（写入即 FAULT）** |
| `state.world.export_demand_ppm[]` | `export_demand_ppm` | `PackedInt64Array` | 4 | 剧本 | S | ppm | S01（冲击） |
| `state.world.import_price_ppm[]` | `import_price_ppm` | `PackedInt64Array` | 4 | 剧本 | S | ppm | S01（冲击） |
| `state.world.delivery_capacity_uqs[]` | `delivery_capacity` | `PackedInt64Array` | 4 | 剧本 | S | μQ_s/季 | S01 |
| `state.world.credit_limit_uu` | `credit_limit` | `int` | — | 剧本 | S | μU | S01, S02 |
| `state.world.credit_used_uu` | `credit_used` | `int` | — | 0 | S | μU | S02 |
| `state.world.sovereign_rate_ppm_per_q` | `sovereign_rate_ppm` | `int` | — | 剧本 | S | ppm/季 | S01, S02 |
| `state.world.current_account_uu` | `current_account` | `int` | — | 0 | S | μU | S06 |
| `flow.world.exports_uu` | `f_exports_uu` | `int` | — | 0 | F | μU | S05 |
| `flow.world.exports_uqs[]` | `f_exports_uqs` | `PackedInt64Array` | 4 | 0 | F | μQ_s | S05 |
| `flow.world.imports_uu` | `f_imports_uu` | `int` | — | 0 | F | μU | S05 |
| `flow.world.imports_uqs[]` | `f_imports_uqs` | `PackedInt64Array` | 4 | 0 | F | μQ_s | S05 |
| `content.world.base_export_uqs[]` | `base_export_uqs` | `PackedInt64Array` | 4 | 剧本 | C | μQ_s | LOAD |
| `content.world.base_export_ppm[]` / `base_import_ppm[]` | 同名 | `PackedInt64Array` ×2 | 4 | 剧本 | C | ppm | LOAD |
| `content.world.base_credit_limit_uu` | `base_credit_limit` | `int` | — | 剧本 | C | μU | LOAD |
| — | `_delivery_remaining` | `PackedInt64Array` | 4 | — | F | μQ_s，本季剩余交付额度 | S05 |

#### 方法

```gdscript
## S01 §01.7：冲击落到外部账户（**这是 state.world.* 的唯一被写路径**）。
## 由 JWShocks 调用；每个 setter 都做 clamp 并写 log.clamp。
## 步骤：S01 §01.7
## 前置：调用方是 JWShocks（静态检查：这四个 setter 的调用点只出现在 sim/world/shocks.gd）
## 后置：export_demand ∈ [0, 3e6]；import_price ∈ [1e5, 5e6]；
##       sovereign_rate ∈ [0, 1e5]；credit_limit >= 0
## 不变量：INV-108（冲击只写 world.* 白名单）、INV-105（fx_rate 不可写）
## 失败：越界 → clamp 并写 log.clamp；写 fx_rate 的任何尝试 → Fault.FLOAT_IN_STATE 之外的
##       专用检查：静态检查 + 运行期 `set_fx_rate` **根本不存在**
func set_export_demand(s: int, value_ppm: int) -> int
func set_import_price(s: int, value_ppm: int) -> int
func set_sovereign_rate(value_ppm: int) -> int
func set_credit_limit(value_uu: int) -> int
func set_delivery_capacity(s: int, value_uqs: int) -> int

## S05 入口：重置本季剩余交付额度。
## 步骤：S05 §5.1
## 前置：phase == S05
## 后置：_delivery_remaining == delivery_capacity
## 不变量：INV-104（imports <= delivery_capacity）
## 失败：无
func begin_quarter_delivery() -> void

## S05：登记一笔出口成交（由 JWInventory 在撮合买方类 4 后回调）。
## 步骤：S05 §5.6
## 前置：qty <= min(mul_ppm(base_export_uqs, export_demand_ppm), delivery_capacity)
## 后置：f_exports_* 增加；post(kind=EXPORT, row.cash → 卖方.cash)
## 不变量：INV-026（对外必有 agent.row 对手方）、INV-059
## 失败：无
func record_export(s: int, qty_uqs: int, value_uu: int) -> int

## S05：登记一笔进口（含项目进口设备与企业投资进口设备）。
## 步骤：S05 §5.6、S04 §4.4（项目设备）
## 前置：qty <= _delivery_remaining[s]；买方现金与外部信用额度双重约束
## 后置：_delivery_remaining 扣减；f_imports_* 增加；post(kind=IMPORT)
## 不变量：INV-104（**双重约束**，test_s_import_cap）、INV-026
## 失败：超交付能力 → 按剩余额度成交并记未满足需求（业务性短缺，不是故障）
func record_import(s: int, qty_uqs: int, value_uu: int) -> int
func delivery_remaining(s: int) -> int

## S02：外部融资额度占用与释放（由 JWTreasury 调用）。
## 步骤：S02 §2.6
## 前置：amount <= credit_limit − credit_used
## 后置：credit_used 增加
## 不变量：INV-034
## 失败：超额 → 返回 Reject.CREDIT_LIMIT，不改状态
func use_external_credit(amount_uu: int) -> int

## S06 §6.8：经常账户与对外头寸。
## 步骤：S06 §6.8
## 前置：本季出口、进口、对外利息、对外净借款已确定
## 后置：current_account += 出口 − 进口 − 对外利息 + 对外净借款
## 不变量：INV-106、INV-107（外债 == Σ holder==row 的未偿本金）、INV-110（Δ净头寸 == −(经常+金融)）
## 失败：残差不为 0 → Fault.LEDGER_IMBALANCE
## external_debt_uu 由 JWTurnRunner 取自 bonds.debt_outstanding_of_holder(JWUnits.Holder.ROW)：
## 本类与 JWBondBook 同为秩 4，同秩之间不得互相引用（§3.2/§3.3），故降级成整数形参。
func settle_current_account(external_interest_uu: int, external_net_borrowing_uu: int,
                            external_debt_uu: int, accounts: JWAccount) -> int

## 派生只读（供 S02 定价、S05 出口需求、报告）。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-105（fx 恒定）、INV-107
## 失败：无
func export_demand(s: int) -> int
func import_price(s: int) -> int
func sovereign_rate() -> int
func credit_headroom() -> int
func net_foreign_position(accounts: JWAccount) -> int

## `derived.world.external_debt_uu`（INV-107）**不在本类**：它 == Σ (holder == row)
## bond.principal_outstanding_uu，两个数组由 JWBondBook 持有（规则 R-A），按规则 R-C
## 「派生量由其所有者以纯函数形式提供」，唯一提供者是
##     JWBondBook.debt_outstanding_of_holder(JWUnits.Holder.ROW)
## 本类秩 4 与 JWBondBook 同秩，不得引用它（§3.2/§3.3）。需要该值的调用方自行向 JWBondBook 取。

## §1.6 状态块协议全部方法（SUBSYS_WORLD）。
```

---

### 4.23 `sim/world/shocks.gd` · `class_name JWShocks extends RefCounted`

**职责**：3 类外生冲击的抽样与传导（用 `rng.shock` 流），**抽样写日志、先查日志再抽样**。
持有 `shock_log`（与命令流分开存储，`docs/11` §6.1 规则 7）。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 写入者 |
|---|---|---|---|---|---|---|
| `state.world.shock_active[]` | `active` | `PackedInt64Array` | 3 | 0 | S | S01 |
| `state.world.shock_remaining_q[]` | `remaining_q` | `PackedInt64Array` | 3 | 0 | S | S01 |
| `state.world.shock_magnitude_ppm[]` | `magnitude_ppm` | `PackedInt64Array` | 3 | 0 | S | S01 |
| — | `duration_q` | `PackedInt64Array` | 3 | 0 | S | S01（衰减因子的分母） |
| — | `last_end_q` | `PackedInt64Array` | 3 | −999 | S | S01（min_gap 判定） |
| `shock_log.*` | `sl_q`/`sl_kind`/`sl_mag`/`sl_dur`/`sl_draw_index`/`sl_raw`/`sl_mapped` | `PackedInt64Array` ×7 | `LOG_CAP0` | — | L | S01 |
| `content.shock.*` | `channel`/`target_weights_ppm`/`hazard_ppm`/`earliest_q`/`min_gap_q`/`max_active`/`mag_min`/`mag_max`/`dur_min`/`dur_max`/`onset_profile`/`decay_profile` | `PackedInt64Array` | 3 或 12 | 剧本 | C | LOAD |

#### 方法

```gdscript
## S01 §01.6：本季冲击的到达、衰减与复用。
## **先查 shock_log：已有本 q 的记录则复用且不推进 rng.shock 的计数器**（堵住「存档重载重抽」）。
## 步骤：S01 §01.6
## 前置：按 shock_id 升序遍历（确定性）；rng.begin_quarter(q) 已调用
## 后置：active / magnitude / remaining_q 更新；新抽样追加 shock_log（含 draw_index、raw_u64、mapped_value）
## 不变量：INV-109（先查后抽）、INV-009（与 rng.event 结构性独立）、INV-010、INV-011
## 失败：shock_log 与计数器矛盾 → Fault.RNG_LOG_MISMATCH，终止并保留现场
func resolve_quarter(rng: JWRngStreams, world: JWWorldMarket, q: int,
                     params: PackedInt64Array) -> int

## S01 §01.7：把本季冲击强度按衰减因子折成对 world.* 的增量。
## 步骤：S01 §01.7
## 前置：resolve_quarter 已完成
## 后置：只调 JWWorldMarket 的五个 setter（**不碰任何国内字段**）
## 不变量：INV-108（不得直接写国内账户、产能、库存或人口）、INV-105
## 失败：本函数若引用任何 state.cell / state.group / state.gov 字段 → 静态检查失败
func apply_to_world(world: JWWorldMarket, q: int, params: PackedInt64Array) -> int

## 重放与读档：把存档里的 shock_log 灌回来。
## 步骤：LOAD
## 前置：行数与 manifest 一致
## 后置：后续 resolve_quarter 在同 q 会复用记录
## 不变量：INV-109、INV-131、INV-133（save→load→advance 与 advance 逐位相同）
## 失败：格式不符 → Load.SAVE_CORRUPT
func load_shock_log(rows: PackedInt64Array) -> JWResult
func export_shock_log() -> PackedInt64Array

## 只读（报告与诊断）。
## 步骤：全部
## 前置：k ∈ [0,3)
## 后置：不改状态
## 不变量：INV-109
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func is_active(k: int) -> bool
func magnitude(k: int) -> int
func remaining(k: int) -> int

## §1.6 状态块协议 + §1.7 日志协议全部方法（SUBSYS_WORLD）。
```

---

### 4.24 `sim/politics/politics.gd` · `class_name JWPolitics extends RefCounted`

**职责**：**票**（支持度与席位）、行政能力、留任与终局判定，以及群组的三个主观量。
**INV-125 的结构性落地**：本类**不引用** `JWInterestGroups` 的任何字段，
`seat_rule()` 也不引用 `admin_capacity_ppm`；三种权力由三个类、三个函数分别计算。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.group.living_index_ppm[]` | `living_index` | `PackedInt64Array` | 36 | 1 000 000 | S | ppm | S08 |
| `state.group.expectation_ppm[]` | `expectation` | `PackedInt64Array` | 36 | 剧本 | S | ppm | S08 |
| `state.group.trust_ppm[]` | `trust` | `PackedInt64Array` | 36 | 剧本 | S | ppm | S08 |
| `state.group.support_ppm[]` | `support` | `PackedInt64Array` | 36 | 剧本 | S | ppm | S08 |
| — | `keep_streak_q` | `PackedInt64Array` | 36 | 0 | S | 季 | S08 |
| `state.politics.seats_total` | `seats_total` | `int` | — | 剧本（奇数） | S | 席 | LOAD |
| `state.politics.seats_gov` | `seats_gov` | `int` | — | 剧本 | S | 席 | S08 |
| `state.politics.term_index` | `term_index` | `int` | — | 0 | S | — | S08 |
| `state.politics.next_election_q` | `next_election_q` | `int` | — | 15 | S | 季 ∈ {15, 31} | S08 |
| `state.politics.next_budget_review_q` | `next_budget_review_q` | `int` | — | 3 | S | 季，`q ≡ 3 (mod 4)` | S02 |
| `flow.politics.budget_review_due` | `f_budget_review_due` | `int` | — | 0 | F | 0/1 | S02 |
| `state.politics.mandate_goal` | `mandate_goal` | `int` | — | 开局选择 | S | 枚举 | LOAD |
| `state.politics.mandate_status` | `mandate_status` | `int` | — | OK | S | 枚举 | S08 |
| `state.politics.admin_capacity_ppm` | `admin_capacity_ppm` | `int` | — | 剧本 | S | ppm | S07 |
| `state.politics.legal_authority_mask` | `legal_authority_mask` | `int` | — | 剧本 | S | 位掩码 | S08 |
| `state.meta.run_terminated` | `run_terminated` | `bool` | — | false | S | — | S08 |
| `state.meta.termination_reason` | `termination_reason` | `int` | — | NONE | S | 枚举 | S08 |
| — | `_support_decomp` | `PackedInt64Array` | 108（36×3） | 0 | L | ppm，三项贡献分解 | S08 |
| — | `_at_risk_streak_q` | `int` | — | 0 | S | 季 | S08 |

#### 方法

```gdscript
## S02 §2.8：预算审查标记（判定在 S08）。
## 步骤：S02 §2.8
## 前置：q == next_budget_review_q
## 后置：f_budget_review_due = 1；next_budget_review_q += 4
## 不变量：INV-127（预算审查在 q ≡ 3 (mod 4)）
## 失败：无
func mark_budget_review(q: int) -> int

## S02：政策资格链里的「权限 / 席位 / 集团否决」判定（只读，不改状态）。
## 注意：**集团立场作为形参传入**（`bloc_stance_ppm` 数组），本类不引用 JWInterestGroups（INV-125）。
## 步骤：S02 §2.1
## 前置：authority_bit 与 min_seats_ppm 来自 JWPolicyDef
## 后置：不改状态
## 不变量：INV-099、INV-125
## 失败：返回 Reject.AUTHORITY / SEATS_SHORT / BLOC_VETO
func check_authority(authority_bit: int, min_seats_ppm: int, veto_bloc_mask: int,
                     bloc_stance_ppm: PackedInt64Array, policy_idx: int) -> int

## S07：行政执行能力更新（只被 P11 类政策与事件影响）。
## 步骤：S07（政策效果落点）
## 前置：delta 来自白名单落点
## 后置：admin_capacity_ppm ∈ [0, 1_000_000]
## 不变量：INV-125（**实施速度函数只引用 admin_capacity_ppm**；它不进 support 公式）
## 失败：无
func set_admin_capacity(value_ppm: int) -> int

## S08 §8.1：三个主观量**分开更新**（生活 / 预期 / 信任）。
## 步骤：S08 §8.1
## 前置：breach_count 由 JWTurnRunner 从欠付、欠拨、项目取消、债券违约四个闭集合事件汇总；
##       consumer_index 来自 JWPricing
## 后置：三者各自 clamp 到自己的区间；keep_streak 更新
## 不变量：INV-121（三者分开存储、分开更新，禁止合成单一满意度）、
##          INV-122（**trust 的更新式里结构上不存在 transfer_income 通道**；
##          且 param.trust_recover_ppm < param.trust_drop_ppm，加载期校验）
## 失败：主观量越界 → clamp 并写 log.clamp
func update_subjective(pop: JWPopulation, pricing: JWPricing,
                       breach_count_by_group: PackedInt64Array, params: PackedInt64Array) -> int

## S08 §8.2：支持度（三项加权）与来源分解。
## 步骤：S08 §8.2
## 前置：三项权重之和 == 1 000 000（加载期校验）
## 后置：support ∈ [0, 1e6]；**逐组 support 必须保留**（禁止只保留全国值）；
##       每次变动写 log.explanations 的三项贡献
## 不变量：INV-123（变动有来源分解）、INV-124（全国值只由逐组按人口最大余数法加权）、INV-125
## 失败：无来源记录 → Fault.SUPPORT_UNEXPLAINED
func update_support(pop: JWPopulation, params: PackedInt64Array) -> int
func support_national_ppm(pop: JWPopulation) -> int
func support_region_ppm(pop: JWPopulation, r: int) -> int

## 席位转换规则（**纯函数**，OQ-221 的首版取法：按支持度比例 + 最大余数法）。
## 步骤：S08 §8.5
## 前置：support_national_ppm ∈ [0, 1e6]；seats_total > 0 且为奇数
## 后置：0 <= seats_gov <= seats_total；整数、最大余数法
## 不变量：INV-126（纯函数）、INV-125（**静态检查：本函数不引用 org_power_ppm 与 admin_capacity_ppm**）
## 失败：无
static func seat_rule(support_national_ppm: int, seats_total: int) -> int

## S08 §8.5：预算审查、选举、留任与终局。
## 步骤：S08 §8.5
## 前置：选举只在 q ∈ {15, 31}；审查在 f_budget_review_due == 1 的季
## 后置：seats_gov 更新；`seats_gov * 2 <= seats_total` ⇒ 终止（刚好过半算失去）；
##       连续 no_confidence_q 季 mandate_status == LOST ⇒ 终止；
##       连续 default_grace_q 季付不出第 1 档 ⇒ 终止；q == horizon_q − 1 ⇒ 终止
## 不变量：INV-127（选举与审查季度）、INV-128（**终局判定式中不含任何 GDP 项**，静态检查；
##          终止后任何 advance_quarter 返回 REJECT 且状态哈希不变）
## 失败：无（终止是正常结果，不是故障）
func review_and_terminate(treasury: JWTreasury, pop: JWPopulation, q: int, horizon_q: int,
                          default_streak_q: int, params: PackedInt64Array) -> int

## 事件效果落点（只允许白名单内的 ppm 增量）。
## 步骤：S08 §8.4
## 前置：target ∈ {expectation_ppm, trust_ppm, support_ppm, admin_capacity_ppm}
## 后置：对应字段加 delta 后 clamp
## 不变量：INV-130（事件不得直接写现金、库存、产能、人口；首版事件无任何账本效应）
## 失败：target 不在白名单 → Fault.WRITE_OUT_OF_SCOPE
func apply_event_delta(target_code: int, scope_idx: int, delta_ppm: int) -> int

## §1.6 状态块协议全部方法（四个主观量归 SUBSYS_GROUP，其余归 SUBSYS_POLITICS；
## run_terminated / termination_reason 归 SUBSYS_META）。
```

---

### 4.25 `sim/politics/interest_groups.gd` · `class_name JWInterestGroups extends RefCounted`

**职责**：3 个集团的**成员规模与组织资源随经济结构动态推导**、对各政策的立场。
**组织影响力（`org_power_ppm`）与票、行政能力是三套独立计算**（INV-125）。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 单位 | 写入者 |
|---|---|---|---|---|---|---|---|
| `state.bloc.org_power_ppm[]` | `org_power` | `PackedInt64Array` | 3 | 剧本 | S | ppm | S08 |
| `state.bloc.stance_ppm[]` | `stance` | `PackedInt64Array` | 36 | 剧本 | S | ppm ∈ [−1e6, 1e6] | S08 |
| `state.bloc.resource_uu[]` | `resource` | `PackedInt64Array` | 3 | 剧本 | S | μU | S08 |
| — | `care_prev` | `PackedInt64Array` | 3 | 0 | S | 各集团「关心指标」的上季值 | S08 |
| `content.bloc.veto_domains[]` | `veto_domain_mask` | `PackedInt64Array` | 3 | 剧本 | C | 位掩码 | LOAD |
| `content.bloc_affiliation_ppm[]` | `affiliation_ppm` | `PackedInt64Array` | 108 | 剧本 | C | ppm（允许 Σ > 1e6） | LOAD |

#### 方法

```gdscript
## S08 §8.3：集团反应（关心指标变化 → 立场；规模与资源 → 组织力）。
## 三个「关心指标」：agri_coop → 农业 cell 的 value_added_real 之和；
## business → 全部 cell 的 profit_pretax 之和；labor_public → 全国就业 + 公共服务可用率的人口加权。
## 步骤：S08 §8.3
## 前置：三项权重（inertia + w_size + w_resource）之和 == 1 000 000（加载期校验）
## 后置：stance ∈ [−1e6, 1e6]；org_power ∈ [0, 1e6]；care_prev 更新
## 不变量：INV-125（**本函数不引用 support_ppm 与 admin_capacity_ppm**，静态检查）、
##          INV-129（成员规模由群组人口映射得出，允许重叠，必须以「加权人数」口径展示）
## 失败：care_prev == 0 → 用 max(|care_prev|, 1)，不除零
func update_blocs(sectors: JWSectorModel, labor: JWLaborMarket, capital: JWCapital,
                  pop: JWPopulation, newly_effective_mask: int, defs: JWPolicyDef,
                  params: PackedInt64Array) -> int

## 加权成员规模（derived.bloc.membership_persons，纯函数）。
## 步骤：S08、报告
## 前置：affiliation_ppm 已加载
## 后置：不改状态
## 不变量：INV-129（**是加权人数不是人头**，OQ-223；展示层必须标注）
## 失败：无
func membership_persons(pop: JWPopulation, b: int) -> int

## 立场读取（供 JWPolicyEngine 的资格链与 JWPolitics.check_authority 使用）。
## 注意：调用方向是**别人读本类**，本类不读别人（除 §4.25 的四个经济指标源）。
## 步骤：S02
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-125
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func stance_of(b: int, p: int) -> int
func stance_array() -> PackedInt64Array
func org_power(b: int) -> int
func has_veto(b: int, policy_idx: int) -> bool

## 事件效果落点（org_power_ppm 与 stance_ppm 两项）。
## 步骤：S08 §8.4
## 前置：target ∈ {org_power_ppm, stance_ppm}
## 后置：加 delta 后 clamp
## 不变量：INV-130
## 失败：target 不在白名单 → Fault.WRITE_OUT_OF_SCOPE
func apply_event_delta(target_code: int, scope_idx: int, delta_ppm: int) -> int

## §1.6 状态块协议全部方法（SUBSYS_POLITICS）。
```

**结构性说明**：`stance` 只影响改革可行性与议程，**不直接进 `support`**
（「反对某政策不会自动等同于反对政府的一切」）。这一点由依赖方向保证：
`JWPolitics.update_support()` 的形参表里没有本类的任何东西。

---

### 4.26 `sim/report/diagnostics.gd` · `class_name JWDiagnostics extends RefCounted`

**职责**：全部 `derived.*` 的汇总与一致性比对、约束诊断与溯源、结构化复盘。
**只读。任何 S01…S08 的结算路径都不得调用本类**（§3.1 规则 R-C，静态检查）。
唯一例外：S08 末 `JWTurnRunner` 调 `snapshot_and_verify()`。

#### 成员变量（全部 `derived.*`，类 = D，**不进 `state_hash`**）

| 稳定 ID | 成员 | 类型 | 长度 | 单位 |
|---|---|---|---|---|
| `derived.gdp.production_uu` | `gdp_production` | `int` | — | μU（**权威口径**） |
| `derived.gdp.expenditure_uu` | `gdp_expenditure` | `int` | — | μU |
| `derived.gdp.income_uu` | `gdp_income` | `int` | — | μU |
| `derived.gdp.price_variance_total_uu` | `price_variance_total` | `int` | — | μU |
| `derived.gdp.real_uu` | `gdp_real` | `int` | — | μU（基年价） |
| `derived.gdp.annual_nominal_uu` | `gdp_annual_nominal` | `int` | — | μU（滚动四季） |
| — | `_gdp_history` | `PackedInt64Array` | 4 | μU，滚动四季缓冲 |
| `derived.labor.unemployment_ppm` | `unemployment_ppm` | `int` | — | ppm |
| `derived.fiscal.debt_to_gdp_ppm` | `debt_to_gdp_ppm` | `int` | — | ppm |
| `derived.fiscal.debt_service_ratio_ppm` | `debt_service_ratio_ppm` | `int` | — | ppm |
| `derived.fiscal.next4q_debt_service_uu` | `next4q_debt_service` | `int` | — | μU |
| `derived.living.consumption_index_ppm` | `living_consumption_index` | `int` | — | ppm |
| `derived.living.public_service_index_ppm` | `living_service_index` | `int` | — | ppm |
| `derived.income_quantile_uu[5]` | `income_quantile` | `PackedInt64Array` | 5 | μU |
| `derived.region.*` / `derived.group.*` / `derived.cell.*` | `region_population` / `labor_force` / `electricity_availability` / `housing_occupied` / `slots_used` / `capacity_value_drift` | `PackedInt64Array` | 4 / 36 / 4 / 4 / 4 / 16 | 各自单位 |
| `log.explanations.*` | `e_entity`/`e_cause`/`e_amount`/`e_qty`/`e_q`/`e_constraint`/`e_kind` | `PackedInt64Array` ×7 | `LOG_CAP0` | — |
| — | `_derived_hash_prev` | `int` | — | INV-014 的重算比对缓存 |

#### 方法

```gdscript
## S06 §6.4：GDP 三口径与价差调节项。
## 步骤：S06 §6.4（由 JWTurnRunner 在 S06 末调用，只读状态、只写 derived.*）
## 前置：本季全部分录已写；三分类码完备（INV-114 已通过）
## 后置：gdp_production = Σ value_added + Σ pubserv(wage + dep)；
##       gdp_expenditure = C + G + I + dINV + X − M；
##       price_variance_total = Σ 入库交易的 (qty − value)
## 不变量：INV-111, INV-112（禁止 Σ 销售额）, INV-115（残差恰为 0）, INV-116, INV-117,
##          INV-118（无命令跑满基年四季 Σ == 100 000 000 μU，容差 0）, INV-119
## 失败：INV-115 残差 != 0 → Fault.GDP_IDENTITY；
##       全国 gdp_production <= 0 → Fault.GDP_IDENTITY（模型已发散，OQ-219）
func compute_gdp(sectors: JWSectorModel, capital: JWCapital, inventory: JWInventory,
                 world: JWWorldMarket, treasury: JWTreasury, ledger: JWLedger) -> int

## S06：财政派生量（债务/GDP、偿债率、未来四季到期）。
## 步骤：S06 末
## 前置：compute_gdp 已完成
## 后置：三项写入；**债务/GDP 单独展示并注明不能替代偿付能力分析**
## 不变量：INV-038（偿债率是新发债利率的单调输入）
## 失败：gdp == 0 → 用 max(gdp,1)，不除零
func compute_fiscal(bonds: JWBondBook, treasury: JWTreasury, q: int) -> int

## S08：收入五分位近似（**不存在精确基尼系数字段**）。
## 步骤：S08
## 前置：各组可支配收入已算出
## 后置：income_quantile[5] 写入
## 不变量：INV-120（近似量，展示必须标注「未模拟组内差异」；静态检查无 gini 字段）
## 失败：无
func compute_income_quantiles(pop: JWPopulation) -> int

## S08 §8.6：结构化复盘（三类信息严格分栏）。
## 步骤：S08 §8.6
## 前置：kind ∈ {ACCOUNTED, INFERRED, PROJECTED}
## 后置：三类分别写入 log.explanations；
##       accounted 可下钻到分录；inferred 只给 binding_code 与五项约束值（**多个瓶颈不做相加**）；
##       projected 必须标注假设
## 不变量：INV-140（三类分离；**projected 条目禁止回写任何状态字段**，静态检查）、INV-123
## 失败：projected 条目触碰状态 → 静态检查失败（构建期）
func add_explanation(kind: int, entity: int, cause: int, amount_uu: int, qty_uqs: int,
                     constraint_code: int, q: int) -> void

## 情景预测结果的登记口（**跑预测的是 Application 层的 JWGame.preview_four_quarters()**，
## 它用 duplicate_state() + JWTurnRunner 空命令跑 4 季；SimCore 不认识 systems/，故本类只收结果）。
## 步骤：S08 §8.6（可按 OQ-230 缓存或降频）
## 前置：value 来自同一个 SimCore 的副本推进结果，**不得来自任何第二套近似模型**
## 后置：写入 kind == PROJECTED 的 log.explanations 条目
## 不变量：INV-140（projected 条目禁止回写任何状态字段，静态检查）
## 失败：无
func record_projection(q_offset: int, metric_code: int, value: int) -> void

## 季末：全部 derived.* 重算并与本季已写值比对（调试构建每季，发布构建抽季）。
## 步骤：S08 末
## 前置：本季结算已完成
## 后置：不改任何 state.* / flow.*
## 不变量：INV-014（派生一致性）
## 失败：不一致 → Fault.LEDGER_IMBALANCE，detail_a = 派生量编号
## 形参 == compute_gdp / compute_fiscal / compute_income_quantiles 三者形参的并集：
## 本类秩 9，不得引用秩 10 的 JWSimState（规则 R-B），故由 JWTurnRunner 逐个传入域类。
func snapshot_and_verify(sectors: JWSectorModel, capital: JWCapital, inventory: JWInventory,
                         world: JWWorldMarket, treasury: JWTreasury, ledger: JWLedger,
                         bonds: JWBondBook, pop: JWPopulation, q: int) -> int

## §1.6 状态块协议：本类只实现 allocate()；`derived.*` 与 `log.explanations` 都**不进 state_hash**
## （`docs/10` §11 的哈希排除清单），因此 STATE_/FLOW_ 注册表为空。
```

---

### 4.27 `sim/state/sim_state.gd` · `class_name JWSimState extends RefCounted`

**职责**：**权威状态根**。持有全部域类实例、`state.meta.*` 与 `state.time.*`、
参数数组，并实现规范化编码、`state_hash` / `subsystem_hash`、流量整表清零、`to_dict` / `from_dict`。
**它是 `sim/` 里唯一认识其它全部域类的文件；反过来没有任何域类认识它**（§3.1 规则 R-B）。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 初值 | 类 | 写入者 |
|---|---|---|---|---|---|
| `state.meta.schema_version` | `schema_version` | `int` | 代码常量 | S | LOAD/MIG |
| `state.meta.build_id` | `build_id` | `String` | 构建期注入 | S | LOAD |
| `state.meta.content_hash` | `content_hash` | `String` | 载入时计算 | S | LOAD |
| `state.meta.state_hash_prev` | `state_hash_prev` | `String` | "" | S | S01 |
| `state.meta.scenario_id` | `scenario_id` | `String` | 剧本 | S | LOAD |
| `state.meta.param_set_version` | `param_set_version` | `int` | 剧本 | S | LOAD |
| `state.meta.replay_unreliable` | `replay_unreliable` | `bool` | false | S | LOAD |
| `state.meta.command_seq` | `command_seq` | `int` | 0 | S | CMD |
| `state.meta.entity_seq` | `entity_seq` | `int` | 0 | S | S02, S07 |
| `state.time.q` | `q` | `int` | 0 | S | **仅 S08 末 +1** |
| `state.time.horizon_q` | `horizon_q` | `int` | 40 或 120 | S | LOAD |
| `state.time.phase` | `phase` | `int` | IDLE | S | S01..S08 |
| `scenario.total_cash_uu` | `total_cash_uu` | `int` | 剧本 | C | LOAD |
| `param.*` | `params` | `PackedInt64Array`（长 `PARAM_N`） | 参数包 | C | LOAD |
| — | `rng` | `JWRngStreams` | 构造 | — | LOAD |
| — | `accounts` | `JWAccount` | 构造 | — | LOAD |
| — | `ledger` | `JWLedger` | 构造 | — | LOAD |
| — | `io` | `JWIoTable` | 构造 | — | LOAD |
| — | `policy_defs` | `JWPolicyDef` | 构造 | — | LOAD |
| — | `pricing` | `JWPricing` | 构造 | — | LOAD |
| — | `bonds` | `JWBondBook` | 构造 | — | LOAD |
| — | `capital` | `JWCapital` | 构造 | — | LOAD |
| — | `pop` | `JWPopulation` | 构造 | — | LOAD |
| — | `world` | `JWWorldMarket` | 构造 | — | LOAD |
| — | `treasury` | `JWTreasury` | 构造 | — | LOAD |
| — | `labor` | `JWLaborMarket` | 构造 | — | LOAD |
| — | `shocks` | `JWShocks` | 构造 | — | LOAD |
| — | `inventory` | `JWInventory` | 构造 | — | LOAD |
| — | `projects` | `JWProjectQueue` | 构造 | — | LOAD |
| — | `migration` | `JWMigration` | 构造 | — | LOAD |
| — | `politics` | `JWPolitics` | 构造 | — | LOAD |
| — | `sectors` | `JWSectorModel` | 构造 | — | LOAD |
| — | `commissioning` | `JWAssetCommissioning` | 构造 | — | LOAD |
| — | `policy` | `JWPolicyEngine` | 构造 | — | LOAD |
| — | `blocs` | `JWInterestGroups` | 构造 | — | LOAD |
| — | `diag` | `JWDiagnostics` | 构造 | — | LOAD |
| — | `_blocks` | `Array[RefCounted]` | 按上表顺序（**顺序进哈希，不得重排**） | — | LOAD |

#### 方法

```gdscript
## 一次性分配全部数组到 §2 的契约长度。此后长度永不改变。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：每个块的 allocate() 都跑过；不再有任何 resize
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate_all() -> void

## S01 §01.3：遍历流量注册表整表清零。**这是全局唯一允许整表清零流量的地方**。
## 步骤：S01 §01.3
## 前置：phase == S01
## 后置：全部 flow.* 为 0；随后 flow_abs_sum_all() 必须为 0
## 不变量：INV-013；清零后非零 → 说明有步骤在 S08 之后写了流量
## 失败：Fault.FLOW_NOT_RESET
func reset_all_flows() -> int
func flow_abs_sum_all() -> int

## `q` 的唯一写入点（INV-012 的静态检查锚点）。
## 步骤：S08 §8.7
## 前置：phase == S08；本季全部步骤已完成
## 后置：q += 1
## 不变量：INV-012（`state.time.q` 只在 S08 末 +1，无其它写入路径）
## 失败：phase 不对 → Fault.PHASE_VIOLATION
func advance_quarter_index() -> int

## 运行期实体 ID 的唯一来源（单调计数器）。
## 步骤：S02（债券、项目）、S07
## 前置：无
## 后置：entity_seq += 1，返回新值
## 不变量：INV-010（**禁止时间戳、指针地址、哈希**）
## 失败：无
func next_entity_seq() -> int

## 规范化编码（`CanonicalEncoder` 的唯一实现，`docs/10` §11 / `docs/11` §6.4）。
## 步骤：每季末、存档、WriteGuard
## 前置：buf 是调用方提供的缓冲（热路径不新建）
## 后置：条目按**稳定 ID 的字节序升序**拼接；
##       int64 小端 8 字节；数组 = uint32 长度 + 逐元素 8 字节；
##       字符串 = uint32 字节长度 + UTF-8（仅用于 SoA 的 ids[]）
## 不变量：INV-001（遇 float 抛 E_FLOAT_IN_STATE）、INV-014
## 失败：遇 float → Fault.FLOAT_IN_STATE
static func canon_scalar(buf: PackedByteArray, id_utf8: PackedByteArray, v: int) -> void
static func canon_array(buf: PackedByteArray, id_utf8: PackedByteArray, a: PackedInt64Array) -> void
static func canon_string(buf: PackedByteArray, id_utf8: PackedByteArray, s: String) -> void
static func sha256_hex(buf: PackedByteArray) -> String

## 全状态哈希与子系统哈希。
## 步骤：S01 入口（记 prev）、每步末（WriteGuard）、S08 末、存档
## 前置：无
## 后置：不改状态
## 不变量：INV-014（同构建 + 同内容 + 同种子 + 同命令流 ⇒ 每季逐位相同）；
##       排除清单：`state.meta.state_hash_prev` 自身、全部 `log.*`、全部 `derived.*`、
##       一切 `label_zh` / `desc_zh` / `report_template_id` / 时间戳
## 失败：无
func state_hash() -> String
func subsystem_hash(subsys: int) -> String

## 事件触发条件的 metric 求值（**只有比较，没有表达式器**）。
## 步骤：S08 §8.4（由 JWEventEngine 调用）
## 前置：metric_code 已在加载期解析成整数码（V-EV-02）
## 后置：不改状态
## 不变量：INV-130；`docs/11` §5.13 的 V-EV-02/03
## 失败：未知 metric → Fault.METRIC_UNKNOWN 返回 0
func read_metric(metric_code: int, scope_idx: int) -> int

## 序列化与反序列化（`docs/11` §6.4 的 scalars / arrays / soa 三段）。
## 步骤：存档 / 读档（冷路径）
## 前置：to_dict 无前置；from_dict 要求 schema_version 已迁移到当前版本
## 后置：from_dict 之后立即重算 state_hash 并与档内值比对
## 不变量：INV-131（存档含全部跨季状态 + root_seed + 6 个计数器 + 完整命令流）、
##          INV-132（不符即 E_SAVE_CORRUPT 拒绝载入，**不做尽力修复**）
## 失败：Load.SAVE_CORRUPT / Load.SAVE_VERSION_TOO_NEW
func to_dict() -> Dictionary
func from_dict(src: Dictionary) -> JWResult

## 只读深拷贝（情景预测与对账页用；**不在热路径调用**）。
## 步骤：S08 §8.6、UI 对账页
## 前置：无
## 后置：返回一个与本对象逐位相同、互不共享数组的副本
## 不变量：docs/12 §14（每季 duplicate 整份状态是被结构性排除的风险）
## 失败：无
func duplicate_state() -> JWSimState

## 全部 P0 不变量的统一检查入口（载入后、每季末、故障包导出前）。
## 步骤：LOAD 末、季末
## 前置：无
## 后置：不改状态
## 不变量：INV-015..021, 024, 025, 027, 028, 035, 047, 071, 083 …（完整清单见 docs/12 §10）
## 失败：返回第一个失败的 Fault 码；**不回滚到「看起来正常」的状态**
func check_all_p0() -> int
```

---

### 4.28 `systems/commands.gd` · `class_name JWCommands extends RefCounted`

**职责**：命令定义、序列化（JSON Lines）、**形状与范围校验**，以及命令缓冲与 `log.rejections`。
**语义校验（权限、冷却、资金）不在这里**——那是 S02 的 `JWPolicyEngine`。
命令是玩家意图，不是状态变更；它是重放的唯一输入（除 `root_seed` 与内容包外）。

#### 成员变量（列式命令缓冲，自开局起全量保留）

| 稳定 ID | 成员 | 类型 | 长度 | 类 | 含义 | 写入者 |
|---|---|---|---|---|---|---|
| — | `c_command_id` | `PackedInt64Array` | `CMD_CAP = 4096` | S | 单调递增、不跳号 | CMD |
| — | `c_issued_q` | `PackedInt64Array` | 同 | S | 提交季 | CMD |
| — | `c_kind` | `PackedInt64Array` | 同 | S | 命令码 1..12, 99 | CMD |
| — | `c_arg` | `PackedInt64Array` | `CMD_CAP * 6` | S | 6 个整数参数槽 | CMD |
| — | `c_accepted` | `PackedInt64Array` | 同 | S | 0/1 | CMD, S01, S02 |
| — | `c_reject_code` | `PackedInt64Array` | 同 | S | `JWResult.Reject` | CMD, S01, S02 |
| — | `count` | `int` | — | S | 命令条数 | CMD |
| `log.rejections.*` | `r_command_id`/`r_code`/`r_detail` | `PackedInt64Array` ×3 | `LOG_CAP0` | L | — | CMD, S01, S02 |

命令参数一律是**整数槽**：政策/项目/债券的 ID 在 `LOAD` 期已解析成下标，
`region_mask`、`scale_ppm`、`funding_source`、`order[]` 等也都是整数。**命令流里没有字符串状态值**。

#### 命令码（`docs/11` §6.1，值不得改）

```gdscript
enum Kind { POLICY_ENACT = 1, POLICY_SET_PARAMS = 2, POLICY_REPEAL = 3, PROJECT_LAUNCH = 4,
            PROJECT_CANCEL = 5, PROJECT_DEFER = 6, BUDGET_REALLOCATE = 7, ISSUE_BOND = 8,
            DEBT_RESTRUCTURE = 9, SET_PAYMENT_PRIORITY = 10, SET_STANDING_RULE = 11,
            SELECT_MANDATE_GOAL = 12, ADVANCE_QUARTER = 99 }
```

#### 方法

```gdscript
## 提交一条命令（UI → 应用层的唯一入口，经 JWGame 转发）。
## 步骤：CMD（季度推进之外）
## 前置：kind 合法；参数槽数量匹配；**命令不得携带任何直接状态值**
## 后置：无论接受还是拒绝都进缓冲并消耗序号；被拒时写 log.rejections 且**状态哈希完全不变**
## 不变量：INV-137（被拒命令仍入档并记原因码）、INV-138（无 set_cash/set_gdp/set_support 之类字段）、
##          `docs/11` §6.1 规则 1（(issued_q, command_id) 是全序主键，不跳号）
## 失败：Reject.DIRECT_STATE_WRITE / PARAM_RANGE / COMMAND_ORDER；缓冲满 → 扩容
func submit(kind: int, args: PackedInt64Array, issued_q: int, defs: JWPolicyDef) -> JWResult

## S01 §01.5：按 (issued_q, command_id) 升序做只判定不执行的校验。
## 步骤：S01 §01.5
## 前置：本季命令已全部提交
## 后置：c_accepted 与 c_reject_code 写好；被拒命令不进执行队列但仍在命令流里
## 不变量：INV-137、INV-008（遍历顺序确定）
## 失败：不返回业务失败；格式非法的命令逐条 REJECT 并继续
func validate_batch(q: int, defs: JWPolicyDef) -> int

## 取本季待执行命令（S02 受理时按同一顺序遍历）。
## 步骤：S02 §2.1
## 前置：validate_batch 已完成
## 后置：out_idx 按 (issued_q, command_id) 升序填充
## 不变量：INV-008
## 失败：无
func accepted_this_quarter_into(out_idx: PackedInt64Array, q: int) -> int

## `advance_quarter` 的位置约束：每季恰好一条且为该季最后一条。
## 步骤：CMD / S01
## 前置：无
## 后置：不改状态
## 不变量：`docs/11` §6.1 的 kind 99 校验
## 失败：多于一条或不在末尾 → Reject.COMMAND_ORDER
func check_advance_marker(q: int) -> int

## JSON Lines 读写（冷路径；**追加写，自动保存 O(1)**）。
## 步骤：存档 / 读档
## 前置：路径可写；单行损坏只丢一条
## 后置：格式逐字符合 `docs/11` §6.1 的示例
## 不变量：INV-131（存档含完整命令流，含被拒命令）
## 失败：Load.FILE_FORMAT / Load.SAVE_CORRUPT
func append_jsonl(path: String, index: int) -> JWResult
func load_jsonl(path: String, ids: JWIds) -> JWResult

## 命令流哈希（replay_hash，供 manifest 与重放交叉验证）。
## 步骤：存档
## 前置：无
## 后置：不改状态
## 不变量：INV-133
## 失败：无
func command_log_hash() -> String

## §1.6 状态块协议全部方法。**注意**：命令缓冲本身**不进 `state_hash`**
## —— 它单独序列化为 `commands.jsonl`（`docs/11` §6.2），进 `replay_hash`；
## 进 `state_hash` 的只有 `JWSimState` 持有的 `state.meta.command_seq`。
## `log.rejections` 同样不进 `state_hash`（`docs/10` §11 排除清单）。
```

---

### 4.29 `systems/turn_runner.gd` · `class_name JWTurnRunner extends RefCounted`

**职责**：八步固定顺序结算的**唯一编排者**，WriteGuard，步骤哈希，故障处置。
**它是全系统唯一持有全部 scratch 数组的地方**（热路径不分配）。

#### 成员变量

| 成员 | 类型 | 长度 | 含义 |
|---|---|---|---|
| `_st` | `JWSimState` | — | 构造注入 |
| `_events` | `JWEventEngine` | — | 构造注入 |
| `_step_hash` | `PackedStringArray` | 8 | 本季 8 个步骤哈希（写 `checkpoints.jsonl`） |
| `_guard_hash` | `PackedStringArray` | 15 | 进入某步前对不可写子系统取的哈希 |
| `_sc_payee` / `_sc_due` / `_sc_paid` | `PackedInt64Array` ×3 | 60 | 支付拆分 scratch |
| `_sc_weights` / `_sc_tiebreak` / `_sc_out` | `PackedInt64Array` ×3 | 256 | 最大余数法 scratch |
| `_sc_cell` | `PackedInt64Array` | 16 | cell 级中间量 |
| `_sc_group` | `PackedInt64Array` | 36 | 群组级中间量 |
| `_sc_group_slot` | `PackedInt64Array` | 180 | 群组×岗位中间量 |
| `_sc_market` | `PackedInt64Array` | 20 | 市场需求／成交 scratch |
| `_sc_project` | `PackedInt64Array` | `PROJECT_CAP0 * 4` | 项目付款 scratch |
| `_sc_breach` | `PackedInt64Array` | 36 | 本季失信计数（S08 输入） |
| `_sc_taxable` | `PackedInt64Array` | 16 | 应税利润（S06 中转） |
| `_sc_distributable` | `PackedInt64Array` | 16 | 可分配利润（S06 中转） |

全部 scratch 在构造期 `resize()` 一次，**每步入口 `fill(0)`**。

#### 方法

```gdscript
## 推进一个季度：八步顺序固定、不可重入、不可回退。
## 步骤：S01..S08 全程
## 前置：!run_terminated；phase == IDLE；本季命令已提交且含恰好一条 advance_quarter
## 后置：成功 → phase 回到 IDLE 且 q 已 +1；失败 → 停在故障步，状态保留现场
## 不变量：INV-012（严格单向推进）、INV-013（每步只写可写子集）、INV-014（逐季哈希可复现）
## 失败：run_terminated → Reject.RUN_TERMINATED（**状态哈希不变**，INV-128）；
##       phase != IDLE → Reject.PHASE_BUSY；任一 Fault → 停止推进、导出故障包、
##       **不回滚到「看起来正常」的状态**
func advance_quarter(cmds: JWCommands) -> int

## 步骤分派（只有一个 match，没有任何逻辑；存在的意义是让 §5 的主循环保持 8 行可读）。
## 步骤：S01..S08
## 前置：step ∈ [1, 8]
## 后置：转调对应的 _step_sNN
## 不变量：INV-012（不回退不跳步）
## 失败：step 越界 → Fault.PHASE_VIOLATION
func _run_step(step: int, cmds: JWCommands) -> int

## 八步的私有实现（顺序见 §5，逐步的调用清单也在 §5）。
## 步骤：各自
## 前置：phase == 对应步
## 后置：该步的可写子集被写，其它子系统哈希不变
## 不变量：见 §5 每步的「步末不变量」行
## 失败：返回第一个非 0 的 Fault 码，立即中止本季
func _step_s01() -> int
func _step_s02(cmds: JWCommands) -> int
func _step_s03() -> int
func _step_s04() -> int
func _step_s05() -> int
func _step_s06() -> int
func _step_s07() -> int
func _step_s08() -> int

## WriteGuard：进入前对**不属于该步可写子集**的子系统取哈希，退出时比对。
## 步骤：每步进入／退出
## 前置：`JWUnits.WRITABLE_SUBSYS[step]` 已定义
## 后置：不改状态；调试构建全开，发布构建按 params[WRITE_GUARD_SAMPLE_Q] 抽季开启
## 不变量：INV-013（越界写入即 WRITE_OUT_OF_SCOPE）；分级策略本身写进参数卡并在存档留痕（OQ-231）
## 失败：哈希不等 → Fault.WRITE_OUT_OF_SCOPE，detail_a = 步，detail_b = 子系统
func _guard_begin(step: int) -> void
func _guard_end(step: int) -> int

## 步末不变量批量检查（清单见 docs/12 §10 的时点表）。
## 步骤：每步末
## 前置：该步已完成
## 后置：不改状态
## 不变量：按步查表
## 失败：返回第一个失败的 Fault 码
func _check_invariants(step: int) -> int

## 记录该步的子系统哈希（只哈希**该步允许写的子集**，不是全状态）。
## 步骤：每步末
## 前置：无
## 后置：_step_hash[step-1] 写入
## 不变量：INV-014；`docs/11` §6.5 的重放二分定位依赖它
## 失败：无
func _record_step_hash(step: int) -> void

## 故障处置：导出故障包并中止。
## 步骤：任意步
## 前置：JWResult.has_pending()
## 后置：写 user://faults/q<NNN>_<code>/ 下的
##       state_before.json、state_after.json、ledger_q.csv、physical_q.csv、
##       step_hashes.json、commands.jsonl 切片、失败的不变量编号与实测残差
## 不变量：docs/12 §9「不修改状态、不尝试修复」
## 失败：写盘失败也不修改状态，只追加一条控制台错误
func _enter_fault(step: int, code: int) -> int

## 本季 8 个步骤哈希（供 checkpoints.jsonl 与重放二分）。
## 步骤：季末
## 前置：本季已完成
## 后置：不改状态
## 不变量：INV-014
## 失败：无
func step_hashes() -> PackedStringArray
```

---

### 4.30 `systems/event_engine.gd` · `class_name JWEventEngine extends RefCounted`

**职责**：12 个事件模板的**条件求值**（不是随机弹窗）。用 `rng.event` 流，与 `rng.shock` 完全独立。
**事件只能写 6 个白名单字段的 ppm 增量，首版没有任何账本效应**（INV-130）。

#### 成员变量

| 稳定 ID | 成员 | 类型 | 长度 | 初值 | 类 | 写入者 |
|---|---|---|---|---|---|---|
| `state.event.fire_count[]` | `fire_count` | `PackedInt64Array` | 12 | 0 | S | S08 |
| `state.event.last_fire_q[]` | `last_fire_q` | `PackedInt64Array` | 12 | −999 | S | S08 |
| `content.event.trigger_metric[]` | `trigger_metric` | `PackedInt64Array` | 12×4 | 剧本 | C | LOAD |
| `content.event.trigger_scope[]` | `trigger_scope` | `PackedInt64Array` | 12×4 | 剧本 | C | LOAD |
| `content.event.trigger_op[]` | `trigger_op` | `PackedInt64Array` | 12×4 | 剧本 | C | LOAD |
| `content.event.trigger_value[]` | `trigger_value` | `PackedInt64Array` | 12×4 | 剧本 | C | LOAD |
| `content.event.probability_ppm[]` | `probability_ppm` | `PackedInt64Array` | 12 | 剧本 | C | LOAD |
| `content.event.cooldown_q[]` | `cooldown_q` | `PackedInt64Array` | 12 | 剧本 | C | LOAD |
| `content.event.max_occurrences[]` | `max_occurrences` | `PackedInt64Array` | 12 | 剧本 | C | LOAD |
| `content.event.effect_target[]` / `effect_scope[]` / `effect_delta_ppm[]` | 同名 | `PackedInt64Array` ×3 | 12×4 | 剧本 | C | LOAD |
| `content.event.evidence_ref[]` | `evidence_ref` | `PackedInt64Array` | 12×4 | 剧本 | C | LOAD |

#### 方法

```gdscript
## S08 §8.4：按 event_id 升序求值并触发。
## 步骤：S08 §8.4
## 前置：冷却未到 / 次数用尽 / 条件不成立 → 跳过；`op ∈ {lt, le, eq, ne, ge, gt}`（**没有表达式求值器**）
## 后置：应用 effects（只能是白名单内的 ppm 增量）；记录 evidence_refs 的实际取值供报告追溯；
##       fire_count += 1；last_fire_q = q
## 不变量：INV-009（即使这里多抽 100 次，rng.shock 取值完全不变）、INV-130（事件无账本效应）、
##          INV-011（每次抽样写 log.rng）
## 失败：条件引用不存在的字段 → Fault.METRIC_UNKNOWN（加载期 V-EV-02 已拦截，运行期是兜底）
func fire_events(st: JWSimState, q: int) -> int

## 单条条件求值（只有比较）。
## 步骤：S08 §8.4
## 前置：metric_code 已在加载期解析
## 后置：不改状态
## 不变量：V-EV-03（op 闭集合）
## 失败：未知 metric → Fault.METRIC_UNKNOWN
func _eval_condition(st: JWSimState, e: int, slot: int) -> bool

## 加载期校验。
## 步骤：LOAD
## 前置：12 个 JSON 已解析
## 后置：不改状态
## 不变量：INV-130
## 失败：Load.EVENT_COUNT / METRIC_UNKNOWN / EVENT_OP / EVENT_STREAM / EVENT_TARGET /
##       EVENT_LEDGER（**首版不存在 ledger_effects 字段，出现即失败**）/ EVENT_FIELD / EVENT_EVIDENCE
func validate() -> JWResult

## §1.6 状态块协议全部方法（SUBSYS_POLITICS）。
```

---

### 4.31 `systems/content_loader.gd` · `class_name JWContentLoader extends RefCounted`

**职责**：加载并校验 `content/*.json`，**缺字段即拒绝启动**；构建初始账本（开账分录）；
计算 `content_hash`；把 ID 解析成下标后冻结 `JWIds`。

#### 成员变量

| 成员 | 类型 | 含义 |
|---|---|---|
| `errors` | `Array[JWResult]` | 逐条校验失败记录（**全部收集完再报，不在第一条就退出**） |
| `content_hash` | `String` | 各内容文件按相对路径升序、逐文件先规范化再拼接的 sha256 |
| `scenario_hash` | `String` | 单独列出，便于定位是剧本改了还是政策改了 |
| `param_set_version` | `int` | 参数包版本 |

#### 方法

```gdscript
## 加载流水线（顺序固定，docs/11 §7）。
## 步骤：LOAD
## 前置：内容目录存在
## 后置：文件格式 → JSON 解析 → 方言限制（无浮点/无 null/无未知键） → schema 校验 →
##       ID 唯一性与正则 → 单文件语义校验 → 跨文件引用解析 → 剧本硬约束与会计对账 →
##       构建初始账本 → 跑一遍 P0 不变量 → 就绪
## 不变量：INV-141..152 全部；INV-023（初值经 q = −1 的开账分录生成）
## 失败：返回第一条错误的 JWResult，`errors` 里是完整清单；**任何一条失败都拒绝启动**
func load_all(root_path: String, st: JWSimState) -> JWResult

## 方言限制：比标准 JSON 更严（docs/11 §3）。
## 步骤：LOAD
## 前置：已解析成 Variant
## 后置：不改状态
## 不变量：INV-001（内容包里出现浮点即 E_FLOAT_IN_CONTENT）
## 失败：Load.FLOAT_IN_CONTENT / NULL_NOT_ALLOWED / UNKNOWN_FIELD / KEY_NAMING / INT_RANGE
func check_dialect(node: Variant, path: String) -> JWResult

## 剧本硬约束（容差一律 0，唯一例外是失业率的 500 ppm 带）。
## 步骤：LOAD
## 前置：各 Init 文件已解析
## 后置：不改状态
## 不变量：INV-141（Σ 人口 == 24 000 000，四地区 9/7/5/3 百万）、INV-142、INV-143（反算失业率
##          ∈ [79 500, 80 500] 且 schema 中不存在失业率输入字段）、INV-144（Σ 债券本金 == 50 000 000）、
##          INV-145（gov.cash == 2 000 000）、INV-146、INV-147、INV-148、INV-149、INV-150、INV-151
## 失败：对应的 Load.* 码
func check_scenario_assertions(st: JWSimState) -> JWResult

## 参数包加载与交叉校验（docs/14 的参数卡 → JWSimState.params 稠密数组）。
## 步骤：LOAD
## 前置：每个数值参数有一张九字段齐全的身份证卡
## 后置：params 数组填满；`sim/**` 内无魔数
## 不变量：INV-152（`observed` 却无对应数据文件即失败，首版 `observed` 必须为 0）、
##          INV-122（trust_recover < trust_drop）、三项 support 权重之和 == 1e6
## 失败：Load.PARAM_CARD / FAKE_OBSERVED / PARAM_DERIVE / PARAM_COVERAGE / PARAM_STALE
func validate_params(st: JWSimState) -> JWResult

## 构建初始账本：把全部初值写成 q = −1 的开账分录。
## 步骤：LOAD
## 前置：全部 Init 已校验通过
## 后置：开账完成后 `agent.opening.cash == 0`（OQ-217：现金腿与各主体自身 nw 配平，
##       不经 opening 的现金科目）；`Σ all cash == scenario.total_cash_uu`
## 不变量：INV-023（初始化不是恒等式的例外）、INV-015、INV-018、INV-020
## 失败：Load.BALANCE_INIT / CASH_TOTAL
func build_opening_ledger(st: JWSimState) -> JWResult

## content_hash：按相对路径升序，每个文件**先解析后做规范化**再拼接（不哈希原始字节）。
## 步骤：LOAD
## 前置：全部文件已解析
## 后置：格式化改动不影响哈希
## 不变量：INV-134（不符即进入只读检视模式）
## 失败：无
func compute_content_hash(root_path: String) -> String
```

---

### 4.32 `systems/saves.gd` · `class_name JWSaves extends RefCounted`

**职责**：存档目录的读写、`manifest.json`、`state.json`、`commands.jsonl`、
`checkpoints.jsonl`、`shock_log.jsonl`，以及版本迁移链。

#### 成员变量

| 成员 | 类型 | 含义 |
|---|---|---|
| `CURRENT_SCHEMA_VERSION` | `const int = 1` | 状态形状版本，**单调整数**，迁移链的唯一依据 |
| `slot_path` | `String` | `user://saves/<slot>/` |
| `migrations` | `Array[Callable]` | 逐版迁移函数链（`Dictionary → Dictionary` 的纯函数，**不允许跳版**） |

#### 方法

```gdscript
## 写存档（目录形态）。
## 步骤：任意（冷路径）
## 前置：phase == IDLE
## 后置：manifest.json / state.json / commands.jsonl / checkpoints.jsonl / shock_log.jsonl 齐全；
##       大数组以 `enc: "b64le64"`（PackedInt64Array.to_byte_array() 的 Base64）编码
## 不变量：INV-131（存档含全部跨季状态 + root_seed + 6 个计数器 + 完整命令流，含被拒命令）；
##          **不用 var_to_bytes()**（其布局是引擎内部表示，跨版本不承诺）
## 失败：写盘失败 → JWResult(Load.FILE_FORMAT)，**不留半个存档**（先写临时目录再原子改名）
func save(st: JWSimState, cmds: JWCommands, slot: String) -> JWResult

## 自动保存：追加 commands.jsonl 与 checkpoints.jsonl 尾行（O(1)，单次 < 1 KB）。
## 步骤：每季末
## 前置：本季已结算完成
## 后置：不重写 state.json
## 不变量：INV-131；`docs/11` §6.2 的工程理由
## 失败：同 save
func autosave_append(st: JWSimState, cmds: JWCommands, slot: String) -> JWResult

## 读档（顺序固定，docs/11 §6.6）。
## 步骤：LOAD
## 前置：目录存在
## 后置：解析 manifest → schema_version 检查 → 迁移链 → 解析各文件 →
##       **重算 state_hash 并比对** → content_hash / param_set_version 比对 →
##       build_id 比对 → 立即跑一遍全部 P0 不变量
## 不变量：INV-132（不符即 E_SAVE_CORRUPT，**拒绝加载，不做尽力修复**）、
##          INV-134（content_hash 不符 ⇒ 只读检视模式；build_id 不符 ⇒ replay_unreliable 但可继续玩）、
##          INV-135（schema_version 高于上限 ⇒ 拒绝，不猜测）
## 失败：Load.SAVE_CORRUPT / SAVE_VERSION_TOO_NEW / MIGRATION_MISSING
func load(slot: String, st: JWSimState, cmds: JWCommands, loader: JWContentLoader) -> JWResult

## 迁移链（逐版递增，不跳版；每个迁移是纯函数，不碰磁盘）。
## 步骤：LOAD
## 前置：from_version < CURRENT_SCHEMA_VERSION
## 后置：升到当前版本；重算 state_hash 写回；保留 migrated_from（原版本 + 原哈希）
## 不变量：INV-136（有序纯函数链；**缺失字段禁止用 0 填充**除非语义就是「无」；
##          部门／地区／群组集合变化 ⇒ 明确拒绝）
## 失败：缺少某一版的迁移函数 → Load.MIGRATION_MISSING
func migrate(src: Dictionary, from_version: int) -> JWResult

## checkpoints.jsonl：每季一行 {q, state_hash, step_hash[8]}。
## 步骤：每季末
## 前置：本季 8 个步骤哈希已记录
## 后置：追加一行
## 不变量：INV-014；`docs/11` §6.5 的重放分歧二分定位
## 失败：无
func append_checkpoint(q: int, state_hash: String, step_hash: PackedStringArray,
                       slot: String) -> JWResult

## 存档安全边界：**不加密、不签名**。哈希只用于检测损坏与内容漂移，不用于防作弊。
## 步骤：—
## 前置：—
## 后置：—
## 不变量：`docs/11` §6.8（玩家改自己的存档不在威胁模型内）
## 失败：—
```

---

### 4.33 `application/game.gd` · `class_name JWGame extends RefCounted`

**职责**：应用层门面。**UI 只能通过它读状态、投命令**；UI 拿到的是只读的 `StateView`。

#### 内部类

```gdscript
## 只读状态快照句柄（Presentation 唯一能拿到的东西）。
## 每个数组访问器**传出前 duplicate()**，所以 UI 拿到的是副本，改它不会影响 SimCore。
## ui/** 中出现 JWLedger / JWSimState 的写方法即违规（静态检查）。
class StateView extends RefCounted:
    func q() -> int
    func phase() -> int
    func run_terminated() -> bool
    func scalar(metric_code: int, scope_idx: int) -> int        ## 走 JWSimState.read_metric
    func array_copy(array_id_code: int) -> PackedInt64Array     ## duplicate() 后返回
    func ledger_rows(from_row: int, to_row: int) -> PackedInt64Array
    func explanations(kind: int) -> PackedInt64Array
    func blocked_reason(policy_idx: int) -> int
    func binding_code(cell: int) -> int
```

#### 成员变量

| 成员 | 类型 | 含义 |
|---|---|---|
| `_st` | `JWSimState` | 权威状态 |
| `_cmds` | `JWCommands` | 命令缓冲 |
| `_runner` | `JWTurnRunner` | 回合驱动 |
| `_saves` | `JWSaves` | 存档 |
| `_loader` | `JWContentLoader` | 内容加载 |
| `_replay` | `JWReplay` | 重放校验 |
| `read_only_mode` | `bool` | `content_hash` 不符时为 true（可看不可推进） |

#### 方法

```gdscript
## 开新局：加载内容、建初始账本、注入 root_seed。
## 步骤：LOAD
## 前置：scenario 路径有效；root_seed == 0 表示运行时注入
## 后置：状态就绪，phase == IDLE，q == 0；已跑一遍 P0 不变量
## 不变量：INV-023、INV-141..152
## 失败：返回加载器的 JWResult；**不进入半初始化状态**
func new_game(scenario_path: String, root_seed: int, horizon_q: int) -> JWResult

## 投一条命令（UI 的唯一写入路径）。
## 步骤：CMD
## 前置：!read_only_mode
## 后置：命令入缓冲；**绝不直接改账**；一切生效发生在 S02
## 不变量：INV-138（命令只写 pending_params 与命令日志）、INV-137
## 失败：转发 JWCommands.submit 的 JWResult；只读模式 → Reject.PHASE_BUSY
func submit_command(kind: int, args: PackedInt64Array) -> JWResult

## 推进一个季度。
## 步骤：S01..S08
## 前置：!read_only_mode；!run_terminated；本季命令流以一条 advance_quarter 结尾
## 后置：成功则 q += 1 并自动追加存档
## 不变量：INV-012、INV-128（终止后任何 advance_quarter 返回 REJECT 且状态哈希不变）
## 失败：返回 JWResult 包住 runner 的 Fault 码；故障时附故障包路径
func advance_quarter() -> JWResult

## 取只读视图（每次调用返回同一个 StateView 实例，内部数据按需 duplicate）。
## 步骤：任意
## 前置：无
## 后置：UI 拿不到任何写接口
## 不变量：计划书 §12（界面层不得直接修改 GDP、民意或库存）
## 失败：无
func view() -> StateView

## 情景预测：对状态做只读副本，用**同一个 SimCore** 空命令跑 4 季（不另写近似模型）。
## 步骤：S08 之后或 UI 请求时
## 前置：phase == IDLE
## 后置：把结果喂给 JWDiagnostics.record_projection()；**不写任何真实状态**
## 不变量：INV-140（projected 禁止回写状态）；`docs/12` §8.6、OQ-230（延迟风险）
## 失败：副本推进失败 → 丢弃预测并返回告警，不影响主线
func preview_four_quarters() -> JWResult

## 存档 / 读档 / 重放校验的门面转发。
## 步骤：冷路径
## 前置：phase == IDLE
## 后置：见各自的实现
## 不变量：INV-131..136
## 失败：转发对应的 JWResult
func save_game(slot: String) -> JWResult
func load_game(slot: String) -> JWResult
func verify_replay(slot: String) -> JWResult
```

---

### 4.34 `application/replay.gd` · `class_name JWReplay extends RefCounted`

**职责**：命令流 + 冲击流重放。**同构建、同种子、同命令流 ⇒ 逐位相同的状态。**
它**不引用 `JWGame`**（避免环）：自己构造一份独立的 `JWSimState` 与 `JWTurnRunner`。

#### 成员变量

| 成员 | 类型 | 含义 |
|---|---|---|
| `mode` | `int` | `COMMANDS_ONLY = 0`（**权威重放**，CI 用）/ `STATE_AND_COMMANDS = 1`（正常读档） |
| `divergence_q` | `int` | 第一个哈希不匹配的季，−1 表示无分歧 |
| `divergence_step` | `int` | 该季 8 个步骤哈希中第一个不匹配的步，−1 表示步骤内一致 |

#### 方法

```gdscript
## 从 q=0 用 commands_only 重跑到存档的 q，逐季比对 checkpoints.jsonl 的 state_hash。
## 步骤：冷路径（CI 与调试）
## 前置：build_id 一致（不一致时 replay_unreliable 为 true，本函数直接返回「不承诺」）
## 后置：divergence_q / divergence_step 写好
## 不变量：INV-014、INV-133（save → load → advance 与 advance 的 state_hash 逐位相同，
##          `log.rng` 完全一致）
## 失败：不修改任何状态，只报告分歧季与分歧步骤；
##       8 个步骤哈希都一致而季末不一致 ⇒ 存在步骤之外的写入 ⇒ **直接报架构缺陷**
func verify(slot: String, loader: JWContentLoader) -> JWResult

## 二分定位：给定分歧季，重算该季任意一次抽样并对齐 log.rng。
## 步骤：冷路径
## 前置：verify 已定位到分歧季
## 后置：输出该季逐步骤哈希与 rng 抽样对照
## 不变量：INV-009（流隔离）、INV-010（可从任意季直接重算任意一次抽样）、INV-011
## 失败：无
func diff_quarter(slot: String, q: int, loader: JWContentLoader) -> JWResult

## 纯重放一段命令流到指定季（压力测试与黄金存档回归用）。
## 步骤：冷路径
## 前置：内容包与参数包版本一致（否则同样进只读检视，M-9）
## 后置：返回终态的 JWSimState（调用方自行断言）
## 不变量：INV-133、INV-136（黄金存档跑「v1 → 当前」全链）
## 失败：任一季 Fault → 停在该季并返回故障码
func run_to(root_seed: int, cmds: JWCommands, target_q: int,
            loader: JWContentLoader) -> JWResult
```

---

## 5 八步调用序列（`systems/turn_runner.gd` 的逐行骨架）

**顺序不可交换、不可重入、不可回退**（INV-012）。下面每一步先给可写子系统位掩码，
再给调用清单（**编号即执行顺序**），最后给步末不变量与失败行为。
`_st` 是 `JWSimState`，`_sc_*` 是 §4.29 的预分配 scratch。

```gdscript
func advance_quarter(cmds: JWCommands) -> int:
	if _st.politics.run_terminated:      return JWResult.Reject.RUN_TERMINATED   # INV-128，状态哈希不变
	if _st.phase != JWUnits.Phase.IDLE:  return JWResult.Reject.PHASE_BUSY
	var fault: int = 0
	for step in range(1, 9):
		_st.phase = step
		JWResult.set_step(step)
		_st.ledger.set_context(_st.q, step)
		_guard_begin(step)                       # 调试全开；发布按 params[WRITE_GUARD_SAMPLE_Q] 抽季
		fault = _run_step(step, cmds)
		var guard: int = _guard_end(step)        # 越权写入 -> WRITE_OUT_OF_SCOPE
		if fault == 0: fault = guard
		if fault == 0: fault = _check_invariants(step)
		_record_step_hash(step)
		if fault != 0: return _enter_fault(step, fault)
	fault = _check_invariants(0)                 # 0 号表示「季末全量」
	if fault != 0: return _enter_fault(8, fault)
	_st.phase = JWUnits.Phase.IDLE
	return 0
```

### 5.1 S01 冻结起点 —— 可写：`META | TIME | CELL | PUBSERV | REGION | PROJECT | WORLD | RNG` + 全部 `flow.*`

| # | 调用 | 对应 `docs/12` | 关键约束 |
|---|---|---|---|
| 1 | `_st.state_hash_prev = _st.state_hash()` | §01.1 | 写 `checkpoints` |
| 2 | `_verify_versions()`（比 `build_id` / `content_hash` / `param_set_version`） | §01.2 | `content_hash` 不符 ⇒ 只读检视、**拒绝推进**（INV-134） |
| 3 | `_st.reset_all_flows()` 然后 `_st.flow_abs_sum_all() == 0` | §01.3 | **全局唯一允许整表清零流量处**；非 0 ⇒ `FLOW_NOT_RESET` |
| 4 | `_st.ledger.log_reset_quarter()`、`_st.rng.begin_quarter(_st.q)`，其余日志通道同 | §01.1 | 日志不进 `state_hash` |
| 5 | `_st.treasury.begin_quarter(_st.accounts)` | §6.9 的基准 | 记季初现金，供 INV-027 |
| 6 | **`_st.capital.commit_pending()`** | §01.4 | **`capacity_active` 的唯一增量写入点**（INV-054/091） |
| 7 | `_st.commissioning.promote_completed(_st.projects, _st.q)` | §01.4 | `completed → commissioned`，`commissioned_q == 完工季+1` |
| 8 | `cmds.validate_batch(_st.q, _st.policy_defs)`、`cmds.check_advance_marker(_st.q)` | §01.5 | **只判定不执行**；被拒命令仍入档（INV-137） |
| 9 | `_st.shocks.resolve_quarter(_st.rng, _st.world, _st.q, _st.params)` | §01.6 | **先查 `shock_log` 再抽样**（INV-109） |
| 10 | `_st.shocks.apply_to_world(_st.world, _st.q, _st.params)` | §01.7 | 只写 `state.world.*` 白名单（INV-108） |

**步末不变量**：`phase == S01`；`Σ pending == 0`；全部 `flow.*` 为 0；
`log.rng` 条数 == `Σ Δdraw_count`（INV-011）；INV-012, INV-054, INV-091, INV-109, INV-134。
**失败**：`content_hash` 不符 → 拒绝推进；命令格式非法 → 逐条 `REJECT` 并继续；
流量清零后非零 → `FLOW_NOT_RESET`；`shock_log` 与计数器矛盾 → `RNG_LOG_MISMATCH`。

### 5.2 S02 审核与融资 —— 可写：`POLICY | PROJECT | GOV | BOND | WORLD | POLITICS | META`

| # | 调用 | 对应 | 关键约束 |
|---|---|---|---|
| 1 | `cmds.accepted_this_quarter_into(_sc_out, _st.q)` | §2.1 | 按 `(issued_q, command_id)` 升序 |
| 2 | 逐条：`_st.policy.try_enact / try_repeal / apply_pending_params(...)` | §2.1 | 资格链 5 道；`effective_from_q` 只能向前（INV-098） |
| 3 | 逐条：`_st.projects.launch / cancel(...)`、`_st.commissioning.pay_cancel_penalty/register_residual` | §2.7 | 取消**不退已付**（INV-093）；槽位（INV-094） |
| 4 | `_st.policy.*` 中的资金来源 → `_st.treasury.reserve(...)` | §2.2 | 预留**不产生现金移动**（INV-033） |
| 5 | `_st.bonds.accrue_interest(_st.q)` | §2.3 | 逐批次 floor + 余数累加器（INV-036/004） |
| 6 | `_st.bonds.schedule_principal(_st.q)` | §2.4 | 分期表 Σ == 面值（INV-037） |
| 7 | `_st.treasury.pay_debt_service(_st.bonds, _st.ledger, _st.accounts, _st.q, _st.params)` | §2.5 | 短缺先显露；**不自动展期**（INV-038/040） |
| 8 | 需要融资时 `_st.treasury.issue_debt(...)`（内部调 `_st.world.use_external_credit`） | §2.6 | 双额度上限（INV-034）；借款不进收入不进 GDP（INV-029） |
| 9 | `_st.politics.mark_budget_review(_st.q)` | §2.8 | `q ≡ 3 (mod 4)`（INV-127） |
| 10 | `_st.policy.blocked_reason()` 重算 | §2.1 | 玩家可见的未生效政策必须有原因码（INV-100） |

**步末不变量**：INV-016, 028, 030, 032, 033, 034, 035, 036, 037, 038, 039, 040, 041,
092, 093, 094, 095, 098, 127；且每条命令恰好被处理一次。
**失败**：现金不足且无法融资 → 按优先级推迟并生成 `arrears`（不静默改账）；
批次数超上限 → 报警并 `REJECT` 新发行（**不自动合并批次**）；
队列无空位 → `blocked_reason = QUEUE`；`gov.cash` 将为负 → `NEGATIVE_CASH`；
`debt != Σ outstanding` → `BOND_MISMATCH`。

### 5.3 S03 计划与就业 —— 可写：`CELL | PUBSERV | GROUP | REGION | MARKET | RNG`

| # | 调用 | 对应 | 关键约束 |
|---|---|---|---|
| 1 | `_st.sectors.plan_output(上季 sold, 上季 unmet, _st.inventory, _st.io, _st.params)` | §3.1 | 用「成交 + 未满足」，**不含本季信息** |
| 2 | `_st.labor.hire_and_fire(_st.sectors.f_output_plan, _st.io, _st.pricing, _st.pop, _st.accounts, _st.params)` | §3.2 | 两道硬闸（劳动力池、工资资金）+ 摩擦（INV-076/079） |
| 3 | `_st.labor.compute_unemployment(_st.pop)` | §3.4 | **反算，不是参数**（INV-075/143） |
| 4 | `_st.labor.check_employment_views(_st.pop)` | §3.2 末 | 两侧口径逐（地区，技能）相等（INV-077） |
| 5 | `_st.sectors.order_inputs(_st.io, _st.pop, _st.params)` | §3.5 | 只登记订单；材料与电力**不在本步分配** |
| 6 | `_st.sectors.compute_invest_intent(_st.capital, _st.params)` | §3.6 | 三项输入全是已实现的量；无外生加成 |

**步末不变量**：INV-074, 075, 076, 077, 078, 079, 080。
**失败**：劳动力不足 → 招工被池压低（S05 中 `bound_labor` 成为紧约束）；
现金不足付期望工资 → 缩减到 `affordable_k` 并写 `log.clamp`；
`Σ employed > pool` → `EMPLOYMENT_OVERFLOW`。

### 5.4 S04 工资与投入 —— 可写：全部 `cash`、`GROUP | CELL | PUBSERV | GOV | PROJECT | POLICY`

| # | 调用 | 对应 | 关键约束 |
|---|---|---|---|
| 1 | `_st.labor.pay_wages(_st.pricing, _st.pop, _st.ledger, _st.accounts)` | §4.1 | **工资先于消费**；付不出 → `WAGE_UNFUNDED`（**不在本步补救、不裁员**） |
| 2 | 按 `payment_priority` 遍历 8 档，逐档： | §4.2 | 实际支付顺序必须与优先级一致（INV-039） |
| 2a | `DEBT_SERVICE` 档在 S02 已处理，本步跳过 | §2.2 表 | 避免重复支付 |
| 2b | `_st.labor.public_wage_due_into(...)` → `_st.treasury.pay_line(PUBLIC_WAGES, ...)` → `_st.labor.record_public_wage_paid(...)` | §4.2 | 同秩不互调，由本文件中转（§3.3） |
| 2c | `_st.policy.transfer_due_into(...)` → `_st.treasury.pay_line(STATUTORY_TRANSFERS, ...)` | §4.2 | 现金不足 → **部分支付 + 欠付**，不得少算人数 |
| 2d | `_st.treasury.pay_line(SERVICE_OPEX, ...)` → `_st.capital.set_funding_ratio(r, paid, due)` | §4.2 | 欠拨只降可用率（INV-102） |
| 2e | `_st.projects.payment_due_into(...)` → `_st.treasury.pay_line(PROJECT_CONTRACTS, ...)` → `_st.projects.record_payment(...)` | §4.4 | **本步不写任何进度字段**（INV-087） |
| 2f | `PROCUREMENT` 档只预留额度，实际采购在 S05 成交 | §5.6 | 采购是买方类 2 |
| 2g | `_st.policy.pay_subsidy(...)` 逐个合格 cell | §4.3 | 幂等键 + 「已发生的实际投资」前置（INV-097） |
| 2h | `DISCRETIONARY` 档按余额支付 | §4.2 | — |
| 3 | `_st.pop.pay_household_support(_st.ledger, _st.accounts, _st.params)` | §4.5 | `Σ support_in == Σ support_out`（INV-085） |
| 4 | `_st.treasury.release_reservations()` | §2.2 | 预留季末归零（INV-033） |

**步末不变量**：INV-003, 015, 016, 030, 079, 085, 087, 092, 096, 097。
**失败**：企业现金不足付工资 → `WAGE_UNFUNDED`（说明 S03 有缺陷）；
政府现金不足付转移 → 按比例部分支付 + 欠付；项目付款超合同剩余 → 拒付、记 `E_OVERPAY` 诊断、项目转 `suspended`；
补助重复申领 → 拒绝并记 `duplicate_claim_blocked`；拆分和不等 → `SPLIT_MISMATCH`。

### 5.5 S05 生产与交易 —— 可写：`CELL | GROUP | PUBSERV | REGION | MARKET | GOV | WORLD | PROJECT | RNG`

严格按 `docs/12` §5.1 的八个次序，**部门有序，打断同期循环**。

| # | 调用 | 对应 | 关键约束 |
|---|---|---|---|
| 1 | `_st.inventory.begin_production()`、`_st.world.begin_quarter_delivery()` | §5.1 | 快照期初库存，重置交付额度 |
| 2 | `_st.sectors.settle_energy(_st.capital, _st.inventory, _st.io, _st.labor, _st.params)` | §5.2 | 能源 cell 先产；自用 ceil 净出；电力**不入库存**（INV-051/052） |
| 3 | `_st.sectors.settle_production(_st.capital, _st.labor, _st.inventory, _st.io)`（内部逐 cell 调 `solve_output` → `inventory.consume_inputs` → `inventory.store_output`） | §5.3/§5.4 | 五项约束取 min；零系数跳过；ceil 反算不透支（INV-043..050） |
| 4 | `_st.projects.compute_construction_capacity(_st.sectors.output_actual_array(), _st.params)` | §5.5 | 由**实际**服务产量折出，不是由付款折出（INV-088） |
| 5 | `_st.projects.advance_progress(_st.world, _st.ledger, _st.accounts)` | §5.5 | 进度函数形参表里**没有 `paid_uu`**（INV-087/089） |
| 6 | `_st.inventory.deliver_public_services(_st.capital, _st.pop)` | §5.7 | `delivered <= capacity × availability`；欠拨**不删资产**（INV-102/103） |
| 7 | `_st.inventory.collect_demand(...)` → `_st.inventory.ration(...)` → `_st.inventory.execute_trades(...)` | §5.6 | 先算全部需求再统一配给；两级规则都完全确定（INV-059..064） |
| 8 | `_st.capital.accumulate_emissions(_st.sectors.output_actual_array(), _st.io)`、`_st.inventory.apply_spoilage(_st.io)` | §5.8 | 损耗显式登记并计入中间消耗（INV-053） |
| 9 | `_st.inventory.check_stock_identity(_st.sectors.output_actual_array())` | §5.8 末 | 逐 cell 逐品种（INV-047） |

**步末不变量**：INV-015, 016, 043..053, 059..064, 087..089, 094, 103, 104。
**失败**：`use > avail` → `NEGATIVE_INVENTORY`（说明 `q_actual` 推导有误）；
需求为 0 而产量 > 0 → 正常（库存上升，S07 压低价格，**不得发 GDP 或支持率奖励**）；
施工能力为 0 → 进度不增、`suspended(congestion)`；设备未到货 → 即使施工 100% 也**不得完工**；
买方现金不足 → 成交量缩减 + 记未满足需求（**没有任何路径可以产生凭空的货**）。

### 5.6 S06 财税结算 —— 可写：`GOV | CELL | PUBSERV | GROUP | REGION | WORLD | BOND`

| # | 调用 | 对应 | 关键约束 |
|---|---|---|---|
| 1 | `_st.capital.depreciate(_st.io, _st.ledger, _st.accounts)` | §6.1 | 非现金分录；两轨同率；维护欠账不减资产（INV-055/056） |
| 2 | `_st.sectors.compute_value_added(_st.inventory, _st.io)` | §6.2 | 名义 + 基年价两轨；**禁止名义除以价格指数**（INV-111/117） |
| 3 | `_st.capital.compute_nonmarket_output(wage_bill, intermediate)`（写 `flow.pubserv.output_uu`） | §6.3 | 按成本计价，全额计入政府最终消费，不重复（INV-101） |
| 4 | `_st.sectors.compute_profit(_st.labor, _st.capital, _st.inventory, _sc_taxable, _st.params)` | §6.6 | 营业盈余按残差定义；价差进经营结果 |
| 5 | `_st.treasury.collect_income_tax(_st.pop, _st.policy.params_ppm_array(), _st.ledger, _st.accounts, _st.params)` | §6.5 | 税基只来自已过账收入；征收能力 + 税基侵蚀（ADV-05） |
| 6 | `_st.treasury.collect_profit_tax(_sc_taxable, _st.policy.params_ppm_array(), _st.ledger, _st.accounts, _st.params)` | §6.6 | 利润 ≠ 现金；差额进应收（INV-031） |
| 7 | `_st.sectors.compute_distributable(_sc_distributable, _st.params)` | §6.7 | 扣税后按 `payout_ratio` |
| 8 | `_st.pop.settle_income_and_savings(_sc_distributable, 利息, _st.ledger, _st.accounts, _st.params)` | §6.7 | `Δcash + Δdeposit == savings` 逐组精确（INV-086/024） |
| 9 | `_st.world.settle_current_account(对外利息, 对外净借款, _st.bonds.debt_outstanding_of_holder(JWUnits.Holder.ROW), _st.accounts)` | §6.8 | INV-106/107/110；外债经整数形参传入（秩 4 同秩不得互引） |
| 10 | `_st.ledger.aggregate_classes(...)` → `_st.diag.compute_gdp(...)` → `_st.diag.compute_fiscal(...)` | §6.4 | 三口径 + 价差调节项；覆盖性检验（INV-112..119） |
| 11 | `_st.treasury.check_fiscal_identities(_st.bonds, _st.accounts)`、`_st.accounts.check_*()` | §6.9 | **本季唯一的终检点**（INV-017..021, 027, 028, 035, 115） |

**步末不变量**：INV-017..021, 027, 028, 035, 101, 106, 107, 110..119。
**失败**：任一恒等式不成立 → `LEDGER_IMBALANCE`，终止并导出故障包，
**不得自动修正，绝不用「平衡修正项」抹平**；
GDP 覆盖性检验失败 → `GDP_CLASS_MISSING` / `GDP_CLASS_DUPLICATE` 并报出具体分录；
群组／企业现金不足缴税 → 按现金上限征收，差额进应收税，报告披露。

### 5.7 S07 跨期变化 —— 可写：`PRICE | CELL | PUBSERV | REGION | GROUP | PROJECT | GOV | POLITICS | RNG`

| # | 调用 | 对应 | 关键约束 |
|---|---|---|---|
| 1 | `_st.commissioning.commission_ready(_st.projects, _st.capital, _st.treasury, _st.labor, _st.ledger, _st.accounts, _st.q)` | §7.1 | **只写 `*_pending_*`**；配套条件（OQ-245）；INV-090/091 |
| 2 | `_st.policy.apply_effects(_st.policy_defs, _st.capital, _st.treasury, _st.politics, _st.pop, _st.q)` | §7.1 | 落点白名单；未生效返回零效应（INV-095） |
| 3 | `_st.capital.update_maintenance_and_availability(_st.params)` | §7.2 | 欠拨只降可用率，**不得写 `capacity_active`/`grid`/`housing_stock`**（INV-102） |
| 4 | `_st.pricing.update_prices(...)`、`update_wages(...)`、`update_housing_rent(...)` | §7.3 | **只写 `pending`**；有界平滑；每次夹逼写 `log.clamp` 并计数（INV-065..070） |
| 5 | `_st.pop.update_demography(_st.rng, _st.params)` | §7.4 | 死亡是唯一净流出，出生是唯一净流入（INV-071/072/074） |
| 6 | `_st.migration.run(_st.pop, _st.labor, _st.capital, _st.pricing, _st.ledger, _st.accounts, _st.rng, _st.params)` | §7.5 | 三道硬闸；被挡回显式登记（INV-073/083/084） |
| 7 | `_st.pop.update_education(_st.capital.pub_teachers, 申请席位, _st.q, _st.params)` | §7.6 | 无教师即无席位；拨款当季无 `skill_in`（INV-081/082）；教师数经数组形参传入（秩 4 同秩不得互引） |
| 8 | `_st.pop.outflow_persons_into(_sc_group)` → `_st.labor.release_for_outflow(_sc_group, _st.pop, _sc_group_slot)` → `_st.pop.apply_employment_cut(_sc_group_slot)` | §7.7 | **S07 对 `employment` 的写只在这一条链上**（INV-080） |
| 9 | `_st.pop.check_conservation(_st.migration.in_by_group(), _st.migration.out_by_group())` | §7.4 第 7 步 | INV-071/072/073 |
| 10 | `_st.pop.update_living_indices(delivered_to_group)` | §7.8 | 相对基准，不冒充国际排名（INV-149） |
| 11 | `_st.capital.update_environment(region_population, _st.params)` | §7.9 | 排放不反馈到生产约束（INV-057） |

**步末不变量**：INV-054, 055, 056, 065..073, 081..084, 091, 102, 149。
**失败**：人口守恒不成立 → `POPULATION_NOT_CONSERVED`；迁移不配对 → `MIGRATION_UNPAIRED`；
住房容量被突破 → `HOUSING_OVERFLOW`；价格连续多季触界 → 由 `clamp_budget_used_count` 累计，
超预算是**压测失败**而不是运行期故障。

### 5.8 S08 社会与报告 —— 可写：`GROUP（四个主观量）| POLITICS | META | PRICE（swap）| TIME | RNG`

| # | 调用 | 对应 | 关键约束 |
|---|---|---|---|
| 1 | `_collect_breach_counts(_sc_breach)`（汇总转移欠付、运行费欠拨、项目取消、债券违约四类闭集合事件） | §8.1 | 失信是**闭集合**，逐季计数 |
| 2 | `_st.politics.update_subjective(_st.pop, _st.pricing, _sc_breach, _st.params)` | §8.1 | 三个主观量分开更新；**trust 的更新式里没有 `transfer_income` 通道**（INV-121/122） |
| 3 | `_st.politics.update_support(_st.pop, _st.params)` | §8.2 | 逐组 `support` 必须保留；全国值只由加权得出（INV-123/124/125） |
| 4 | `_st.blocs.update_blocs(_st.sectors, _st.labor, _st.capital, _st.pop, 本季新生效政策掩码, _st.policy_defs, _st.params)` | §8.3 | 与 support 互不引用（INV-125/129） |
| 5 | `_events.fire_events(_st, _st.q)` | §8.4 | 用 `rng.event`；即使多抽 100 次，`rng.shock` 取值不变（INV-009/130） |
| 6 | `_st.politics.review_and_terminate(_st.treasury, _st.pop, _st.q, _st.horizon_q, 连续违约季数, _st.params)` | §8.5 | 选举只在 `q ∈ {15, 31}`；**终局式中无任何 GDP 项**（INV-127/128） |
| 7 | `_st.diag.compute_income_quantiles(_st.pop)`、`_st.diag.add_explanation(...)` 三类分栏 | §8.6 | `projected` 禁止回写状态（INV-140） |
| 8 | **`_st.pricing.swap_pending()`** | §8.7 | 价格与工资切换的**唯一时点**（INV-065/070） |
| 9 | **`_st.advance_quarter_index()`** | §8.7 | `state.time.q` 的**唯一写入点**（INV-012） |
| 10 | `_st.diag.snapshot_and_verify(_st.sectors, _st.capital, _st.inventory, _st.world, _st.treasury, _st.ledger, _st.bonds, _st.pop, _st.q)`、`_record_step_hash(8)`、写 `checkpoints` | §8.7 | 派生一致性（INV-014）；逐个传域类，**不传 `_st`**（秩 9 不得引用秩 10） |

**步末不变量**：INV-011, 012, 014, 121..130, 140。
**失败**：事件条件引用不存在的字段 → `METRIC_UNKNOWN`；
`support_ppm` 变动无来源记录 → `SUPPORT_UNEXPLAINED`；主观量越界 → `clamp` 并写 `log.clamp`。

### 5.9 顺序为什么不可交换（给想「优化一下」的人）

| 想换的顺序 | 会破坏什么 |
|---|---|
| 把 S01 的 `commit_pending` 挪到 S07 末 | 依赖「S05 在 S07 之前」这一隐含顺序，将来插步即**静默失效**（R-06 裁定） |
| 把电力分配挪回 S04 | 回到「计划与实际错位」的整类风险（S-01 裁定） |
| 把折旧挪到 S07 | 制造跨步暂存，且 `capacity_active` 的两个写者位置变得不确定（S-03 裁定） |
| 把利息还本挪到 S06 | 违反计划书 §13 第 02 步「处理到期债务」（R-07 裁定） |
| 把价格 swap 提前到 S07 | 同季「价格 → 数量 → 价格」回路复活（INV-065） |
| 把 `q += 1` 挪到 S01 | 需要为第 0 季开例外，且 `q` 出现第二个写入点（R-04 裁定） |
| 在 S04 因付不出工资而裁员 | `employment` 出现第三个写者，INV-080 失去可检查性（R-17 裁定） |

---

## 6 序列化、哈希与随机流状态接口（一次定死）

### 6.1 三个哈希的唯一实现

| 哈希 | 输入 | 实现 | 用途 |
|---|---|---|---|
| `state_hash` | 全部 `state.*` 与 `flow.*` 条目，按**稳定 ID 字节序升序**拼接 | `JWSimState.state_hash()` | INV-014 的逐季比对 |
| `subsystem_hash` | 单个子系统的同样编码 | `JWSimState.subsystem_hash(subsys)` | WriteGuard 与步骤哈希 |
| `content_hash` | 各内容文件按相对路径升序，**先解析后规范化**再拼接 | `JWContentLoader.compute_content_hash()` | INV-134 |
| `replay_hash` | `canonical(command_log)` | `JWCommands.command_log_hash()` | 重放交叉验证 |

**规范化编码**（`JWSimState.canon_*`，四者共用）：

```
int 标量   -> int64 小端 8 字节
整数数组   -> uint32 长度（小端） + 逐元素 8 字节
字符串     -> uint32 字节长度 + UTF-8（**仅用于 SoA 的 ids[]**）
每条条目   -> uint16 len(id) + id 的 UTF-8 + uint8 type_tag + 值
遇 float   -> Fault.FLOAT_IN_STATE（INV-001）
```

**哈希排除清单**（被 `test_u_hash_coverage` 锁定：反射遍历状态树，断言除白名单外每个字段都进哈希）：
`state.meta.state_hash_prev` 自身、全部 `log.*`、全部 `derived.*`、
一切 `label_zh` / `desc_zh` / `report_template_id` / `_note_*` / `created_utc` / `client_build_id`。

### 6.2 随机流状态的序列化（只有 7 个数）

```
root_seed: int64          # state.rng.root_seed
draw_count: int64[6]      # state.rng.draw_count
```

**这 7 个数就是完整的随机流状态**（计数器式抽样，不存内部状态）。
`manifest.json` 的 `draw_count` 字段与 `state.json` 里的必须一致，不一致即 `E_SAVE_CORRUPT`。
`content.rng.salt[6]` 属 schema，不在存档里，**一经发布不得更改**（改了全部存档重放失效，INV-136）。

冲击流的已决记录单独存 `shock_log.jsonl`（与命令流分开，计划书 §12「多写一句新闻不改变经济抽样」）：
`JWShocks.export_shock_log()` / `load_shock_log()`。S01 **先查后抽**，因此读档不重抽（INV-109/133）。

### 6.3 存档目录与读档顺序

```
user://saves/<slot>/
  manifest.json       # JWSaves 写；字段见 docs/11 §6.3
  state.json          # JWSimState.to_dict()；大数组 enc = "b64le64"
  commands.jsonl      # JWCommands.append_jsonl()；自开局起全量，含被拒命令
  checkpoints.jsonl   # 每季一行 {q, state_hash, step_hash[8]}
  shock_log.jsonl     # JWShocks.export_shock_log()
  log/q0000.bin       # 可选，可丢弃，不影响重放
```

读档顺序（`JWSaves.load()`，**顺序固定**）：
解析 manifest → `schema_version` 检查（高于上限 ⇒ 拒绝，INV-135）→ 迁移链（逐版递增不跳版）→
解析各文件 → **重算 `state_hash` 并比对**（不符 ⇒ `E_SAVE_CORRUPT`，拒绝，**不做尽力修复**）→
`content_hash` / `param_set_version` 比对（不符 ⇒ 只读检视，INV-134）→
`build_id` 比对（不符 ⇒ `replay_unreliable = true`，禁用重放验证，仍可继续游玩）→
立即跑一遍全部 P0 不变量 → 任一失败即拒绝加载。

### 6.4 `enc: "b64le64"` 的字节布局是协议的一部分

`PackedInt64Array.to_byte_array()` 的 Base64（小端、每元素 8 字节）。
**不用 `var_to_bytes()`**（其二进制布局是引擎内部表示，跨版本不承诺）。
必须有单元测试 `test_u_packed_int64_byte_layout` 断言这个布局 —— 因为我们把它写进了协议。

---

## 7 文件 → 负责模块 → 依赖的其它文件（分工总表）

**一个文件一个负责人。** 「依赖」列里的文件是你**可以读的接口**；不在列里的文件你**不得引用**。
「被谁调用」列告诉你：改了签名会影响谁（所以要走 §8 的变更流程）。
`#` 列是**按秩排序的实现序号**（与 §7.1 的批次对应），与 §4 的小节号不一定相同；
按类名查 §4 即可。

| # | 文件 | 类 | 秩 | 负责模块 | 依赖的其它文件 | 被谁调用 | 主要不变量 |
|---|---|---|---|---|---|---|---|
| 1 | `sim/jw_units.gd` | `JWUnits` | 0 | 基础设施 | — | 全部 | INV-007, 114, 152 |
| 2 | `sim/jw_result.gd` | `JWResult` | 0 | 基础设施 | — | 全部 | docs/12 §9 |
| 3 | `sim/jw_math.gd` | `JWMath` | 1 | 基础设施 | `jw_units`, `jw_result` | 全部 | INV-002..007 |
| 4 | `sim/jw_ids.gd` | `JWIds` | 1 | 基础设施 | `jw_units`, `jw_result` | 全部 | INV-008, 010 |
| 5 | `sim/state/rng_streams.gd` | `JWRngStreams` | 2 | 确定性 | 秩 ≤1 | `shocks`, `migration`, `population`, `inventory`, `event_engine`, `politics`, `turn_runner` | INV-009..011 |
| 6 | `sim/ledger/account.gd` | `JWAccount` | 2 | 账本 | 秩 ≤1 | `ledger`（唯一写者）、几乎全部（只读） | INV-016..020, 022 |
| 7 | `sim/sectors/io_table.gd` | `JWIoTable` | 2 | 生产 | 秩 ≤1 | `sector_model`, `inventory`, `capital`, `labor_market` | INV-044, 052, 150 |
| 8 | `sim/policy/policy_def.gd` | `JWPolicyDef` | 2 | 政策 | 秩 ≤1 | `policy_engine`, `project_queue`, `commands`, `content_loader` | INV-099 |
| 9 | `sim/sectors/pricing.gd` | `JWPricing` | 2 | 市场 | 秩 ≤1 | `labor_market`, `inventory`, `migration`, `politics`, `turn_runner` | INV-065..070 |
| 10 | `sim/ledger/ledger.gd` | `JWLedger` | 3 | 账本 | `account`, 秩 ≤1 | 全部要动钱的类 | INV-015, 022, 114 |
| 11 | `sim/ledger/bond_book.gd` | `JWBondBook` | 4 | 财政 | 秩 ≤3 | `treasury`, `world_market`, `politics`, `diagnostics` | INV-035..041 |
| 12 | `sim/sectors/capital.gd` | `JWCapital` | 4 | 资产 | 秩 ≤3 | `sector_model`, `inventory`, `project_queue`, `commissioning`, `migration`, `policy_engine`, `blocs` | INV-054..058, 091, 102 |
| 13 | `sim/population/population.gd` | `JWPopulation` | 4 | 人口 | 秩 ≤3 | `labor_market`, `inventory`, `migration`, `politics`, `blocs`, `policy_engine` | INV-071..086 |
| 14 | `sim/world/world_market.gd` | `JWWorldMarket` | 4 | 外部 | 秩 ≤3 | `shocks`, `treasury`, `inventory`, `project_queue` | INV-104..110 |
| 15 | `sim/ledger/treasury.gd` | `JWTreasury` | 5 | 财政 | 秩 ≤4 | `policy_engine`, `project_queue`, `inventory`, `commissioning`, `politics`, `turn_runner` | INV-027..034, 039 |
| 16 | `sim/population/labor_market.gd` | `JWLaborMarket` | 5 | 劳动 | 秩 ≤4 | `sector_model`, `migration`, `blocs`, `commissioning`, `policy_engine`, `turn_runner` | INV-075..080 |
| 17 | `sim/world/shocks.gd` | `JWShocks` | 5 | 外部 | 秩 ≤4 | `turn_runner`, `saves` | INV-108, 109 |
| 18 | `sim/sectors/inventory.gd` | `JWInventory` | 6 | 市场 | 秩 ≤5 | `sector_model`, `turn_runner`, `diagnostics` | INV-047..053, 059..064 |
| 19 | `sim/projects/project_queue.gd` | `JWProjectQueue` | 6 | 项目 | 秩 ≤5 | `policy_engine`, `commissioning`, `turn_runner` | INV-087..094 |
| 20 | `sim/population/migration.gd` | `JWMigration` | 6 | 人口 | 秩 ≤5 | `turn_runner` | INV-073, 083, 084 |
| 21 | `sim/politics/politics.gd` | `JWPolitics` | 6 | 政治 | 秩 ≤5 | `policy_engine`, `event_engine`, `turn_runner` | INV-121..128 |
| 22 | `sim/sectors/sector_model.gd` | `JWSectorModel` | 7 | 生产 | 秩 ≤6 | `blocs`, `turn_runner`, `diagnostics` | INV-043..046, 111..117 |
| 23 | `sim/projects/asset_commissioning.gd` | `JWAssetCommissioning` | 8 | 项目 | 秩 ≤7 | `turn_runner` | INV-090, 091, 093 |
| 24 | `sim/policy/policy_engine.gd` | `JWPolicyEngine` | 8 | 政策 | 秩 ≤7 | `turn_runner`, `game` | INV-095..100 |
| 25 | `sim/politics/interest_groups.gd` | `JWInterestGroups` | 8 | 政治 | 秩 ≤7 | `politics`（**只经形参**）、`turn_runner` | INV-125, 129 |
| 26 | `sim/report/diagnostics.gd` | `JWDiagnostics` | 9 | 报告 | 秩 ≤8（只读） | `turn_runner`（仅 S08 末）、`game` | INV-014, 111..120, 140 |
| 27 | `sim/state/sim_state.gd` | `JWSimState` | 10 | 状态 | 秩 ≤9 | `turn_runner`, `content_loader`, `saves`, `event_engine`, `game`, `replay` | INV-012..014, 131..136 |
| 28 | `systems/commands.gd` | `JWCommands` | A0 | 调度 | 秩 ≤1, `policy_def` | `turn_runner`, `saves`, `game`, `replay` | INV-137, 138 |
| 29 | `systems/content_loader.gd` | `JWContentLoader` | A1 | 内容 | 秩 ≤10, A0 | `game`, `saves`, `replay` | INV-023, 141..152 |
| 30 | `systems/event_engine.gd` | `JWEventEngine` | A2 | 调度 | 秩 ≤10 | `turn_runner` | INV-130 |
| 31 | `systems/turn_runner.gd` | `JWTurnRunner` | A3 | 调度 | 秩 ≤10, A0, A2 | `game`, `replay` | INV-012, 013 |
| 32 | `systems/saves.gd` | `JWSaves` | A4 | 存档 | 秩 ≤10, A0, A1 | `game`, `replay` | INV-131..136 |
| 33 | `application/replay.gd` | `JWReplay` | A5 | 应用 | 秩 ≤10, A0..A4 | `game` | INV-014, 133 |
| 34 | `application/game.gd` | `JWGame` | A6 | 应用 | 秩 ≤10, A0..A5 | `ui/**`（只经 `StateView`） | 计划书 §12 |

### 7.1 建议的实现顺序（并行批次）

| 批次 | 文件 | 前置 | 可并行人数 |
|---|---|---|---|
| B0 | 1–4（infra） | — | 1 人（必须先完成，全员依赖） |
| B1 | 5–9（rng / account / io / policy_def / pricing） | B0 | 5 |
| B2 | 10（ledger） | B1 | 1（最关键的单点，建议最有经验者） |
| B3 | 11–14（bond / capital / population / world） | B2 | 4 |
| B4 | 15–17（treasury / labor / shocks） | B3 | 3 |
| B5 | 18–21（inventory / project / migration / politics） | B4 | 4 |
| B6 | 22（sector_model） | B5 | 1 |
| B7 | 23–25（commissioning / policy_engine / blocs） | B6 | 3 |
| B8 | 26–27（diagnostics / sim_state） | B7 | 2 |
| B9 | 28–32（systems） | B8 | 5（commands 与 content_loader 可提前到 B1 起跑） |
| B10 | 33–34（application） | B9 | 2 |

**测试作者与实现者并行**：测试依据 `docs/12` 与本骨架的签名独立写，**不看实现体**
（`docs/15` 的接口纪律第 2 条）。测试与实现不一致时，先判定契约怎么说，而不是改测试迁就实现。

### 7.2 静态检查清单（骨架落地后必须能跑通的机器检查）

| 检查 | 内容 | 对应 |
|---|---|---|
| 分层 | `sim/**` 无 `Node`/`SceneTree`/`get_tree()`/UI 类型/`float`/浮点字面量/`randf` | `tools/layer_check.py`（已有） |
| 无环 | 按 §3.2 的秩逐文件检查引用图，越秩或同秩引用即失败 | 新增 `tools/check_ranks.py` |
| `JWSimState` 隔离 | `sim/**` 除 `sim/state/sim_state.gd` 外不出现 `JWSimState` | §3.1 规则 R-B |
| 派生量隔离 | `sim/**`（除 `report/diagnostics.gd`）与结算路径不出现 `JWDiagnostics` | §3.1 规则 R-C |
| 唯一过账 | `_apply_delta` 的调用点只在 `sim/ledger/ledger.gd` | INV-022 |
| 唯一时间写入 | `state.time.q` 的写只在 `JWSimState.advance_quarter_index()` | INV-012 |
| 唯一产能写入 | `*_capacity_active*` 的增量写只在 `JWCapital.commit_pending()` | INV-054 |
| 唯一价格写入 | `price`/`wage` 的写只在 `JWPricing.swap_pending()`；`pending` 的写只在 `update_*` | INV-065, 070 |
| 进度无付款依赖 | `advance_progress` 的形参表不含 `paid_uu` | INV-087 |
| 政治三分立 | `seat_rule` 不引用 `org_power_ppm`/`admin_capacity_ppm`；`update_support` 不引用 `JWInterestGroups` | INV-125 |
| 终局无 GDP | `review_and_terminate` 不引用任何 `gdp_*` 字段 | INV-128 |
| 实际 GDP 不用指数 | `compute_value_added` / `compute_gdp` 的实际值路径不引用 `consumer_index_ppm` | INV-117 |
| 借款不进 GDP | GDP 聚合的 `kind` 白名单不含 `BOND_ISSUE`/`BOND_PRINCIPAL` | INV-029 |
| 取整注释 | 每个 `floor_div`/`ceil_div`/`split_lr*` 调用点有 `# rounding: …, reason=…` | INV-002 |
| 无魔数 | `sim/**` 的裸数字字面量白名单仅 `0, 1, -1, 1_000_000` 与 §2.1 维度常量 | INV-152 |
| 遍历确定性 | 不出现 `for k in dict` | INV-008 |
| 热路径不分配 | 结算路径不出现 `JWMath.split_lr`（非 `_into` 版本）、`.new()`、`Dictionary`、`String` 拼接 | §1.4 |
| 待决引用 | 代码注释里的 `# OQ-2xx` 与 `docs/13` 双向齐全 | docs/13 §H |

---

## 8 接口变更流程与已登记缺口

### 8.1 变更流程（签名冻结后）

1. 实现者**不得**自行改签名。发现不够用 → 在任务返回值的 `interface_requests` 里登记，写清：
   谁需要、需要什么方法、为什么现有接口做不到、影响哪些不变量。
2. 骨架负责人一人统一改本文件，递增 `skeleton_revision`，并在 §8.3 追加一行变更记录。
3. 受影响的实现者与测试作者同步更新；**不允许两个人各改各的**。
4. 若变更触及稠密下标布局（§2）→ 同时升 `save.schema_version` 并写迁移函数（INV-136）。

### 8.2 本骨架已知的接口缺口与临时取法（需要在 G1 之前关闭）

| 编号 | 缺口 | 临时取法 | 关闭条件 |
|---|---|---|---|
| `IR-01` | `docs/11` §5.2 用 `IntMath.idiv_floor` 等名，本骨架用 `JWMath.floor_div` 等名 | §1.1 的对照表为唯一映射；语义完全照 11 号文件 | 11 号文件统一改名，或本表被测试引用固化 |
| `IR-02` | `MechanismRegistry` 在 `docs/11` §5.12 被引用但 `docs/15` 无对应文件 | 落在 `JWPolicyDef.MECHANISM_IDS`，12 个机制 ID 先写死 | 十一项政策规格补齐后（OQ-220）复核清单 |
| `IR-03` | `WriteGuard` / `CanonicalEncoder` / `StateView` / `IdRegistry` 在契约里是名词，`docs/15` 无文件 | 分别落在 `JWTurnRunner` 私有方法 / `JWSimState` 静态族 / `JWGame` 内部类 / `JWIds` | 骨架通过解析闸门后即可关闭 |
| `IR-04` | `param.*` 的 72 项契约最小集在内容包里**尚未写出**（`registry.json` 的 `contract_min_set_missing == 72`） | §2.6 已按该最小集把下标布局与 `PARAM_N = 76` 定死；内容作者逐项补参数卡 | 72 张卡补齐且 `validate_params()` 通过 |
| `IR-05` | `docs/10` §2.1 的「持有现金的主体共 55 个」与表内 56 行不一致 | §2.3 给出两个常量并按 OQ-217 解释：`opening` 有 cash 科目但恒为 0 | `T-U-OPENING-BALANCE` 通过后关闭 |
| `IR-06` | `state.region.emissions_stock` / `env_exposure` 在 `docs/15` 无归属文件 | 归 `JWCapital`（与地区设施同表，保 INV-054 的单一写入点纪律） | 若将来环境反馈到生产（OQ-226），须拆出独立文件并重排秩 |
| `IR-07` | 国内市场撮合（`docs/12` §5.6）在 `docs/15` 无归属文件 | 归 `JWInventory`（INV-047 与 INV-059 是同一笔账的两半） | 若市场规则复杂化到独立模块，走 §8.1 流程 |
| `IR-08` | `pubserv` 的服务种类拆分（health/education/utility）在契约里只出现在 `service_access` 与 `queue_persons` | §2.1 固化 `SERVICE_KIND = 3`，`OPEX_N = 12` | OQ-239（服务部门内「施工」与「公共服务」的产能拆分）定稿后复核 |
| `IR-09` | 事件模板的条件槽位数（本骨架取 4）与效果槽位数（取 4）无契约来源 | 取 4，加载期超出即 `Load.EVENT_FIELD` | 12 个事件模板定稿后（OQ-243）对齐真实最大值 |
| `IR-10` | `CLAIM_CAP = 2048`、`CMD_CAP = 4096`、`MIGRATION_CAP = 256` 三个容量上限无契约来源 | 按 120 季 × 规模上界估出；写满即 `INDEX_OUT_OF_RANGE`（**不静默丢弃**） | 压力测试 `T-X-*` 实测峰值后固化 |

### 8.3 变更记录

| revision | 日期 | 变更 | 影响文件 |
|---|---|---|---|
| 1 | 2026-09-12 | 首次定稿：34 个文件的类名、成员、签名、调用方向与八步序列 | 全部 |

---

## 9 给实现者的十条硬提醒

1. **`post()` 是唯一的过账入口。** 你的类里不该出现任何直接改 `balance` 的代码。
2. **失败要显式返回。** 钱不够、货不够、人不够 → 登记欠付／延期／取消／配给／未满足，
   **返回 `OK` 并继续**；恒等式破裂才返回 Fault。没有第三种。
3. **除法只走 `JWMath`。** 裸 `/` 与 `%` 在 `sim/**` 是构建失败。每个调用点写 `# rounding: …, reason=…`。
4. **拆分只走 `split_lr_into`。** `Σ 分项 == 总额` 是后置断言，不是「一般成立」。
5. **零系数跳过，不除零，也不用 `max(c, 1)`。** 后者会造出一个巨大的假候选值，是隐蔽缺陷。
6. **能力类效果只写 `*_pending_*`。** 写 `*_active_*` 的代码一定是错的，WriteGuard 会抓住你。
7. **热路径不新建对象。** 需要临时数组 → 找 `JWTurnRunner` 要一个 scratch，或把 `out` 参数加进签名
   （改签名要走 §8.1）。
8. **不要为了方便引用 `JWSimState`。** 你需要的数据以形参传进来；如果参数太长，说明这一步
   的输入确实就有这么多，**让它显式**。
9. **不要新建错误码。** 全在 `JWResult`。需要新的 → 走 §8.1。
10. **不要写「平衡修正」。** 不存在 S09，不存在 `apply_balance_fix()`。
    掩盖错账比崩溃更危险（计划书 §13）。

---

*本文件是实现期的唯一接口契约。与之冲突的实现是缺陷，不是特性。*
*语义冲突时，以 `docs/ref/plan_v1.0.txt` → `docs/10` → `docs/11` → `docs/12` → `docs/15` → `docs/13` 的优先级为准。*
