# 12 结算合同（唯一权威版）

> 对应计划书 §13「把每个季度结算成可审计的过程」、§06（生产约束、价格、库存）、§07（财政恒等式与融资）、
> §10（P04 验收测试）、§12（分层与禁止事项）、§17（质量门槛与恶意玩家测试）。
>
> 本文件把八步结算写成**可以直接照着写代码**的规格：每步给出输入、输出、可写状态子集、必记日志、
> 步末不变量、失败行为。所有公式为 int64 整数运算，逐处标注单位与取整方向。
> 变量语义见 `10_variable_dictionary.md`，数据形态见 `11_data_contract.md`。
>
> 立场：**结算是一次记账，不是一次计算。** 每一步的产物首先是分录，其次才是指标。
> 不存在「先算出结果再补一笔账」的环节；**不存在 S09**，也不存在 `apply_balance_fix()`。

---

## 0 全局执行约定

### 0.1 分层职责与可静态检查的禁止事项（计划书 §12 的可执行版）

| 层 | 目录 | 职责 | 禁止事项（可被静态检查的形式） |
|---|---|---|---|
| SimCore | `res://sim/**` | 权威状态、八步结算、账本、领域规则 | 禁止引用 `Node` / `SceneTree` / `get_tree()` / `tr(` / `res://ui/**`；禁止 `float`；禁止 `String` 拼接与 `Dictionary` 键查找；禁止读时钟、读文件、读引擎随机源；禁止叙事文案 |
| Application | `res://systems/**` | 命令校验、回合调度、存档、重放、内容加载 | 禁止绕开资金与政策权限校验直接调 SimCore 的私有写函数；SimCore 的状态写接口一律以 `_` 开头且只由 `TurnRunner` 调用 |
| Presentation | `res://ui/**` | 地图、表格、图表、报告、输入 | 禁止引用 SimCore 的写接口；只能拿 `StateView`（只读快照句柄）；传出前 `duplicate()` |
| Content | `res://content/**` | 剧本、政策、事件、冲击、参数、本地化 | 只有 JSON，无脚本；一切副作用必须经 `MechanismRegistry` 中已注册的机制 |

| 工具 | 检查 | 对应不变量 |
|---|---|---|
| `tools/check_layers.gd` | 各层源码的引用图，越层引用即失败 | — |
| `tools/check_no_float.gd` | `sim/**`、`systems/**` 中的 `float`、`PackedFloat`、小数字面量 | INV-001 |
| `tools/check_int_div.gd` | `sim/**` 中整数上下文的裸 `/` 与 `%`；`# rounding:` 注释缺失；**`floor_div(mul(a,b), c)` / `ceil_div(mul(a,b), c)` 形态的先乘后除**（R-SCALE-01：一律改走 `mul_div_floor`，见 §0.3） | INV-002, INV-006 |
| `tools/check_dict_iteration.gd` | 直接 `for k in dict` | INV-008 |
| `tools/check_writers.gd` | 每个状态数组的写调用点必须落在字典声明的写者步骤所在文件内 | INV-013 |
| `tools/check_param_coverage.gd` | `sim/**` 中的裸数字字面量（白名单 `0,1,-1,1000000` 与维度常量） | INV-152 |
| `tools/check_gdp_inputs.gd` | GDP 函数的输入白名单不含借款／还本；实际 GDP 函数不引用任何价格指数 | INV-029, INV-117 |
| `tools/check_politics_separation.gd` | `seat_rule` 不引用 `org_power_ppm`；实施速度函数只引用 `admin_capacity_ppm` | INV-125 |

### 0.2 唯一的过账入口

SimCore 内改变金额／数量的唯一入口：

```gdscript
# 一次调用产生一笔 txn，含 >= 2 条有符号过账行（10_variable_dictionary.md §2.5）
func post(kind: int, payer_account: int, payee_account: int,
          amount_uu: int, qty_uqs: int, product: int,
          cause: int, entity_ref: int) -> int      # 返回 Fault 码
```

- `amount_uu >= 0`，方向由 `payer → payee` 决定；三重分类码由 `kind` 查 `11_data_contract.md` §5.3 的表自动填入。
- 每次调用后立即检查 `payer` 现金 ≥ 0（INV-016）；不足则**整笔回滚**并返回 `INSUFFICIENT_CASH`，
  由调用方决定转欠付、缩减规模还是延期。**永远不允许先扣成负数再想办法。**
- 实物移动写 `log.physical`（`from`/`to` 为库存位置），与资金行同 `txn_id`。
- `post()` 之外**不存在**直接赋值 `cash` / `inv` / `capital` / `debt` 的 API（INV-022，静态检查）。

### 0.3 整数工具与遍历确定性

一切除法经 `IntMath.idiv_floor / idiv_ceil / mul_div_floor / mul_ppm / mul_ppm_2 / split_largest_remainder`
（前四者的实现名见 `17_api_skeleton.md` §1.1，语义见 `11_data_contract.md` §5.2）。
一切乘法经 `IntMath.mul` 的**显式**溢出前置检查（不用 `assert`：Godot 在 release 会剥离它）。

#### 0.3.1 货币刻度与本文件全部溢出复核的前提（裁定 R-SCALE-01）

| 常量 | 值 | 出处 |
|---|---|---|
| `U_SCALE`（1 U = ? μU） | `1 000 000 000` | `sim/jw_units.gd` |
| `Q_SCALE`（1 Q_s = ? μQ_s） | `1 000 000` | 同上 |
| `PPM` | `1 000 000` | 同上 |
| `BASE_PRICE` | `1 000 000 000` μU/Q_s | 同上，INV-148 |
| `BASE_YEAR_GDP_UU`（基年全年名义） | `100 000 000 000` μU | 同上，INV-118 |
| `AMOUNT_MAX` | `4 000 000 000 000 000`（4e15） | 同上，INV-007 |
| `QTY_MAX` | `1 000 000 000 000`（1e12） | 同上，INV-007 |
| `PRICE_MIN` / `PRICE_MAX` | `400 000 000` / `2 500 000 000` μU/Q_s | 同上，INV-066 |
| `INT64_MAX` | `9 223 372 036 854 775 807`（≈9.22e18） | 同上 |

本文件每一处「溢出：… ✓」的复核都以上表为上界，**不以剧本实测值为上界**。

#### 0.3.2 「先乘后除」的唯一合法入口

新刻度下 `mul(AMOUNT_MAX, PPM) = 4e21` 与 `mul(QTY_MAX, PRICE_MAX) = 2.5e21` **真的溢出 int64**。
因此：

```gdscript
mul_div_floor(a, b, c) -> int          # c > 0；精确等于 floor(a*b/c) 的数学真值
    # 实现：a = q*c + r（0 <= r < c，floor 语义）；返回 q*b + floor(r*b/c)
    # 中间量最大只到 max(|q*b|, |r*b|)，而不是 |a*b|
```

- **凡是「先乘后除」，一律写成 `mul_div_floor(a, b, c)`**，不得再写 `idiv_floor(IntMath.mul(a, b), c)`。
  `tools/check_int_div.gd` 静态拦截后者（§0.1）。
- `mul_ppm(x, p)` ≡ `mul_div_floor(x, p, 1_000_000)`，`mul_ppm_2(x, p1, p2)` 的第二次缩放同样走它。
  **本文件中一切 `mul_ppm` / `mul_ppm_2` 因此已经是合规写法，无需逐处展开**；
  这也是 `mul_ppm(capital_value_uu ≤ 4e15, depreciation_ppm)`、`mul_ppm(base_credit_limit_uu, …)`、
  `mul_ppm(value_uu, 1e6 + logistics_cost_ppm)` 这类「金额 × ppm」在新刻度下仍然安全的唯一理由。
- **`mul_ppm_2` 有一个仍然裸乘的位置**：它的第一步是 `floor_div(mul(p1, p2), 1e6)`，
  即**两个 ppm 相乘**，不经 `mul_div_floor`。只要 `p1, p2` 都在 `0…3e6` 的常规 ppm 区间内，
  积 ≤ 9e12，安全；但若某个「ppm」实际上是一个**无上界的派生比率**（§7.9 的 `density_ppm` 就是），
  这一步会溢出。**每个 `mul_ppm_2` 调用点必须自己写明两个 ppm 的上界**（本文件已逐处写明）。
- 需要向上取整的先乘后除，写成本文件的别名：

```
mul_div_ceil(a, b, c)  ≡  -mul_div_floor(-a, b, c)          # c > 0，精确等于 ceil(a*b/c)
```

  > `JWMath` 目前**没有**独立的 `mul_div_ceil` 实现。实现者要么按右边的展开式逐处写，
  > 要么走 `17_api_skeleton.md` §8 的接口变更请求补一个同名静态函数。
  > **不允许**退回 `ceil_div(mul(a, b), c)`——那正是被静态检查拦截的形态。

- `mul_div_floor` / `mul_div_ceil` 与数学真值**精确相等**，所以本文件中一切以「floor / ceil 的数学性质」
  为前提的推导（§5.4 的整数引理、§6.4 的 GDP 恒等式）在换用它们之后**逐字成立，不需要重证**。

#### 0.3.3 基年价计值 `at_base`（R-SCALE-01 打破了旧的数值巧合）

```
at_base(qty_uqs, s) = mul_div_floor(qty_uqs, content.price.base_uu_per_qs[s], 1_000_000)   # μQ_s -> μU
```

- 因 INV-148 钉死 `base_uu_per_qs[s] == BASE_PRICE == 1 000 000 000`，而 `1e9 / 1e6 == 1000` 整除，
  故 **`at_base(q) == 1000 · q`，精确无余数**，且对加减法完全线性（先求和再计值 ≡ 逐项计值再求和）。
- **旧刻度下 `BASE_PRICE / Q_SCALE == 1`，于是「基年价计值的 μU 数值恒等于 μQ_s 数值」。
  新刻度下这个巧合没有了。** `10_variable_dictionary.md` §2.3 与 §4 库存科目的表述仍停留在旧巧合上，
  必须同步（登记于本文件 §16 的同步记录）。本文件凡是「按基年价计值」的地方**一律显式写 `at_base(...)`**，
  不再依赖两个数字碰巧相等。
- 溢出：`mul(QTY_MAX, BASE_PRICE) = 1e21` 裸乘溢出；走 `mul_div_floor` 后中间量
  `floor(1e12 / 1e6) × 1e9 = 1e15` ✓，且 `1e15 < AMOUNT_MAX = 4e15`，与 INV-007 相容。

#### 0.3.4 遍历确定性

任何对集合的遍历必须先取键并按稳定 ID／下标升序；禁止 `for k in dict`（INV-008）。
理由：重放一致性，也是最大余数法决胜键能生效的前提。

### 0.4 确定性抽样（计数器式，无偏）

```gdscript
const SALT: PackedInt64Array = content.rng.salt     # 6 个 int64 常量，属 schema

static func splitmix64(x: int) -> int:
    # 纯 int64 环绕算术；右移必须用逻辑右移 (x >> n) & mask，GDScript 的 >> 对负数是算术右移
    # 已知测试向量见 tests/unit/test_u_splitmix64.gd
    ...

static func draw_raw(stream: int, q: int, index: int) -> int:
    return splitmix64(state.rng.root_seed ^ SALT[stream] ^ (q << 32) ^ index)

# 无偏的 [0, n) 均匀整数：拒绝采样，消除取模偏差
static func draw_below(stream: int, q: int, n: int) -> int:
    var limit: int = (1 << 62) - ((1 << 62) % n)        # 拒绝阈
    while true:
        var r: int = draw_raw(stream, q, state.rng.draw_count[stream]) & ((1 << 62) - 1)
        state.rng.draw_count[stream] += 1
        log_rng(stream, r)                               # INV-011：每次抽样都写日志，含被拒的那次
        if r < limit:
            return r % n

static func draw_ppm(stream: int, q: int) -> int:        # [0, 1_000_000)
    return draw_below(stream, q, 1_000_000)

static func draw_range(stream: int, q: int, lo: int, hi: int) -> int:   # 闭区间 [lo, hi]
    return lo + draw_below(stream, q, hi - lo + 1)
```

拒绝采样的重抽也推进计数器并写日志，因此重放逐位一致；期望重抽次数 < 1e-12 次/抽样。
**被拒的那次抽样必须写进 `log.rng`**，否则「同季 `log.rng` 条数 == Σ Δdraw_count」（INV-011）会误报。

### 0.5 结算骨架

```gdscript
# systems/turn_runner.gd （Application 层）
func advance_quarter(st: SimState, cmds: CommandBatch) -> int:      # 返回 Fault 码
    if st.meta.run_terminated:            return reject(E_RUN_TERMINATED)
    if st.time.phase != PHASE_IDLE:       return reject(E_PHASE_BUSY)

    for step in range(1, 9):
        st.time.phase = step
        WriteGuard.begin(step)                        # 调试构建全开，发布构建按季抽样
        var fault: int = _run_step(step, st, cmds)
        WriteGuard.end()                              # 越权写入 -> Fault.WRITE_OUT_OF_SCOPE
        _check_invariants(STEP_INVARIANTS[step])      # 步末不变量
        _record_step_hash(st, step)                   # 逐步骤子系统哈希，用于重放二分
        if fault != Fault.OK:
            return _enter_fault(st, step, fault)      # 见 §8

    _check_invariants(QUARTER_END_INVARIANTS)
    st.time.phase = PHASE_IDLE
    return Fault.OK
```

- 八步**顺序固定、不可重入、不可回退**（INV-012）。没有任何步骤可以回头调用前面的步骤。
- 每步只允许写其可写子集白名单（INV-013）。白名单是本文件每一步表格中的「可写子集」行，
  由 `check_writers.gd` 静态验证 + `WriteGuard` 运行期验证（进入前对不属于该步的子系统取哈希，
  退出时比对）。
- 每步入口把该步要用的 scratch 数组 `fill(0)`（预分配，不新建）。
- 每步结束记录 `step_hash`（对该步**允许写的子集**做规范化 SHA-256），8 个哈希写入 `checkpoints.jsonl`。

### 0.6 三种失败语义（贯穿八步）

| 语义 | 何时用 | 状态后果 | 日志 | 测试判据 |
|---|---|---|---|---|
| `REJECT` | 命令不合法（只发生在命令提交与 S02 受理） | **完全不变** | `log.rejections` | 状态哈希不变 |
| `ARREARS` | 现实约束不满足：钱不够、货不够、人不够、队列满 | 变，但账目自洽：记欠付／延期／取消／配给／未满足 | `log.arrears` / `log.constraint_diag` | 相关不变量仍成立 |
| `FAULT` | 恒等式破裂 = 程序缺陷 | 结算中止，导出故障包 | 故障包 | 测试期望永不发生 |

**禁止第四种**：没有「先记负数，季末统一抹平」这种路径（计划书 §13 禁止后处理补丁）。

---

## 1 S01 冻结起点

**计划书**：读取状态快照；校验命令；确定当季外部条件。必须记录版本、命令、随机流状态与冲击。

| 项 | 内容 |
|---|---|
| 输入 | 上季末完整状态；本季命令队列；`content_hash`；`shock_log` |
| 输出 | 本季只读快照；已校验命令列表；本季外部条件；待投运产能转入 |
| **可写子集** | 全部 `flow.*`（清零）；`state.cell.capacity_active_uqs_per_q`、`state.pubserv.capacity_active_uqs_per_q`、`state.region.grid_capacity_uqs_per_q`、`state.region.housing_stock_units`、`state.region.port_capacity_uqs_per_q`、`state.region.irrigation_index_ppm`（转入）；对应的全部 `*_pending_*`（置 0）；`state.project.status`、`state.project.commissioned_q`；`state.world.*`；`state.rng.draw_count`；`state.meta.state_hash_prev`；`log.rejections`、`log.rng` |
| 日志 | `schema_version` / `content_hash` / `param_set_version` / `q`；每条命令（含被拒与原因码）；本季冲击抽样完整记录（含 `draw_index`、`raw_u64`、`mapped_value`） |

### 1.1 执行顺序

**01.1 记录入口哈希**：`state.meta.state_hash_prev = state_hash()`，写 `checkpoints`。

**01.2 版本校验**：`build_id` 不符 ⇒ 置 `replay_unreliable` 并禁用重放验证（仍可推进）；
`content_hash` 或 `param_set_version` 不符 ⇒ 进入只读检视模式，**拒绝推进**（INV-134）。

**01.3 流量清零**：遍历**流量注册表**，对全部 `flow.*` 数组 `fill(0)`。
**这是全局唯一允许整表清零流量的地方**；任何其它步骤清零流量都是缺陷（会掩盖重复记账）。
清零后断言 `Σ|flow| == 0`（否则 `Fault.FLOW_NOT_RESET`，说明有步骤在 S08 之后写了流量）。

**01.4 待投运资产转入（「当季完工，下季供能」的唯一实现点，INV-054/091）**

```
for i in 0..15:
    cell.capacity_active_uqs_per_q[i]     += cell.capacity_pending_uqs_per_q[i]
    cell.capacity_pending_uqs_per_q[i]     = 0
for r in 0..3:
    pubserv.capacity_active_uqs_per_q[r]  += pubserv.capacity_pending_uqs_per_q[r]
    pubserv.capacity_pending_uqs_per_q[r]  = 0
    region.grid_capacity_uqs_per_q[r]     += region.grid_capacity_pending_uqs_per_q[r]
    region.grid_capacity_pending_uqs_per_q[r] = 0
    region.housing_stock_units[r]         += region.housing_pending_units[r]
    region.housing_pending_units[r]        = 0
    region.port_capacity_uqs_per_q[r]     += region.port_capacity_pending_uqs_per_q[r]
    region.port_capacity_pending_uqs_per_q[r] = 0
    region.irrigation_index_ppm[r]         = clamp(region.irrigation_index_ppm[r]
                                                 + region.irrigation_index_pending_ppm[r], 0, 2_000_000)
    region.irrigation_index_pending_ppm[r] = 0
for p in projects where status == completed:
    status = commissioned ; commissioned_q = state.time.q
```

**统一规则**：**一切「完工后才生效的能力或设施」都必须经 `*_pending_*` 缓冲，并且只在本步转入。**
政策效果的落点白名单（`11_data_contract.md` §5.12）在加载期就拒绝任何直接写 `*_active_*` 的效果（V-PD-11）。
这样「下季供能」不依赖任何步骤顺序的隐含假设。

**为什么在 01 而不是 07**：项目在第 `q` 季的 S07 完工 ⇒ 写 `*_pending`；第 `q+1` 季的 S01 转 `*_active`；
第 `q+1` 季的 S03 制定计划时才看得见，S05 生产时才用得上。放在 S07 末尾 swap 则依赖「S05 在 S07 之前」
这一隐含顺序，将来插入步骤即静默失效。
**验收测试** `T-S-COMMISSION-LAG`：项目在 q=7 完工，断言 q=7 的 `bound_capacity` 不含新增，q=8 的含，
且 `commissioned_q == 8`。

断言：转入后 `Σ capacity_pending == 0`、`Σ housing_pending == 0`。

**01.5 命令校验（只判定，不执行）**：逐条按 `(issued_q, command_id)` 升序检查格式、权限、前置条件。
被拒命令写 `log.rejections` 并附原因码，**仍进入命令流**，不进入执行队列（INV-137）。

**01.6 冲击确定**（按 `shock_id` 升序，确定性）

```
for k in [S01, S02, S03]:
    # (a) 先查 shock_log：已有本 q 的记录则直接复用，rng.shock 不推进
    if shock_log.has(q, k):
        apply_record(shock_log.get(q, k)) ; continue         # 堵住「存档重载重抽已确定事件」(INV-109)

    # (b) 衰减既有冲击
    if world.shock_remaining_q[k] > 0:
        world.shock_remaining_q[k] -= 1
        if world.shock_remaining_q[k] == 0:
            world.shock_active[k] = 0 ; world.shock_magnitude_ppm[k] = 0
        continue

    # (c) 到达抽样
    if q < earliest_q[k] or q - last_end_q[k] < min_gap_q[k]: continue
    if draw_ppm(STREAM_SHOCK, q) >= hazard_ppm_per_q[k]: continue
    var m: int = draw_range(STREAM_SHOCK, q, mag_min[k], mag_max[k])
    var d: int = draw_range(STREAM_SHOCK, q, dur_min[k], dur_max[k])
    world.shock_active[k] = 1 ; world.shock_magnitude_ppm[k] = m ; world.shock_remaining_q[k] = d
    shock_log.append({q, k, m, d, draw_index, raw_u64, mapped_value})
```

**01.7 冲击落到外部账户**（只写 `state.world.*` 白名单，INV-108）

```
# 衰减因子：step -> 1e6 全程；linear -> 剩余季数/总季数
decay_ppm = (profile == step) ? 1_000_000
                              : mul_div_floor(remaining_q, 1_000_000, duration_q)
                                # 前置：duration_q >= 1（由 dur_min[k] >= 1 保证；为 0 即 Fault.DIV_ZERO）
                                # 溢出：remaining_q <= dur_max <= 40 -> 4e7 ✓
eff_ppm[k] = mul_ppm(shock_magnitude_ppm[k], decay_ppm)                       # ppm

world.export_demand_ppm[s] = clamp(base_export_ppm[s]
        + mul_ppm(eff_ppm[S01], target_weights_ppm[S01][s]), 0, 3_000_000)
world.import_price_ppm[s]  = clamp(base_import_ppm[s]
        + mul_ppm(eff_ppm[S02], target_weights_ppm[S02][s]), 100_000, 5_000_000)
world.sovereign_rate_ppm_per_q = clamp(param.market_rate_base_ppm
        + mul_ppm(eff_ppm[S03], param.rate_sensitivity_ppm), 0, 100_000)
world.credit_limit_uu = mul_ppm(base_credit_limit_uu,
        clamp(1_000_000 - eff_ppm[S03], 0, 1_000_000))
# 溢出：base_credit_limit_uu <= AMOUNT_MAX = 4e15，裸乘 ×1e6 = 4e21 会溢出；
#       mul_ppm 走 mul_div_floor（§0.3.2），中间量 = floor(4e15/1e6)×1e6 = 4e15 ✓
```

**01.8 债券分期表的起点定义（INV-037 的断言落点）**

`amort_schedule` 是**只读派生表**，不是状态：每个批次一生只生成一次，此后永不重算
（重算会让「旧债不重定价、不自动展期」的 INV-036/038 失去数据依据）。

| 批次来源 | 生成时点 | 覆盖季区间 | 期数 `n` | 权重 |
|---|---|---|---|---|
| 剧本开局存量（`issue_q < 0`） | 载入期，解析 `government_init.json` 时 | `issue_q + 1 … maturity_q`（**闭区间**） | `maturity_q − issue_q` | 全 1（等权重） |
| 运行期新发（见 02.6） | 发行当季 S02 | 同上 | 同上 | 全 1 |

```
bullet          : amort_schedule = { maturity_q: principal_initial_uu }，其余季为 0
level_principal : parts = split_largest_remainder(principal_initial_uu, [1]×n, 期下标升序)
                  amort_schedule[issue_q + 1 + i] = parts[i]      for i in 0..n-1
                  # 等权重下最大余数法退化为「余 r 单位给最早的 r 期，各 +1 μU」
                  # Σ parts == principal_initial_uu，精确（INV-003）
```

**起点为什么是 `issue_q + 1` 而不是 `issue_q`**：02.3／02.4 在第 q 季对**季初仍未偿还的本金**计息并还本，
而发行当季的资金在 02.6 才到账。若把第一期放在 `issue_q`，发行季末 `principal_outstanding` 会小于面值，
而 02.6 的过账额是面值 —— 同一季的两笔账对不上，INV-035（`debt == Σ outstanding`）当季即破。

**S01 的断言（INV-037 的唯一可执行写法）**：

```
for b in sorted(bonds by bond_idx):
    if bond.status[b] == active:
        assert Σ_{q' >= state.time.q} amort_schedule[b][q'] == bond.principal_outstanding_uu[b]
    # 不成立 -> Fault.BOND_MISMATCH（不是 ARREARS：这是表与账脱钩，属于缺陷）
```

**开局剧本的复核**（`content/scenarios/chengwan/government_init.json`，两笔 `level_principal`）：

| 批次 | `issue_q` | `maturity_q` | `n` | 每期 | q<0 已还 | q=0 起剩余 | `principal_outstanding_uu` |
|---|---|---|---|---|---|---|---|
| `bond.q-12_01` | −12 | 24 | 36 | 400 000 000 | 11 期 = 4 400 000 000 | 25 期 = 10 000 000 000 | 10 000 000 000 ✓ |
| `bond.q-8_01` | −8 | 19 | 27 | 500 000 000 | 7 期 = 3 500 000 000 | 20 期 = 10 000 000 000 | 10 000 000 000 ✓ |

两笔面值（14 400 000 000 / 13 500 000 000）都被 `n` 整除，等权重拆分无余数。
`tools/validate_content.py` 的 `amort_schedule()` 已按本定义实现并逐笔复核（注释中引用的正是本节）。

### 1.2 步末不变量

INV-012（`phase == S01`）、INV-054/091（`Σ pending == 0`）、全部 `flow.*` 为 0、
INV-011（`log.rng` 条数 == Σ Δdraw_count）、INV-037（01.8 的分期表与余额对账）、INV-109、INV-134。

### 1.3 失败行为

| 情形 | 行为 |
|---|---|
| `content_hash` 不符 | 拒绝推进，进入只读检视模式 |
| 命令格式非法 | `REJECT` 该条，记原因码，继续 |
| 流量清零后仍非零 | `Fault.FLOW_NOT_RESET` |
| 分期表剩余额 ≠ `principal_outstanding_uu` | `Fault.BOND_MISMATCH`（01.8） |
| `shock_log` 与计数器矛盾 | `Fault.RNG_LOG_MISMATCH`，终止并保留现场 |

---

## 2 S02 审核与融资

**计划书**：通过生效政策；预留合同资金；处理到期债务。必须检查可用现金、信用额度、支付优先级。

| 项 | 内容 |
|---|---|
| 输入 | 已校验命令；`state.gov.*`；`state.bond.*`；`agent.invpool.cash`；`state.world.credit_limit_uu`；`content.scenario.annual_plan`、`content.scenario.season_factor_ppm` |
| 输出 | 本季财政额度（年计划拆季）；政策生效状态；项目立项／取消；资金预留；到期债务处理；新发债 |
| **可写子集** | `flow.gov.primary_budget_q_uu`、`state.policy.*`（除 `pending_params`）、`state.project.*`（新建/取消/槽位）、`state.gov.cash/arrears/arrears_by_payee/committed_memo/reserved_memo/rounding_residual`、`flow.gov.interest_paid/principal_paid/new_borrowing/recognized_writeoffs/arrears_added/arrears_cleared`、`state.bond.*`、`state.world.credit_used_uu`、`state.invpool.*`、`flow.invpool.*`、`state.group.deposit_uu`（认购）、`state.politics.next_budget_review_q`、`state.meta.entity_seq`、`log.*` |
| 日志 | 本季基本支出额度与其年计划来源；每项政策的资格判定与 `blocked_reason`；每笔预留（金额、用途、来源）；每笔发行（批次、票息、期限、债权人）；每笔利息与还本；每条支付优先级裁决；票息取整余数 |

### 2.1 执行顺序（不可交换）

**02.0 年计划拆季：季节系数的作用基数（裁定 R-SEASON-01，INV-042）**

季节系数**只作用于基本支出**，即「年度支出 − 全年利息 − 全年到期本金」。
利息与到期本金由 `bond_book` 逐批次逐季单独算出（02.3／02.4），**不受季节性支配**。

**逐季重算，不跨季暂存**：本步的全部量都是「当季 `bond_book` 的纯函数」，每季重新推一遍，
不写任何跨季字段（与 §0.5「每步入口 `fill(0)`」、S03 裁定「跨步暂存消失」同一纪律）。
后果必须写明：**年中新发债或重组会改变本年剩余各季的基本支出额度**——年度支出总额不变，
利息变多则基本支出变少。这是正确的挤出行为，不是缺陷；代价是「年初算出的四季数」与
「逐季实际额度」在发生年中融资时会不一致，报告须按当季重算值展示。

```
# (a) 全年利息与全年到期本金：不是计划值，是把 01.8 的分期表与票息率在本会计年四季上求和。
#     第 t 季的未偿本金由 amort_schedule 前推得到，故这是确定性的纯推算，不需要跑结算。
year        = idiv_floor(state.time.q, 4)                     # 基年为 0
interest_year_uu  = Σ_{t=0..3} Σ_{b: status == active at 4*year+t} interest_due(b, 4*year + t)
                    # 02.3 的逐批次口径，含余数累加器；不得用平均利率近似（INV-036）
principal_year_uu = Σ_{t=0..3} Σ_b amort_schedule[b][4*year + t]    # 01.8 的分期表

# (b) 现金口径的年计划（annual_plan.expenditure_incl_interest_uu 按定义**不含还本**）
annual_cash_outflow_plan_uu = content.annual_plan.expenditure_incl_interest_uu
                            + principal_year_uu

# (c) 季节系数的作用基数 = 基本支出年额
gov_primary_annual_uu = annual_cash_outflow_plan_uu - interest_year_uu - principal_year_uu
                      = content.annual_plan.expenditure_incl_interest_uu - interest_year_uu

# (d) 拆四季：最大余数法，禁止逐季 mul_ppm 后丢余数（INV-042、INV-003）
primary_q_uu[0..3] = split_largest_remainder(gov_primary_annual_uu,
                                             content.season_factor_ppm.gov_primary,
                                             季下标升序)
flow.gov.primary_budget_q_uu = primary_q_uu[state.time.q mod 4]
# 收入侧同法：receipts_q_uu[0..3] = split_largest_remainder(annual_plan.receipts_uu,
#                                    season_factor_ppm.gov_receipts, 季下标升序)
```

**校验式（四季合计 + 全年利息 + 全年还本 ≡ 年计划）**

```
Σ_{t=0..3} primary_q_uu[t] == gov_primary_annual_uu                       # 最大余数法的后置断言
Σ_{t=0..3} primary_q_uu[t] + interest_year_uu + principal_year_uu
        == annual_cash_outflow_plan_uu                                     # 现金口径，恒等式
Σ_{t=0..3} primary_q_uu[t] + interest_year_uu
        == content.annual_plan.expenditure_incl_interest_uu                # 支出口径，等价写法
Σ season_factor_ppm.<line> == 1_000_000                                    # 加载期，INV-042
```
前三条在每季 S02 末检查，不成立即 `Fault.LEDGER_IMBALANCE`；第四条在加载期检查。
**第二条与第三条必须同时写出来**：第二条钉住「还本也在现金计划里」，第三条钉住「还本不是支出」。
只写其中一条，实现者就能在两个口径之间悄悄换算而不被发现——这正是 R-SEASON-01 要堵的洞。

**基年剧本的复核**（`government_init.json` + `scenario.json`，全部为 μU）：

| 项 | 值 | 来源 |
|---|---|---|
| `expenditure_incl_interest_uu` | 22 000 000 000 | `annual_plan` |
| `interest_year_uu`（q=0..3 逐批次） | 2 033 700 000 | 523 500 000 / 513 450 000 / 503 400 000 / 493 350 000 |
| `principal_year_uu`（q=0..3 逐批次） | 3 600 000 000 | 两笔 `level_principal` 各 400 000 000 + 500 000 000，每季 900 000 000 |
| `gov_primary_annual_uu` | 19 966 300 000 | 22 000 000 000 − 2 033 700 000 |
| `primary_q_uu[0..3]` | 4 791 912 000 / 4 991 575 000 / 5 091 406 500 / 5 091 406 500 | 系数 240 000 / 250 000 / 255 000 / 255 000 |
| `annual_cash_outflow_plan_uu` | 25 600 000 000 | 22 000 000 000 + 3 600 000 000 |

四季合计 19 966 300 000 ＋ 利息 2 033 700 000 ＋ 还本 3 600 000 000 ＝ 25 600 000 000 ✓。
`interest_year_uu` 与 `annual_plan.expenditure_lines_uu.interest` 逐 μU 相等（V-FIN-05、INV-147）。
新刻度下 `19 966 300 000 × 255 000 / 1e6` 整除，四季拆分**没有余数**——
旧刻度注释里「余 1 μU 给到第 3 季」的说法已作废。

> **这条以前是空的。** `season_factor_ppm` 与 `annual_plan` 在本契约中曾是零命中：
> 内容层推出四季数只写在 `_note_*` 里，结算无人读，INV-042 退化成「四项和等于 1e6」的空断言。
> 02.0 是它们唯一的读取点。`flow.gov.primary_budget_q_uu` 是本次同步**新增**的流量字段，
> 需要 `11_data_contract.md` §4 与 `10_variable_dictionary.md` 补声明（见 §16）。

**02.1 命令受理**（按 `(issued_q, command_id)` 升序）

```
资格检查链（任一失败即 REJECT，记 reject_code，命令仍入档）：
  1 legal_authority : (politics.legal_authority_mask >> bit) & 1 == 1
                      且 mul_div_floor(seats_gov, 1_000_000, seats_total) >= min_seats_ppm
                      # seats_total 为奇数且 >= 1（V-POL-02）；溢出：101 × 1e6 = 1.01e8 ✓
                      且 无 bloc 否决（bloc.veto_domains 命中且 stance_ppm < 阈值）      -> E_AUTHORITY / E_SEATS_SHORT / E_BLOC_VETO
  2 cooldown        : q >= policy.cooldown_until_q                                      -> E_POLICY_COOLDOWN
  3 precondition    : 逐条求值（只有比较，无表达式器）                                    -> E_PRECONDITION
  4 queue slot      : derived.region.construction_slots_used[r] < region.construction_slots_total[r]  -> E_NO_SLOT
  5 funding         : 见 02.2                                                            -> E_NO_FUNDING / E_BUDGET_INSUFFICIENT
```

通过后：

```
policy.enacted_q        = q
policy.effective_from_q = q + lag.enact_to_effect_q          # 只能向前，不得回溯（INV-098）
policy.toggle_count    += 1
policy.cooldown_until_q = q + policy_def.cooldown_q
post(kind=policy_toggle_cost, gov -> pubserv 运营, param.policy_toggle_cost_uu)   # 开关有真实成本
```

**INV-095**：所有政策效应函数在 `q < effective_from_q` 或 `enabled == 0` 时返回零效应。

**02.2 预算预留（不是支付）**

```
need_uu  = policy_def.cost.per_quarter_uu                    # μU
avail_uu = gov.cash_uu - gov.reserved_memo_uu                # μU
funding_source == "cash"  且 need > avail   -> REJECT(E_BUDGET_INSUFFICIENT)
funding_source == "bond"                    -> 进入 02.6 的发债需求队列
gov.reserved_memo_uu      += need_uu
gov.committed_memo_uu     += policy_def.cost.one_off_uu      # 未来全部季承诺
policy.budget_committed_uu += policy_def.cost.one_off_uu
```

> **预算不是资产**（计划书 §07）：`reserved_memo` 只减少可用额度，**不产生任何现金移动**。
> 真正的付款在 S04。预留写 `log.ledger` 的 `kind = 4`（状态变更）通道，**不写资金行**——混记会让 INV-027 失衡。

**02.3 到期利息（逐批次，固定利率不重定价）** 按 `bond_idx` 升序：

```
if status == active and principal_outstanding_uu > 0:
    # (a) 利息本身：先乘后除，必须走 mul_div_floor
    interest = mul_div_floor(principal_outstanding_uu, coupon_ppm_per_q, 1_000_000)
               # rounding: floor, reason=少付优于多付
               # **裸乘在新刻度下溢出**：AMOUNT_MAX(4e15) × coupon_max(1e5) = 4e20 > 9.22e18
               # mul_div_floor 的中间量 = floor(4e15/1e6) × 1e5 = 4e14 ✓

    # (b) 计提余数（INV-004 的累加器）：旧写法 rem = raw - interest*1e6 需要 raw 这个已溢出的中间量。
    #     用同余改写，与 raw mod 1e6 精确相等，且中间量 < 1e11：
    #         (P · c) mod 1e6 == ((P mod 1e6) · c) mod 1e6
    r_lo     = principal_outstanding_uu
             - IntMath.mul(idiv_floor(principal_outstanding_uu, 1_000_000), 1_000_000)  # 0..999_999
    t        = IntMath.mul(r_lo, coupon_ppm_per_q)         # <= 999_999 × 100_000 = 9.99999e10 ✓
    rem      = t - IntMath.mul(idiv_floor(t, 1_000_000), 1_000_000)     # 0..999_999，单位 μU·ppm

    interest_remainder_ppmuu += rem
    if interest_remainder_ppmuu >= 1_000_000:
        interest += 1 ; interest_remainder_ppmuu -= 1_000_000               # 余数结转，长期不漂移
    flow.bond.interest_due_uu = interest
```

**禁止**先把 `gov.debt` 求和再乘一个平均利率（计划书 §07「利息逐债券批次计算」，INV-036）。
**也禁止**为了拿到 `rem` 而重新构造 `principal_outstanding_uu × coupon_ppm_per_q` 这个积——
它在契约上界处确实溢出，`test_scaled_ceilings_require_mul_div_floor` 已钉死这一点。

**02.4 到期本金**

```
amortization == bullet          : due = (q == maturity_q) ? principal_outstanding_uu : 0
amortization == level_principal : due = amort_schedule[q]      # 缺该季即 0
        # amort_schedule 的覆盖区间、期数与权重见 §1.1 的 01.8（issue_q+1 … maturity_q，等权重预生成，
        # 各期之和精确等于面值）。本步只**读**这张表，不重算、不改写（INV-037）。
```

**02.5 支付与「短缺先显露」**

```
obligations = Σ interest_due + Σ principal_due                             # μU
if gov.cash_uu >= obligations:
    逐批次 post(gov -> holder, interest_due, kind=bond_interest)
    逐批次 post(gov -> holder, principal_due, kind=bond_principal)
           principal_outstanding_uu -= principal_due
           若归 0 则 status = matured
else:
    gap = obligations - gov.cash_uu
    按 gov.payment_priority 顺序支付（债务档在本步只处理 debt_service 一档）：
        利息未付 -> bond.accrued_unpaid_interest_uu += x ; gov.arrears += x ;
                    bond.status = defaulted ; politics.mandate_status = at_risk
        本金未付 -> 同上，并进入**重组分支**：必须由玩家在下一季用 debt_restructure 命令选择
                    （延期 / 减记 / 违约）。**不允许自动展期**（INV-038，否则 ADV-02 无法失败）
    连续 param.default_grace_q 季无法处理 -> meta.termination_reason = fiscal_restructuring_failed
**`gov.cash_uu` 恒不为负**（INV-016）。若代码路径会导致负数，直接 Fault.NEGATIVE_CASH。
```

**02.6 新发债（利率由规则给出，玩家不能设）**

```
dsr_ppm     = mul_div_floor(未来4季(利息+本金)_uu, 1_000_000, max(年化收入_uu, 1))
              # **裸乘在新刻度下溢出**：AMOUNT_MAX(4e15) × 1e6 = 4e21 > 9.22e18
              # mul_div_floor 的中间量 = floor(债务负担/年化收入) × 1e6，实测约 2.2e5 × 1e6 = 2.2e11 ✓
market_ppm  = param.market_rate_base_ppm
            + mul_ppm(param.market_rate_slope_ppm, min(dsr_ppm, 2_000_000))
            + (holder == row ? 外部收紧冲击加成 : 0)
coupon_ppm_per_q = clamp(market_ppm, param.coupon_min_ppm, param.coupon_max_ppm)   # 写入后永不可改

domestic_capacity = min(gov.credit_limit_domestic_memo_uu,
                        mul_ppm(invpool.cash_uu, param.household_bond_appetite_ppm))
external_capacity = world.credit_limit_uu - world.credit_used_uu
issue_domestic    = min(need, domestic_capacity)
issue_external    = min(need - issue_domestic, external_capacity)
if issue_domestic + issue_external < need:
    差额进入「无法融资」-> 回到 02.5 的排序／延期／重组分支，REJECT(E_CREDIT_LIMIT) 或记 arrears
```

发行过账（**融资必须有对手方**，INV-034）：

```
post(kind=bond_issue, payer=holder.cash, payee=gov.cash, amount=face)
holder.bondhold += face ; gov.debt（派生）随 bond 表变化
world.credit_used_uu += issue_external
# 同时按 §1.1 的 01.8 生成本批次的 amort_schedule（覆盖 issue_q+1 … maturity_q，等权重），
# 此后永不重算；本季（q == issue_q）不还本，故 02.4 对新批次取 0
```

`flow.gov.new_borrowing_uu` 单独登记，**不进入收入构成，也不进入任何 GDP 口径**（INV-029）。

**02.7 项目新建与取消**

```
新建：占用 queue_slot（region.construction_slots_total 上限，INV-094）；
      state.meta.entity_seq += 1 生成 project_id；
      spend_plan_uu 由 policy_def.cost 展开，Σ == total_cost_uu（INV-092）
取消：gov.committed_memo_uu -= 剩余合同额
      penalty = mul_ppm(剩余合同额, exit_rule.compensation_ppm)
      post(kind=cancel_penalty, gov -> 承包方, penalty)
      residual_value_uu = 已形成的可回收部分；wip 中超出残值的部分确认为损失（政府净值减少）
      **paid_uu 不返还、现金不增加**（INV-093）
      释放 queue_slot
```

**02.8 预算审查标记**：`q == politics.next_budget_review_q` 时置流量标记
`flow.politics.budget_review_due = 1`（判定在 S08），并 `next_budget_review_q += 4`（INV-127）。

### 2.2 支付优先级（8 档全排列，默认顺序）

| 档 | 类别码 | 推迟后果 |
|---|---|---|
| 1 | `debt_service` 利息与本金 | 违约，`credit_limit` 收紧、信任下降、可能触发重组 |
| 2 | `public_wages` 公共部门工资 | 公共服务可用率下降（INV-102），`bloc.labor_public` 反应 |
| 3 | `statutory_transfers` 法定转移 | 群组生活指数下降、信任下降 |
| 4 | `service_opex` 已投运服务运行费 | 可用率下降，**不删除资产**（INV-102） |
| 5 | `project_contracts` 项目合同款 | 项目 `suspended(financing)`，可能触发违约金 |
| 6 | `procurement` 政府采购 | 公共服务中间投入不足，交付量下降 |
| 7 | `subsidies` 企业补助 | 企业投资意愿下降 |
| 8 | `discretionary` 可自由裁量支出 | 直接压缩 |

### 2.3 步末不变量

INV-016、INV-028、INV-030、INV-032、INV-033、INV-034、INV-035、INV-036、INV-037、INV-038、
INV-039、INV-040、INV-041、INV-042（02.0 的三条校验式）、INV-092、INV-093、INV-094、INV-095、
INV-098、INV-127；且每条命令恰好被处理一次（`accepted` 全部已写）。

### 2.4 失败行为

| 情形 | 行为 |
|---|---|
| 现金不足且无法融资 | 按优先级推迟，生成 `arrears`，在报告中列为「支出排序结果」；不静默改账 |
| 债券批次数超过 `param.bond_batch_cap` | 报警并 `REJECT` 新发行；**不自动合并批次**（合并会破坏 INV-036 的「旧债不重定价」） |
| 项目队列无空位 | `blocked_reason = queue`，不入队 |
| `gov.cash` 将为负 | `Fault.NEGATIVE_CASH` |
| `debt != Σ outstanding` | `Fault.BOND_MISMATCH` |

---

## 3 S03 计划与就业

**计划书**：按滞后需求形成生产、招工与投入订单。必须检查雇佣不超过可用劳动力；工资有资金来源。

| 项 | 内容 |
|---|---|
| 输入 | 上季成交量与未满足需求；上季末库存；`capacity_active`（含本季 S01 转入）；群组劳动力；`cell.cash`；本季价格 |
| 输出 | `output_plan_uqs`；招工／裁员；投入订单与电力需求；失业率；扩产意愿 |
| **可写子集** | `flow.cell.output_plan_uqs`、`state.cell.employment_persons`、`flow.cell.hires_persons/separations_persons`、`state.pubserv.employment_persons/teachers_persons/health_staff_persons`、`state.group.employed_persons`、`flow.market.inventory_target_uqs`、`flow.region.electricity_demand_uqs`、`flow.cell.invest_intent_uu`、`state.rng.draw_count[market]`、`log.clamp`、`log.constraint_diag` |
| 日志 | 每 cell 的计划产量来源（上季成交、未满足、库存缺口）；每次招工的可用劳动力与资金检查结果；被摩擦／资金／劳动力夹住的量 |

### 3.1 需求预期（滞后，不含本季信息）

```
D_prev[i]  = flow.cell.sold_uqs_prev[i] + flow.cell.unmet_demand_uqs_prev[i]        # μQ_s
             # 用「成交 + 未满足」而不是产量，避免「卖不掉也照产」
E[i]       = E_prev[i] + mul_ppm(D_prev[i] - E_prev[i], param.demand_smooth_ppm)    # μQ_s
inv_target[i] = (storable[s] == 1) ? mul_ppm(E[i], param.inventory_target_ppm) : 0  # μQ_s
inv_gap[i]    = inv_target[i] - state.cell.inventory_output_uqs[i]                  # 可负
output_plan_uqs[i] = max(0, E[i] + inv_gap[i])                                      # μQ_s
```

`E_prev` 是一个跨季存量（`state.cell.demand_expect_uqs`，写者 S03），存档必须包含它。

### 3.2 招工（两道硬闸 + 摩擦）

**(a) 目标在岗**

```
need_k[i] = mul_div_ceil(output_plan_uqs[i], labor_coeff_persons_per_qs[i][k], 1_000_000)
            # rounding: ceil, reason=不得少算用工
            # 单位：μQ_s × (人/Q_s) / 1e6(μQ_s/Q_s) = 人 ✓
            # 溢出：裸乘上界 QTY_MAX(1e12) × labor_coeff_max(4e5，剧本 agri/low) = 4e17 < 9.22e18，
            #       本身不溢出；但按 §0.3.2 统一走 mul_div_ceil，中间量降到
            #       floor(1e12/1e6) × 4e5 = 4e11 ✓
```

**(b) 摩擦上限**

```
max_hire_k = mul_ppm(employment_k, param.hiring_friction_ppm) + 1
max_fire_k = mul_ppm(employment_k, param.firing_friction_ppm)
delta_k    = clamp(need_k - employment_k, -max_fire_k, +max_hire_k)     # 写 log.clamp
```

**(c) 闸一：地区同技能可用劳动力**（INV-076）

```
pool[r][k] = Σ_{g ∈ (r, working, k)} ( derived.group.labor_force_persons[g] - employed_g_total )
# 同地区多个 cell 与 pubserv 竞争同一池子：先按 cell_id / pubserv_id 的下标升序汇总需求，
# 若 Σ delta > pool，则 alloc = split_largest_remainder(pool, 各自 delta, 下标) —— 禁止随机分配
```

**(d) 闸二：工资有资金来源**（INV-079，首版不允许欠薪）

```
wage_rate_k    = state.price.wage_uu_per_person_q[k]                    # μU/人/季
cash_for_wages = mul_ppm(state.cell.cash_uu[i], param.wage_cash_share_ppm)
# 按技能档的工资占比拆分可用现金，再算各档可负担人数
budget_k       = split_largest_remainder(cash_for_wages, 各档 need_k*wage_rate_k, 档下标)[k]
affordable_k   = idiv_floor(budget_k, wage_rate_k)      # rounding: floor, reason=宁可少雇也不欠薪
employment_k   = min(need_k, employment_k + alloc_k, affordable_k)
hires_k        = max(0, employment_k - prev_k)
separations_k  = max(0, prev_k - employment_k)
```

同步写回群组侧 `state.group.employed_persons`，两处必须逐（地区，技能）相等（INV-077）。
**裁员不产生遣散费**（首版简化，OQ-211）。

### 3.3 技能错配

`labor_coeff_persons_per_qs` 对某 cell 的某技能档给出刚性需求。该档劳动力不足 ⇒ 该档 `employment_k` 被压低
⇒ S05 的 `bound_labor` 被压低。**错配是分档配给的自然结果，不需要额外的「错配惩罚系数」，
也不允许技能替代**（INV-078）。

### 3.4 失业率（反算，不是参数）

```
labor_force_total = Σ_{g: age==working} mul_div_floor(population_persons[g],
                                                      participation_ppm[g], 1_000_000)
                    # 溢出：2.4e7 × 1e6 = 2.4e13 ✓（走 mul_div_floor 后中间量 ≤ 2.4e7）
employed_total    = Σ_g Σ_sector employed_persons[g][sector] + employed_persons[g][pubserv]
unemployed_total  = labor_force_total - employed_total                  # 必须 >= 0
derived.labor.unemployment_ppm = mul_div_floor(unemployed_total, 1_000_000,
                                               max(labor_force_total, 1))
                                 # 溢出：2.4e7 × 1e6 = 2.4e13 ✓
```

q=0 时必须落在 [79 500, 80 500] ppm（INV-075/143）。**禁止把 8% 写成参数再反推就业。**

### 3.5 投入订单与电力需求

```
material_need_j[i] = mul_div_ceil(output_plan_uqs[i], io_coeff[j][s], 1_000_000)             # μQ_j
energy_need[i]     = mul_div_ceil(output_plan_uqs[i], io_coeff[energy][s], 1_000_000)
flow.region.electricity_demand_uqs[r] = Σ_{i ∈ r} energy_need[i] + 居民用电需求[r]
# rounding: ceil, reason=不得少订投入
# 溢出：裸乘上界 QTY_MAX(1e12) × io_coeff_max(2.6e5，剧本 manu→manu) = 2.6e17 < 9.22e18；
#       走 mul_div_ceil 后中间量 floor(1e12/1e6) × 2.6e5 = 2.6e11 ✓
```

> **能源系数与 IO 表的关系**：`energy_coeff_uqs_per_qs[s]` 是 IO 表能源行的**冗余副本**，
> 加载期校验 `energy_coeff[s] == io_coeff_uqs_per_qs[idx_io(energy, s)]`（V-IO-08），
> 不符即拒绝加载。运行期只用 IO 表那一份。故意冗余，用于交叉校验。

### 3.6 扩产意愿（部门行为规则，不是 AI，不是「信心 +10」）

```
util_ppm = clamp(mul_div_floor(output_actual_prev[i], 1_000_000,
                               max(1, capacity_active[i])), 0, 1_000_000)
           # 溢出：产能为 1 μQ 的退化 cell 上，真值本身可达 QTY_MAX × 1e6 = 1e18 < 9.22e18 ✓
           # （mul_div_floor 在 c 很小时并不缩小中间量；这里靠的是 1e18 的 9.2 倍裕度，而不是拆商）
if binding_code_prev[i] == CAPACITY and profit_pretax_prev[i] > 0:
    invest_intent_uu[i] = mul_ppm_2(max(0, profit_pretax_prev[i]),
                                    param.invest_propensity_ppm, util_ppm)
                          # mul_ppm_2 第一步裸乘两个 ppm：两者都 <= 1e6（util_ppm 已 clamp）-> 1e12 ✓
                          # 第二步走 mul_div_floor：4e15 × 1e6 / 1e6，中间量 4e15 ✓
else:
    invest_intent_uu[i] = 0
```

三项输入（上季瓶颈、上季利润、产能利用率）全部是**已实现的量**；无任何外生加成项（计划书 §06）。
静态检查：投资函数不得引用 `expectation_ppm` / `trust_ppm` / `support_ppm`。

### 3.7 步末不变量与失败行为

INV-074、INV-075、INV-076、INV-077、INV-078、INV-079、INV-080。

| 情形 | 行为 |
|---|---|
| 劳动力不足 | 招工被 `pool` 压低；S05 中 `bound_labor` 成为紧约束 |
| 现金不足以支付期望工资 | 缩减招工至 `affordable_k`，记 `log.clamp` 与 `hire_capped_by_cash` |
| `Σ employed > pool` | `Fault.EMPLOYMENT_OVERFLOW`（计划书 §17「就业人数不超过同口径劳动力」的执行点） |

---

## 4 S04 工资与投入

**计划书**：支付工资、补助、项目款；分配材料与能源。必须检查付款双边入账；投入不能重复分配。

| 项 | 内容 |
|---|---|
| 输入 | S03 的就业决定；政策的转移与补助规则；项目 `spend_plan`；`cell.cash`；`gov.cash` 与优先级 |
| 输出 | 已支付的工资、转移、赡养、补助、项目款、运行费；居民本季可用现金 |
| **可写子集** | 全部主体 `cash`；`flow.group.wage_income/transfer_income/support_in/support_out`；`flow.cell.wage_bill`、`flow.cell.subsidy_received`；`flow.pubserv.wage_bill/funding_ratio_ppm`；`flow.gov.*`（支付类）、`state.gov.arrears/arrears_by_payee/reserved_memo/committed_memo/deferral_flag/rounding_residual`；`state.project.paid_uu/status/suspension_reason`；`state.gov.wip_uu`、`state.cell.wip_uu`；`state.policy.budget_spent_uu/claim_ledger`；`log.*` |
| 日志 | 每笔付款的 `payer/payee/amount/cause`；每笔补助的领取登记与拦截；每笔项目付款对应的合同条款；每笔欠付 |

### 4.1 支付顺序（固定，保证「工资先于消费」）

**04.1 企业付工资**

```
wage_bill[i] = Σ_k IntMath.mul(employment_persons[idx_emp(i,k)], wage_uu_per_person_q[k])   # μU
              # 单位：人 × μU/人/季 = μU ✓ 纯乘法，无除法
              # 溢出：2.4e7 人 × param.wage_ceil_uu（新刻度 2e10）= 4.8e17 < 9.22e18 ✓
              # 另有 INV-007 的金额闸：wage_bill 必须 <= AMOUNT_MAX = 4e15
              #（剧本实测约 1.3e10 μU/季，裕度 5 个数量级）
assert wage_bill[i] <= cell.cash_uu[i]        # 由 S03 闸二保证；若不成立 -> Fault.WAGE_UNFUNDED
按各组在该 cell 的在岗人数用 split_largest_remainder 拆分 wage_bill，逐组 post(cell -> group)
```

若 `Fault.WAGE_UNFUNDED` 发生，说明 S03 有缺陷 —— **不在 S04 补救、不裁员**（INV-080）。

**04.2 政府付款（按 8 档优先级，只在可用现金内）**

```
for line in gov.payment_priority:              # 8 档，全排列
    due = 本季该档应付                          # μU
    pay = min(due, gov.cash_uu)
    按收款方 ID 升序，用 split_largest_remainder(pay, 各收款方应付额) 拆分并逐笔 post()
    if pay < due:
        gov.arrears_by_payee_uu[payee] += (due - pay)
        gov.deferral_flag[line] = 1
        log.arrears.append({payee, due - pay, reason=line})
```

其中：

- `public_wages`：付给 `pubserv` 的在岗人员 → 群组现金。
- `statutory_transfers`（P03 失业保障等）：
  ```
  eligible_persons   = Σ 符合资格的失业人数（按 P03 的 eligibility/duration 判定）
  benefit_per_person = mul_ppm(ref_wage_uu, policy.P03.replacement_ppm)   # x 位必须是金额，p 位必须是 ppm
  total              = IntMath.mul(eligible_persons, benefit_per_person)
  # 溢出：2.4e7 × 2e10（wage_ceil）= 4.8e17 < 9.22e18 ✓；仍受 AMOUNT_MAX 闸约束
  ```
  现金不足时**部分支付 + 欠付**，**不得少算人数装作没人符合资格**。
- `service_opex`：付给 `pubserv`，决定 `flow.pubserv.funding_ratio_ppm`，S07 据此更新可用率（INV-102）：
  ```
  funding_ratio_ppm[r] = (due_uu == 0) ? 1_000_000
                                       : mul_div_floor(paid_uu, 1_000_000, due_uu)
  # **裸乘在新刻度下溢出**：AMOUNT_MAX(4e15) × 1e6 = 4e21 > 9.22e18
  # mul_div_floor 中间量 = floor(paid/due) × 1e6 <= 1e6（paid <= due）✓
  # due == 0 的分支是本次同步补写的：原文没有它，应付为 0 时会直接 DIV_ZERO。
  # 取 1e6（「无应付即足额」）与 §5.2 的 `(Σ demand == 0) ? 1_000_000` 同一取法。
  ```
- `project_contracts`：见 04.4。
- `subsidies`：见 04.3。

**04.3 补助防重复领取（INV-097，恶意玩家测试 ADV-01）**

```
claim_key = hash64(policy_id, beneficiary_cell, q, qualifying_investment_id)
if policy.claim_ledger.has(claim_key):
    记 duplicate_claim_blocked，跳过
else:
    前置：该 cell 的 flow.cell.investment_uu（上季实际投资）> 0 且已付款      # 以「已发生的实际投资」为前置，
    amount = min(申请额, 上限)                                             # 不是以「政策开启」为前置
    post(kind=subsidy, gov -> cell, amount)
    policy.claim_ledger[claim_key] = amount            # 台账只增不减；政策退出也不清零
```

**04.4 项目付款（付款 ≠ 进度，INV-087）**

```
pay_uu = min(spend_plan_uu[本季序][全部分项之和], 优先级内可用额)
project.paid_uu += pay_uu
按 spend_lines 用 split_largest_remainder 拆成三笔，各有收款方：
    import_equipment     -> agent.row          （同时增 flow.world.imports_uu / imports_uqs）
    domestic_material    -> cell.<r>.manu
    construction_service -> cell.<r>.services
gov.wip_uu += pay_uu
**本步不写 project.construction_progress_ppm / delivery_progress_ppm**（那是 S05 的事）
资金不足 -> project.status = suspended ; suspension_reason = financing ; 已付部分不退
```

**04.5 组间赡养转移（INV-085）**

```
pool_r = Σ_{g ∈ r, age==working} mul_ppm(derived.group.disposable_income_uu_prev[g],
                                          support_out_weight_ppm[g])
分配给同地区的 minor / elder 组，权重 = 各组人口，用 split_largest_remainder 拆分 pool_r
逐组 post(kind=household_support, working组 -> 受养组)
断言 Σ support_in == Σ support_out（精确）
```

### 4.2 「投入不能重复分配」的实现

每个可分配资源在本季有唯一的 `pool` scratch 数组，分配一次即从 `pool` 扣减；
`pool` 在 S01 建立、S05 末归零。**禁止任何代码持有 `pool` 的副本**；
`_allocated_flag` scratch 数组防重（`Fault.DOUBLE_ALLOCATION`）。

材料与电力**不在本步分配**：材料在 S05 由生产直接从**上季持有库存**中消耗（INV-050），
电力在 S05 由能源部门实际产量分配（见 §5.2）。本步只登记订单。

> **裁定**：草案 B/C 把电力分配放在 S04（按「上季末已知的本季可供计划」），
> 并各自登记了「计划与实际错位」的风险。本契约把电力分配移到 S05 能源部门实际产出之后，
> **整类风险消失**，代价只是 S05 内部需要一个固定的部门结算次序（§5.1），而那是可测的。

### 4.3 步末不变量与失败行为

INV-015、INV-016、INV-003、INV-030、INV-079、INV-085、INV-087、INV-092、INV-096、INV-097。

| 情形 | 行为 |
|---|---|
| 企业现金不足付工资 | 不应发生（S03 已闸住）；发生即 `Fault.WAGE_UNFUNDED` |
| 政府现金不足付转移 | 按比例部分支付 + 欠付；报告列出未付金额与受影响人数 |
| 项目付款超出合同剩余额 | 拒绝付款，`Fault` 不触发但记 `E_OVERPAY` 诊断，项目转 `suspended` |
| 补助重复申领 | 拒绝，记 `duplicate_claim_blocked` |
| 拆分和不等于原额 | `Fault.SPLIT_MISMATCH`（最严重的一类缺陷，立即停） |

---

## 5 S05 生产与交易

**计划书**：生产入库；完成居民、企业、政府和外部交易。必须检查预算约束、实际成交、库存与未满足需求。

| 项 | 内容 |
|---|---|
| 输入 | `capacity_active`；就业；上季末库存；本季**已固定**的价格；消费预算；外部需求与交付能力 |
| 输出 | 实际产量；紧约束诊断；电力分配；交易明细；期末库存；未满足需求；项目进度；排放 |
| **可写子集** | `flow.cell.bound_*/binding_code/output_actual/consumed_input/purchased_input/sold/spoilage/unmet_demand/energy_allocated/energy_unused/price_variance/investment`、`state.cell.inventory_output_uqs/inventory_input_uqs/cash`、`flow.group.consumption*/housing_cost/unmet_consumption`、`state.group.cash`、`flow.pubserv.delivered_uqs/intermediate_uu`、`state.pubserv.queue_persons`、`flow.gov.pay_procurement_uu/receipts_other_uu`、`state.gov.cash/wip`、`flow.world.*`、`state.project.delivery_progress_ppm/construction_progress_ppm/status/suspension_reason`、`flow.region.construction_capacity_uqs/construction_used_uqs/electricity_supply_uqs/emissions_uqe`、`flow.market.*`、`state.rng.draw_count[market]`、`log.*` |
| 日志 | 每 cell 的五项约束值、argmin 与各项 slack；每笔交易（买方、卖方、量、价、金额）；每次配给的比例与未满足量；每个项目的进度增量来源；每笔实物流水 |

### 5.1 结算次序（部门有序，打断同期循环）

```
1) 4 个 energy cell 生产            -> 形成各地区可交付电力（电力不入库存）
2) 电力配给（见 5.2）
3) 12 个 agri / manu / services cell 生产（互不使用对方本季产出）
4) 服务产出的施工份额结算 -> flow.region.construction_capacity_uqs
5) 项目进度推进（消耗施工能力与已到货设备）
6) 公共服务交付
7) 市场交易：居民消费 -> 公共服务采购 -> 政府采购 -> 企业投入与补库 -> 出口
8) 期末库存结转、损耗、未满足需求登记、排放
```

> **显式的离散化简化**（计划书 §13 明示）：第 3 步的各 cell **不使用彼此本季产出**，
> 只使用上季库存与本季电力。本季购入补的是**下季**可用库存。
> 代价：投入产出的同期循环被打断。收益：「一个回合里不会反复相互放大」与整数可对账。
> 玩家可见的规则说明中必须写明这一点。
> 测试 `T-U-NO-SAME-QUARTER-CHAIN`：构造 A 生产 → B 需要 A，断言 B 同季只能用期初库存。

### 5.2 电力（当期供给，当期使用，不入库存）

能源 cell 的**能源约束被跳过**（自供），自用量从产出净出：

```
# 能源 cell i（sector == energy）：五项约束中不计 bound_energy
Q_e[i]      = min(bound_plan, bound_capacity, bound_labor, bound_materials)     # μQ_energy
self_use[i] = mul_div_ceil(Q_e[i], io_coeff[energy][energy], 1_000_000)
              # rounding: ceil, reason=不得少算自用；加载期已保证 io_coeff[energy][energy] < 1e6
              # 溢出：裸乘 1e12 × 1e6 = 1e18 < 9.22e18；走 mul_div_ceil 后中间量 1e6 × 1e6 = 1e12 ✓
deliver[i]  = Q_e[i] - self_use[i]                                              # > 0
flow.region.electricity_supply_uqs[r] = min(Σ_{i ∈ r} deliver[i],
                                            state.region.grid_capacity_uqs_per_q[r])
# 超出电网输配容量的部分作废（记 energy_unused，不入库存）
```

配给（两级规则，见 §5.6）：

```
需求档 1 生命线：pubserv 与居民用电
需求档 2 生产用电：各 cell 的 energy_need
逐档满足；同档内 alloc = split_largest_remainder(该档可分配量, 各需求量, 需求方下标)
flow.cell.energy_allocated_uqs[i] = alloc[i]
derived.region.electricity_availability_ppm[r]
    = (Σ demand == 0) ? 1_000_000
                      : mul_div_floor(Σ alloc, 1_000_000, Σ demand)
                        # 溢出：裸乘 1e12 × 1e6 = 1e18；走 mul_div_floor 后因 alloc <= demand，
                        #       中间量 floor(alloc/demand) × 1e6 <= 1e6 ✓
```

`INV-060`：`Σ alloc == min(供给, Σ 需求)`（精确）。

### 5.3 五项约束的整数换算（计划书 §06 的可实现形式）

全部换算为**该 cell 自己产品的 μQ_s**，取 `min`。用哨兵 `SENTINEL = QTY_MAX` 表示「该约束不适用」。

```
# 1) 计划
bound_plan = flow.cell.output_plan_uqs[i]                                      # μQ_s

# 2) 产能
bound_capacity = state.cell.capacity_active_uqs_per_q[i]                       # μQ_s/季 == 本季 μQ_s
if maintenance_backlog_ppm[i] > 0:
    bound_capacity = mul_ppm(bound_capacity, 1_000_000 - maintenance_backlog_ppm[i])

# 3) 劳动（逐技能档取最紧；系数为 0 的档跳过）
bound_labor = SENTINEL
for k in [0, 1, 2]:                                        # 固定顺序
    c = content.io.labor_coeff_persons_per_qs[idx_emp(i, k)]     # 人/Q_s
    if c == 0: continue                                     # 跳过，不做除零，也不用 max(c,1)
    avail = state.cell.employment_persons[idx_emp(i, k)]    # 人
    bound_labor = min(bound_labor, mul_div_floor(avail, 1_000_000, c))  # rounding: floor
                  # 溢出：2.4e7 × 1e6 = 2.4e13 ✓；c >= 1 由上一行的 `if c == 0: continue` 保证
# 全部档系数为 0 -> bound_labor 保持 SENTINEL（该 cell 不受劳动约束）

# 4) 能源（能源 cell 跳过此项，见 5.2）
a_e = content.io.io_coeff_uqs_per_qs[idx_io(SECTOR_ENERGY, s)]   # μQ_energy / Q_s
bound_energy = (a_e == 0 or s == SECTOR_ENERGY)
               ? SENTINEL
               : mul_div_floor(flow.cell.energy_allocated_uqs[i], 1_000_000, a_e)
               # 溢出：真值上界 energy_alloc(1e12) × 1e6 / 1 = 1e18 < 9.22e18 ✓（9.2 倍裕度）
               # a_e 很小时 mul_div_floor 不缩小中间量，裕度来自 1e18 本身

# 5) 材料（逐投入部门取最紧；能源行不在此列）
bound_materials = SENTINEL
for j in [agri, manu, services]:                            # 固定顺序，不含 energy
    a = content.io.io_coeff_uqs_per_qs[idx_io(j, s)]             # μQ_j / Q_s
    if a == 0: continue                                     # 跳过
    avail_j = state.cell.inventory_input_uqs[idx_inv(i, j)] # 上季末库存（本季不可用本季产出）
    bound_materials = min(bound_materials, mul_div_floor(avail_j, 1_000_000, a))
                      # 溢出：同上，真值上界 1e18 ✓

# 取最小
cands = [bound_plan, bound_capacity, bound_labor, bound_energy, bound_materials]
q_actual = cands[0] ; binding = 0
for n in 1..4:
    if cands[n] < q_actual:                                 # 严格小于 -> 并列时保留先出现者
        q_actual = cands[n] ; binding = n
flow.cell.output_actual_uqs[i] = max(0, q_actual)
flow.cell.binding_code[i] = binding
slack[n] = cands[n] - q_actual                              # binding 项的 slack 恒为 0
```

**并列的确定性**：固定序 `plan(0) < capacity(1) < labor(2) < energy(3) < materials(4)`，
严格小于才替换 ⇒ 并列时取序号最小者（INV-045）。

**`binding_code` 是报告里「模型中的限制因素」的唯一数据来源**（计划书 §13）。
**多个瓶颈的影响不做简单相加**：报告只列出 argmin 与五项数值，不合成「瓶颈分数」。

**零系数跳过**在三处各出现一次（劳动、能源、材料），实现为 `continue` / `SENTINEL`，
**绝不写成 `x / 0`，也绝不用「除以 max(c,1)」代替**——后者会造出一个巨大的假候选值，是隐蔽缺陷。
`test_u_zero_coefficient` 对每一处做单测。
若五项全为 SENTINEL（理论上不可能：`bound_plan` 与 `bound_capacity` 永远有限）⇒ `Fault.UNBOUNDED_PRODUCTION`。

### 5.4 实际消耗（从 `q_actual` 反算，用 ceil，保证不透支）

```
for j in [agri, manu, services]:
    a = io_coeff[j][s] ; if a == 0: continue
    use = mul_div_ceil(q_actual, a, 1_000_000)                  # rounding: ceil, reason=不少耗料
          # 溢出：裸乘 1e12 × 2.6e5 = 2.6e17；走 mul_div_ceil 后中间量 1e6 × 2.6e5 = 2.6e11 ✓
    if use > state.cell.inventory_input_uqs[idx_inv(i,j)]: Fault.raise(NEGATIVE_INVENTORY)
    state.cell.inventory_input_uqs[idx_inv(i,j)] -= use
    flow.cell.consumed_input_uqs[idx_inv(i,j)]   += use

energy_use = mul_div_ceil(q_actual, a_e, 1_000_000)
flow.cell.energy_unused_uqs[i] = flow.cell.energy_allocated_uqs[i] - energy_use   # 当季作废

state.cell.inventory_output_uqs[i] += q_actual                  # 成品入库（storable == 1）
# storable == 0（energy / services）：产出直接进入当期供给，期末库存恒为 0（INV-049）
```

**整数引理（必须写成单元测试 `T-U-CEIL-SAFE`）**

> 设 `q_actual ≤ mul_div_floor(A, 1 000 000, c)`，则 `mul_div_ceil(q_actual, c, 1 000 000) ≤ A`。
> 证明：由前提得 `q_actual × c ≤ A × 1 000 000`；两边除以 1 000 000 并向上取整，
> 因 `A` 为整数，`ceil(q_actual×c / 1e6) ≤ ceil(A) = A`。∎
>
> ⇒ **「用 ceil 防止少算投入」与「不透支库存」可以同时成立**（INV-046）。断言恒成立。
>
> **R-SCALE-01 后为什么不用重证**：`mul_div_floor` / `mul_div_ceil` 与 `floor(a·b/c)` / `ceil(a·b/c)`
> 的**数学真值精确相等**（§0.3.2），本引理只用到 floor 与 ceil 的数学性质，不涉及中间量的表示，
> 故逐字成立。反过来说：若实现里用了任何**近似**的先乘后除（例如先除后乘、或分段近似），本引理立刻失效，
> `Fault.NEGATIVE_INVENTORY` 会在压测中随机出现且极难定位。

同理用工：`labor_used_k = mul_div_ceil(q_actual, labor_coeff_k, 1e6) ≤ employment_k`。

### 5.5 施工能力与项目进度（付款不制造进度）

```
# 施工能力：由服务 cell 的实际产量按上限比例折出（不是由付款折出）
svc_out = flow.cell.output_actual_uqs[idx_cell(r, SECTOR_SERVICES)]                  # μQ_services
flow.region.construction_capacity_uqs[r] = mul_ppm(svc_out, param.construction_share_cap_ppm)
# 该份额从服务的市场可售量中扣除（§5.6 的 supply 不含这部分）

# 分配给本地区 status == in_progress 的项目（按 project 下标升序）
need_uqs[p]  = 本季计划施工量 = idiv_floor(required_construction_uqs[p], planned_quarters[p])
grant_uqs[p] = split_largest_remainder(min(capacity, Σ need), need_uqs, 项目下标)[p]
flow.region.construction_used_uqs[r] += Σ grant_uqs

# 施工进度：只由 grant_uqs 决定，与 paid_uu 无任何数据依赖（INV-087）
Δconstruction_ppm = (required_construction_uqs[p] == 0)
                    ? 1_000_000 - construction_progress_ppm      # 无施工需求 -> 该维度立刻满格
                    : mul_div_floor(grant_uqs[p], 1_000_000, required_construction_uqs[p])
                      # 溢出：grant <= QTY_MAX(1e12)，真值上界 1e18 < 9.22e18 ✓
construction_progress_ppm = clamp(construction_progress_ppm + Δconstruction_ppm, 0, 1_000_000)

# 交付进度：只由实际到货设备量决定，受外部交付能力约束（INV-089）
delivered_uqs = min(本季已订设备量, world.delivery_capacity_uqs[SECTOR_MANU] 的剩余额)
Δdelivery_ppm = (required_equipment_uqs[p] == 0)
                ? 1_000_000 - delivery_progress_ppm              # 无设备需求 -> 该维度立刻满格
                : mul_div_floor(delivered_uqs, 1_000_000, required_equipment_uqs[p])
delivery_progress_ppm = clamp(delivery_progress_ppm + Δdelivery_ppm, 0, 1_000_000)
# 两条 `== 0` 分支是本次同步补写的：原文直接除，需求为 0 的项目会 DIV_ZERO，
# 而 §7.1 的完工条件要求两项进度都达 1e6 —— 不补分支则「纯设备采购」「纯土建」两类项目永远无法完工。

if grant_uqs[p] == 0 and need_uqs[p] > 0:
    status = suspended ; suspension_reason = congestion
```

**验收测试落点**（计划书 §10）：
`T-S-P04-PAY-NO-PROGRESS` —— 构造「有钱、无施工能力」场景，断言 `Δconstruction_ppm == 0`
且 `paid_uu` 仍可增加（或记欠付）。静态检查：进度函数的形参表中不含 `paid_uu`。

### 5.6 市场闭合与配给

**可售供给**

```
supply_uqs[s] = Σ_r ( inventory_output_start[idx_cell(r,s)] + output_actual[idx_cell(r,s)] )
                - (s == services ? Σ_r construction_capacity_uqs[r] : 0)
                - (s == energy   ? 全部（电力已在 5.2 分配） : 0)
```

**需求形成**（先算全部需求再统一配给，避免先到先得的顺序依赖）

买方类固定顺序：`0 居民 / 1 公共服务 / 2 政府采购 / 3 企业投入与补库 / 4 出口`。

```
# 0 居民（计划书 §13：不能花未收到的钱，INV-063）
cash_avail[g] = flow.group.wage_income_uu[g] + flow.group.transfer_income_uu[g]
              + flow.group.support_in_uu[g] - flow.group.support_out_uu[g]
              + mul_ppm(state.group.deposit_uu[g], param.dissave_ppm)
budget[g]     = min(mul_ppm(cash_avail[g], param.mpc_ppm) + 住房支出, state.group.cash_uu[g])
budget_i[g]   = split_largest_remainder(budget[g], param.engel_weight_ppm, 产品下标)
demand_uqs[0][s] = Σ_g mul_div_floor(budget_i[g][s], 1_000_000,
                                     state.price.sector_uu_per_qs[s])
# **裸乘在新刻度下溢出**：AMOUNT_MAX(4e15) × 1e6 = 4e21 > 9.22e18
# mul_div_floor 中间量 = floor(4e15 / PRICE_MIN 4e8) × 1e6 = 1e7 × 1e6 = 1e13 ✓
# 价格恒 >= PRICE_MIN = 4e8 > 0（INV-066），无需除零保护

# 1 公共服务：按 pubserv 的中间投入需求（已由 S04 的 funding_ratio 决定上限）
# 2 政府采购：按已预留预算换算成数量
# 3 企业投入与补库：max(0, inv_target - inventory_input_end_est)，受 cell.cash 约束
# 4 出口：min(mul_ppm(基准出口量[s], world.export_demand_ppm[s]), world.delivery_capacity_uqs[s])
```

**配给（两级规则，两级都完全确定）**

```
if Σ demand <= supply:
    全额成交；flow.market.rationing_rule[s] = none
else:
    第一级 —— 公开优先级（内容配置 rationing_priority，默认 0..4 的顺序）：
        逐档满足，后面的吃剩余
    第二级 —— 同档内按需求量比例：
        alloc = split_largest_remainder(该档可分配量, 各需求量, 买方下标)
    flow.market.rationing_rule[s] = priority（或 gov.ration_mode == 1 时的 proportional）
unmet_demand = demand - traded
```

`INV-059`：`Σ traded + Σ unmet == Σ demand` 且 `Σ traded ≤ supply`；
卖方库存减少量精确等于 `Σ traded`（实物双边）。
未成交的居民预算**留作现金（被迫储蓄）**并记 `flow.group.unmet_consumption_uu`——
不允许静默消失，也不允许当作已消费（INV-064）。

**成交过账**

```
value_uu = mul_div_floor(qty_uqs, state.price.sector_uu_per_qs[s], 1_000_000)
# **这是 R-SCALE-01 点名的两处真溢出之一**：mul(QTY_MAX, PRICE_MAX) = 1e12 × 2.5e9 = 2.5e21 > 9.22e18
# mul_div_floor 中间量 = floor(1e12/1e6) × 2.5e9 = 2.5e15 ✓（且 2.5e15 < AMOUNT_MAX = 4e15）
# 单位：μQ_s × (μU/Q_s) / 1e6(μQ_s/Q_s) = μU ✓
if 跨地区: value_uu = mul_ppm(value_uu, 1_000_000 + region.logistics_cost_ppm[idx_od(r_sell, r_buy)])
           # mul_ppm 走 mul_div_floor，故 4e15 × 1.2e6 = 4.8e21 的裸乘不会发生
post(kind, buyer.cash -> seller.cash, value_uu, qty_uqs, s)
# 卖方库存 -= qty；买方若入库（企业投入）：
    buyer.inventory_input_uqs += qty_uqs                              # 数量账，μQ_s
    base_value_uu = at_base(qty_uqs, s)                               # 价值账，μU（§0.3.3）
    flow.cell.price_variance_uu[buyer] += (base_value_uu - value_uu)  # 见 §6.4
# 买方若不入库（居民消费、政府采购、资本品）：不产生价差
```

> **`price_variance` 的定义在 R-SCALE-01 下必须改写。** 旧刻度里 `BASE_PRICE / Q_SCALE == 1`，
> 于是「基年价计值的 μU 数」与「μQ_s 数」是同一个整数，本式才能写成 `qty_uqs − value_uu`。
> 新刻度里这个系数是 1000，再写 `qty_uqs − value_uu` 会让价差**偏掉 999/1000**，
> §6.4 的 INV-115 残差立刻非零。**这不是记法问题，是会计口径问题**：
> `price_variance = 入库价值(基年价) − 实付现金`，两边都必须是 μU。

### 5.7 公共服务交付

```
capacity = state.pubserv.capacity_active_uqs_per_q[r]
funded   = mul_ppm(capacity, state.pubserv.availability_ppm[r])
delivered_uqs = min(funded, 本地区服务需求)
queue_persons = 因 delivered < 需求 而未获服务的人数（按各组需求用最大余数法摊回）
```

`INV-102`：拨款不足**只降 `availability_ppm`**（在 S07 更新），
**不得降 `capacity_active`、不得删资产**（计划书 §07「停拨款会降低实际服务，而非删除建筑」）。

### 5.8 期末库存、损耗与排放

```
spoilage[i] = mul_ppm(inventory_output_uqs[i], content.io.spoilage_ppm[s])      # rounding: floor
inventory_output_uqs[i] -= spoilage[i]
（投入品库存同法，spoil_in）
flow.region.emissions_uqe[r] += Σ_s mul_ppm(output_actual[idx_cell(r,s)], content.io.emission_ppm[s])
```

损耗必须显式登记，**不允许用「盘点差异」吸收**；损耗计入中间消耗（§6.4，INV-053）。

**库存恒等式检查（逐 cell 逐品种，INV-047）**

```
inv_end == inv_start + produced + purchased - sold - used_in_production - spoilage   # 全部 μQ_s
```

> 这条恒等式跑在**数量账**（`state.cell.inventory_*_uqs`，μQ_s）上。
> 对应的**价值账**科目 `inv.<sector>`（μU）恒等于 `at_base(数量账, s)`（§0.3.3）：
> R-SCALE-01 之前两者是同一个整数，现在差 1000 倍，必须各自成立、由 `at_base` 唯一地联系起来。
> 因 `at_base` 无余数，数量账成立 ⇒ 价值账逐项成立，不需要第二条断言。

### 5.9 步末不变量与失败行为

INV-043..053、INV-059..064、INV-087..089、INV-094、INV-103、INV-104、INV-015、INV-016。

| 情形 | 行为 |
|---|---|
| `use > avail` | `Fault.NEGATIVE_INVENTORY`（说明 `q_actual` 推导有误），终止保留现场 |
| 需求为 0 而产量 > 0 | 正常：产量入库，`unmet_demand = 0`，库存上升 → S07 压低价格。**不得因此发放 GDP 或支持率奖励**（计划书 §10 验收测试 `T-S-P04-NO-DEMAND-NO-BONUS`） |
| 施工能力为 0 | 进度不增加，`suspended(congestion)` |
| 设备未到货 | `delivery_progress < 1e6`，即使施工 100% 也**不得完工**（INV-090） |
| 买方现金不足 | 成交量缩减 + 记未满足需求；**没有任何路径可以产生「凭空的货」** |

---

## 6 S06 财税结算

**计划书**：计算所得税、经营结果、利息与现金结余。必须检查收入／融资区分；账目和债务对手方一致。

| 项 | 内容 |
|---|---|
| 输入 | S02/S04/S05 的全部分录；`state.bond.*`；政策 P01/P02/P11 参数 |
| 输出 | 税收、折旧、企业利润与分配、储蓄、GDP 三口径、外部账户、恒等式终检 |
| **可写子集** | `flow.gov.receipts_*`、`state.gov.cash/tax_receivable/arrears`、`flow.cell.gross_output/intermediate/value_added/value_added_real/depreciation*/operating_surplus/profit_pretax/tax_profit_paid/distributed`、`state.cell.cash/capital_value/loss_carryforward`、`state.cell.capacity_active_uqs_per_q`（折旧）、`state.pubserv.capital_value/capacity_active`（折旧）、`state.region.grid_capacity_uqs_per_q`（折旧）、`flow.pubserv.depreciation_uu/output_uu`、`flow.group.property_income/income_tax_paid/savings`、`state.group.cash/deposit_uu`、`state.invpool.*`、`flow.invpool.*`、`state.region.port_capacity_uqs_per_q`（折旧）、`state.world.current_account_uu`、`derived.*`（重算）、`log.*` |
| 日志 | 每组税基、侵蚀量、征收能力与实缴；每 cell 利润构成；每批次利息；GDP 三口径构成与调节项 |

### 6.1 折旧（计算并落账，均在本步）

```
flow.cell.depreciation_uu[i]        = mul_ppm(state.cell.capital_value_uu[i],
                                              content.io.depreciation_ppm_per_q[s])   # rounding: floor
state.cell.capital_value_uu[i]     -= flow.cell.depreciation_uu[i]
flow.cell.depreciation_uqs_per_q[i] = mul_ppm(state.cell.capacity_active_uqs_per_q[i],
                                              content.io.depreciation_ppm_per_q[s])
state.cell.capacity_active_uqs_per_q[i] -= flow.cell.depreciation_uqs_per_q[i]
（pubserv 与 region.grid_capacity 同法）
# 溢出：capital_value_uu <= AMOUNT_MAX = 4e15，裸乘 ×1e6 = 4e21 会溢出；
#       mul_ppm 走 mul_div_floor（§0.3.2），中间量 = floor(4e15/1e6) × 1e6 = 4e15 ✓
```

折旧是**非现金分录**（`kind = depreciation`）：资产 ↓、净值 ↓。
**维护与折旧分开记**（计划书 §06）：折旧减资产账面值与产能；维护欠账（S07 更新）只降本季可用率，不减资产（INV-055）。

> **裁定**：草案 A 在 S06 计算、S07 落账并自己登记为待决问题（跨步暂存）；草案 B/C 全放 S07。
> 本契约放在 S06 —— 折旧是经营结果的费用项，而计划书 §13 的第 06 步就是「经营结果」。
> 跨步暂存消失，`capacity_active` 的两个写者（S01 转入、S06 折旧）用途明确且都在生产（S05）之后或之前的确定位置。

### 6.2 增加值与总产出（计划书 §06 [1]，防重复核算）

```
# 全部为 μU。**凡标「基年价」的项，一律经 at_base(qty_uqs, s) 从 μQ_s 换成 μU（§0.3.3）。**
# R-SCALE-01 之前 BASE_PRICE / Q_SCALE == 1，μU 数与 μQ 数碰巧相等，本节曾直接拿数量当金额用；
# 现在这个系数是 1000，必须显式换算，否则下面每一个恒等式都会差三个数量级。
sales_rev[i]   = Σ 本季全部销售交易的成交额（现价，直接是 μU）
d_inv_out[i]   = at_base(inventory_output_end[i], s) - at_base(inventory_output_start[i], s)
d_inv_in[i]    = Σ_j ( at_base(inventory_input_end[i][j], j) - at_base(inventory_input_start[i][j], j) )
spoil_out[i]   = at_base(spoilage_out_uqs[i], s)
spoil_in[i]    = Σ_j at_base(spoilage_in_uqs[i][j], j)
used[i]        = Σ_j at_base(flow.cell.consumed_input_uqs[idx_inv(i,j)], j)

gross_output_uu[i] = sales_rev[i] + d_inv_out[i] + spoil_out[i]
intermediate_uu[i] = used[i] + spoil_out[i] + spoil_in[i]                    # 损耗计入中间消耗
value_added_uu[i]  = gross_output_uu[i] - intermediate_uu[i]
                   = sales_rev[i] + d_inv_out[i] - used[i] - spoil_in[i]
```

> `at_base` 对加减法**完全线性且无余数**（`at_base(q) == 1000·q` 精确，§0.3.3），
> 所以「先在数量上求差再计值」与「逐项计值再求差」给出同一个整数——本节两种写法可互换，
> §6.4 的推导不因换算而多出任何取整残差。这是 INV-115「残差恰为 0」能继续成立的前提。

实际值（基年价，INV-117）：

```
value_added_real_uu[i] = at_base(sold_qty_uqs[i], s) + d_inv_out[i] - used[i] - spoil_in[i]
                         # 全部数量口径，再统一用基年价计值成 μU
```

**禁止**用名义值除以任何价格指数得到实际值。静态检查：实际 GDP 函数不引用 `consumer_index_ppm`。

### 6.3 公共非市场产出（按成本）

```
flow.pubserv.output_uu[r] = flow.pubserv.wage_bill_uu[r]
                          + flow.pubserv.intermediate_uu[r]
                          + flow.pubserv.depreciation_uu[r]
其增加值 = wage_bill + depreciation
flow.gov.final_consumption_uu = Σ_r flow.pubserv.output_uu[r]
```

这笔产出**不走市场销售**（§5.6 中不出现 pubserv 作为卖方），只进 GDP，避免重复（INV-101）。

### 6.4 GDP 三口径与价差调节项（**本契约最关键的一处纠正**）

**权威口径是生产法：**

```
derived.gdp.production_uu = Σ_i value_added_uu[i] + Σ_r (pubserv wage_bill + depreciation)
```

**支出法分解：**

```
C     = Σ 居民消费成交额（现价）
G     = Σ_r flow.pubserv.output_uu[r]
I     = Σ 资本品购入额（现价，含 flow.cell.investment_uu 与项目形成的资产）
dINV  = Σ_i ( d_inv_out[i] + d_inv_in[i] )                 # 基年价
X     = flow.world.exports_uu
M     = flow.world.imports_uu
derived.gdp.expenditure_uu = C + G + I + dINV + X - M
```

**价差调节项：**

```
derived.gdp.price_variance_total_uu = Σ over 全部「入库交易」 ( at_base(qty_uqs, s) - value_uu )
                                    = Σ_i flow.cell.price_variance_uu[i]
# R-SCALE-01：被减数是**基年价计值的 μU**，不是裸 μQ 数（§0.3.3、§5.6）
```

**恒等式（INV-115，残差必须恰为 0）：**

```
derived.gdp.expenditure_uu == derived.gdp.production_uu + derived.gdp.price_variance_total_uu
```

**推导**（实现者必须能复核；测试 `T-U-GDP-IDENTITY` 用构造数据逐项验证）：

设销售按去向分解 `Σ sales_rev = C + SG + SI + SK + X`（SG 卖给公共服务、SI 中间品、SK 资本品），
其**基年价计值**（即 `at_base(该笔数量)`，单位仍是 μU）记为 `C_q, SG_q, SI_q, SK_q, X_q`；
进口分为中间品 `M_int` 与资本品 `M_cap`。
> **下标 `_q` 读作「同一笔交易按基年价计的 μU 值」，不是「μQ 数量」。**
> R-SCALE-01 之前两者是同一个整数，写法可以含混；现在差 1000 倍，必须分清，
> 否则 `SI − SI_q` 这一项会被算成「现价金额减数量」，量纲直接错。
由库存恒等式 `d_inv_in = purch_q − used − spoil_in`（三项均为基年价 μU），其中 `purch_q = SI_q + M_int_q`：

```
Σ value_added = Σ sales_rev + Σ d_inv_out − Σ used − Σ spoil_in
              = (C+SG+SI+SK+X) + Σ d_inv_out − (SI_q + M_int_q − Σ d_inv_in − Σ spoil_in) − Σ spoil_in
              = C+SG+SI+SK+X + dINV − SI_q − M_int_q
gdp_production = 上式 + pubserv(wage + dep)
gdp_expenditure = C + [SG + pubserv_wage + pubserv_dep] + [SK + M_cap] + dINV + X − [M_int_val + M_cap]
                = C + SG + SK + X + dINV + pubserv_wage + pubserv_dep − M_int_val
gdp_production − gdp_expenditure = SI − SI_q + M_int_val − M_int_q = −price_variance_total   ∎
```

因为每一项都由**同一批整数**构成（买方付款额与卖方收款额是同一个整数；库存变动是整数量差
经 `at_base` 精确放大 1000 倍，无余数），所以该等式在整数下**精确成立**，残差为 0。

> **为什么不是「三法残差恒为 0」**：草案 A 主张三法由同一批分录分类汇总、残差由构造恒为 0。
> 该主张在「库存按基年价计价」下不成立：生产法用基年价计存货与中间消耗，支出法用现价计最终需求，
> 两者相差恰好等于全部入库交易的价差之和。把不成立的等式写进契约，等于让 G1 阶段的第一个测试永远红。
> 本契约保留 A 的分类法（因为覆盖性检验有价值），把等式改写成成立的形式，并要求调节项**逐笔可追溯**（INV-119）。

**收入法分解（恒等式 + 覆盖性检验）：**

```
operating_surplus_uu[i] = value_added_uu[i] - flow.cell.wage_bill_uu[i]     # 含固定资本消耗，残差定义
derived.gdp.income_uu   = Σ_i (wage_bill + operating_surplus) + Σ_r (pubserv wage + dep)
                       == derived.gdp.production_uu                          # INV-116，定义上成立
```

**真正的检验是覆盖性（INV-114）：**

```
按 11 号文件 §5.3 的 kind → 三分类表反查：
  (a) 存在 kind 未在表中登记            -> Fault.LEDGER_KIND_UNCLASSIFIED
  (b) 应被分类的 kind 出现 none          -> Fault.GDP_CLASS_MISSING
  (c) 同一行在同一口径被计入两个类        -> Fault.GDP_CLASS_DUPLICATE
测试 test_u_gdp_class_coverage：故意给一个 kind 漏标，断言检查会红。
```

### 6.5 个人所得税（P01，含征收能力 P11 与税基侵蚀）

```
for g in sorted(groups):
    base = flow.group.wage_income_uu[g] + flow.group.property_income_uu[g]
           # 转移收入不计税（首版简化，OQ-212）
    # 税基侵蚀：税率越高，实际可征税基越小（计划书 §17「提高税率后税收是否绕过实际税基」）
    avg_rate_ppm = mul_div_floor(gross_tax_at(base), 1_000_000, max(base, 1))
                   # **裸乘在新刻度下溢出**：AMOUNT_MAX(4e15) × 1e6 = 4e21 > 9.22e18
                   # mul_div_floor 中间量 = floor(税额/税基) × 1e6 <= 1e6（税额 <= 税基）✓
    evasion_ppm  = mul_ppm(param.tax_evasion_slope_ppm,
                           max(0, avg_rate_ppm - param.tax_base_rate_ppm))
    base_eff     = base - mul_ppm(base, evasion_ppm)
    liability    = Σ_bracket mul_ppm(max(0, min(base_eff, upper_b) - lower_b), rate_b_ppm)
                   # rounding: floor, reason=少征优于多征
    collected    = mul_ppm(liability, min(state.gov.tax_capacity_ppm, 1_000_000))
    collected    = min(collected, state.group.cash_uu[g])        # 不得把群组现金打成负
    post(kind=income_tax, group -> gov, collected)
    state.gov.tax_receivable_uu += (liability - collected)       # 差额显式登记，不消失
```

**恶意玩家防线 ADV-05**：`base` 只来自**已过账的收入分录**，不存在独立的「税收系数」字段；
`base_eff` 与 `collected` 分别可观测，所以「税率 10% → 60%」的收入曲线是非线性且有拐点的。

### 6.6 企业利润税（P02，利润与现金严格分开）

```
profit_pretax_uu[i] = value_added_uu[i] - wage_bill_uu[i] - depreciation_uu[i]
                    + flow.cell.price_variance_uu[i]                 # 价差进经营结果
taxable   = max(0, profit_pretax_uu[i] - state.cell.loss_carryforward_uu[i])
state.cell.loss_carryforward_uu[i] =
      max(0, loss_carryforward - max(0, profit_pretax_uu[i])) + max(0, -profit_pretax_uu[i])
tax       = mul_ppm(taxable, policy.P02.rate_ppm)
tax       = mul_ppm(tax, min(state.gov.tax_capacity_ppm, 1_000_000))
paid      = min(tax, state.cell.cash_uu[i])                          # 利润 ≠ 现金
post(kind=profit_tax, cell -> gov, paid)
state.gov.tax_receivable_uu += (tax - paid)                          # 差额进应收，不是核销
```

**「利润与现金不能混用」的落地**：利润是流量概念，纳税受现金约束；
差额进应收税，**不允许「有利润但没现金就不交税且不记欠」**。

### 6.7 财产收入分配与储蓄

```
distributable = max(0, profit_pretax_uu[i] - paid_tax)
payout        = mul_ppm(distributable, param.payout_ratio_ppm)
按 cells_init.equity_share_ppm 用 split_largest_remainder 拆给各群组 -> property_income_uu
债券利息：invpool 收到的利息按各组 deposit_uu 份额用最大余数法分回 -> property_income_uu

derived.group.disposable_income_uu[g] = wage + property + transfer + support_in
                                      - support_out - income_tax_paid                 # INV-086
flow.group.savings_uu[g] = disposable - consumption - housing_cost
断言 Δcash[g] + Δdeposit[g] == savings[g]      （逐组逐季精确）
储蓄的存款部分 post(group.cash -> invpool.cash)，同时 group.deposit_uu += x（双边）
```

**闭环意义**：政府赤字必须有人真金白银买单。居民不储蓄 ⇒ `invpool` 没钱 ⇒ 政府借不到 ⇒
只能排序支出。这是「融资必须有对手方」（计划书 §07）在整数账本上的真实体现。

### 6.8 外部账户

```
state.world.current_account_uu += flow.world.exports_uu - flow.world.imports_uu
                                - 对外利息 + 对外净借款                        # INV-106
derived.world.external_debt_uu = Σ (holder == row) principal_outstanding_uu    # INV-107
derived.world.net_foreign_position_uu = -agent.row.nw
断言 Δ net_foreign_position == -(经常账户 + 金融账户)                          # INV-110
```

### 6.9 恒等式终检（本季唯一的终检点）

```
assert gov.cash_end == gov.cash_start + 收入 + 新增借款 - 基本支出 - 利息 - 还本     # INV-027
assert gov.debt_end == gov.debt_start + 新增借款 - 还本 - 确认减记                  # INV-028
assert gov.debt_end == Σ active bond.principal_outstanding_uu                      # INV-035
assert Σ over all agents Δcash == 0                                                # INV-017
assert Σ over all agents cash == scenario.total_cash_uu                            # INV-018
assert Σ recv == Σ pay                                                             # INV-019
assert 逐主体资产负债恒等式成立                                                     # INV-020
assert gdp_expenditure == gdp_production + price_variance_total                    # INV-115
```

### 6.10 失败行为

| 情形 | 行为 |
|---|---|
| 任一恒等式不成立 | `Fault.LEDGER_IMBALANCE`，终止结算，导出故障包。**不得自动修正，绝不用「平衡修正项」抹平** |
| GDP 覆盖性检验失败 | `Fault.GDP_CLASS_MISSING` / `GDP_CLASS_DUPLICATE`，报出具体分录 |
| 群组／企业现金不足缴税 | 按现金上限征收，差额进应收税，报告披露 |

---

## 7 S07 跨期变化

**计划书**：更新下一季价格、资产、技能队列与迁移。必须检查当季完工资产下一季提供能力；人口守恒。

| 项 | 内容 |
|---|---|
| 输入 | S05/S06 的结果；项目完工状态；教育队列；迁移诱因 |
| 输出 | 下季价格与工资率（写 pending）；完工资产写 pending；维护欠账；服务可用率；人口与迁移；教育结业；生活与服务指数；排放存量 |
| **可写子集** | `state.price.pending_uu_per_qs`、`state.price.wage_pending_uu_per_person_q`、`state.price.housing_rent_*`、`state.price.clamp_budget_used_count`、`flow.price.gap_ppm`；`state.cell.capacity_pending_uqs_per_q/capital_value_uu/wip/maintenance_backlog_ppm`、`state.pubserv.capacity_pending/availability_ppm/teachers_persons/health_staff_persons`、`state.region.grid_capacity_pending/housing_pending/port_capacity_pending/irrigation_index_pending/emissions_stock/env_exposure`、`state.gov.capital_uu/housing_uu/wip_uu/committed_memo/service_opex_committed_uu/tax_capacity_ppm`、`state.project.status/residual_value`、`state.group.*`（人口、教育队列、住房、指数、就业的人口流出配对）、`state.cell.employment_persons`（仅人口流出配对）、`state.politics.admin_capacity_ppm`、`state.rng.draw_count[demography]`、`log.*` |
| 日志 | 每次价格与工资调整的输入（缺口、库存偏离）与输出；每个完工资产；每条人口流动的来源与去向；每次夹逼 |

### 7.1 项目完工（写 pending，不写 active）

```
for p in sorted(projects where status == in_progress):
    if delivery_progress_ppm == 1_000_000 and construction_progress_ppm == 1_000_000
       and 配套条件满足（运行费已纳入预算、人员到位）:
        status = completed
        目标数组的 *_pending_* += capacity_effect_uqs_per_q       # **只写 pending**（INV-091）
        目标主体 capital_value_uu += 已形成资产的 wip 部分
        gov.wip_uu -= 该部分
        gov.service_opex_committed_uu += opex_per_q_uu
        释放 queue_slot
```

因为 `capacity_active` 只在下一季 S01 从 `pending` 转入，**本季完工的产能对本季生产毫无影响**——
这是数据流层面的保证，不是约定（INV-054）。

### 7.2 维护欠账与服务可用率

```
# 维护欠账：运行费未足额支付则累积（只降可用率，不减资产，INV-055）
shortfall_ppm = 1_000_000 - flow.pubserv.funding_ratio_ppm[r]
maintenance_backlog_ppm = clamp(
      maintenance_backlog_ppm + mul_ppm(shortfall_ppm, param.maintenance_backlog_gain_ppm)
                              - mul_ppm(maintenance_backlog_ppm, param.maintenance_backlog_recover_ppm),
      0, param.maintenance_backlog_max_ppm)

# 公共服务可用率
if funding_ratio_ppm < 1_000_000:
    availability_ppm = max(0, availability_ppm
                              - mul_ppm(param.opex_starve_decay_ppm, shortfall_ppm))
    对应项目 status = suspended(financing)（若是断供降效）
else:
    availability_ppm = min(1_000_000, availability_ppm + param.opex_recover_ppm)
# state.pubserv.capacity_active、region.grid_capacity、region.housing_stock 在本路径下不得被写（INV-102）
```

### 7.3 价格（有界、平滑，只在此处写 pending）

单位 μU/Q_s，按部门（全国统一价，4 个）。

```
# (a) 供需缺口（ppm，有界）
S_uqs = flow.market.supply_uqs[s]
D_uqs = Σ_买方类 flow.market.demand_uqs[*][s]
gap_demand_ppm = (S_uqs == 0) ? param.gap_cap_ppm
                              : clamp(mul_div_floor(D_uqs - S_uqs, 1_000_000, S_uqs),
                                      -1_000_000, 1_000_000)
                                # 被乘数可负；mul_div_floor 对负数仍是 floor（向 −∞），与 mul_ppm 的
                                # 取整偏置同源，见下文「取整偏置的登记」
                                # 溢出：|D−S| <= QTY_MAX = 1e12，真值上界 1e18 < 9.22e18 ✓

# (b) 库存偏离（ppm，有界；不可库存部门此项为 0）
IT = max(Σ_r flow.market.inventory_target_uqs[idx_cell(r,s)], 1)
I  = Σ_r state.cell.inventory_output_uqs[idx_cell(r,s)]
gap_cover_ppm = (storable[s] == 0) ? 0
                                   : clamp(mul_div_floor(IT - I, 1_000_000, IT),
                                           -1_000_000, 1_000_000)
                                     # IT 已由上一行 max(…, 1) 保证 >= 1
                                     # 溢出：|IT−I| <= 1e12，真值上界 1e18 ✓

# (c) 合成并截断（记 log.clamp）
gap_ppm = clamp( mul_ppm(gap_demand_ppm, param.price_gap_gain_ppm)
               + mul_ppm(gap_cover_ppm, param.price_cover_gain_ppm),
                 -param.gap_cap_ppm, param.gap_cap_ppm )

# (d) 原始变动与步长封顶
delta_raw = mul_ppm(state.price.sector_uu_per_qs[s], gap_ppm)
max_step  = mul_ppm(state.price.sector_uu_per_qs[s], param.price_step_max_ppm)
delta     = clamp(delta_raw, -max_step, +max_step)                         # 记 log.clamp

# (e) 绝对上下限（R-SCALE-01 后的值；base_uu_per_qs == BASE_PRICE == 1 000 000 000，INV-148）
p_floor = mul_ppm(content.price.base_uu_per_qs[s], param.price_floor_ppm)   #   400 000 000 == PRICE_MIN
p_ceil  = mul_ppm(content.price.base_uu_per_qs[s], param.price_ceil_ppm)    # 2 500 000 000 == PRICE_MAX
state.price.pending_uu_per_qs[s] = clamp(state.price.sector_uu_per_qs[s] + delta,
                                         p_floor, p_ceil)                  # 记 log.clamp
# 加载期必须校验 p_floor == PRICE_MIN 且 p_ceil == PRICE_MAX（INV-066）：
# 这两个数在新刻度下各 ×1000，若参数卡与 jw_units.gd 不同源，价格会在一个错误的箱子里平滑
```

**每次 clamp 生效都写 `log.clamp` 并 `clamp_budget_used_count += 1`**（INV-069）。
压力测试中该计数超过 `param.price_clamp_budget_count` 即判失败——
护栏收紧不得变成「撞墙被掩盖」。

**取整偏置的登记**：`mul_ppm` 内部 `idiv_floor` 对负数向 −∞ 取整，降价方向会多 1 μU。
这是确定性偏置，由 `T-U-PRICE-NEG-ROUNDING` 锁定；**不得改为向零截断**。
`T-U-PRICE-FIXPOINT` 断言缺口恒为 0 时价格序列严格不变（偏置不累积，INV-068）。

**「不在同一季循环放大」的落地**：`price.sector_uu_per_qs` 在本季 S05 全程是常量；
只有 `price.pending_uu_per_qs` 被写；S08 末一次性 swap。
同季内「价格 → 数量 → 价格」的回路在结构上被切断（INV-065）。

**工资同法**（参数不同，写 `wage_pending_uu_per_person_q`）：

```
wage_gap_ppm = clamp(mul_div_floor(空缺人数 - 失业人数, 1_000_000,
                                   max(labor_force_total, 1)), -1_000_000, 1_000_000)
               # 溢出：|人数差| <= 2.4e7，真值上界 2.4e13 ✓
delta = clamp(mul_ppm_2(wage_cur, wage_gap_ppm, param.wage_gain_ppm),
              -mul_ppm(wage_cur, param.wage_step_max_ppm),
              +mul_ppm(wage_cur, param.wage_step_max_ppm))
        # 原文写作 mul_ppm(wage_cur, mul_ppm(wage_gap_ppm, param.wage_gain_ppm))，
        # 数值等价但违反 M2 的书写规则（两个 ppm 必须先合成再缩放，走 mul_ppm_2），已改正
wage_pending = clamp(wage_cur + delta, param.wage_floor_uu, param.wage_ceil_uu)
# param.wage_floor_uu / wage_ceil_uu 是 μU 参数，已随 R-SCALE-01 ×1000
```

> **R-SCALE-01 对工资平滑的实际意义**：旧刻度下人均季度工资只有 1…3 μU，
> `mul_ppm(w, param.wage_step_max_ppm = 20 000)` 对 `w <= 49` 恒为 0，工资整局冻结、
> INV-067/INV-070 的有界平滑在工资侧永不触发。新刻度下 `wage_cur ≈ 1 360 μU`，
> 同一个 2% 步长给出 27 μU 的可用步长，本节公式才第一次真的会动。

### 7.4 人口（守恒，来源与去向齐全）

按固定顺序，每一步都是**配对的转移**；取整余数用 `split_largest_remainder` 分配到组，
保证 INV-071/072 精确成立。

```
1) 死亡:  deaths[g]  = mul_ppm(population_persons[g], demography.death_ppm_per_q[age])
          -> 去向：无（**死亡是唯一允许的净流出**）
2) 出生:  births[r]  = mul_ppm(Σ_{g ∈ r, working} population, demography.birth_ppm_per_q[r])
          -> 去向：group.<r>.minor.low（**出生是唯一允许的净流入**）
3) 成年:  age_out[g] = mul_ppm(population_persons[g], demography.age_out_ppm_per_q["minor"])
          minor -> working，配对写 age_out / age_in；目标技能档由该 minor 组的技能档（教育准备度）决定
4) 退休:  age_out[g] = mul_ppm(population_persons[g], demography.age_out_ppm_per_q["working"])
          working -> elder，配对；退休者同时从 employment_persons 中扣除（见 7.7）
5) 技能:  education_cohort 到期 -> skill_out（低档）与 skill_in（高档）等量配对（INV-082）
6) 迁移:  见 7.5（跨地区，配对）
7) 核对:  逐组 INV-072；全国 INV-071；迁移 INV-073
```

### 7.5 迁移（受职位、住房与迁移成本三重约束）

```
for (r_from, r_to) in sorted(邻接对):                    # 只在邻接地区之间发生（OQ-208）
    # 拉力：目的地相对来源地的三项优势，全部 ppm、各自 clamp，再按权重合成（权重和 == 1e6）
    wage_adv_ppm    = clamp(mul_div_floor(wage_index[r_to] - wage_index[r_from], 1_000_000,
                                          max(wage_index[r_from], 1)), -1_000_000, 1_000_000)
                      # 溢出：|工资差| <= param.wage_ceil_uu（新刻度 2e10），裸乘 ×1e6 = 2e16 尚可，
                      # 但走 mul_div_floor 后中间量 <= 1e6 × 1e6 = 1e12（因结果被 clamp 到 ±1e6）✓
    job_adv_ppm     = clamp(unemp_ppm[r_from] - unemp_ppm[r_to], -1_000_000, 1_000_000)
    service_adv_ppm = clamp(service_access_avg_ppm[r_to] - service_access_avg_ppm[r_from],
                            -1_000_000, 1_000_000)
    pull_ppm = clamp( mul_ppm(wage_adv_ppm,    param.migration_w_wage_ppm)
                    + mul_ppm(job_adv_ppm,     param.migration_w_job_ppm)
                    + mul_ppm(service_adv_ppm, param.migration_w_service_ppm), 0, 1_000_000)
    # 推力：目的地的住房紧张与环境暴露（劝退项）
    push_ppm = clamp( mul_ppm(housing_stress_ppm[r_to], param.migration_w_house_ppm)
                    + mul_ppm(env_exposure_ppm[r_to],   param.migration_w_env_ppm), 0, 1_000_000)
    net_ppm  = pull_ppm - push_ppm
    # wage_index[r] = 该地区在岗人员的平均季度工资（μU/人/季），按 cell 在岗人数加权，向下取整
    # unemp_ppm[r]  = mul_div_floor(该地区失业人数, 1_000_000, max(该地区劳动力, 1))   # 2.4e13 ✓
    # housing_stress_ppm[r] = clamp(mul_div_floor(occupied, 1_000_000, max(capacity, 1)),
    #                               0, 1_000_000)                                       # 2.4e13 ✓
    if net_ppm < param.migration_threshold_ppm: continue
    intent   = mul_ppm(eligible_pop, min(net_ppm, param.migration_max_share_ppm))
    # 三道硬闸
    cap_jobs    = r_to 的空缺岗位数
    cap_housing = max(0, IntMath.mul(region.housing_stock_units[r_to], param.persons_per_housing_unit)
                        - derived.region.population_persons[r_to])
                  # 溢出：8e6 套 × 个位数人/套 = 数千万 ✓；纯乘法，无除法
    cap_cost    = idiv_floor(state.group.cash_uu[g], content.region.migration_cost_uu[idx_od(r_from,r_to)])
    movers      = min(intent, cap_jobs, cap_housing, cap_cost)
    migrate_rejected_persons[g] += (intent - movers)        # 被挡回必须显式登记（INV-084）
    migrate_flow_persons[g_from][g_to] += movers
    post(kind=migration_cost, group -> cell.services[r_to],
         IntMath.mul(movers, migration_cost_uu))            # 迁移成本是真实支出
    # 溢出：2.4e7 人 × migration_cost_uu（剧本 2 000…4 000 μU，已随 R-SCALE-01 ×1000）= 9.6e10 ✓
    # 邻接对上 migration_cost_uu > 0；对角线为 0，但 §7.5 只遍历邻接对，不会走到 cap_cost 的除零
```

**恶意玩家防线 ADV-04**：`cap_housing` 是硬闸；
`Σ housing_units_occupied ≤ housing_stock ≤ housing_capacity` 恒成立（INV-083）；
容量**不会自动增长**。

### 7.6 教育队列（P05）

```
max_seats = IntMath.mul(state.pubserv.teachers_persons[r], param.student_teacher_ratio)
            # 溢出：教师数 <= 2.4e7 × 师生比（两位数）= 数亿 ✓；纯乘法，与货币刻度无关
new_seats = min(申请席位, max_seats - 在读席位)                       # 教师为 0 -> new_seats == 0
state.group.education_cohort_persons[g][q + param.training_lag_q] += new_seats
到期队列 -> skill_out（本档）与 skill_in（高一档）等量配对
```

**拨款当季不得产生任何 `skill_in`**（INV-081）。
**恶意玩家防线 ADV-03**：把 `teachers_persons` 设为 0 ⇒ `new_seats == 0`、`skill_in == 0` 全程；
拨款照付但形成无效支出并可解释。

### 7.7 就业的人口流出配对（INV-080）

```
for g in sorted(groups):
    outflow = deaths[g] + age_out[g] + Σ migrate_out[g]
    employed_share = mul_div_floor(outflow, employed_persons[g], max(population_prev[g], 1))
                     # 溢出：2.4e7 × 2.4e7 = 5.76e14 ✓（人 × 人，无 ppm 参与）
    按各 cell / pubserv 在该组的在岗人数用 split_largest_remainder 拆分 employed_share 并扣减
    断言 Σ 扣减 == employed_share      # S07 对 employment 的写入必须精确等于人口流出带走的就业
```

这是 `employment_persons` 允许有第二个写者（S07）的**唯一理由与唯一形式**；
静态检查：S07 中对 `employment_persons` 的写调用只允许出现在这一个函数内。

### 7.8 生活与服务指数

```
real_cons_g = Σ_i flow.group.consumption_by_product_uqs[g][i]            # 数量口径，天然是实际量
state.group.consumption_index_ppm[g]
    = mul_div_floor(real_cons_g, 1_000_000, max(base_real_cons_g, 1))
service_access_ppm[g][kind]
    = mul_div_floor(delivered_to_g[kind], 1_000_000, max(base_delivered_g[kind], 1))
# 溢出：两者的被乘数都是 μQ，上界 QTY_MAX = 1e12，真值上界 1e18 < 9.22e18 ✓
# 这两个指数是**数量比**，与货币刻度无关，R-SCALE-01 不改变它们的取值
```

基准 `base_*` 在 q=0 由剧本固定，之后只读。全国指数按人口用最大余数法加权。
**报告口径**：这是相对基准，不冒充国际排名（计划书 §05，INV-149）。

### 7.9 排放与环境

```
state.region.emissions_stock_uqe[r] += flow.region.emissions_uqe[r]
# 存量按季衰减（自然消纳），再按人口密度折算成暴露指数
state.region.emissions_stock_uqe[r] = mul_ppm(state.region.emissions_stock_uqe[r],
                                              1_000_000 - param.emission_decay_ppm)
density_ppm = mul_div_floor(derived.region.population_persons[r], 1_000_000,
                            max(content.region.area_index[r], 1))
              # 溢出：2.4e7 × 1e6 = 2.4e13 ✓
state.region.env_exposure_ppm[r] = clamp(
        mul_ppm_2(state.region.emissions_stock_uqe[r], param.env_exposure_gain_ppm, density_ppm),
        0, 3_000_000)
# 前置（加载期校验，V-REG）：content.region.area_index[r] >= 24_000。
# 理由：mul_ppm_2 的第一步是 floor_div(mul(p1, p2), 1e6)，这一步是**裸乘两个 ppm**。
#   p1 = env_exposure_gain_ppm <= 1e6；p2 = density_ppm 没有上界，
#   若 area_index 允许取到 1，density_ppm 可达 2.4e7 × 1e6 = 2.4e13，
#   裸乘即 1e6 × 2.4e13 = 2.4e19 > 9.22e18 —— 溢出。
#   要求 area_index >= 24_000 即钉住 density_ppm <= 1e9，裸乘 <= 1e15 ✓。
#   剧本最小的 area_index 是海岬的 500 000（density_ppm = 1e7），裕度 20 倍。
# 这条不是 R-SCALE-01 带来的（两个量都与货币刻度无关），是本次逐处复核发现的既有缺口。
```

首版不模拟完整气候系统（计划书 §08），**排放不反馈到生产约束**（INV-057）。

### 7.10 步末不变量与失败行为

INV-054/055/056、INV-065..070、INV-071..074、INV-081..084、INV-091、INV-102、INV-149。

| 情形 | 行为 |
|---|---|
| 人口守恒不成立 | `Fault.POPULATION_NOT_CONSERVED` |
| 迁移进出不配对 | `Fault.MIGRATION_UNPAIRED` |
| 住房容量被突破 | 不可能（硬闸）；若发生即 `Fault.HOUSING_OVERFLOW` |
| 价格连续多季触界 | 由 `clamp_budget_used_count` 累计；超预算即压测失败（不是运行期故障） |

---

## 8 S08 社会与报告

**计划书**：更新组织反应、留任条件；生成结构化复盘。必须区分会计贡献、约束诊断与情景预测。

| 项 | 内容 |
|---|---|
| 输入 | 本季全部结果；S01 冻结的起点快照；上季报告的预期值 |
| 输出 | 群组主观量与支持度；集团反应；事件触发；留任判定；结构化复盘；价格与工资 swap；`q` 递增 |
| **可写子集** | `state.group.living_index_ppm/expectation_ppm/trust_ppm/support_ppm`、`state.bloc.*`、`state.politics.*`、`state.meta.run_terminated/termination_reason`、`state.price.sector_uu_per_qs`、`state.price.wage_uu_per_person_q`（swap）、`state.time.q`、`state.rng.draw_count[event, politics]`、`log.explanations` |
| 日志 | 每次支持度变动的来源分解；每次事件触发的条件取值；留任判定的完整输入 |

### 8.1 三个主观量分开更新（计划书 §08「民众不是一个满意度」）

```
# 当期生活
real_income_uu[g]  = mul_div_floor(derived.group.disposable_income_uu[g], 1_000_000,
                                   max(derived.price.consumer_index_ppm, 1))       # 基年价口径的 μU
                     # **裸乘在新刻度下溢出**：AMOUNT_MAX(4e15) × 1e6 = 4e21 > 9.22e18
                     # mul_div_floor 中间量 = floor(收入/指数) × 1e6，实测约 1e4 × 1e6 = 1e10 ✓
per_capita_uu[g]   = idiv_floor(real_income_uu[g], max(state.group.population_persons[g], 1))
real_income_norm_ppm[g] = clamp(mul_div_floor(per_capita_uu[g], 1_000_000,
                                max(content.base_per_capita_real_income_uu[g], 1)), 0, 3_000_000)
                          # 溢出：per_capita 实测约 1.4e3 μU（R-SCALE-01 后），×1e6 = 1.4e9 ✓；
                          # 契约上界 AMOUNT_MAX × 1e6 会溢出，故必须走 mul_div_floor
# base_per_capita_real_income_uu 在 q=0 由剧本固定，之后只读（与消费指数同一套基准纪律）
# R-SCALE-01：该基准已随迁移 ×1000（剧本现值 1 000…6 000 μU），与 per_capita_uu 同刻度
w_income_ppm = 1_000_000 - param.living_weight_house_ppm - param.living_weight_service_ppm
               # 加载期校验 > 0；剧本口径 1e6 − 250 000 − 250 000 == 500 000
living_index_ppm[g] = mul_ppm(real_income_norm_ppm[g],            w_income_ppm)
                    + mul_ppm(1_000_000 - housing_burden_ppm[g],  param.living_weight_house_ppm)
                    + mul_ppm(service_access_avg_ppm[g],          param.living_weight_service_ppm)
                    # 三权重和 == 1 000 000（由 w_income_ppm 的定义式恒成立）
# 原文此处的收入权重误写成 param.support_weight_ppm[0]（支持度的生活权重），
# 那是另一张权重表：它的三项和也是 1e6，但它约束的是 living/expectation/trust 的合成，
# 与 living 内部的 income/house/service 合成没有任何关系。两张表串用会让
# 「三权重和 == 1e6」在两处同时成立却各自含义错位，是最难被测试发现的一类错。已改正。

# 未来预期：对生活指数的滞后平滑（惯性），可被事件修改
expectation_ppm[g] = clamp(mul_ppm(expectation_ppm[g], param.expectation_inertia_ppm)
                         + mul_ppm(living_index_ppm[g], 1_000_000 - param.expectation_inertia_ppm),
                           0, 2_000_000)

# 程序信任：只受「承诺兑现与否」驱动。失信事件是一个**闭集合**，逐季计数：
#   breach_count[g] = （本季对该组的转移支付欠付 ? 1 : 0）
#                   + （本组所在地区的公共服务运行费欠拨 ? 1 : 0）
#                   + （本组所在地区有项目被取消 ? 1 : 0）
#                   + （政府对债券违约 ? 1 : 0，全国一致）
#   keep_streak[g]  = 连续 breach_count == 0 的季数，上限 param.trust_streak_cap_q
breach_ppm = clamp(IntMath.mul(breach_count[g], 250_000), 0, 1_000_000)      # 每次失信记 0.25
keep_ppm   = clamp(mul_div_floor(keep_streak[g], 1_000_000,
                                 max(param.trust_streak_cap_q, 1)), 0, 1_000_000)
             # 溢出：keep_streak <= cap <= horizon_q(40) -> 4e7 ✓；cap 为 0 时取 1 避免 DIV_ZERO
trust_ppm[g] = clamp(trust_ppm[g]
                   - mul_ppm(param.trust_drop_ppm,    breach_ppm)
                   + mul_ppm(param.trust_recover_ppm, keep_ppm),
                     0, 1_000_000)
# 加载期校验 param.trust_recover_ppm < param.trust_drop_ppm（恢复慢于下降，INV-122）
```

**「短期补贴不能自动修复长期失信」的结构性落地**：`trust_ppm` 的更新式里**根本不存在
`transfer_income` 通道**——这不是把参数取零，而是结构上没有这条路（INV-122）。
且 `param.trust_recover_ppm < param.trust_drop_ppm`（加载期校验）。
测试 `T-S-TRUST-ASYMMETRY`：先制造一次欠付，再全额补发，断言 `trust_ppm` 不能在同季恢复原值。

### 8.2 支持度（相对基年的映射，来源可追溯）

**裁定 R-SUPPORT-01：支持度由三个指标相对基年的 *变化量* 驱动，不是对三个指标的绝对加权。**

```
# (a) 基准：全部取自剧本，是内容常量，q=0 之后只读（与 §7.8 的指数基准同一套纪律）
base_support_ppm[g]    = content.population_init.groups[g].support_ppm
base_living_ppm[g]     = content.population_init.groups[g].living_index_ppm
base_expectation_ppm[g]= content.population_init.groups[g].expectation_ppm
base_trust_ppm[g]      = content.population_init.groups[g].trust_ppm
# 这四项在 11_data_contract.md §5.7 的 PopulationInit schema 中已存在，不需要新字段；
# 载入器把它们同时写进 state.group.*（q=0 的现值）与 content.base_*（只读基准）两处。

# (b) 权重：仍是 param.support_weight_ppm[3]，Σ == 1_000_000（加载期校验）。
#     语义变了 —— 它现在加权的是**变化量**，不是水平值。取值本身不必改。
Δliving      = living_index_ppm[g]      - base_living_ppm[g]
               # 可负。|Δ| <= 3e6：living_index 是三项的凸组合，上界由 real_income_norm_ppm 的
               # clamp 上界 3e6 给出（另两项各 <= 1e6），docs/10 只写了「>= 0」，此处补出上界
Δexpectation = expectation_ppm[g]       - base_expectation_ppm[g]     # 可负，|Δ| <= 2e6（docs/10 区间 0..2e6）
Δtrust       = trust_ppm[g]             - base_trust_ppm[g]           # 可负，|Δ| <= 1e6（docs/10 区间 0..1e6）

# (c) 单次取整：三项先各自成积再求和，最后只除一次（禁止逐项 mul_ppm 后相加，那是三次取整）
num = IntMath.mul(param.support_weight_ppm[0], Δliving)
    + IntMath.mul(param.support_weight_ppm[1], Δexpectation)
    + IntMath.mul(param.support_weight_ppm[2], Δtrust)
      # 溢出：|num| <= 1e6 × (3e6 + 2e6 + 1e6) = 6e12 < 9.22e18 ✓
      # 这里不是「先乘后除」的溢出形态（三个积先求和），故不经 mul_div_floor；
      # 但下面这一次除法必须是全式唯一的一次取整，否则 §8.2 的可加性分解对不上
delta_ppm = idiv_floor(num, 1_000_000)                     # rounding: floor，对负数向 −∞
support_ppm[g] = clamp(base_support_ppm[g] + delta_ppm, 0, 1_000_000)

log.explanations.append({entity = g,
                         base = base_support_ppm[g],
                         分解 = [mul_ppm(w0, Δliving), mul_ppm(w1, Δexpectation), mul_ppm(w2, Δtrust)],
                         合计 = delta_ppm})                 # INV-123
# 分解项用 mul_ppm 逐项算只为**展示**；Σ 分解 与 delta_ppm 可差至多 2 ppm（三次 floor vs 一次 floor），
# 报告必须显示 delta_ppm 为准并把差额并入最后一项，**不得反过来用分解和覆盖 delta_ppm**。

derived.politics.support_national_ppm =
    split_largest_remainder 加权(support_ppm, 权重 = population_persons(age != minor))
# **必须同时保留逐组 support_ppm**（禁止只保留全国值，计划书 §18 的「玩家只看一条综合分数」风险）
```

**为什么绝对加权在基年会给出与席位占比脱节的 87%**

`living_index_ppm` 的基年值按定义就是满分口径的 `1 000 000`——`11_data_contract.md` 的 **V-POP-07**
（R-ACCESS-01 之后只剩消费指数与生活指数两项）要求它的人口加权值恰为 1e6，剧本里 36 组逐组都是 1 000 000。
于是绝对加权式 `Σ wᵢ · indexᵢ` 的第一项**恒定贡献满权重**；另两项也偏高：
剧本的非未成年人口加权 `expectation_ppm` = 964 935、`trust_ppm` = 569 117。代入：

| 口径 | 值（ppm） |
|---|---|
| 绝对加权 `Σ wᵢ·indexᵢ`，取 w = [450 000, 275 000, 275 000] | **871 864**（R-SUPPORT-01 所说的「约 87%」） |
| 同式取 w = [500 000, 250 000, 250 000] | 883 513 |
| 同式取 w = [400 000, 300 000, 300 000] | 860 215 |
| 同式的**理论下界**（w = [0, 0, 1 000 000]，全押信任） | 569 117 |
| 剧本登记的基年支持度（人口加权，非未成年） | **544 127** |
| `politics_init` 的席位占比 `56 / 101` | **554 455** |

绝对加权式在基年是 `{1 000 000, 964 935, 569 117}` 的凸组合，
所以**对任何合法权重（wᵢ ≥ 0，Σ == 1e6）它都 ≥ 569 117 ppm，恒高于席位占比 554 455 ppm**；
生活权重取 40%–50%、另两项对分时，落在 860 215–883 513 ppm（86.0%–88.4%）。
这不是参数没调好，是结构性的：
`living_index` 的基年满分由 V-POP-07 钉死，不受任何权重选择影响。
**差 30 多个百分点等于开局白送一个不存在的执政基础。**

改用相对映射后，q=0 时三个 Δ 全为 0 ⇒ `delta_ppm == 0` ⇒ `support_ppm[g] ≡ base_support_ppm[g]`，
逐组恒等于剧本登记值，全国 544 127 ppm 与席位 554 455 ppm 只差 10 328 ppm（约 1 个百分点）——
这正是 `politics_init` 的 `_note_seats_gov` 想要的「上届授权与当下民意已经分叉」的开局。
此后支持度只由**变化量**驱动，「政策的受益与受损能追溯到具体群组」仍然成立（INV-123）。

**验收断言**

```
T-S-SUPPORT-BASE-IDENTITY : q=0 跑完 S08，逐组 support_ppm[g] == content.base_support_ppm[g]，容差 0
T-S-SUPPORT-DELTA-ONLY    : 把任一组的 living/expectation/trust 三项同时置回基年值，
                            断言该组 support_ppm 回到 base_support_ppm（路径无关，只看当期差）
```

**INV-124 的落点不变**：`support_national_ppm` 仍用最大余数法加权，Σ 权重后的残差不得丢弃。

**INV-125**：`bloc.org_power_ppm` 与 `politics.admin_capacity_ppm` **不出现在上式中**。
票、组织影响力、行政能力由三个不同函数计算，静态检查互不引用。

### 8.3 集团反应

```
for b in [agri_coop, business, labor_public]:
    # 每个集团有一个「关心指标」（内容包给定的 metric id）：
    #   agri_coop    -> 农业 cell 的 value_added_real 之和
    #   business     -> 全部 cell 的 profit_pretax 之和
    #   labor_public -> 全国就业人数 + 公共服务可用率的人口加权
    care_delta_ppm = clamp(mul_div_floor(care[b] - care_prev[b], 1_000_000,
                                         max(absi(care_prev[b]), 1)), -1_000_000, 1_000_000)
                     # **裸乘在新刻度下溢出**：care 可以是 value_added_real / profit 之和，
                     # |care − care_prev| 的契约上界是 AMOUNT_MAX = 4e15，×1e6 = 4e21 > 9.22e18
                     # mul_div_floor 中间量 = floor(差/基数) × 1e6，因结果被 clamp 到 ±1e6，实测 <= 1e12 ✓
                     # absi 对 INT64_MIN 无正绝对值，由 JWMath.absi 显式挡掉
    stance_ppm[b][p] = clamp(stance_prev[b][p]
                           + （本季 p 刚生效 ? policy_def[p].political_reaction[b] : 0）
                           + mul_ppm(care_delta_ppm, param.bloc_care_gain_ppm),
                             -1_000_000, 1_000_000)

    derived.bloc.membership_persons[b] =
        Σ_g mul_ppm(state.group.population_persons[g], content.bloc_affiliation_ppm[g][b])   # 加权人数
    size_ppm  = clamp(mul_div_floor(membership_persons[b], 1_000_000,
                                    max(nation.population_persons, 1)), 0, 1_000_000)
                # 溢出：2.4e7 × 1e6 = 2.4e13 ✓
    res_ppm   = clamp(mul_div_floor(state.bloc.resource_uu[b], 1_000_000,
                                    max(param.bloc_resource_ref_uu, 1)), 0, 1_000_000)
                # **裸乘在新刻度下溢出**：resource_uu <= AMOUNT_MAX = 4e15，×1e6 = 4e21 > 9.22e18
                # param.bloc_resource_ref_uu 也已随 R-SCALE-01 ×1000，两者同刻度，比值不变
    org_power_ppm[b] = clamp( mul_ppm(org_power_prev[b], param.bloc_org_inertia_ppm)
                            + mul_ppm(size_ppm, param.bloc_w_size_ppm)
                            + mul_ppm(res_ppm,  param.bloc_w_resource_ppm),
                              0, 1_000_000)
    # 三项权重（inertia + w_size + w_resource）之和 == 1_000_000，加载期校验
```

「反对某政策不会自动等同于反对政府的一切」：`stance` 与 `support` 是两套变量；
`stance` 只影响改革可行性与议程，**不直接进 `support`**。

### 8.4 事件触发（用 `rng.event`，与 `rng.shock` 完全独立）

```
for E in sorted(event_templates by event_id):
    if q < last_fire_q[E] + cooldown_q or fire_count[E] >= max_occurrences: continue
    if 不是所有 trigger 条件成立: continue
    if draw_ppm(STREAM_EVENT, q) >= probability_ppm: continue
    应用 effects（**只能是事件白名单内的 ppm 增量**，11 号文件 §5.13）
    记录 evidence_refs 中各字段的实际取值 -> 报告可追溯
    fire_count[E] += 1 ; last_fire_q[E] = q
```

即使这里多抽 100 次，`rng.shock` 的取值也完全不变（计数器式抽样，INV-009）。

### 8.5 留任、选举与终局

```
if flow.politics.budget_review_due == 1:           # 由 S02 置位；q ≡ 3 (mod 4)
    预算审查：连续赤字超限或欠付超限 -> mandate_status = at_risk，集团 stance 惩罚
if q in {15, 31}:                                   # 第 16、32 季（q 从 0 起）
    seats_gov = seat_rule(derived.politics.support_national_ppm, seats_total)   # 纯函数，最大余数法
    if seats_gov * 2 <= seats_total:
        meta.run_terminated = true ; meta.termination_reason = lost_election
if mandate_status == lost 连续 param.no_confidence_q 季:
    meta.run_terminated = true ; meta.termination_reason = lost_confidence
if 连续 param.default_grace_q 季无法支付第 1 档:
    meta.run_terminated = true ; meta.termination_reason = fiscal_restructuring_failed
if q == state.time.horizon_q - 1:
    meta.run_terminated = true ; meta.termination_reason = horizon
```

**经济下滑本身不是失败**（计划书 §04）：终局判定式中**没有任何 GDP 项**（INV-128，静态检查）。
终局结算展示生活、分配、能力、韧性与政治五类结果，**不合成单一国力分数**。
选举规则是游戏抽象，不模拟真实选区（计划书 §08），报告措辞必须这样写。

### 8.6 结构化复盘（三类信息严格分栏）

| 栏目 | `kind` | 内容 | 措辞要求 |
|---|---|---|---|
| 已经发生 | `accounted` | 本季支出、收入、产量、就业的**精确加总**，每项可下钻到分录 | 「本季支出构成」；可以精确加总 |
| 规则推断 | `inferred` | 逐 cell 的 `binding_code` 与五项约束值；`suspension_reason`；`blocked_reason` | 「模型中的限制因素」；**多个瓶颈不做相加展示**；禁止「导致」「因为」等因果断言 |
| 情景预测 | `projected` | 四季现金预测、基线／不利两条粗略预览 | 必须标注假设；不宣称识别真实世界因果 |

**情景预测的实现**：对状态做一份只读副本（`duplicate()`），用**同一个 SimCore** 空命令跑 4 季，
**不另写一套近似模型**（避免两套核心不一致）。估算约 40 ms；若玩家在预算页频繁切换方案成为可感延迟，
按 OQ-230 缓存或降频。`projected` 条目**禁止回写任何状态字段**（INV-140，静态检查）。

报告必须包含（计划书 §07「财政页面必须展示」）：当前现金、未来四季到期本金、利息、
已签项目承诺（`committed_memo`）、服务运行费（`service_opex_committed`）、新政策的资金来源。
债务/GDP 单独展示并注明**不能替代偿付能力分析**。

### 8.7 收尾

```
state.price.sector_uu_per_qs      = state.price.pending_uu_per_qs          # 价格切换的唯一时点
state.price.wage_uu_per_person_q  = state.price.wage_pending_uu_per_person_q
state.time.q += 1                                                          # q 的唯一写入点（INV-012）
meta.state_hash = CanonicalEncoder.sha256(state)
checkpoints.append({q_settled, state_hash, step_hash[8]})
```

### 8.8 步末不变量与失败行为

INV-121..130、INV-011、INV-012、INV-014、INV-140。

| 情形 | 行为 |
|---|---|
| 事件触发条件引用不存在的字段 | 加载期已拦截；运行期出现即 `Fault.METRIC_UNKNOWN` |
| `support_ppm` 变动无来源记录 | `Fault.SUPPORT_UNEXPLAINED` |
| 主观量越界 | 由 `clamp` 保证并写 `log.clamp` |

---

## 9 故障处置与故障包

```gdscript
enum Fault {
    OK = 0, RUN_ENDED = 1,
    # 流程
    FLOW_NOT_RESET = 10, WRITE_OUT_OF_SCOPE = 11, PHASE_VIOLATION = 12, RNG_LOG_MISMATCH = 13,
    # 资金
    NEGATIVE_CASH = 20, BOND_MISMATCH = 21, LEDGER_IMBALANCE = 22, SPLIT_MISMATCH = 23,
    CASH_TOTAL_CHANGED = 24, BALANCE_SHEET_BROKEN = 25,
    # 实物
    NEGATIVE_INVENTORY = 30, UNBOUNDED_PRODUCTION = 31, ENERGY_STORED = 32,
    DOUBLE_ALLOCATION = 33, STOCK_IDENTITY = 34,
    # 人口与劳动
    POPULATION_NOT_CONSERVED = 40, MIGRATION_UNPAIRED = 41, EMPLOYMENT_OVERFLOW = 42,
    HOUSING_OVERFLOW = 43, WAGE_UNFUNDED = 44,
    # 核算
    GDP_CLASS_MISSING = 50, GDP_CLASS_DUPLICATE = 51, LEDGER_KIND_UNCLASSIFIED = 52,
    GDP_IDENTITY = 53,
    # 政治与报告
    SUPPORT_UNEXPLAINED = 60, METRIC_UNKNOWN = 61,
    # 工程
    INT_OVERFLOW = 90, DIV_ZERO = 91, INDEX_OUT_OF_RANGE = 92, FLOAT_IN_STATE = 93,
}
```

**处置原则**

| 类别 | 处置 | 依据 |
|---|---|---|
| **业务性短缺**（融资不足、材料不足、施工拥堵、燃料不足、无需求） | **不是故障**。产生欠付／延期／取消／配给／未满足需求状态，继续结算，写日志与诊断 | 计划书 §13「结算失败应产生欠付、延期或取消状态，而非静默改账」 |
| **不变量违反** | 立即 `FAULT`：停止推进、保留当前状态、导出故障包 | 计划书 §13 禁止后处理补丁；§17 P0 |
| **工程性错误**（溢出、越界、除零） | 显式检查后 `FAULT`（**不用 `assert`**，release 会剥离） | 计划书 §17「无崩溃、NaN 或未处理越界」 |
| **重放分歧** | 不修改状态，报告分歧季与分歧步骤 | 计划书 §12 |

**故障包** `user://faults/q<NNN>_<code>/`：
`state_before.json`、`state_after.json`、`ledger_q.csv`、`physical_q.csv`、`step_hashes.json`、
`commands.jsonl` 切片、`失败的不变量编号与实测残差`。

**任一 P0 失败的统一行为**：终止本季结算，导出故障包，**不回滚到「看起来正常」的状态**——
掩盖错账比崩溃更危险。

**发布构建的检查保留策略**

- 资金／物资／人口类不变量用**显式 `if` + `Fault`**，release 中仍然执行
  （每季约 300 次整数比较，代价 < 0.2 ms）。
- `assert()` 只用于「理论上不可能」的前置条件，允许在 release 剥离，因为它们已被上面的显式检查间接覆盖。
- `WriteGuard`（逐步骤子系统哈希比对）在调试构建全开；发布构建按 `param.write_guard_sample_q`
  的周期抽季开启（默认每 8 季一次），**分级本身写进参数卡并在存档中留痕**，
  以免调试与发布行为分叉成新的风险源（OQ-231）。

---

## 10 不变量检查时点表

| 时点 | 检查 | 等级 |
|---|---|---|
| 每次 `post()` 后 | INV-015、INV-016、INV-007 | P0 |
| 每次拆分后 | INV-003 | P0 |
| 每次计提后（首版仅票息） | INV-004（余数累加器结转） | P0 |
| 每次换算取整后 | INV-005（写 `log.rounding`；季末 `rounding_residual` 的变化被逐条解释） | P0 |
| 每次涉及外部的过账 | INV-026（对外收支必有 `agent.row` 作对手方） | P0 |
| 每次乘法前 | INV-006 | P0 |
| 每次抽样后 | INV-010、INV-011 | P0 |
| 每步进入／退出 | INV-012、INV-013 | P0 |
| S01 末 | 流量全 0、INV-037（01.8 分期表与余额对账）、INV-054/091、INV-109、INV-134 | P0 |
| S02 末 | INV-028、INV-030、INV-032..INV-042、INV-092..INV-098 | P0 |
| S03 末 | INV-074..INV-080 | P0 |
| S04 末 | INV-079、INV-085、INV-087、INV-096、INV-097、INV-030 | P0 |
| S05 末 | INV-043..INV-053、INV-059..INV-064、INV-088..INV-090、INV-103、INV-104 | P0 |
| S06 末 | INV-017..INV-021、INV-027、INV-028、INV-035、INV-101、INV-106、INV-107、INV-110..INV-119 | P0 |
| S07 末 | INV-055、INV-056、INV-065..INV-073、INV-081..INV-084、INV-102 | P0 |
| S08 末 | INV-121..INV-130、INV-140 | P0/P1 |
| 季末（全部步骤后） | INV-018、INV-019、INV-020、INV-021、INV-024、INV-025、INV-014 | P0 |
| 载入后 | 全部 P0 不变量 + INV-141..INV-152 | P0 |
| 构建期（静态） | INV-001、INV-002、INV-008、INV-022、INV-029、INV-057、INV-065、INV-078、INV-102、INV-105、INV-117、INV-120、INV-121、INV-125、INV-128、INV-138、INV-140 | P0 |

**分级策略**：以上全部 P0 不变量在**调试构建**中逐季全查。
**发布构建**中，每次 `post()` 级与每步级的检查照常执行（代价极低），
而「逐主体资产负债表」「派生量一致性」「日志可追溯性」这三类重计算型检查按
`param.write_guard_sample_q` 抽季执行。抽样周期是参数卡的一部分，在存档中留痕。

---

## 11 恶意玩家测试（计划书 §17）的可执行表达

每条对应 `tests/scenario/test_s_adv_<nn>.gd`，且**必须先写出会失败的版本**（先证明防线有效）。

| ID | 玩法 | 机制防线 | 断言 |
|---|---|---|---|
| `ADV-01` | 反复开关补助重复领钱 | `claim_ledger` 幂等键（INV-097）+ `effective_from_q` 单调不回溯 + 开关成本 + 冷却（INV-098）+ 补助以「已发生的实际投资」为前置 | 连续 20 季交替开关：`Σ subsidy_paid == Σ 合格实际投资对应额`，`duplicate_claim_blocked > 0`，`gov.cash` 逐季可复算 |
| `ADV-02` | 借新还旧永远无成本 | 利率随 `dsr_ppm` 单调上升 + 额度上限 + **不自动展期**（INV-038/040） | 40 季只滚动不偿还：`Σ interest_paid` 严格递增，且某季必然 `REJECT(E_CREDIT_LIMIT)` 或进入重组分支 |
| `ADV-03` | 没有教师照样培训 | `max_seats = teachers × ratio`；结业队列滞后（INV-081/082） | `teachers_persons = 0` ⇒ `new_seats == 0`、`skill_in == 0` 全程；拨款照付但形成可解释的无效支出 |
| `ADV-04` | 全员迁入一区享无限住房 | 目的地容量硬上限 + 迁移成本 + `migrate_rejected_persons`（INV-083/084） | 极端收入差下 `housing_occupied ≤ housing_capacity` 恒成立，`migrate_rejected > 0`，人口守恒 |
| `ADV-05` | 提税绕过税基 | 征收能力 + 税基侵蚀 + 税基只来自已过账收入（INV-031、§6.5） | 税率 10% → 60%：`receipts` 非线性且存在拐点；`base_eff` 明显下降，两者可分别观测 |
| `ADV-06` | 存档重载重抽已确定事件 | 计数器式 RNG + `draw_count` 全量入档 + `shock_log` 先查后抽（INV-109/131/133） | `save → load → advance` 与 `advance` 的 `state_hash` 逐位相同；`log.rng` 完全一致 |

---

## 12 P04 失败路径与验收测试（计划书 §10）

| 失败码 | 构造方式 | 期望行为 | 断言 |
|---|---|---|---|
| `financing` | 立项后把现金与信用额度降到 0 | `suspended(financing)`，已付不退 | `paid_uu` 不变；`progress` 不增；`committed_memo` 不减 |
| `delivery` | `world.delivery_capacity_uqs[manu] = 0` | `delivery_progress` 停滞 | 第 8 季 `delivery < 1e6` ⇒ **不得投运** |
| `congestion` | 同区并发项目数 > `construction_slots_total` | 后到项目 `suspended(congestion)` | `Σ queue_slot_held ≤ slots` |
| `fuel` | 切断能源部门投入 | 电力供给下降 ⇒ 电网项目运行受限 | `electricity_availability_ppm` 下降，`capacity_active` 不变 |
| `no_demand` | 压低 `export_demand_ppm` 与居民收入 | 新增电力容量闲置 | energy cell 的 `binding_code == plan`；**GDP 与支持度不得因投运本身上升** |

**三条验收断言（计划书 §10 原文的机器版）**

```
T-S-P04-PAY-NO-PROGRESS     : 施工能力 = 0 时，付款可发生但 Δconstruction_progress_ppm == 0
T-S-P04-NO-EARLY-COMMISSION : 第 8 季任一进度 < 1_000_000 ⇒ capacity_active 不变
T-S-P04-CONSTRAINT-ORDER    : 投运后，若 binding_code 曾为 energy，则下季 binding_code ∈
                              {plan, capacity, labor, materials}（先解除电力约束，再由其它约束决定产量）
T-S-P04-NO-DEMAND-NO-BONUS  : 无销路时不得直接发放 GDP 与支持率奖励
```

---

## 13 测试分层与门槛

| 层 | 目录 / 前缀 | 跑什么 | 通过判据 | 预算 |
|---|---|---|---|---|
| unit | `tests/unit/` `T-U-*` | 纯函数与单步：整数除法、最大余数、五项约束表、价格公式、票息、splitmix64 黄金向量、schema 校验、全部静态检查 | 逐项相等 | 全套 < 10 s |
| replay | `tests/replay/` `T-R-*` | 同种子同命令流 40/120 季逐季哈希；存档往返；迁移；重载不重抽 | `state_hash` 逐位相同 | 全套 < 60 s |
| scenario | `tests/scenario/` `T-S-*` / `ADV-*` | 机制链路：12 政策各 ≥1 成功链 + ≥1 失败链；P04 四条验收；失败路径五条；恶意玩家六条 | 不变量成立 + 期望状态命中 | 全套 < 5 min |
| stress | `tests/stress/` `T-X-*` | 100 种子 × 120 季；极端参数；长命令流；性能 | 无崩溃／无越界／不变量全程成立；季度结算中位数 < 0.5 s、P95 < 1 s（REF-01 参考机） | 夜间跑 |

**不变量覆盖率工具**：`tests/tools/invariant_registry.gd` 维护 INV-001..INV-152；
`invariant_coverage.gd` 遍历注册表与用例元数据，**任一不变量未被任何用例引用即 CI 失败**。

**阶段门槛**（对应计划书 §15 G0–G5 与 §17）

- G0 之前：`tools/bench_quarter.gd` 在 REF-01 上先跑一次空跑基准并登记（**不等到 G5 才测性能**）。
- G1 之前：unit + replay 全绿；连续 40 季可重放；无无来源资金或物资。
- G2 之前：P01/P03/P04/P05 的 scenario 链路全绿。
- G3 之前：`ADV-01..06` 全绿；三类冲击组合可解释。
- G5 之前：stress 全绿且性能达标。**任一 P0（错账、坏档、崩溃）未清零，不出试玩包。**

---

## 14 性能预算

**目标**（计划书 §17，REF-01 参考机，`--headless`）：季度结算中位数 < 0.5 s，95 分位 < 1 s。

**规模**：16 cell + 4 pubserv + 36 群组 + 64 库存项 + 48 就业项 + ≤512 债券批次 + ≤60 项目。
单季整数运算量级约 3e4 ~ 1e5 次；账本行约 1.5e3 ~ 4e3 行；8 次子系统哈希 ≈ 700 KB SHA-256。

**裕度会被什么吃掉（必须结构性排除）**

| 风险 | 处置 |
|---|---|
| 每季建 `Dictionary` 对象、`String` 拼接 | SimCore 零字符串、零 Dictionary（静态检查） |
| 日志用 `Array[Dictionary]` | 列式 `PackedInt64Array` |
| 每季 `duplicate()` 整份状态做快照 | 只在存档、情景预测与对账页复制；S01 的「冻结起点」只复制参与不变量校验的数组，进预分配 `_snapshot` |
| 日志数组反复扩容 | 预分配 `param.log_capacity_rows = 8192` 行；满则 1.5 倍扩并记告警 |
| 每季新建 `RefCounted` 中间结果 | 全部落在 `TurnRunner` 的预分配 scratch 数组，跨步骤复用，每步入口 `fill(0)` |
| 逐季全量不变量重计算 | §10 的分级策略：`post()` 级与步级全开，重计算型按季抽样 |
| 逐步骤子系统哈希 | 只哈希该步可写子集，不是全状态 |

**测量协议**：`tools/bench_quarter.gd` 无界面跑 100 种子 × 120 季，用 `Time.get_ticks_usec()` 逐季计时，
输出中位数 / P95 / 最大值与每步耗时分解到 CSV。参考机与构建号见 `docs/ENGINE.md` 的 REF-01 登记。
**在别的机器上测出的数字不能直接与门槛比较。**

---

## 15 裁定记录（结算合同部分）

> 下表是本文件**自身**在三份草案之间做的裁定（S-01…S-15）。
> `18_rulings.md` 中的 **R-** 系列裁定优先级更高（`18 > 12 > 11 > 10`），
> 其中 R-SCALE-01 / R-SUPPORT-01 / R-SEASON-01 对本文件的逐处落实见 **§16**。

| # | 冲突点 | 各方主张 | 裁定 | 理由 |
|---|---|---|---|---|
| S-01 | 电力分配的步骤 | A：S05（能源先产，按实际分配）；B/C：S04（按「上季末已知的本季可供计划」） | **S05，按能源部门实际产量分配** | B 自己把「计划与实际错位」登记为 Q-SIM-02 风险并只能用「差额记未满足」兜住；移到 S05 后整类风险消失，代价只是 S05 内部一个可测的固定次序 |
| S-02 | 能源自用（`a(e→e) > 0`） | 三稿均未处理这个自指 | **能源 cell 跳过能源约束；自用量用 ceil 从产出净出；加载期要求 `a(e→e) < 1e6`** | 唯一能在整数下闭合且不引入同期迭代的写法 |
| S-03 | 折旧的步骤 | A：S06 算 / S07 落账（自认待决）；B/C：S07 | **S06 算并落账** | 折旧是经营结果的费用项；消除跨步暂存；`capacity_active` 的两个写者用途明确且位置确定 |
| S-04 | GDP 三法一致 | A：分类法，残差恒 0；B/C：只做生产法 | **生产法为权威；支出法 + 价差调节项；收入法为定义式 + 覆盖性检验** | A 的「残差恒 0」在基年价计价下不成立（§6.4 推导）；写进契约等于让第一个测试永远红 |
| S-05 | 库存损耗的核算位置 | A：库存恒等式的最后一项；B/C：同 | **既减库存又计入中间消耗，且不重复扣减总产出** | 只有这一种写法能让 §6.4 的恒等式在整数下精确闭合（推导中 `spoil_in` 项恰好相消） |
| S-06 | 工资付不出时怎么办 | A/C：S03 现金闸，不允许欠薪；B：S04 二次裁员 | **S03 闸住；S04 发现不足即 `Fault.WAGE_UNFUNDED`** | B 自认破坏单一写者；把它变成故障而不是补救，缺陷才会被发现 |
| S-07 | 招工的确定性分配 | A：最大余数法；B：最大余数法；C：cell_id 升序 + 出价降序，再最大余数法 | **下标升序汇总 + 最大余数法，禁止随机分配** | 三者相容；显式禁止随机分配以保重放 |
| S-08 | 施工能力的来源 | A：由服务部门**计划**产量折出（S03）；B：剧本给定的产能存量；C：只有槽位 | **由服务 cell 的**实际**产量折出（S05）+ 槽位并存** | 与 S-01 同理：用实际而非计划；两条约束对应两种可测的拥堵形态 |
| S-09 | 抽样映射的取模偏差 | B、C 均登记为待决 | **拒绝采样，被拒的抽样也写日志并推进计数器** | 直接消除一个待决问题；重放仍逐位一致 |
| S-10 | 发布构建的检查强度 | A：全开；B：分级；C：全开并自认会拖慢 | **`post()` 级与步级全开；重计算型按 `param.write_guard_sample_q` 抽季** | C 自认「分级会让调试与发布行为分叉」；把抽样周期写进参数卡并在存档留痕，使分叉本身可追溯 |
| S-11 | 情景预测的实现 | A：未定；B：`duplicate()` 跑只读副本；C：未定 | **跑只读副本，不写第二套近似模型** | 避免两套核心不一致；延迟风险登记为 OQ-230 |
| S-12 | `binding_constraint` 并列 | A：固定优先序；B：取最小序号；C：保留先出现者 | **固定序 plan<capacity<labor<energy<materials，严格小于才替换** | 三者等价，取最易静态验证的写法 |
| S-13 | 配给规则 | A：分档 + 档内最大余数；B：两种模式可切换；C：两级规则 | **两级规则（公开优先级 + 档内比例），`gov.ration_mode` 可切到全比例** | 三者并集；`rationing_rule` 字段使实际路径可被报告解释 |
| S-14 | 居民可支配预算的口径 | A：已到手现金；B：工资+转移+可动用资产−预缴税；C：本季已收 + 上季结余 | **已到手工资 + 转移 + 赡养净额 + `dissave_ppm` 比例的存款，且不超过当前现金** | 三者并集中最严格的一版；「未收到的预计收入不可支配」由「不超过当前现金」硬保证 |
| S-15 | 终局条件 | 三稿一致：不含 GDP | **静态检查终局判定式不引用任何 GDP 字段** | 把「经济下滑不是失败」从文档变成构建期检查 |

---

## 16 R-SCALE-01 同步记录

本节登记 `18_rulings.md` 的 **R-SCALE-01**（1 U = 10⁹ μU）、**R-SUPPORT-01**（支持度相对基年）、
**R-SEASON-01**（季节系数的作用基数）三条裁定对本文件的逐处改动，以及由此**向外**产生的待同步项。
裁定文件优先级高于本文件；本节只记录「本文件已经改到位了什么」与「别处还欠什么」。

### 16.1 「先乘后除」的逐处改造（R-SCALE-01 连带要求 1）

`mul_div_floor` 成为唯一合法入口（§0.3.2），向上取整用别名 `mul_div_ceil ≡ -mul_div_floor(-a, b, c)`。
`mul_ppm` / `mul_ppm_2` 内部已走 `mul_div_floor`，故本文件中它们的全部调用点**无需改写**。
以下是被逐处改写的**显式**先乘后除，标 ⚠ 者在新刻度下**裸乘真的溢出 int64**：

| 节 | 位置 | 旧写法的裸乘上界 | 改为 |
|---|---|---|---|
| §1.1 | 01.7 `decay_ppm` | 4e7 | `mul_div_floor(remaining_q, 1e6, duration_q)` |
| §2.1 | 02.1 席位占比 | 1.01e8 | `mul_div_floor(seats_gov, 1e6, seats_total)` |
| §2.1 | ⚠ 02.3 票息 `interest` | **4e20** | `mul_div_floor(outstanding, coupon_ppm, 1e6)` |
| §2.1 | ⚠ 02.3 计提余数 `rem` | **4e20**（旧式需要 `raw` 这个已溢出的中间量） | 用同余改写，中间量 < 1e11 |
| §2.1 | ⚠ 02.6 `dsr_ppm` | **4e21** | `mul_div_floor(未来4季债务负担, 1e6, 年化收入)` |
| §3.2 | (a) `need_k` | 4e17 | `mul_div_ceil(output_plan, labor_coeff, 1e6)` |
| §3.4 | `labor_force_total`、`unemployment_ppm` | 2.4e13 | `mul_div_floor` |
| §3.5 | `material_need_j`、`energy_need` | 2.6e17 | `mul_div_ceil` |
| §3.6 | `util_ppm` | 1e18 | `mul_div_floor` |
| §4.1 | ⚠ 04.2 `funding_ratio_ppm` | **4e21** | `mul_div_floor` + 新增 `due == 0` 分支 |
| §5.2 | `self_use`、`electricity_availability_ppm` | 1e18 | `mul_div_ceil` / `mul_div_floor` |
| §5.3 | `bound_labor`、`bound_energy`、`bound_materials` | 2.4e13 / 1e18 / 1e18 | `mul_div_floor`（并删掉 `bound_labor` 上一行多余的裸 `IntMath.mul` 溢出探针） |
| §5.4 | `use`、`energy_use` | 2.6e17 / 1e18 | `mul_div_ceil` |
| §5.5 | `Δconstruction_ppm`、`Δdelivery_ppm` | 1e18 | `mul_div_floor` + 新增「需求为 0」分支 |
| §5.6 | ⚠ 居民 `demand_uqs` | **4e21** | `mul_div_floor(budget_i, 1e6, price)` |
| §5.6 | ⚠ 成交 `value_uu` | **2.5e21**（R-SCALE-01 点名的 `mul(QTY_MAX, PRICE_MAX)`） | `mul_div_floor(qty, price, 1e6)` |
| §6.5 | ⚠ `avg_rate_ppm` | **4e21** | `mul_div_floor` |
| §7.3 | `gap_demand_ppm`、`gap_cover_ppm`、`wage_gap_ppm` | 1e18 / 1e18 / 2.4e13 | `mul_div_floor` |
| §7.5 | `wage_adv_ppm`、`unemp_ppm`、`housing_stress_ppm` | 2e16 / 2.4e13 / 2.4e13 | `mul_div_floor` |
| §7.7 | `employed_share` | 5.76e14 | `mul_div_floor` |
| §7.8 | `consumption_index_ppm`、`service_access_ppm` | 1e18 | `mul_div_floor` |
| §7.9 | `density_ppm` | 2.4e13 | `mul_div_floor` |
| §8.1 | ⚠ `real_income_uu`、`real_income_norm_ppm` | **4e21** | `mul_div_floor` |
| §8.1 | `keep_ppm` | 4e7 | `mul_div_floor` + `max(cap, 1)` |
| §8.3 | ⚠ `care_delta_ppm`、`res_ppm` | **4e21** | `mul_div_floor` |
| §8.3 | `size_ppm` | 2.4e13 | `mul_div_floor` |

**保留裸乘**（纯乘法，无后续除法）的 6 处已逐处复核并写明上界：
§2.1 计提余数的两次 `mul(·, 1e6)`（≤ 4e15 / ≤ 1e11）、§4.1 `wage_bill`（4.8e17）、
§4.1 P03 `total`（4.8e17）、§7.5 `cap_housing` 与迁移成本（9.6e10）、§7.6 `max_seats`、
§8.1 `breach_ppm`、§8.2 支持度的三个加权项（6e12）。

**§8.2 是唯一被判定「不该走 `mul_div_floor`」的先乘后除**：它是「三个积先求和、最后只除一次」，
拆成三次 `mul_div_floor` 等于把一次取整变成三次，会破坏「分解之和 == 合计」的可追溯性（INV-123）。
该式的分子上界 6e12，已逐项复核。

### 16.2 `at_base`：R-SCALE-01 打破的一个数值巧合（新增 §0.3.3）

旧刻度 `BASE_PRICE / Q_SCALE == 1`，于是「按基年价计值的 μU 数」与「μQ_s 数」是同一个整数；
本文件 §5.6、§6.2、§6.4 三处曾直接把数量当金额用。新刻度下该系数是 **1000**，巧合消失。
改动：

- §0.3.3 定义 `at_base(qty_uqs, s) = mul_div_floor(qty_uqs, base_uu_per_qs[s], 1e6)`，
  并证明它 `== 1000·q` 精确无余数、对加减完全线性（这是 §6.4 残差仍恒为 0 的前提）。
- §5.6 `price_variance` 由 `qty_uqs − value_uu` 改为 `at_base(qty_uqs, s) − value_uu`。
  **不改这一处，价差会偏掉 999/1000，INV-115 立刻非零。**
- §6.2 `d_inv_out` / `d_inv_in` / `spoil_*` / `used` / `value_added_real_uu` 逐项加 `at_base`。
- §6.4 明确下标 `_q` 读作「按基年价计的 μU」而非「μQ 数量」，并据此重述推导的量纲。
- §5.8 补一句把数量账与价值账用 `at_base` 唯一地联系起来。

### 16.3 R-SUPPORT-01（§8.2 重写）

绝对加权改为相对基年的映射；`base_*` 四项取自 `population_init.groups[g]` 的
`support_ppm / living_index_ppm / expectation_ppm / trust_ppm`（schema 已有，不需新字段）；
权重仍是 `param.support_weight_ppm[3]`（Σ == 1e6），但语义从「加权水平值」变为「加权变化量」。
§8.2 用剧本实测值给出了绝对加权的 871 864 ppm 与席位占比 554 455 ppm 的 33 个百分点缺口，
并补了两条验收断言。连带改正 §8.1 把 `param.support_weight_ppm[0]` 误当作生活指数收入权重的串用。

### 16.4 R-SEASON-01（§2.1 新增 02.0）

`season_factor_ppm` 与 `annual_plan` 此前在本文件是**零命中**——内容层算出的四季数只写在 `_note_*` 里，
结算无人读，INV-042 退化成「四项和等于 1e6」的空断言。02.0 是它们唯一的读取点：
季节系数只作用于「年度支出 − 全年利息 − 全年到期本金」，利息与到期本金由 `bond_book` 逐批次逐季单算；
给出三条必须同时成立的校验式与基年剧本的逐项复核（19 966 300 000 + 2 033 700 000 + 3 600 000 000
= 25 600 000 000）。

### 16.5 §1.1 新增 01.8：债券分期表的起点定义

写死为「覆盖 `issue_q + 1 … maturity_q` 闭区间、`n = maturity_q − issue_q`、等权重最大余数法预生成」，
并给出 INV-037 的可执行断言与两笔开局 `level_principal` 的逐笔复核。
`tools/validate_content.py` 的 `amort_schedule()` 早已按此实现并在注释中引用本节，此前本文件却没有写。

### 16.6 本次同步补写的、原文未定义的分支（不是放宽，是补齐）

| 位置 | 原文 | 补写 | 理由 |
|---|---|---|---|
| §4.1 04.2 | `funding_ratio = 实付 × 1e6 / 应付` | `应付 == 0 ⇒ 1e6` | 应付为 0 时原式 `DIV_ZERO` |
| §5.5 | `Δconstruction_ppm`、`Δdelivery_ppm` 直接除 | 需求为 0 ⇒ 该维度直接补满 | 否则「纯设备采购」「纯土建」两类项目 `DIV_ZERO`，且因 §7.1 要求两项进度都达 1e6 而永不完工 |
| §8.1 | `keep_ppm` 除以 `param.trust_streak_cap_q` | `max(cap, 1)` | cap 为 0 时 `DIV_ZERO` |
| §7.3 | `p_floor` / `p_ceil` 注释写旧刻度的 400 000 / 2 500 000 | 400 000 000 / 2 500 000 000，并要求加载期与 `PRICE_MIN/MAX` 同源校验 | 参数卡与 `jw_units.gd` 若不同源，价格会在错误的箱子里平滑 |
| §7.3 | `mul_ppm(w, mul_ppm(gap, gain))` | `mul_ppm_2(w, gap, gain)` | 数值等价，但原写法违反 M2 的书写规则 |
| §4.1 04.2 | `mul_ppm(replacement_ppm, ref_wage_uu)` | `mul_ppm(ref_wage_uu, replacement_ppm)` | `mul_ppm(x, p)` 的 `x` 位按定义是金额，前置条件「`x` 的绝对值不超过 `AMOUNT_MAX`」写在 `x` 上 |
| §7.9 | `mul_ppm_2(emissions_stock, gain_ppm, density_ppm)` 无 `density_ppm` 上界 | 加载期要求 `area_index >= 24 000` | `mul_ppm_2` 第一步是**裸乘两个 ppm**；`density_ppm` 是无上界的派生比率，`area_index` 取到 1 时裸乘达 2.4e19，溢出。**这条与货币刻度无关，是本次逐处复核发现的既有缺口** |

### 16.7 本文件**向外**产生的待同步项（不在本次改动范围内）

| # | 对象 | 问题 |
|---|---|---|
| 1 | `11_data_contract.md` §4、`10_variable_dictionary.md` §5 | 缺 `flow.gov.primary_budget_q_uu`（§2.1 02.0 新增的流量字段，S02 写、S04 读） |
| 2 | `10_variable_dictionary.md` §2.3 | 「所有库存按基年价格 **1 000 000** μU/Q_s 计价」「μU 数值恒等于 μQ_s 数值」两句均已随 R-SCALE-01 失效，须改为 1 000 000 000 与 `at_base`（本文件 §0.3.3） |
| 3 | `10_variable_dictionary.md` §4 库存科目行 | `inv.<sector>` 的「μU（恒等于 μQ_s 数值）」同上 |
| 4 | `10_variable_dictionary.md` `content.price.base_uu_per_qs` 行、INV-148 | 「恒 1 000 000」须改为 1 000 000 000 |
| 5 | `10_variable_dictionary.md` INV-118 | 「Σ gdp_production == 100 000 000 μU」须改为 100 000 000 000 |
| 6 | `10_variable_dictionary.md` `state.gov.cash_uu` 行 | 「剧本 = 2 000 000」须改为 2 000 000 000 |
| 7 | `11_data_contract.md` §5.2 的 `IntMath` 代码块 | 常量仍是旧刻度（`AMOUNT_MAX = 4e12`、`PRICE_MIN/MAX = 4e5/2.5e6`），且**没有 `mul_div_floor`**；`mul_ppm` 仍写成裸乘后除 |
| 8 | `11_data_contract.md` §5.9 `GovernmentInit` 示例与 V-FIN-01/02/03 | 示例值与校验常量仍是旧刻度（2 000 000 / 50 000 000 / 20 000 000 …） |
| 9 | `17_api_skeleton.md` §1.1 命名对照表 | 缺 `IntMath.mul_div_floor → JWMath.mul_div_floor`；`JWMath` 中**没有** `mul_div_ceil`，需走 §8 的接口变更请求补上，否则 §3.2/§3.5/§5.2/§5.4 的四处 ceil 只能逐处手写展开式 |
| 10 | `sim/jw_units.gd` | `U_SCALE` 上方的文档注释仍写「1 U = 1 000 000 μU」，与其下的 `1_000_000_000` 自相矛盾 |
| 11 | `content/scenarios/chengwan/scenario.json` `_note_season_factor_ppm` | 四季拆分数仍是旧刻度，且「余 1 μU 给到第 3 季」在新刻度下已无余数；`_note_season_factor_ppm_unread` 登记的「契约零命中」缺口已由本文件 §2.1 02.0 填上，可以销案 |
| 12 | `param.support_weight_ppm`、`param.living_weight_house_ppm`、`param.living_weight_service_ppm` | 三张参数卡在 `content/parameters/registry.json` 中仍是 `contract_min_set_missing`；§8.1 的 `w_income_ppm` 是残差式，不需要第四张卡，但前三张必须落地并在加载期校验 Σ == 1e6 |
| 13 | `10_variable_dictionary.md` 的 `content.*` 只读基准族 | `base_support_ppm` / `base_living_ppm` / `base_expectation_ppm` / `base_trust_ppm`（§8.2 新用）与既有的 `base_per_capita_real_income_uu`、`base_real_cons`、`base_delivered` 一样，**都没有在 10 号文件里建条目**。它们的取值来源是 `population_init`（已有字段），缺的只是「载入期把剧本值复制一份为只读基准」这条登记 |
| 14 | `content.region.area_index` 的加载期下界 | §7.9 新增 `area_index >= 24_000` 的前置，需要在 `11_data_contract.md` 的 regions 校验里落一条（当前剧本最小值 500 000，通过） |


## 17 第四轮裁定的契约变更（2026-09-21，无命令基线校准）

本节是 `18_rulings.md` 第四轮在本文件中的落点。下列条款**覆盖**正文中与之冲突的写法；正文未改动处以本节为准。

### 17.1 §2.6 新发债定价的偿债率分母（R-DSR-01）
`年化收入_uu` 是状态标量 `state.gov.receipts_annualized_uu`：S06 全部经常性收入（个税、利润税、其它收入）入账之后写
`(本季三项之和) × 4`，下一季 02.6 读；开局取剧本年度计划收入。它进存档与状态哈希（否则读档后第一季按分母 1 定价，续跑与直跑分叉）。

### 17.2 §3.1 投入品目标存量（R-ORDER-01）
`plan_output` 在写出本季计划的同时，为每个 cell 的每种非能源投入 j 登记
`target_in = ceil(max(plan, E) × io(j, s) / 1e6) × (1e6 + param.inventory_target_ppm) / 1e6`；
§5.6 买方类 3 的补库需求 = `max(0, target_in − 现有投入库存)`。本季买入的投入品供下季生产（INV-050），
所以目标按**下季**预期产量而不是本季实耗。

### 17.3 §3.2 公共部门补员（R-PUBSTAFF-01）
新增状态 `state.pubserv.establishment_persons[R×K]`（开局 == 剧本在岗）。闸一（地区同技能劳动力池）先给公共部门补员：
`hire = min(编制 − 在岗, floor(在岗 × hiring_friction) + 1, 池)`，池扣减后再按原式拆给 cell。

### 17.4 §5.2 电力：电网约束交付，跨区输电，电网进口（R-GRID-01、R-IMPORT-01）
1. 本地发电（加进口）先供本地区用户，`交付 ≤ grid(r)`；生命线档优先，生产用电按 `现金 ÷ max(电价, 进口电价)` 封顶后按最大余数法配给。
2. 进口量 `= min(floor(生产用电需求 × import_share[energy]), 交付能力余额, grid(r))`，先用；按各 cell 配给量最大余数拆出进口部分，
   按进口价付给 agent.row 并 `record_import`。
3. 全国输电：各地区未被本地用掉的发电进入输电池，按各地区剩余缺口（以其电网余量封顶）配给；两侧最大余数拆分，
   配对按下标升序；用电 cell 按当季电价付给发电地区的能源 cell。首版无输电损耗与输电费。
4. 仍未用掉的发电进入 §5.6 零售市场；`flow.region.electricity_supply_uqs` = 本地可交付给本地区用户的量 + 跨区输入量。

### 17.5 §5.6 进口计划与配给模式（R-IMPORT-01、R-RATION-01）
1. 配给前：进口计划 = `floor(需求 × import_share[s])`（出口与中央政府采购为 0），总量超过交付能力余额时按计划量最大余数压到余额；
   国内可供量只对 `需求 − 进口计划` 配给（INV-060 对国内部分精确成立）。
2. 成交：本档进口计划按请求量比例（`floor(请求 × 进口计划 / 本档计划)`）分到买方实体，先向 agent.row 按进口价购买；
   进口部分买不起时记未满足需求，**不转向国内卖方**。`flow.market.imported_uqs[MARKET_N]` 累计进口成交量；
   INV-059 的卖方侧 = `Σ 国内卖方市场售出 + Σ 进口 == Σ 成交`。
3. `ration()` 的第一个参数是政策旗（0 优先级 / 1 全比例），不是 `Rationing` 结果枚举。

### 17.6 §5.6 居民消费预算（R-CONS-01）
`cash_avail = wage + transfer + support_in − support_out + nonlabor_net_prev + mul_ppm(deposit, dissave_ppm)`，
其中 `nonlabor_net_prev = 上季(财产收入 − 个税 − 公共服务收费)`（状态 `state.group.nonlabor_net_prev_uu`，可负）；
预算 `= min(mul_ppm(cash_avail, mpc), 现金)`，下限 0。上季可支配收入 `state.group.disposable_prev_uu` 同步进状态块。

### 17.7 §6.5–§6.7 执行次序与税基（R-TAXBASE-01、R-FEE-01）
S06 次序改为：6.1 折旧 → 6.2 增加值 → 6.3 公共产出 → 6.4 利润 → **6.6 利润税 → 6.7 可分配额 → 财产收入过账** →
**6.5 个税**（税基含本季财产收入）→ **公共服务收费** → 收入年化（17.1）→ 储蓄与存款腿 → 6.8 外部账户 → 6.9 终检。
公共服务收费：每组 `fee = min(floor(Σ_k 本季交付量 × 基价 × param.pubserv_fee_ppm / 1e6 / Q_SCALE), 现金)`，
kind `PUBLIC_FEE`（32，三口径全 none），计 `flow.gov.receipts_other_uu` 与 `flow.group.fees_paid_uu`（可支配收入扣减项）。

### 17.8 §7.8 生活与服务指数的基准（R-LIVING-01）
`content.base_real_consumption_uqs` 与 `content.base_delivered_service` 由 `population_init` 群组字段
`base_real_consumption_uqs`、`base_delivered_service_uqs` 给出（`tools/refit_living.py` 生成）：
服务基准 = 地区产能按服务构成拆到三类、再按「人口 × 年龄权重」拆到群组，基年可用率 100% 时可及率恰为 100%。

### 17.9 企业分配（R-STATIONARY-01）
`param.payout_ratio_ppm` = 1 000 000：可分配额 = 税后利润（正值部分）。更新投资由折旧留存的现金支付。

### 17.10 §2.5 到期本金续发（R-ROLLOVER-01）
02.5 付本息之前：`spare = max(0, gov.cash − state.gov.receipts_annualized_uu ÷ 4)`；本季本息合计超过 `spare` 的部分，
对持有人为投资池或外部、票息未触 `param.coupon_max_ppm` 的到期批次（下标升序）由原持有人续发：旧批次按原条款结清该部分，
新批次按本季封存票息、`_new_issue_maturity` 期限、等额本金发行（同季同条件并入，R-BONDCAP-01）；无现金腿，
`flow.gov.new_borrowing_uu` 与 `flow.gov.principal_paid_uu` 同额增加并另记 `flow.gov.rollover_uu`。续发不占增量额度。
其后才走 R-FINANCE-01 的预融资与 02.5 付款；仍付不出的照常显露为违约。

### 17.11 §4.2 采购档（R-PROCURE-01）
2f 不再是空操作：`budget = 年度计划采购档 ÷ 4`；先按 R-FINANCE-01 融资，再核定 `flow.gov.procurement_budget_q_uu = min(budget, gov.cash)`；
§5.6 买方类 2 的预算取它（不再取 S05 末才登记的 `pay_procurement_uu`）。

### 17.12 §4.2 法定转移的常设部分（R-PENSION-01）
2c 的应付清单 = P03 失业救济（原式）+ 每个老年组 `population × param.pension_uu_per_elder_q`，同档支付。

### 17.13 §6.7 分配留足发薪现金（R-PAYOUT-02）
`distributable[c] = min(distributable[c], max(0, cash[c] − 本季工资现金流出[c] × 1e6 ÷ param.wage_cash_share_ppm))`。

### 17.14 §5.6 消费预算扣租金（R-CONS-01 补遗二）
17.6 的 `cash_avail` 再减本季住房支出 `housing_cost`（开市前已付）。

### 17.15 §01 能源 cell 的 D_prev（R-GRID-01 补遗）
能源 cell：`D_prev = 市场售出 + 直接售出 + flow.cell.elec_delivered_uqs`，`unmet_prev += flow.region.elec_unmet_uqs[本地区]`
（取代「+ 本地区用电总需求」）。

### 17.16 §2.1 改参数的时滞与窗口（R-PARAMS-01、R-ENACT-01）
命令 2 对执行中政策：新参数写入 `state.policy.scheduled_params`，`params_due_q[p] = q + max(1, lag.enact_to_effect_q)`；
S02 开头（受理命令之前）`params_due_q[p] <= q` 的政策把排期值落到参数槽并清 −1。`requires_budget_review` 的政策只能在审议季改参数。
命令 1 对执行中政策 ⇒ `REJECT(ALREADY_ENACTED)`，不触碰参数；资格链任一拒绝 ⇒ 该政策 pending / ppm / uu 参数槽还原（INV-137）。

### 17.17 §2.1 集团否决的并集（R-AUTHORITY-01）
否决集团位掩码 = `requires_bloc_mask[p]` ∪ {b : `policy_domain[p]` ∈ `veto_domains[b]`}；`policy_domain` 由授权位推出（0/1/2 ↔ tax_law / social_program / capital_project，
位 3 未映射）。其余判据（立场低于 `param.bloc_veto_stance_threshold_ppm` 才否决）不变。

### 17.18 §2.6 规则发行的期限（R-TENOR-01）
`_new_issue_maturity(q) = q + param.rule_issue_tenor_q`（32 季，等额本金），取代 `param.commitment_horizon_q`。

### 17.19 §7.3 工资式的锚点（R-NAIRU-01）
`tightness = clamp((vacancies − unemployed) × 1e6 ÷ labor_force − content.labor.anchor_tightness_ppm, −1e6, 1e6)`；
`anchor = −(Σ劳动力 − Σ在岗) × 1e6 ÷ Σ劳动力`，加载期由剧本初值求得（基年空缺为 0）。

### 17.20 §6.5 税基侵蚀参数（R-LAFFER-01）
式不变；`param.tax_base_rate_ppm` = 250 000，`param.tax_evasion_slope_ppm` = 1 350 000（区间 [0, 3 000 000]），单一税率静态拐点 ≈ 49.5%。

### 17.21 §4.2 能力类与行政类政策的项目期支出（R-POLSPEND-01）
2d 的应拨额 += Σ_p program_due(p)：`kind ∈ {capacity, admin}`、生效且 `q < effective_from_q + planned_quarters` 时取
`min(per_quarter_uu, budget_committed − budget_spent)`，按 region_mask 等权拆到地区、地区内按服务种类等分；实付按本档可拨付比例折算记入 `budget_spent`。
§7.1 非项目政策的效果落点季：`service_opex_committed += opex_per_q_uu`（能力类与行政类）。

### 17.22 §4.3 补助（R-SUBSIDY-01、R-PSLOT-01）
合格 cell、应得额与每季封顶按 docs/18 R-SUBSIDY-01；补助档付款前按「补助 + 待花采购预算」融资。`flow.cell.investment_uu` 由资本品入账记入。

### 17.23 §7.6 教育申请（R-P05-01）
第 7 条的逐组申请量 = 项目期内培训政策的 `seats_per_q_units` 按 track 与 region_mask 拆到劳动年龄组；§7.7 的 outflow 加 `skill_out`。

### 17.24 §7.5 迁移的推力（R-MIGRATE-01）
`push_ppm` 改为 `mul_ppm(housing_stress[r_to] − housing_stress[r_from], w_house) + mul_ppm(env[r_to] − env[r_from], w_env)`；
拉力与推力不再各自 clamp 到 [0, 1e6]，`net_ppm = clamp(pull − push, −1e6, 1e6)`。`post(kind=migration_cost, …)` 的三口径为 none（再分配类）。

### 17.25 §7.1 P11 与 P12 的效果（R-P11-01、R-P12-01）
`apply_effects(…, params)`：落点 `tax_capacity` 的政策按 docs/18 R-P11-01 缩放并夹上限（落点季一次）；
落点 `admin_capacity` 的政策在生效期内逐季按 E1—E16 更新（不只落点季）。无 params 的旧调用退回满额增量／零效应。

### 17.26 §8.4 事件（R-EVENT-01）
条件 `metric` 解析为注册表下标或 `DERIVED_BASE + k`（`derived.*` 与账户视图，按 docs/10 同口径从状态计算）；`read_metric` 收到的是
scope 的稠密下标（`scope_index_of`）；按群组的数组配 `region.<r>` 取该地区 9 个群组之和。`fire_count` / `last_fire_q` 是
`state.event.*` 状态数组（政治块），进存档与哈希。

### 17.27 §2.7 立项的资格链（R-LAUNCH-01）
`project_launch` 先判法定权限、席位、集团否决（并集）与预算审议窗口，再判施工槽位与规模。

### 17.28 §2.7 项目延期（R-DEFER-01）
命令 6 在 S02 受理（复工之后）：在建、不在延期中、次数与累计季数未超限；项目转 `suspended(deferred)` 至 `q + quarters`，
期间不开应付、不配施工能力、槽位照占、承诺不变；延期赔偿 = floor(剩余合同额 × 每季赔偿率 × 季数)，当季按三条线付给承包方
（kind 27），现金不足转欠付。`resume_suspended(q)` 对 `deferred` 只在 `q ≥ defer_until_q` 时复工。

### 17.29 §4.1 / §7.2 政策运行费的拨款上限与行政类衰减（R-P10-01、R-P11-02、R-P12-02、R-EXIT-OPEX-01）
S04 运行费档：带拨款槽的政策（P10）欠额 = max(已并入义务 − 拨款, 0)，从其作用地区实拨额中扣下，应拨额不变。
S07 第 2′ 条（政策效应之后、可用率之前）：P11 征收能力按中州到位率（退出后按完全断供）在 [地板, 建成水平] 内升降；
P12 撤回后 `decay_q` 季内按比例回落。S02 撤回行政类政策时从 `service_opex_committed` 扣回其 `opex_landed`。

---

*本文件为唯一权威版本。任何与之冲突的草案内容一律作废。*
