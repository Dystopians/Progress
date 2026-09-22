# 30 质量门与测试矩阵（唯一权威版）

> 计划书 §17 的可执行展开。计划书给出八类验收标准，本文件把每一条拆成**可以被一个程序员照着写、
> 被一条测试判定真假**的用例：测试 ID、所属套件、前置状态、操作、整数断言、失败时说明什么坏了。
>
> 本文件不重新定义任何机制。机制定义在
> `docs/10_variable_dictionary.md`（变量、单位、INV-001..152）、
> `docs/11_data_contract.md`（数据协议、错误码、加载校验）、
> `docs/12_simulation_contract.md`（八步结算、故障码、ADV 概述、性能预算）。
> **与那三份文件冲突的表述以那三份为准；与计划书冲突的以计划书为准。**

---

## 0 总则

### 0.1 本文件与 12 号文件 §11–§14 的关系

12 号文件 §11（恶意玩家）、§12（P04）、§13（测试分层）、§14（性能预算）给出了骨架与判据方向。
本文件是它们的**逐条展开**：骨架里的一行，在这里变成一条有前置夹具、有操作脚本、有整数断言的用例。
两处 ID 完全一致，**不新造别名**。

### 0.2 测试 ID 规则（与 11 号文件 §8 一致）

| 前缀 | 套件 | 目录 | 含义 |
|---|---|---|---|
| `T-U-*` | unit | `tests/unit/` | 纯函数与单步；不跑完整季度 |
| `T-R-*` | replay | `tests/replay/` | 确定性、存档往返、迁移、追溯 |
| `T-S-*` | scenario | `tests/scenario/` | 机制链路；跑若干完整季度 |
| `T-X-*` | stress | `tests/stress/` | 100 种子 × 120 季、极端参数、性能 |
| `ADV-*` | scenario | `tests/scenario/` | 计划书 §17「恶意玩家」六条 |
| `T-P-*` | 人工 | `docs/playtest/` | 试玩观察，不进 CI，但进发布门 |

**ID 与方法名的映射（强制）**：`T-U-A-01` 的实现方法名形如 `test_u_<语义名>`，
写在文件头的 `suite_note` 里登记本文件覆盖的矩阵 ID。
10 号文件 §14 已经点名引用的方法名（如 `test_u_rng_isolation`、`test_s_base_year_gdp`）
**必须原样使用**，本文件在「方法名」列中逐条给出。

**注册表**：`tests/tools/test_registry.gd` 维护「矩阵 ID → 方法名 → 覆盖的 INV 编号」三元组。
11 号文件 V-PD-06 / V-PD-07 要求政策内容包里的 `test_id` 在该注册表中真实存在——
注册表的唯一数据源就是本文件的矩阵表。**本文件新增一行，注册表加一条；注册表有而本文件无，即为脏条目，CI 失败。**

### 0.3 断言纪律

1. **一切断言是整数断言。** SimCore 禁用 float（INV-001），测试里也不做浮点近似比较。
   断言一律写成「期望 X 精确等于 Y」，用 `JWTest.eq_int` / `eq_str` / `eq_int_array`。
2. **容差一律 0。** 唯一例外是加载期反算失业率的 `[79_500, 80_500] ppm`（11 号文件裁定 D-02），
   该例外写死在协议里，放宽它必须先改 11 号文件。
3. **禁止「≥ 0 就算过」式的空断言。** 每条用例至少有一条形如 `eq_int(actual, <字面量或独立复算值>, ...)` 的断言。
   断言数为 0 的测试被运行器判为失败（`tests/run_tests.gd` 已实现）。
4. **期望值不得由被测代码算出。** 期望值只能来自：字面量、剧本硬约束常量、
   或一段**与被测实现不共享代码路径**的独立复算（例如用 Python 离线脚本预生成的黄金向量文件）。
5. **先写会失败的版本。** 每条「防线类」用例（拒绝、拦截、闸门）必须先证明去掉防线时它会红。
   实现方式：在用例注释里写明「拆掉哪一行会让它失败」，评审逐条核对。

### 0.4 用例六字段格式

矩阵每一行给出六个字段，缺一不可：

| 字段 | 要求 |
|---|---|
| ID | 本文件的矩阵 ID，全局唯一 |
| 套件 | unit / replay / scenario / stress / 人工 |
| 前置状态 | 夹具 ID（§1）+ 需要额外覆盖的字段与其精确取值 |
| 操作 | 提交哪些命令、推进几季；无命令也要写「无命令推进 N 季」 |
| 断言 | 整数精确断言，写成 `字段 == 字面量` 或 `残差 == 0` |
| 失败说明 | 这条红了，说明系统的哪一部分坏了、属于哪一级缺陷（§10） |

---

## 1 测试夹具登记

「前置状态」要可执行，就必须有登记在案的夹具。夹具全部放在 `content/test/`，
**每个夹具是一张卡**，声明：派生自谁、精确覆盖了哪些字段、破坏了哪条加载期硬约束（若有）。

> **夹具纪律**：夹具只允许覆盖字段，不允许绕过加载流水线。
> 若某个夹具必然违反 INV-141..152 中的某一条（例如 FX-NOTEACH 让教师数为 0），
> 必须在卡里写 `waived_invariants: ["INV-xxx"]`，并且**豁免只在 `content/test/` 下生效**；
> 发行内容包出现任何 `waived_invariants` 非空的文件，加载器拒绝启动（`E_ASSERT_TOLERANCE`）。

| 夹具 ID | 派生自 | 覆盖内容（精确） | 豁免 | 主要服务的用例 |
|---|---|---|---|---|
| `FX-BASE` | — | 出厂剧本 `scenario.chengwan`，40 季，无覆盖 | 无 | 绝大多数 scenario 用例 |
| `FX-MIN` | — | 计划书 §16 T06 的最小切片：1 地区（`region.haijia`）、2 部门（`sector.manu` / `sector.energy`）、1 个人口群组、1 种可库存投入 | INV-141..143、INV-150 的部门完整性 | 账本、库存、约束换算类 unit 用例 |
| `FX-P04` | `FX-BASE` | 无字段覆盖；附带命令脚本：`q=0` 在 `region.haijia` 立项 P04，`funding_source="bond"`，`scale_ppm=1_000_000` | 无 | 全部 P04 用例 |
| `FX-NOCON` | `FX-P04` | `cell.haijia.services.capacity_active_uqs_per_q = 0` | 无 | `T-S-P04-PAY-NO-PROGRESS` |
| `FX-NODEL` | `FX-P04` | `world.delivery_capacity_uqs[sector.manu] = 0` | 无 | `T-S-P04-NO-EARLY-COMMISSION`、`T-S-P04-FAIL-DELIVERY` |
| `FX-CONG` | `FX-BASE` | `region.haijia.construction_slots_total = 1`；命令脚本 `q=0` 同季立项 3 个项目 | 无 | `T-S-P04-FAIL-CONGESTION`、`T-S-D-14` |
| `FX-NOFUEL` | `FX-BASE` | `cell.xiling.energy` 的全部可库存投入期初库存 = 0，且 `world.delivery_capacity_uqs[sector.manu] = 0`（断绝补库） | 无 | `T-S-P04-FAIL-FUEL` |
| `FX-NODEMAND` | `FX-BASE` | `world.export_demand_ppm[*] = 0`；全部群组 `dissave_ppm = 0` | 无 | `T-S-P04-FAIL-NODEMAND`、`T-S-P04-NO-DEMAND-NO-BONUS` |
| `FX-BROKE` | `FX-BASE` | `gov.cash_uu = 0`；`world.credit_limit_uu = 0`；`invpool.cash_uu = 0` | INV-145、D-11 的 `invpool.cash ≥ 年赤字` | `T-S-P04-FAIL-FINANCING`、`T-U-D-10` |
| `FX-RICHPOOL` | `FX-BASE` | `invpool.cash_uu = 400_000_000`；`world.credit_limit_uu = 400_000_000` | 无 | `ADV-02` |
| `FX-NOTEACH` | `FX-BASE` | 全部 `pubserv.*.teachers_persons = 0` | 无 | `ADV-03` |
| `FX-MIGRA` | `FX-BASE` | `cell.zhongzhou.*.wage_rate_uu` 期初 ×3；住房容量与存量不变 | 无 | `ADV-04` |
| `FX-TAXRAMP` | `FX-BASE` | 无字段覆盖；命令脚本把 P01 的税率从 100_000 ppm 逐季提到 600_000 ppm | 无 | `ADV-05` |
| `FX-STRESS120` | `FX-BASE` | `horizon_q = 120`；终局判定按 §6.5 的开关处理 | 见 §6.5 与 OQ-210 | 全部 `T-X-*` |
| `FX-GOLDEN-<n>` | — | 由 Python 离线脚本生成的黄金向量文件（整数序列），不含状态树 | 不过加载器 | `T-U-E-12`、`T-X-D-03` |

**路线脚本**（策略差异用，§8）：`content/test/routes/route_a.jsonl` / `route_b.jsonl` / `route_c.jsonl`，
三份命令流，同一 `FX-BASE`、同一 `root_seed`。

---

## 2 类别 A：资金与物资

计划书 §17：**每笔交易双边相等；金额整数对账零残差；库存恒等式成立，不得无提示负库存。**

### 2.1 双边相等与过账入口

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-U-A-01`<br>`test_u_post_balanced` | unit | `FX-MIN`，账本为空（仅开账分录） | 调用 `post()` 写一笔三行交易：`agent.gov −150_000`、`agent.cell_hj_manu +100_000`、`agent.row +50_000` | 返回码 `== Fault.OK(0)`；该 `txn` 的有符号行之和 `== 0`；行数 `== 3`；三行 `amount` 均 `!= 0`；三行的 `account_id` 两两不同 | 复式账本入口失效。INV-015 的全部下游（INV-017..021、027、028）失去基础。**P0** |
| `T-U-A-02`<br>`test_u_post_rejects_unbalanced` | unit | 同上 | 调用 `post()` 写 `−100_000 / +99_999` | 返回码 `== Fault.LEDGER_IMBALANCE(22)`；`log.ledger` 行数增量 `== 0`；`state_hash` 与调用前逐位相同 | 不平交易能落账，或落账后才检查。**P0** |
| `T-U-A-03`<br>`test_u_post_rejects_negative_cash` | unit | `FX-MIN`，`agent.gov.cash_uu = 1_000` | 调用 `post()` 支付 `1_001` | 返回码 `== Fault.NEGATIVE_CASH(20)`；`agent.gov.cash_uu == 1_000`（精确不变）；`log.ledger` 行数增量 `== 0` | 出现「先扣成负数再想办法」的路径，违反 INV-016 的原文约束。**P0** |
| `T-U-A-04`<br>`test_u_no_direct_cash_write` | unit（静态） | 全仓源码 | 运行 `tools/check_writers.gd`：扫描 `sim/` 与 `systems/` 中对 `cash` / `inv` / `capital` / `debt` 字段的赋值语句 | `post()` 与开账装载器之外的赋值点数量 `== 0` | 存在绕过账本的余额修改（计划书 §16 人工评审第一条）。**P0** |
| `T-S-A-05`<br>`test_s_cash_total_constant` | scenario | `FX-BASE` | 无命令推进 40 季 | 每季末 `Σ 全部主体 cash_uu == scenario.total_cash_uu`（40 次精确相等）；每季 `Σ Δcash == 0`（40 次 `== 0`） | 货币被凭空创造或消失。首版不模拟商业银行与货币创造（INV-018）。**P0** |
| `T-S-A-06`<br>`test_s_balance_sheet` | scenario | `FX-BASE` | 无命令推进 40 季 | 每季末对每个主体：`cash + Σinv + wip + capital + housing + recv + bondhold + deposit_claim − pay − debt − deposit_liab − nw == 0`，残差恰为 0（主体数 × 40 次断言） | 资产负债恒等式破裂，净值自己动了（INV-020/021）。**P0** |
| `T-U-A-07`<br>`test_u_receivable_payable_paired` | unit | `FX-MIN` | 造一笔欠付：应付 `300_000` 记入 `agent.gov`，对应应收记入承包方 | `Σ recv == Σ pay`（精确相等）；`gov.arrears_uu` 增量 `== 300_000`；`log.arrears` 增 1 行且 `amount_uu == 300_000` | 欠付单边登记，INV-019/030 破裂。**P0** |

### 2.2 整数对账零残差

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-U-A-08`<br>`test_u_split_sum` | unit | — | `split_largest_remainder(1_000_001, [1,1,1])` | 返回 `[333_334, 333_334, 333_333]`（逐位相等）；三项之和 `== 1_000_001` | 最大余数法实现错误，一切拆分（季节系数、分期表、配给、加权支持度）失去 INV-003。**P0** |
| `T-U-A-09`<br>`test_u_split_sum_fuzz` | unit | `FX-GOLDEN-01`（离线生成的 1_000 组 `(total, weights)`） | 逐组调用 `split_largest_remainder` | 1_000 组全部满足 `Σ 分项 == total`（1_000 次精确相等）；无任一分项为负当且仅当 `total ≥ 0` | 拆分在某些权重组合下漏 1 μU。**P0** |
| `T-U-A-10`<br>`test_u_idiv_directions` | unit | `FX-GOLDEN-02`（含负数的除法黄金向量） | 逐条比对 `idiv_floor` / `idiv_ceil` | 全部条目逐位相等；特别地 `idiv_floor(−7, 2) == −4`、`idiv_ceil(−7, 2) == −3`、`idiv_floor(7, 2) == 3`、`idiv_ceil(7, 2) == 4` | 取整方向对负数不一致，长周期出现系统性偏置（10 号文件 §0.10）。**P0** |
| `T-U-A-11`<br>`test_u_mul_ppm_single_rounding` | unit | — | 取一组**能区分两种写法**的输入：`x = 10`、`p1 = p2 = 333_333` | `mul_ppm_2(10, 333_333, 333_333) == 1`（合并后只取整一次：`10 × 333_333 × 333_333 = 1_111_108_888_890`，除 `1e12` 下取整为 1）；朴素嵌套写法 `mul_ppm(mul_ppm(10, 333_333), 333_333) == 0`（两次取整各丢一次）；断言实现返回 `1`；静态检查 `mul_ppm(mul_ppm(` 出现次数 `== 0` | 双重取整引入系统性向下偏置（11 号文件 §5.2 第 4 条）。**P0** |
| `T-S-A-12`<br>`test_s_rounding_residual_explained` | scenario | `FX-BASE` | 无命令推进 8 季 | 每季 `Δgov.rounding_residual_uu == Σ 本季 log.rounding.residual`（8 次精确相等）；`log.rounding` 中每条的 `total − Σ parts == residual`（逐条精确） | 换算余数凭空产生或消失，或余数被静默塞进某个账户（INV-005）。**P0** |
| `T-X-D-03` 见 §5 | stress | — | 票息余数累加器 120 季不漂移 | 见 §5 | — |

### 2.3 库存恒等式与负库存

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-U-A-13`<br>`test_u_inventory_identity` | unit | `FX-MIN`，单 cell 单品种，期初 `1_000` μQ_s | 注入：生产 `500`、购入 `300`、售出 `400`、生产耗用 `200`、损耗 `50` | 期末库存 `== 1_150`（精确）；恒等式残差 `== 0` | 库存恒等式实现错误（INV-047）。**P0** |
| `T-S-A-14`<br>`test_s_inventory_identity_all` | scenario | `FX-BASE` | 无命令推进 40 季 | 每季末逐 cell 逐品种（16 cell × 4 品种 = 64 项）恒等式残差 `== 0`，共 2_560 次断言；任一库存字段 `≥ 0` 的违例次数 `== 0` | 某条生产／交易路径漏记了一项流量。**P0** |
| `T-U-A-15`<br>`test_u_no_silent_negative_inventory` | unit | `FX-MIN`，某投入库存 `= 100`，技术系数要求消耗 `150` | 跑 S05 的约束换算与实际消耗 | `q_actual` 被下调到使消耗 `== 100`（精确等于可用量，不是 150）；期末库存 `== 0`（不是 `−50`）；`log.constraint_diag` 增 1 行且 `binding_code == 5`（materials）；`slack[materials] == 0` | 出现无提示负库存，或用「盘点差异」吸收缺口（INV-048/053）。**P0** |
| `T-S-A-16`<br>`test_s_energy_not_stored` | scenario | `FX-BASE` | 无命令推进 40 季 | 每季末 `inventory[sector.energy] == 0` 且 `inventory[sector.services] == 0`（4 地区 × 2 部门 × 40 季 = 320 次精确等于 0）；每季 `Σ 电力配给 + energy_unused_uqs == min(能源可交付量, 电网容量)`（精确相等） | 电力被当成可跨季储存的库存，或未用电力被悄悄结转（INV-049/051）。**P0** |
| `T-U-A-17`<br>`test_u_no_same_quarter_chain` | unit | `FX-MIN`，期初投入库存 `= 0`，本季该投入产量 `= 1_000` | 跑一季 S05 | 使用该投入的下游 cell 的 `bound_materials == 0`，`q_actual == 0`（本季产出不可本季使用）；下季同一 cell 的可用投入 `== 本季购入量`（精确相等） | 同季链条被打通，一季内互相放大（INV-050，计划书 §13）。**P0** |
| `T-U-A-18`<br>`test_u_market_clearing` | unit | `FX-MIN`，供给 `800`，三个买方需求 `500 / 400 / 300` | 跑一次市场闭合（比例配给） | `Σ 成交 == 800`（精确）；`Σ 未满足 == 400`；`Σ 成交 + Σ 未满足 == Σ 需求 == 1_200`；卖方库存减少量 `== 800`；每个买方 `alloc_i ≤ requested_i`；`alloc` 由最大余数法给出且逐位等于独立复算值 `[333, 267, 200]`（底数 `[333, 266, 200]` 合计 799，余 1 归给小数部分最大的第 2 个买方） | 市场对账不闭合，需求静默消失（INV-059/060/064）。**P0** |
| `T-U-A-19`<br>`test_u_no_double_allocation` | unit | `FX-MIN`，某投入可用 `1_000` | 令两个下游 cell 同季各请求 `800` | 两者实际消耗之和 `== 1_000`（精确，不是 1_600）；`Fault.DOUBLE_ALLOCATION(33)` 未触发；`log.physical` 中该品种的流出总量 `== 1_000` | 投入被重复分配（计划书 §13 第 04 步）。**P0** |
| `T-S-A-20`<br>`test_s_no_phantom_income` | scenario | `FX-BASE` + 全部群组 `deposit_uu = 0`、`dissave_ppm = 0` | 推进 4 季 | 每季每组：`Σ household_consumption 付款 ≤ 本季已实际到账的（工资 + 转移 + 赡养净额）`，且 `group.cash_uu ≥ 0` 恒成立（36 组 × 4 季 = 144 次）；`unmet_consumption_uqs ≥ 0` 且其变化被 `log.explanations` 逐条解释 | 居民花了没收到的钱（INV-063，计划书 §13）。**P0** |

### 2.4 核算边界（防 GDP 重复核算）

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-U-A-21`<br>`test_u_gdp_no_double` | unit | `FX-MIN` 的两 cell 链：cell1 产出 `100_000` 且无中间投入；cell2 产出 `250_000`、中间投入 `100_000`（全部按基年价，μU 数值等于 μQ 数值） | 跑 S06 的增加值与 GDP 计算 | `value_added(cell1) == 100_000`；`value_added(cell2) == 150_000`；`gdp_production_uu == 250_000`（精确）；本季 `Σ 销售额 == 350_000` 且 `gdp_production != Σ 销售额` | 把产业链每笔销售额都加进 GDP（计划书 §06 [1]，INV-112）。**P0** |
| `T-U-A-22`<br>`test_u_gdp_class_coverage` | unit | `FX-BASE` | 推进 4 季，遍历本季全部账本行 | 三重分类白名单条目数 `== 28`（`kind` 是闭集合）；应分类却为 `none` 的行数 `== 0`；`kind ∈ {10..18, 27, 28}` 的行在三种口径下分类均为 `none` 的比例：违例数 `== 0` | 新增交易类型没登记分类，或借款／还本混进 GDP（INV-114/029/113）。**P0** |
| `T-U-A-23`<br>`test_u_gdp_identity` | unit | `FX-BASE` | 推进 4 季 | 每季 `gdp_expenditure_uu − gdp_production_uu − price_variance_total_uu == 0`（4 次，残差恰为 0）；`gdp_income_uu == gdp_production_uu`（4 次精确相等） | GDP 三口径不闭合（INV-115/116）。**P0** |
| `T-S-A-24`<br>`test_s_base_year_gdp` | scenario | `FX-BASE` | 无命令推进 4 季 | `Σ_{q=0..3} gdp_production_uu == 100_000_000`，**容差 0** | 基年剧本与核算实现对不上；一切相对指标失去基准（INV-118）。**P0** |
| `T-U-A-25`<br>`test_u_real_gdp_not_deflated` | unit（静态） | 全仓源码 | 扫描实际 GDP 计算函数的引用图 | 该函数对 `consumer_index_ppm` 的引用次数 `== 0`；对 `base_price` 的引用次数 `> 0` | 用名义 GDP 除价格指数冒充实际 GDP（计划书 §06，INV-117）。**P0** |
| `T-U-A-26`<br>`test_u_subsidy_not_output` | unit | `FX-MIN` | 政府向 cell 发补助 `500_000` | `cell.cash_uu` 增量 `== 500_000`；`cell.gross_output_uu` 增量 `== 0`；`gdp_production_uu` / `gdp_expenditure_uu` / `gdp_income_uu` 的增量均 `== 0` | 补助被重复算成最终产出（INV-113，计划书 §06）。**P0** |

---

## 3 类别 B：人口与就业

计划书 §17：**人口迁移来源去向一致；出生死亡单独登记；就业人数不超过同口径劳动力。**

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-S-B-01`<br>`test_s_population_conserved` | scenario | `FX-BASE` | 无命令推进 40 季 | 载入后 `Σ pop_persons == 24_000_000`（精确）；各地区 `9_000_000 / 7_000_000 / 5_000_000 / 3_000_000`（4 次精确）；每季末 `Σpop(q) − Σpop(q−1) − Σbirths + Σdeaths == 0`（40 次，残差恰为 0） | 人口凭空增减；出生死亡之外出现了净流入／流出口（INV-071/141）。**P0** |
| `T-U-B-02`<br>`test_u_group_flow_identity` | unit | `FX-BASE` 状态快照 | 跑一次 S07 的人口更新 | 对 36 组逐组：`pop_g − (pop_g_prev + 出生 − 死亡 + 成年入 − 成年出 + 技能入 − 技能出 + 迁入 − 迁出) == 0`（36 次，残差恰为 0） | 某条人口流动没有来源或没有去向（INV-072，计划书 §08）。**P0** |
| `T-U-B-03`<br>`test_u_migration_paired` | unit | `FX-BASE` 状态快照，构造中州→海岬迁出 `12_345` 人 | 跑一次 S07 迁移 | 对 4×4 全部有序对：`migrate_out[a][b] == migrate_in[b][a]`（16 次精确相等）；对角线 `migrate_out[a][a] == 0`（4 次）；`Σ 迁入 == Σ 迁出 == 12_345`（精确） | 迁移单边记账，人口在路上丢失或复制（INV-073）。**P0** |
| `T-U-B-04`<br>`test_u_birth_death_separate` | unit | `FX-BASE` 状态快照 | 构造本季 `Σ births == 1_000`、`Σ deaths == 1_000` | `births_persons` 字段值 `== 1_000`、`deaths_persons` 字段值 `== 1_000`（两个字段各自精确，**不允许只登记净额 0**）；`Σpop` 变化 `== 0`；出生写入的目标档全部为 `age.minor`（写入到非 minor 档的次数 `== 0`） | 出生死亡被合并成净额，分布与队列信息丢失（计划书 §08「必须有来源与去向」）。**P0** |
| `T-U-B-05`<br>`test_u_employment_le_labor_force` | unit | `FX-BASE` 状态快照，把某（地区,技能）的用工需求设为该口径劳动力的 2 倍 | 跑一次 S03 招工 | `employed == labor_force`（精确相等，不是 2 倍）；`unemployed == 0`；该 cell 的 `bound_labor` 成为最紧约束且 `slack[labor] == 0` | 就业人数超过同口径劳动力；招工的硬闸失效（INV-075/076）。**P0** |
| `T-U-B-06`<br>`test_u_employment_two_views` | unit | `FX-BASE` 状态快照 | 跑一次 S03 后交叉对账 | 对 4 地区 × 3 技能 = 12 个口径：`Σ_g group.employed_persons(region, skill) == Σ_cell cell.employment_persons(region, skill) + Σ_pubserv pubserv.employment_persons(region, skill)`（12 次精确相等） | 群组侧与生产侧的就业是两套账，任何一侧的修改不会被另一侧发现（INV-077/151）。**P0** |
| `T-U-B-07`<br>`test_u_unemployment_derivation` | unit | `FX-BASE` 载入后 `q = 0` | 读取派生失业率并独立复算 | `unemployment_ppm ∈ [79_500, 80_500]`（协议里唯一的非零容差）；`unemployment_ppm == idiv_floor(Σ unemployed × 1_000_000, Σ labor_force)`（与独立复算值精确相等）；剧本 schema 中「失业率输入字段」数量 `== 0`（静态） | 失业率被当参数填进剧本而不是由就业分配反算（计划书 §05，INV-143）。**P0** |
| `T-U-B-08`<br>`test_u_age_role` | unit | `FX-BASE` 载入后 | 遍历 24 个非 working 组（minor 与 elder） | 24 组的 `participation_ppm == 0` 且 `employed_persons == 0`（48 次精确等于 0） | 儿童档或老年档进入劳动力口径（计划书 §08，INV-074）。**P0** |
| `T-U-B-09`<br>`test_u_support_transfer_paired` | unit | `FX-BASE` 状态快照 | 跑一次 S04 的组间赡养转移 | `Σ support_in_uu == Σ support_out_uu`（精确相等）；跨地区转移笔数 `== 0`（首版默认区内发生，OQ-208 未定前如此） | 赡养转移凭空产生收入（INV-085）。**P0** |
| `T-S-B-10`<br>`test_s_wage_funded` | scenario | `FX-BASE` | 无命令推进 8 季 | 每季 `Σ 各组工资收入 == Σ 各 cell 与 pubserv 工资总额`（8 次精确相等）；S04 进入前每个 cell 的 `cash_uu ≥ wage_bill_uu`（违例数 `== 0`）；`Fault.WAGE_UNFUNDED(44)` 触发次数 `== 0` | 工资无资金来源，或 S03 的现金闸没闸住（INV-079，裁定 S-06）。**P0** |
| `T-U-B-11`<br>`test_u_wage_unfunded_is_fault` | unit | `FX-MIN`，**绕过 S03 直接**把 `employment_persons` 设成现金无法负担的水平 | 跑 S04 | 返回 `Fault.WAGE_UNFUNDED(44)`；结算中止；`cell.cash_uu` 保持进入 S04 前的值（精确不变） | 防线不存在：工资缺口被静默补救而不是变成故障（裁定 S-06「把它变成故障而不是补救，缺陷才会被发现」）。**P0** |
| `T-U-B-12`<br>`test_u_training_cohort_lag` | unit | `FX-BASE` 状态快照，本季新增培训席位 `10_000` | 推进 `param.training_lag_q` 季 | 拨款当季 `Σ skill_in_persons == 0`（精确）；第 `training_lag_q` 季 `skill_in == skill_out`（等量配对，精确相等）；升档只发生在相邻档（跨档次数 `== 0`） | 拨款当季全民升级（计划书 §08「教育按队列结业」，INV-081/082）。**P0** |
| `T-U-B-13`<br>`test_u_housing_cap` | unit | `FX-BASE` 状态快照 | 令某地区迁入请求超过住房容量 `50_000` 单位 | `Σ_g housing_units_occupied ≤ region.housing_stock_units ≤ region.housing_capacity_units`（两条精确不等式，违例数 `== 0`）；`migrate_rejected_persons > 0` 且等于被挡回人数的独立复算值；`region.housing_capacity_units` 增量 `== 0`（容量不自动增长） | 住房容量被自动撑大（INV-083/084）。**P0** |

---

## 4 类别 C：政策时滞

计划书 §17：**所有 12 政策都有作用路径与失败测试；未满足前置条件不得发放效果。**

### 4.1 目录级门槛

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-U-C-00`<br>`test_u_policy_catalog_complete` | unit | 发行内容包 `content/policies/` | 加载并校验 12 个 `PolicyDefinition` | 政策文件数 `== 12`；`policy_id` 恰为 `policy.P01..policy.P12`（12 次字符串精确相等，无缺无重）；九项必填字段缺失计数 `== 0`；`failure_paths` 为空的政策数 `== 0`；`failure_paths` 与 `acceptance_tests` 中在 `test_registry` 找不到的 `test_id` 数 `== 0`；`mechanism_ids` 中未注册的 `mech.*` 数 `== 0` | 「没有这些字段的政策不进入可玩菜单」（计划书 §09）没有被机器执行；或存在写不出失败测试的政策（V-PD-02/06/07/08）。**P0** |
| `T-U-C-01`<br>`test_u_policy_cost_exact` | unit | 同上 | 校验成本字段 | 每个政策 `per_quarter_uu × planned_quarters == one_off_uu`（12 次精确相等）；`Σ spend_lines_uu_per_q == per_quarter_uu`（12 次精确相等）；加载器的归一化补偿次数 `== 0` | 成本字段互相矛盾却被加载器悄悄抹平（V-PD-03）。**P0** |
| `T-U-C-02`<br>`test_u_effect_target_pending_only` | unit | 同上 | 校验 `effect.target` | 落在 `*_active_*` 或直接容量字段上的政策数 `== 0`；每个 `effect.target` 命中白名单（12 次命中）；`lag.commission_delay_q ≥ 1` 的政策数 `== 12` | 政策可以绕过「完工资产下一季才供能」的时滞（INV-091，V-PD-04/11）。**P0** |
| `T-U-C-03`<br>`test_u_policy_no_pseudo_depth` | unit | 同上 | 运行 `tools/check_policy_dup.gd` | `mechanism_ids` 与参数完全相同的政策对数 `== 0` | 同一个效果被复制成多个名字（计划书 §09「避免两种伪深度」）。**P1** |

### 4.2 十二项政策的作用路径与测试对

每项政策**至少三条测试**：成功链 `T-S-P<nn>-CHAIN`、前置闸门 `T-S-P<nn>-GATE`、失败链 `T-S-P<nn>-FAIL-<code>`。
「作用路径」列写的是必须被 `log.explanations`（`kind == accounted`）逐段串起来的链条；
链条断在哪一段，对应的失败链测试就必须能把它抓住。

> **数值状态**：P04 的全部数值已在 11 号文件 §5.12 定稿（测试夹具值）。
> 其余 11 项的具体参数由 OQ-220 登记为待定。**本文件约束的是路径形状与测试对，而不是参数取值**：
> 参数定稿时只能填进已登记的字段，不能改变下表的路径与测试 ID。

| 政策 | 作用路径（必须逐段可追溯） | 最早反馈 | 成功链 | 前置闸门 | 失败链（至少一条） |
|---|---|---|---|---|---|
| P01 个人所得税 | 命令 → `policy.params_ppm`（S02 受理）→ S06 §6.5 税基（**只来自已过账收入**）× `tax_capacity_ppm` → `gov.receipts` ↑ / `group.disposable` ↓ → S07 生活指数 → S08 支持度 | 1 季 | `T-S-P01-CHAIN` | `T-S-P01-GATE`（`E_AUTHORITY` / 预算审查窗口未到） | `T-S-P01-FAIL-CAPACITY`（征收能力不足 ⇒ 实收 < 应计，差额进 `tax_receivable`） |
| P02 企业利润税 | 命令 → 税率生效季 → S06 §6.6 **利润**（非现金）→ `gov.receipts`；亏损结转 | 1 季 | `T-S-P02-CHAIN` | `T-S-P02-GATE` | `T-S-P02-FAIL-NOPROFIT`（全行业亏损季实收 `== 0`，且不得从现金里扣）；`T-S-P02-FAIL-ARREARS`（企业现金不足 ⇒ 欠税入 `tax_receivable`） |
| P03 失业保障 | 命令 → S02 预留 → S04 按**合格失业人数**自动形成转移支出 → `group.disposable` → 生活/信任 | 1 季 | `T-S-P03-CHAIN` | `T-S-P03-GATE`（`E_BUDGET_INSUFFICIENT`） | `T-S-P03-FAIL-PRIORITY`（现金不足时第 3 档被推迟 ⇒ `arrears` 增加、`trust_ppm` 下降、给付不得静默缩水） |
| P04 电网可靠性升级 | `PolicyCommand → Eligibility → BudgetReservation → ProjectQueue → AssetCommissioning → ServiceCapacity → SectorResponse`（计划书 §10 原图） | 4—8 季 | `T-S-P04-CHAIN` | `T-S-P04-GATE` | 五条，见 §4.4 |
| P05 职业培训扩容 | 命令 → S02 预算 → S04 拨款 → S07 §7.6 队列（席位 `≤ teachers × ratio`）→ 滞后 `training_lag_q` 结业 → `skill_in/out` → S03 就业匹配 | 4—8 季 | `T-S-P05-CHAIN` | `T-S-P05-GATE` | `ADV-03`（无教师）；`T-S-P05-FAIL-NOJOB`（结业后无对应岗位 ⇒ 失业率不降，且不得直接增加就业） |
| P06 公共住房建设 | 命令 → 项目队列（施工能力 + 槽位）→ `housing_pending_units` → 下季 `housing_stock_units` → S07 迁移与住房负担 → 生活指数 | 6—12 季 | `T-S-P06-CHAIN` | `T-S-P06-GATE`（`E_NO_SLOT`） | `T-S-P06-FAIL-OPEX`（运行费欠拨 ⇒ 可用率下降但**资产不删除**） |
| P07 灌溉与农业物流 | 命令 → 项目 → `region.irrigation_index_pending_ppm` → 下季农业 cell 的产能/系数 → 产量 → 供给 | 4—8 季 | `T-S-P07-CHAIN` | `T-S-P07-GATE` | `T-S-P07-FAIL-SEASON`（季节系数低谷季投运 ⇒ 当季产出增量 `== 0`，效果推迟到生产季） |
| P08 港口与物流升级 | 命令 → 项目（进口设备受 `world.delivery_capacity` 约束）→ `region.port_capacity_pending` → `world.delivery_capacity` 与出口成交上限 | 6—10 季 | `T-S-P08-CHAIN` | `T-S-P08-GATE` | `T-S-P08-FAIL-NOORDER`（`export_demand_ppm == 0` ⇒ 港口能力提升后出口成交量增量 `== 0`，**不能自造订单**） |
| P09 设备投资补助 | 命令 → S04 按**已发生的实际投资**发放（`claim_key` 幂等）→ `cell.cash` ↑（不进 GDP）→ 扩产意愿 | 2—4 季 | `T-S-P09-CHAIN` | `T-S-P09-GATE` | `ADV-01`（重复领取）；`T-S-P09-FAIL-NOINVEST`（无实际投资季发放额 `== 0`） |
| P10 基础医疗拨款 | 命令 → `pubserv.capacity_pending` + `health_staff_persons` → 下季 `capacity_active` → S05 交付 `≤ capacity × availability` → 未获服务入 `queue_persons` | 2—4 季 | `T-S-P10-CHAIN` | `T-S-P10-GATE` | `T-S-P10-FAIL-QUEUE`（人员或设施不足 ⇒ `queue_persons` 上升而交付量不上升） |
| P11 税务能力建设 | 命令 → S04 先付成本 → 滞后 → `gov.tax_capacity_ppm` ↑ → S06 实收/应计比上升 | 4—8 季 | `T-S-P11-CHAIN` | `T-S-P11-GATE` | `T-S-P11-FAIL-COSTFIRST`（生效前 N 季净财政效应为负，且这段负效应必须出现在报告里） |
| P12 采购透明化 | 命令 → S04 流程成本 → 滞后 → `politics.admin_capacity_ppm` / 采购价差改善 | 2—6 季 | `T-S-P12-CHAIN` | `T-S-P12-GATE` | `T-S-P12-FAIL-LOWCAP`（`admin_capacity_ppm` 低于阈值时净效应为负，且可解释） |

### 4.3 三类通用用例的统一规格

这三条不是三条测试，而是**三个参数化模板 × 12 个政策 = 36 条用例**，在注册表里逐条展开。

**`T-S-P<nn>-GATE`（未满足前置条件不得发放效果）**

| 字段 | 内容 |
|---|---|
| 套件 | scenario |
| 前置状态 | `FX-BASE`，按政策的 `preconditions` 逐条构造**恰好一条不满足**（其余全部满足）：`legal_authority` 位清零 / `min_seats_ppm` 不足 / 预算不足 / 无施工槽位 / 冷却期内 |
| 操作 | 提交启用命令；随后无命令推进 12 季 |
| 断言 | ① 命令返回 `REJECT`，错误码精确等于该前置对应的码（`E_AUTHORITY` / `E_SEATS_SHORT` / `E_BLOC_VETO` / `E_BUDGET_INSUFFICIENT` / `E_NO_SLOT` / `E_POLICY_COOLDOWN` / `E_PRECONDITION` 之一）；② 提交前后 `state_hash` 逐位相同；③ `log.rejections` 行数增量 `== 1`；④ 该政策 `effect.target` 字段在随后 12 季的累计变化 `== 0`；⑤ `policy.enabled == 0` 且 `blocked_reason != none`，且该 `blocked_reason` 在本地化表中有对应条目 |
| 失败说明 | 未满足前置条件却发放了效果，或拒绝时改了状态（INV-095/098/100/137）。**P0** |

**`T-S-P<nn>-CHAIN`（作用路径与时滞）**

| 字段 | 内容 |
|---|---|
| 套件 | scenario |
| 前置状态 | `FX-BASE`，全部前置条件满足 |
| 操作 | 在 `q = q0` 启用；无其他命令推进到 `q0 + max_feedback_q + 2` |
| 断言 | ① `q ∈ [q0, q0 + lag.enact_to_effect_q)` 期间 `effect.target` 累计变化 `== 0`；② `q == q0 + lag.enact_to_effect_q` 时首次出现非零变化，且该变化量等于按政策参数独立复算的值（精确相等）；③ 结果指标（该政策声明的可观察结果）首次非零出现的季 `≥ q0 + lag.min_feedback_q` 且 `≤ q0 + lag.max_feedback_q`；④ 每一段路径在 `log.explanations` 中存在 `kind == accounted` 的条目，链条条数 `== 路径段数`（无断段） |
| 失败说明 | 时滞被跳过、效果被直接加到结果指标上、或路径不可追溯（计划书 §17「政策影响通过机制传导，而非直接改 GDP」）。**P0** |

**`T-S-P<nn>-OFF`（退出规则）**

| 字段 | 内容 |
|---|---|
| 套件 | scenario |
| 前置状态 | `T-S-P<nn>-CHAIN` 结束时的状态 |
| 操作 | 关停该政策；推进 4 季 |
| 断言 | ① 关停当季起，效应函数返回值 `== 0`（4 次精确等于 0）；② 已发生的支出 `paid_uu` 不回退（精确不变）；③ 已交付资产 `capacity_active` 不减少（`exit_rule.delivered_assets == "retain"` 的政策）；④ 一次性行政成本 `toggle_cost_uu` 恰好扣 1 次；⑤ `toggle_count` 增量 `== 1`；⑥ 冷却期内的再开启命令返回 `REJECT(E_POLICY_COOLDOWN)` |
| 失败说明 | 退出规则没实现，或关停能退钱（INV-095/098）。**P0** |

### 4.4 P04 的完整验收（计划书 §10 原文的机器版）

数值全部来自 11 号文件 §5.12 的 P04 夹具值，**测试里写字面量，不从内容包读**（否则内容包写错时测试跟着错）。

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-S-P04-CHAIN` | scenario | `FX-P04` | `q=0` 立项，推进到 `q=10` | ① `q=0..7` 每季 `project_payment` 合计 `== 500_000` μU（8 次精确），8 季累计 `== 4_000_000`；② 每季分项：进口设备 `== 200_000`、国产材料 `== 100_000`、施工服务 `== 200_000`，三笔各有收款方且双边入账（24 次精确）；③ `q=7` 末 `construction_progress_ppm == 1_000_000` 且 `delivery_progress_ppm == 1_000_000`；④ `q=7` 末 `region.haijia.grid_capacity_pending_uqs_per_q` 增量 `== 10_000_000`，`grid_capacity_active` 增量 `== 0`；⑤ `q=8` 的 S01 之后 `grid_capacity_active` 增量 `== 10_000_000` 且 `pending == 0`；⑥ `q=8` 起每季 `service_opex == 20_000` | 计划书 §10 的主链路断了。**P0** |
| `T-S-P04-PAY-NO-PROGRESS` | scenario | `FX-NOCON` | `q=0` 立项，推进 8 季 | `Σ paid_uu == 4_000_000`（付款照常发生）；`Δconstruction_progress_ppm == 0`（8 季逐季精确等于 0）；`grid_capacity_active` 增量 `== 0`；`grid_capacity_pending` 增量 `== 0` | **付款直接制造了完工进度**——计划书 §10 明令禁止的头号缺陷（INV-087）。**P0** |
| `T-S-P04-NO-EARLY-COMMISSION` | scenario | `FX-NODEL` | `q=0` 立项，推进 9 季 | `q=7` 末 `delivery_progress_ppm < 1_000_000`；`grid_capacity_pending` 增量 `== 0`；`q=8` 末 `grid_capacity_active` 增量 `== 0`；`project.status ∈ {in_progress, suspended}`（状态码精确命中） | 第 8 季未交付齐全却投运（计划书 §10，INV-090）。**P0** |
| `T-S-P04-CONSTRAINT-ORDER` | scenario | `FX-P04` | 推进到投运后 2 季 | ① 投运前至少存在一季使 `cell.haijia.manu.binding_code == 4`（energy）；② 投运后的下一季 `binding_code ∈ {1, 2, 3, 5}`（plan/capacity/labor/materials）且 `slack[energy] > 0`；③ 并列时按 `plan<capacity<labor<energy<materials` 取最小序号（INV-045 的序） | 投运后电力约束没被解除，或解除后没有交给其他约束决定产量（计划书 §10）。**P1** |
| `T-S-P04-NO-DEMAND-NO-BONUS` | scenario | `FX-NODEMAND` | 推进到投运后 2 季 | ① 投运当季与下季，能源 cell 的 `binding_code == 1`（plan）；② `log.explanations` 中 `cause == policy_bonus` 的条数 `== 0`；③ `support_national_ppm` 的来源分解中 `cause == commission` 的条数 `== 0`；④ 本季 `Δgdp_production_uu` 能被 `kind == accounted` 的条目完全解释（未解释残差 `== 0`） | 没有销路却直接发放 GDP 与支持率奖励（计划书 §10 原文）。**P0** |
| `T-S-P04-FAIL-FINANCING` | scenario | `FX-P04` → `q=2` 起切到 `FX-BROKE` 的现金与额度 | 立项后第 2 季把 `gov.cash` 与 `credit_limit` 降到 0，推进 6 季 | `project.status == suspended` 且 `suspend_reason == financing`（码精确）；`paid_uu` 停在切断前的值（精确不变）；`construction_progress_ppm` 增量 `== 0`；`committed_memo` 减少量 `== 0`（承诺不因缺钱而消失） | 缺钱时项目被静默取消或进度照走（12 号文件 §12）。**P0** |
| `T-S-P04-FAIL-DELIVERY` | scenario | `FX-NODEL` | 推进 8 季 | `delivery_progress_ppm` 逐季增量 `== 0`（8 次）；`construction_progress_ppm` 可继续增长（证明两条进度独立）；第 8 季不得投运（同 `T-S-P04-NO-EARLY-COMMISSION` 断言 ③） | 交付进度由付款或施工推动，而不是由实际到货推动（INV-089）。**P0** |
| `T-S-P04-FAIL-CONGESTION` | scenario | `FX-CONG` | 同季立 3 个项目，推进 4 季 | `Σ_{project ∈ haijia} queue_slot_held == 1`（精确等于 `construction_slots_total`）；后到的 2 个项目 `status == suspended` 且 `suspend_reason == congestion`（2 次精确）；这 2 个项目的 `paid_uu == 0` | 队列容量被静默突破，或拥堵表现为「悄悄排队」而不是可见状态（INV-094）。**P0** |
| `T-S-P04-FAIL-FUEL` | scenario | `FX-NOFUEL` | 推进到投运后 2 季 | `region.haijia.electricity_availability_ppm` 相对基线严格下降（与 `FX-BASE` 同季值比较，差值 `< 0`）；`grid_capacity_active` 增量 `== 0`（燃料不足**不减资产**）；能源 cell 的 `binding_code == 5`（materials） | 燃料不足被表达成「资产消失」而不是「可用率下降」（INV-102）。**P1** |
| `T-S-P04-FAIL-NODEMAND` | scenario | `FX-NODEMAND` | 推进到投运后 2 季 | 新增电力容量的实际使用量 `== 0`（精确）；`energy_unused_uqs > 0`；`gdp_production_uu` 的变化中来自本项目的可追溯部分 `== 0` | 无需求时新增供给仍然变成产出（计划书 §10 的第五条失败路径）。**P0** |

---

## 5 类别 D：债务与承诺

计划书 §17：**期限、票息、还本和债权人一致；项目取消不会释放已实际花掉的钱。**

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-U-D-01`<br>`test_u_coupon_per_batch` | unit | `FX-MIN`，两批债券：批 A 面值 `10_000_000`、`coupon_ppm_per_q = 10_000`；批 B 面值 `10_000_000`、`coupon_ppm_per_q = 20_000` | 发行第三批，`coupon_ppm_per_q = 30_000`；跑一季 S02 | 批 A 本季利息 `== 100_000`（`idiv_floor(10_000_000 × 10_000, 1_000_000)`）；批 B `== 200_000`；**批 A/B 的 `coupon_ppm_per_q` 在发行后被写入的次数 `== 0`**（静态 + 运行期计数） | 固定利率旧债被新发利率重定价（计划书 §07，INV-036）。**P0** |
| `T-U-D-02`<br>`test_u_principal_schedule` | unit | `FX-MIN`，面值 `10_000_000`，`level_principal` 分 7 季 | 生成分期表并逐季推进 | 分期表由最大余数法预生成，`Σ scheduled == 10_000_000`（精确）；逐季 `Σ_{q'≥q} scheduled(q') == principal_outstanding(q)`（7 次精确相等）；末季后 `outstanding == 0` | 期限与还本对不上；债务在表与账之间漂移（INV-037）。**P0** |
| `T-X-D-03`<br>`test_x_coupon_drift` | stress | `FX-STRESS120`，512 个债券批次（`param.bond_batch_cap`） | 推进 120 季 | 每批次 `|Σ 实付票息 − Σ 应计票息的整数下界| ≤ 1` μU（512 次）；余数累加器 `remainder_ppmuu ∈ [0, 1_000_000)` 全程成立（违例数 `== 0`） | 票息取整长期漂移，系统性少付或多付（INV-041，裁定 R-08）。**P1** |
| `T-S-D-04`<br>`test_s_debt_holder_consistency` | scenario | `FX-BASE` | 无命令推进 40 季 | 载入后 `Σ bond.principal_outstanding_uu == 50_000_000`（精确）；每季末三条残差均 `== 0`：`derived.gov.debt_uu − Σ active outstanding`、`Σ(invpool.bondhold + row.bondhold) − derived.gov.debt_uu`、`derived.world.external_debt_uu − Σ_{holder==row} outstanding` | 债权人口径与债务总额是两套账（INV-025/035/107，计划书 §07「融资必须有对手方」）。**P0** |
| `T-S-D-05`<br>`test_s_fiscal_identity` | scenario | `FX-BASE` | 无命令推进 40 季 | 每季末 `cash_end − (cash_start + 收入 + 新增借款 − 基本支出 − 利息 − 还本) == 0`（40 次，残差恰为 0）；`debt_end − (debt_start + 新增借款 − 还本 − 确认减记) == 0`（40 次） | 计划书 §07 的两条恒等式破裂。**P0** |
| `T-U-D-06`<br>`test_u_borrowing_is_not_income` | unit | `FX-MIN` | 发行 `5_000_000` 债券 | `gov.receipts_uu` 增量 `== 0`；`gdp_production/expenditure/income` 三口径增量均 `== 0`；`gov.cash_uu` 增量 `== 5_000_000`；`gov.debt_uu` 增量 `== 5_000_000` | 借款被当税收，或还本被当 GDP（计划书 §07，INV-029）。**P0** |
| `T-S-D-07`<br>`test_s_cancel_keeps_spent` | scenario | `FX-P04` | `q=0` 立项；推进到 `q=3` 末（已付 `2_000_000`）；`q=4` 提交取消命令 | ① `paid_uu == 2_000_000`（取消后精确不变，**不回退**）；② 取消当季 `gov.cash_uu` 的增量 `== −600_000`（赔偿 `= mul_ppm(剩余合同 2_000_000, compensation_ppm 300_000)`），即现金**减少**，绝不增加；③ `committed_memo` 减少量 `== 2_000_000`（只减未付部分）；④ `residual_value_uu > 0` 且作为双边分录入账（对手方账户 ID 精确命中）；⑤ `grid_capacity_pending` 增量 `== 0` | **项目取消释放了已经花掉的钱**——计划书 §17 点名的缺陷（INV-093）。**P0** |
| `T-U-D-08`<br>`test_u_committed_memo_sources` | unit | `FX-MIN` | 依次：签 `4_000_000` 合同 → 履约付 `500_000` → 取消 | 三次读数精确等于 `4_000_000` / `3_500_000` / `0`；`committed_memo` 的写入点数量（静态扫描）`== 3` | 承诺台账被第四种路径修改，签约不再占用未来预算（计划书 §07「预算不是资产」，INV-032）。**P0** |
| `T-S-D-09`<br>`test_s_reservation_zeroed` | scenario | `FX-BASE` | 无命令推进 12 季 | 每季末 `reserved_memo_uu == 0`（12 次精确等于 0）；季内任一时点 `reserved_memo ≤ cash`（违例数 `== 0`） | 预留既不执行也不释放，变成隐形占款（INV-033）。**P0** |
| `T-U-D-10`<br>`test_u_payment_priority` | unit | `FX-BROKE` 变体：`gov.cash_uu` 恰好等于前 3 档应付额之和 | 跑 S02 + S04 的支付 | ① `payment_priority` 是 8 类的全排列（元素个数 `== 8`、去重后 `== 8`）；② 第 1/2/3 档实付额 `==` 各自应付额（3 次精确相等）；③ 第 4..8 档实付额 `== 0`（5 次精确等于 0）；④ `arrears` 增量 `== 第 4..8 档应付额之和`（精确相等）；⑤ `gov.cash_uu` 期末 `== 0`（不为负） | 短缺没有先显露，出现了无提示的负国库余额或随意的支付次序（计划书 §07，INV-039）。**P0** |
| `T-S-D-11`<br>`test_s_financing_counterparty` | scenario | `FX-BASE`，`invpool.cash_uu = 1_000_000`，`world.credit_limit_uu = 0` | 提交发行 `2_000_000` 的命令 | 返回 `REJECT(E_CREDIT_LIMIT)`；`gov.debt_uu` 增量 `== 0`；`state_hash` 逐位不变；`log.rejections` 增 1 行 | 融资没有对手方能力约束，国库变成无限资金源（计划书 §07，INV-034）。**P0** |
| `T-S-D-12`<br>`test_s_restructuring_failure` | scenario | `FX-BROKE` | 连续 `param.default_grace_q + 1` 季无法支付第 1 档 | 宽限期内 `termination_reason == none`（逐季精确）；超期当季 `termination_reason == fiscal_restructuring_failed`（字符串精确）；`run_terminated == true`；自动展期发生次数 `== 0` | 违约被静默展期掉，财政重组失败这条终局路径不存在（INV-040）。**P1** |
| `T-U-D-13`<br>`test_u_season_split` | unit | `FX-BASE` 的季节系数 | 把年收入计划 `20_000_000` 按四季拆分 | `Σ season_factor_ppm == 1_000_000`（精确）；四季拆分额之和 `== 20_000_000`（精确）；同理年支出计划 `22_000_000`、赤字 `2_000_000` 三条载入期断言全部命中 | 初始四季合计与年计划不一致（计划书 §05，INV-042/146）。**P0** |
| `T-U-D-14`<br>`test_u_interest_matches_bonds` | unit | `FX-BASE` 载入后 | 校验年支出计划中的利息项 | 利息项 `== 基年四季逐批次票息之和`（精确相等） | 债务与利息各写各的（INV-147）。**P0** |
| `T-S-D-15`<br>`test_s_bond_batch_cap` | scenario | `FX-RICHPOOL` | 连续发行直到批次数达到 `param.bond_batch_cap` 后再发一次 | 第 `cap+1` 次返回 `REJECT`；批次自动合并次数 `== 0`；`Σ outstanding` 与 `debt_uu` 仍精确相等 | 批次被自动合并，破坏「旧债不重定价」（12 号文件 §2.4）。**P1** |

---

## 6 类别 E：稳定与重放

计划书 §17：**同构建 100 个种子各运行 120 季压力测试，无崩溃、NaN 或未处理越界；终局可正常记录。**

### 6.1 「NaN」在本项目的改写（必读）

本项目 SimCore 禁用 float（INV-001），**因此不存在 NaN**。计划书这一条的实质要求是
「不得出现无声的数值污染」。在整数世界里，它精确对应三类可检查的事实：

| 计划书原文 | 本项目的可执行改写 | 检查手段 |
|---|---|---|
| 无 NaN | **无 float 进入状态** | 静态：`sim/` 与 `systems/` 中 float 字面量数 `== 0`、`float` 类型标注数 `== 0`、`sqrt/pow/log/exp/randf/lerp` 调用数 `== 0`（`tools/layer_check.py` 扩展规则）。运行期：状态树序列化遇 float → `E_FLOAT_IN_STATE`，压测中触发次数 `== 0` |
| 无 NaN（续） | **无整数溢出** | 一切乘法经 `IntMath.mul(a, b)`，内部 `if b != 0 and absi(a) > INT64_MAX / absi(b): FAULT(INT_OVERFLOW)`。**用显式 `if`，不用 `assert`**（release 会剥离 assert）。压测断言 `Fault.INT_OVERFLOW(90)` 触发次数 `== 0`，且每次写入满足 `|金额| ≤ 4_000_000_000_000`、`|数量| ≤ 1_000_000_000_000`、`price ∈ [400_000, 2_500_000]`，越界写入尝试计数 `== 0` |
| 无 NaN（续） | **无除零** | 一切除法经 `idiv_floor` / `idiv_ceil` / `mul_ppm`，入口 `if divisor == 0: FAULT(DIV_ZERO)`；系数为 0 的约束走 `continue`/`SENTINEL`，**禁止用 `max(c, 1)` 代替**（静态：`max(` 与除法在同一行出现的次数 `== 0`）。压测断言 `Fault.DIV_ZERO(91)` 触发次数 `== 0` |
| 无未处理越界 | **无未检查的数组下标** | ① 静态：`sim/` 中裸下标 `arr[i]` 的索引变量必须来自 `for i in range(<同数组 size>)` 或 `JWIds` 的稠密映射函数返回值，其余形式计数 `== 0`；② 压测构建（`--stress` 开关）把全部下标访问换成带检查的 `at(i)`，`Fault.INDEX_OUT_OF_RANGE(92)` 触发次数 `== 0`；③ 发布构建保留 `at()` 于非热路径 |
| 无崩溃 | **进程级与脚本级双计数** | 运行器捕获子进程 stderr，`"SCRIPT ERROR"` / `"Condition \"` / `"Cannot call method"` 的出现次数 `== 0`；子进程退出码 `== 0`；被 OS 杀死（非零信号）次数 `== 0` |

> 这五行是本类别的判据定义。压测用例 `T-X-E-08` 直接断言这五个计数器为 0。

### 6.2 确定性与重放

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-R-E-01`<br>`test_r_replay_40` | replay | `FX-BASE`，`root_seed = 1_000_000`，路线脚本 `route_a.jsonl` | 同一构建内跑两遍 40 季 | 两遍逐季 `state_hash` 字符串精确相等（40 次）；逐季 8 个 `step_hash` 精确相等（320 次）；`log.rng` 条数与逐条取值完全相同 | 重放不确定，一切回归测试失去意义（INV-014，计划书 §12）。**P0** |
| `T-R-E-02`<br>`test_r_save_roundtrip` | replay | `FX-BASE` 推进到 `q=17` | 分支 A：直接 `advance`；分支 B：`save → load → advance` | 两分支 `state_hash` 逐位相同；`log.rng` 逐条相同；`draw_count` 六个计数器逐个精确相等 | 存档没装全跨季状态或随机流状态（INV-131/133）。**P0** |
| `T-R-E-03`<br>`test_r_migrate` | replay | 每个历史 `schema_version` 的黄金存档各一份 | 逐版迁移到当前版本后推进 1 季 | 迁移链逐版递增无跳版（版本序列精确相等于期望数组）；迁移后 `state_hash` 等于该黄金存档登记的期望哈希；迁移中新增字段的默认值数量 `== 0`（不得发明数据） | 存档迁移编造数据或跳版（INV-136）。**P0** |
| `T-R-E-04`<br>`test_r_trace` | replay | `FX-BASE` | 推进 8 季，逐季对比状态树全部数值字段的变化 | 每个发生变化的字段，在本季日志（`log.ledger` / `log.physical` / `log.explanations` / `log.clamp` / `log.rounding` / `log.arrears`）中存在至少一条同 `q`、同 `entity` 的条目；无法解释的变化字段数 `== 0` | 存在没有来源的状态变化（INV-139，计划书 §13「每条变化附带实体 ID、来源操作、金额/数量、时间和约束」）。**P1** |
| `T-U-E-05`<br>`test_u_rng_isolation` | unit | 固定 `root_seed` | 基准：各流各抽 10 次并记录。对照：在 `rng.event` 上**额外**抽 1_000 次后，再取各流的下一个值 | `rng.shock` / `rng.pop` / `rng.market` / `rng.fuzz` 的下一个值与基准逐位相同（每条流精确相等）；`rng.event` 自身的计数器增量 `== 1_010` | 「多写一句新闻就改变经济抽样」（计划书 §12，INV-009）。**P0** |
| `T-U-E-06`<br>`test_u_reject_pure` | unit | `FX-BASE` | 提交 3 条非法命令 | 三次均返回 `REJECT` 且错误码精确命中；`state_hash` 三次均与提交前逐位相同；`log.rejections` 行数增量 `== 3`；`(q, seq)` 序号消耗量 `== 3`（裁定 D-09） | 被拒命令有副作用；或序号复用导致重放分歧（INV-137）。**P0** |
| `T-U-E-07`<br>`test_u_hash_coverage` | unit | 当前状态树定义 | 反射遍历状态树 | 除白名单外每个数值字段都进 `state_hash`：未进哈希的非白名单字段数 `== 0`；白名单条目数等于 10 号文件 §11 登记的条目数（精确相等） | 有跨季状态不进哈希，重放检查有盲区。**P0** |
| `T-U-E-08`<br>`test_u_command_no_direct_state` | unit | 命令 schema | 校验全部命令类型的字段名 | 含 `set_cash` / `set_gdp` / `set_support` 之类直接状态值字段的命令类型数 `== 0`（INV-138） | 玩家或脚本能直接设置结果（计划书 §02「不能直接设置经济与民众的结果」）。**P0** |
| `T-U-E-09`<br>`test_u_price_fixpoint` | unit | `FX-MIN`，供需缺口恒为 0，库存偏离恒为 0 | 推进 120 季 | 每季价格 `== 1_000_000`（120 次精确等于 1_000_000）；`log.clamp` 行数增量 `== 0` | 取整偏置在无扰动下自行漂移（INV-068）。**P0** |
| `T-U-E-10`<br>`test_u_golden_rng` | unit | `FX-GOLDEN-03`（离线生成的 splitmix64 黄金向量 1_024 条） | 逐条比对 | 1_024 条逐位相等；拒绝采样的被拒次数也与黄金向量一致（保证 `log.rng` 条数可复算，裁定 S-09） | 随机实现被改动，历史存档与重放全部失效。**P0** |

### 6.3 主压力测试

| 字段 | 内容 |
|---|---|
| ID | `T-X-E-11` / `test_x_100seeds_120q` |
| 套件 | stress（夜间跑，不进每次提交的门） |
| 前置状态 | `FX-STRESS120`；`root_seed = 1_000_000 + i`，`i ∈ [0, 100)`；构建为**固定 `build_id`** 的同一份二进制 |
| 操作 | 三档命令流各跑一遍全部 100 个种子 × 120 季：<br>① **空命令**（检查基线是否自行崩溃，计划书 §14 校准流程第一步）；<br>② **脚本化路线**（`route_a/b/c` 轮换）；<br>③ **合法随机命令 fuzz**（用 `rng.fuzz` 流生成，与 sim 的五条流完全独立） |
| 断言 | ① 成功结算的季数 `== 12_000`（每档精确等于 100 × 120）；<br>② `Fault` 计数：`INT_OVERFLOW == 0`、`DIV_ZERO == 0`、`INDEX_OUT_OF_RANGE == 0`、`FLOAT_IN_STATE == 0`、`NEGATIVE_CASH == 0`、`NEGATIVE_INVENTORY == 0`、`POPULATION_NOT_CONSERVED == 0`、`LEDGER_IMBALANCE == 0`（8 个计数器逐个精确等于 0）；<br>③ 子进程 stderr 中 `"SCRIPT ERROR"` 出现次数 `== 0`，退出码 `== 0`；<br>④ 每季全部 P0 不变量残差 `== 0`（抽样策略在压测中**强制全开**，`param.write_guard_sample_q = 1`）；<br>⑤ 越界写入尝试计数 `== 0`（金额、数量、价格三类）；<br>⑥ 终局：每个种子结束后 `run_terminated == true`，发展档案文件存在且字段齐全（字段缺失数 `== 0`）；其后任一 `advance_quarter` 返回 `REJECT(E_RUN_TERMINATED)` 且 `state_hash` 逐位不变（100 次）；<br>⑦ 日志扩容告警次数记录在案（不作为失败判据，作为性能回归信号） |
| 失败说明 | 计划书 §17 的稳定性门未过。任一计数器非 0 即 **P0**，除第 ⑦ 项外不接受「概率极低」的辩解——压测就是用来把低概率变成确定性的。 |

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-X-E-12`<br>`test_x_price_stable` | stress | `FX-STRESS120`，含三类冲击 | 100 种子 × 120 季 | `clamp_budget_used_count ≤ param.price_clamp_budget_count`（100 次）；价格全程 `∈ [400_000, 2_500_000]`（越界次数 `== 0`）；无任一部门价格连续 8 季顶在同一边界（计数 `== 0`） | 宏观指标无原因地振荡或爆炸（计划书 §18），且被 clamp 掩盖（INV-069）。**P1** |
| `T-X-E-13`<br>`test_x_fuzz_commands` | stress | `FX-BASE` | 生成 10_000 条**合法**命令与 10_000 条**非法**命令交替提交 | 合法流：`Fault` 触发次数 `== 0`；非法流：`REJECT` 次数 `== 10_000` 且每次 `state_hash` 不变（10_000 次） | 命令校验有漏网，或拒绝路径有副作用。**P0** |
| `T-X-E-14`<br>`test_x_long_ledger` | stress | `FX-STRESS120` | 120 季，记录账本行数与耗时 | 账本行数 `≤ param.log_capacity_rows × 1.5^k` 的扩容次数被记录；每季结算耗时不随季数单调上升超过 20%（回归判据，见 §7.4）；无内存分配失败 | OQ-232 登记的风险成真：账本行数拖垮长局。**P1** |

---

## 7 类别 F：性能目标

计划书 §17：**登记参考电脑后，季度结算中位数低于 0.5 秒、95 分位低于 1 秒；未达标先剖析再优化。**

### 7.1 参考机与构建

- 参考机 `REF-01` 已在 `docs/ENGINE.md` 登记（登记日期 2026-09-12）。
- **在别的机器上测出的数字不能直接与门槛比较**：必须先在该机重跑并登记为新的 `REF-xx`，
  报告里写明机器 ID 与 `build_id`。
- 全部计时在 `--headless` 下进行，排除渲染开销——门槛约束的是 SimCore，不是绘制。

### 7.2 计时点的精确定义

```gdscript
# tools/bench_quarter.gd
# 计时区间 = TurnRunner.advance_quarter() 的整个调用，含八步与全部不变量检查，
# 不含：内容加载、剧本解析、存档写盘、日志落盘、屏幕绘制。
var t0: int = Time.get_ticks_usec()
var fault: int = runner.advance_quarter(state, cmds)   # 被测区间
var dt_us: int = Time.get_ticks_usec() - t0
```

**明确排除项**（各自单独计时，单独登记，不计入门槛）：

| 排除项 | 为什么排除 | 单独门槛 |
|---|---|---|
| 内容包加载与校验 | 一局只发生一次 | `T-X-F-05`：< 3 s |
| 存档写盘 | 与结算异步，且受磁盘影响 | `T-X-F-04`：自动保存 < 100 ms |
| `state_hash` 全量重算（调试模式的派生量比对） | 发布构建按季抽样，不是每季必付的成本 | 在分解报告中单列 |
| 首次 `load()` 脚本与资源 | 冷启动一次性成本 | 由剔除规则处理 |

### 7.3 测量协议

| 项 | 规定 |
|---|---|
| 样本 | 100 种子 × 120 季 = **12_000 个季度样本**（与 `T-X-E-11` 同一次运行，共用数据） |
| 热身 | 整份基准开始前，先完整跑 1 个种子 × 3 季并**整份丢弃**（不进任何统计） |
| 剔除首次加载 | 每个种子的 `q = 0` 与 `q = 1` **两季剔除**（覆盖日志数组首次扩容、scratch 数组首次触碰、类缓存）。有效样本 `== 100 × 118 == 11_800`（精确，报告必须打印该数字） |
| 重复 | 整份基准跑 **3 轮**，取「每轮中位数」的中位数作为登记值；三轮中位数的极差 > 15% 则判定测量环境不稳定，作废重测 |
| 环境要求 | 插电、电源模式「高性能」、无其他前台负载；这三项写入报告头 |
| 统计量 | 中位数、P95、P99、最大值、每步（S01..S08）耗时分解，全部为**整数微秒** |
| 输出 | `tools/out/bench_<build_id>_<REF-id>_<日期>.csv` + 一行登记写入 `docs/ENGINE.md` 的性能登记表 |

### 7.4 判据

| ID | 套件 | 断言 | 失败说明 |
|---|---|---|---|
| `T-X-F-01`<br>`test_x_quarter_median` | stress | 有效样本数 `== 11_800`；中位数 `< 500_000` μs | 计划书 §17 的中位数门未过。**先剖析再优化**：必须先提交每步耗时分解，指出耗时占比最高的两步，再动代码。**P1**（G5 前不清零则阻断发布） |
| `T-X-F-02`<br>`test_x_quarter_p95` | stress | P95 `< 1_000_000` μs | 存在长尾季（多半是日志扩容、批次数增长或不变量全量重算）。**P1** |
| `T-X-F-03`<br>`test_x_step_breakdown` | stress | 八步耗时之和与总耗时的差 `≤ 总耗时的 5%`（计时开销自检）；每步耗时单独登记 | 分解不可信，无法定位瓶颈 |
| `T-X-F-04`<br>`test_x_autosave_cost` | stress | 自动保存耗时中位数 `< 100_000` μs；自动保存不改变 `state_hash`（精确不变） | OQ-234 登记的风险成真 |
| `T-X-F-05`<br>`test_x_load_cost` | stress | 内容包加载 + 校验 + 开账 < `3_000_000` μs | 启动太慢，影响试玩流程。**P2** |
| `T-X-F-06`<br>`test_x_perf_regression` | stress | 本次中位数 `≤ 上次登记值 × 120 / 100`（整数比较，避免 float）；P95 同理 | 性能回归。**P1**，且必须在同一次提交里给出原因 |

> **G0 阶段就要跑一次**（12 号文件 §13）：在 SimCore 还只有骨架时先跑 `bench_quarter.gd` 的空跑基准并登记，
> 建立「加了什么之后变慢」的基线，而不是等到 G5 才第一次测。

---

## 8 类别 G：可理解性与策略差异

计划书 §17：**5 名首次体验者中至少 4 名可完成前 4 季，并解释一项政策未按预期生效的原因；
至少 3 条可描述路线；同等条件下结果差异可追溯，不要求每条路线人为等强。**

### 8.1 试玩观察（人工，进发布门但不进 CI）

| 字段 | 内容 |
|---|---|
| ID | `T-P-G-01` |
| 前置状态 | 发布候选包；`FX-BASE` 出厂剧本；观察者一人；被试 5 名，**均为首次接触本作** |
| 操作 | 被试独立游玩前 4 季。观察者**不得口头教学**，只能回答「请继续」「按你的判断来」。全程录屏 + 计时。第 4 季结束后做结构化访谈 |
| 断言（判定规则） | ① **完成**定义：在 60 分钟内推进到第 4 季结束且未卡死。达成人数 `≥ 4`（5 人中）。<br>② **解释**定义：被试指出一项政策未按预期生效的原因，其表述必须与该季 `log.explanations` / `blocked_reason` / `binding_constraint` 中的**同一个机制码**对应（例如说「电还不够」对应 `binding_code == 4`）。判定由观察者对照当季日志逐条核对，**是/否两分，不打分**。达成人数 `≥ 4`。 |
| 记录项（计划书 §17 全部七项，缺一不可） | 第一次有效决策耗时（秒，整数）／无法理解的指标（指标 ID 列表）／被忽视的警告（警告 ID 与出现次数）／重复点击（控件 ID 与次数）／失败原因（若中途卡死）／第二局的策略变化（自由文本 + 命令流 diff）／每人的完整命令流存档 |
| 失败说明 | 计划书 §17 的可理解性门未过。达成 3 人及以下 ⇒ 归为 **P1**（不可解释结果），整包不发试玩版之外的任何版本；同时按「无法理解的指标」清单排 P1/P2 修复顺序 |
| 口径声明 | **5 名测试者只是方向性检查，不具统计代表性**，报告里必须原样写这句话（计划书 §17） |

### 8.2 策略差异（自动化）

| ID | 套件 | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|---|
| `T-S-G-01`<br>`test_s_three_routes_run` | scenario | `FX-BASE`，同一 `root_seed = 1_000_000` | 分别执行 `route_a`（产业升级）、`route_b`（民生优先）、`route_c`（财政修复）各 40 季 | 三条路线均完成 40 季且 `Fault` 计数 `== 0`；三条路线的终局档案文件均生成且字段齐全 | 存在无法走完的「可描述路线」，计划书 §05「开局允许选择三种任期目标」落空。**P1** |
| `T-S-G-02`<br>`test_s_routes_differ` | scenario | 同上 | 对比三份终局档案的五类结果向量（生活、分配、能力、韧性、政治） | 三条路线两两之间，**至少 3 个维度**的整数值不同（`ne_int`，共 3 对 × 至少 3 次）；不要求任何维度上的强弱关系 | 不同排序产生相同轨迹，「可重玩」这条体验不成立（计划书 §02）。**P1** |
| `T-S-G-03`<br>`test_s_route_diff_traceable` | scenario | 同上 | 对任意两条路线运行 `tools/route_diff.gd`：二分定位第一个 `state_hash` 分歧的 `(q, step)`，再在该步内定位第一个差异字段 | ① 分歧的 `(q, step)` 唯一且可复现（两次运行给出相同的 `(q, step)`，精确相等）；② 该差异字段在同 `q` 的日志中存在至少一条同 `entity` 的条目（条数 `≥ 1`）；③ 该条目能回溯到两条路线命令流中的**具体差异命令**（命令 ID 精确命中） | 结果差异无法溯源到机制与命令，报告只能给出「就是不一样」（计划书 §17「同等条件下结果差异可追溯」）。**P1** |
| `T-U-G-04`<br>`test_u_no_balance_knob` | unit（静态） | 全仓源码与内容包 | 扫描参数名与内容包字段名 | 含 `balance` / `handicap` / `route_bonus` / `difficulty_multiplier` 语义的参数数 `== 0`；结算后修改结果的「平衡修正」函数数 `== 0` | 出现人为等强的补丁，违反计划书 §13「禁止后处理补丁」与 §17「不要求每条路线人为等强」。**P0** |
| `T-U-G-05`<br>`test_u_no_single_score` | unit（静态） | 全仓源码 | 扫描状态树与结算档案 | SimCore 中合成单一「满意度」字段数 `== 0`；终局档案中的单一「国力分数」字段数 `== 0`；生活/预期/信任三者为三个独立字段且三个更新函数互不引用（引用次数 `== 0`） | 计划书 §08「民众不是一个满意度」与 §04「不以单一国力分数替代」被违反（INV-121/125）。**P0** |
| `T-S-G-06`<br>`test_s_three_kinds_separated` | scenario | `FX-BASE` | 推进 8 季，读取每季结构化复盘 | `log.explanations.kind` 取值集合 `⊆ {accounted, inferred, projected}`（越界值数 `== 0`）；`kind == projected` 的条目回写状态字段的次数 `== 0`；三类在报告数据结构中分属三个数组（不混装） | 「已经发生 / 规则推断 / 情景预测」混为一谈（计划书 §04 信息设计底线，INV-140）。**P0** |

---

## 9 恶意玩家测试（计划书 §17 六条的完整展开）

12 号文件 §11 给了六条的机制防线与断言方向，这里补齐前置、操作与整数断言。
**每条必须先写出会失败的版本**（去掉防线后必须红），评审时逐条核对注释里标注的「拆掉哪一行」。

| ID | 前置状态 | 操作 | 断言 | 失败说明 |
|---|---|---|---|---|
| `ADV-01`<br>反复开关补助重复领钱 | `FX-BASE`，P09 全部前置满足；一个 cell 在 `q=2` 发生一笔合格实际投资，金额 `1_000_000` | 连续 20 季交替「开启 / 关停」P09 | ① `Σ subsidy_paid_uu == 按合格实际投资独立复算的应发额`（精确相等，与开关次数无关）；② `duplicate_claim_blocked_count > 0`；③ 同一 `claim_key` 的支付次数 `== 1`（对全部 key，违例数 `== 0`）；④ `toggle_count == 20` 且 `Σ policy_toggle_cost == 20 × toggle_cost_uu`（精确）；⑤ 冷却期内的开关命令被 `REJECT(E_POLICY_COOLDOWN)`，次数与期望精确相等；⑥ `gov.cash_uu` 逐季可由账本复算（残差 `== 0`） | 幂等键失效或关停能补发历史季（INV-097/098）。**P0** |
| `ADV-02`<br>借新还旧永远没有成本 | `FX-RICHPOOL` | 40 季只滚动发新债偿旧债，从不用税收还本 | ① `Σ interest_paid_uu` 逐季严格递增（40 次 `>` 判定，写成 `ge_int(cur, prev + 1)`）；② `market_rate_ppm` 对 `debt_service_ratio_ppm` 单调不减（逐季比较，违例数 `== 0`）；③ 存在某季 `t ≤ 40` 使发行命令返回 `REJECT(E_CREDIT_LIMIT)` 或进入重组分支（该季号写入报告）；④ 自动展期次数 `== 0` | 借新还旧成了无成本永动机（INV-038/040）。**P0** |
| `ADV-03`<br>没有教师照样培训 | `FX-NOTEACH` | 启用 P05 并按最大规模拨款，推进 12 季 | ① 每季 `new_seats_persons == 0`（12 次精确等于 0）；② 全程 `Σ skill_in_persons == 0`（精确）；③ 拨款照付：`Σ policy_spend_uu ==` 按参数复算的应付额（精确相等）；④ 该支出在报告中被标为可解释的无效支出（`log.explanations` 中对应条目数 `≥ 1`） | 培训绕过教师约束凭空产生技能（INV-081）。**P0** |
| `ADV-04`<br>全员迁入一区享无限住房 | `FX-MIGRA` | 推进 20 季，不干预 | ① 每季每地区 `housing_units_occupied ≤ housing_stock_units ≤ housing_capacity_units`（4 地区 × 20 季 × 2 条 = 160 次，违例数 `== 0`）；② `Σ migrate_rejected_persons > 0`；③ 每季人口守恒残差 `== 0`（20 次）；④ `housing_capacity_units` 的非项目来源增量 `== 0` | 住房容量自动膨胀，迁移没有硬上限（INV-083/084）。**P0** |
| `ADV-05`<br>提高税率后税收绕过税基 | `FX-TAXRAMP` | P01 税率从 `100_000` ppm 逐季提到 `600_000` ppm，推进 24 季 | ① `receipts_uu` 关于税率**非单调**：存在季 `t` 使 `receipts(t+1) < receipts(t)`（拐点季号写入报告，且该季号在两次运行中相同）；② `base_eff_uu`（有效税基）严格下降（逐季比较，违例数 `== 0`）；③ 税基只来自已过账收入：本季税基 `== Σ 已过账的工资 + 财产 + 转移`（精确相等，与「应得未付」无关）；④ 税率与实收的关系可分别观测（两个字段分别存在，不是一个合成量） | 提税直接等比例增加收入，税基与征收能力形同虚设（INV-031、12 号文件 §6.5）。**P0** |
| `ADV-06`<br>存档重载重抽已确定事件 | `FX-BASE` 推进到某个已发生冲击的季 | 在冲击季之前存档；读档后重新推进该季 | ① `save → load → advance` 与直接 `advance` 的 `state_hash` 逐位相同；② `log.rng` 条数与逐条取值完全相同；③ `shock_log` 中该季记录被**复用**而非重抽：`draw_count` 增量 `== 0`（精确）；④ 抽到的冲击强度与持续时间与首次完全相同（逐字段精确相等） | 读档重抽（俗称 save-scum）成立，一切随机承诺失效（INV-109/133）。**P0** |

---

## 10 不变量覆盖门

| ID | 套件 | 断言 | 失败说明 |
|---|---|---|---|
| `T-U-Z-01`<br>`test_u_invariant_coverage` | unit | 遍历 `tests/tools/invariant_registry.gd`（INV-001..INV-152）与全部用例元数据：**未被任何用例引用的不变量数 `== 0`**；注册表条目数 `== 152` | 有不变量写在文档里但没有任何测试会证伪它——等于没有这条不变量。**P0** |
| `T-U-Z-02`<br>`test_u_test_registry_clean` | unit | 本文件矩阵 ID 集合与 `test_registry` 中的 ID 集合**互为子集**（两个方向的差集大小均 `== 0`） | 文档与注册表分叉；政策内容包的 `test_id` 指向不存在的用例（V-PD-06）。**P0** |
| `T-U-Z-03`<br>`test_u_no_empty_test` | unit | 全部用例的 `assertion_count > 0`（运行器已实现）；本次运行的测试数 `≥` 注册表登记数 | 有用例被悄悄改空，仍然显示绿色。**P0** |

---

## 11 缺陷分级与执行方式

### 11.1 判定标准（机器优先，人工兜底）

| 级别 | 定义（计划书 §17 原文） | 机器判据（命中任一即定级） | 人工判据 |
|---|---|---|---|
| **P0** | 错账、坏档、崩溃与无法继续 | ① 任一 P0 不变量（10 号文件 §14 中「级」列为 P0 的条目）残差 `!= 0`；② 任一 `Fault` 触发；③ 任一 replay 用例 `state_hash` 分歧；④ 存档写出后无法读回，或读回触发 `E_SAVE_CORRUPT`；⑤ 进程崩溃 / 退出码非 0 / stderr 出现 `SCRIPT ERROR`；⑥ 某季结算无法完成且无法继续推进；⑦ §2–§6、§9 中标注 P0 的用例变红 | 玩家在正常操作下无法继续游玩；或报告中的数字与账本对不上 |
| **P1** | 机制错误、不可解释结果与操作阻断 | ① 标注 P1 的不变量违反；② §4 的政策链路用例变红（非 P0 标注者）；③ 性能门 `T-X-F-01/02/06` 未达标；④ `T-P-G-01` 达成人数 ≤ 3；⑤ `T-S-G-02/03` 变红；⑥ `T-R-E-04`（可追溯性）变红 | 结果与规则说明不一致；玩家有合法操作被无理由阻断；报告无法把问题定位到机制 |
| **P2** | 信息层级、重复操作与视觉细节 | ① 试玩记录中同一控件重复点击次数 ≥ 3 的条目；② `T-X-F-05`（加载时长）未达标；③ 文案、排版、图标、对比度类问题 | 不影响正确性与可继续性的一切体验问题 |

**定级争议的裁决顺序**：能否继续 → 账是否对 → 是否可解释 → 其余。
即：只要账不对，无论表现多轻微，一律 P0；能玩能算但解释不了，P1；解释得了只是不好用，P2。

### 11.2 执行方式

**缺陷登记**：`tools/defects.jsonl`，一行一条，机器可读：

```jsonc
{ "id": "DEF-0007", "severity": "P0", "opened_q": "2026-09-20",
  "title_zh": "取消项目后国库现金增加",
  "repro_test": "T-S-D-07",          // 必填：能复现它的矩阵 ID；没有就先补一条测试
  "invariants": ["INV-093"],          // 命中的不变量
  "status": "open",                   // open | fixed | verified | wontfix
  "fixed_commit": "", "verified_by": "" }
```

- **每条 P0 必须先有一条会红的测试**（`repro_test` 不得为空）。没有复现测试的 P0 不许直接改代码——
  否则修完无人知道它是否回来了。这条对 AI 生成的修复同样适用（计划书 §16）。
- 修复流程固定为：**补测试（红）→ 改规则/步长/参数/初值（绿）→ 留作回归**。
  **禁止**用「平衡修正」「事后补钱补货」修数值稳定问题（计划书 §13）。

**门禁脚本**（`tools/gate.sh`，退出码即结论）：

| 门 | 内容 | 退出码非 0 的条件 |
|---|---|---|
| `gate:parse` | 全部 `.gd` 可解析 | 任一解析失败 |
| `gate:layer` | `tools/layer_check.py` + `check_writers.gd` 的全部静态检查 | 任一静态规则违例数 `> 0` |
| `gate:unit` | `tests/unit` 全绿，预算 < 10 s | 任一失败或超时 |
| `gate:replay` | `tests/replay` 全绿，预算 < 60 s | 任一失败 |
| `gate:scenario` | `tests/scenario` + `ADV-*` 全绿，预算 < 5 min | 任一失败 |
| `gate:coverage` | `T-U-Z-01..03` | 未覆盖不变量数 `> 0` 或注册表脏 |
| `gate:p0` | 读 `tools/defects.jsonl`，统计 `severity == "P0" && status ∈ {open, fixed}` 的条数 | **条数 `> 0`** |

**「任何 P0 未清零不发布试玩包」的落地**：
打包脚本 `tools/package.sh` 的**第一条语句**是 `tools/gate.sh gate:p0 || exit 1`，
并在此之后依次跑 `gate:parse`、`gate:layer`、`gate:unit`、`gate:replay`、`gate:scenario`、`gate:coverage`。
**任一门不过，打包脚本不产出任何文件**（不是产出一个带警告的包）。
`status == "fixed"` 也算未清零——只有独立复验人把它改成 `verified` 才不计数，
这对应计划书 §18「主开发同时负责规则和实现时，必须安排独立试玩与核算复查」。

**阶段门槛**（与 12 号文件 §13 一致，此处给出对应的矩阵 ID）：

| 阶段 | 必须全绿的用例 |
|---|---|
| G0 前 | `T-X-F-01` 的空跑基准已在 REF-01 登记（数值可不达标，但必须有基线） |
| G1 前 | 全部 `T-U-A-*`、`T-U-B-*`、`T-R-E-01/02`、`T-S-A-05/06/14` |
| G2 前 | `T-S-P01/P03/P04/P05-CHAIN` + 对应 `-GATE`；全部 `T-S-P04-*` |
| G3 前 | `ADV-01..06`；三类冲击组合的可解释性用例 |
| G4 前 | `T-P-G-01` 首轮（可不达标，但必须跑过并留下记录） |
| G5 前 | 全部 `T-X-*` 与性能门；`T-P-G-01` 达标；`gate:p0` 通过 |

---

## 12 首版发布清单

计划书 §18：**打包可运行版本、版本说明、已知限制、操作指南、样例存档与反馈表；保留调试日志导出。
没有登录、在线依赖、默认遥测和 AI 订阅要求。反馈内容若含玩家信息，应仅收集测试所需部分。**

每一项都给出**验收方式**——否则清单只是愿望。

### 12.1 必须产出的物件

| # | 物件 | 位置 | 验收方式 | 判据 |
|---|---|---|---|---|
| R-01 | 可运行版本 | `dist/jingwei_<版本>_win64/` | 在一台**未装 Godot 的**干净机器上解压即运行，完成前 4 季 | 启动成功且 4 季无 `Fault`；`build_id` 与 `docs/ENGINE.md` 登记一致 |
| R-02 | 版本说明 | `dist/.../RELEASE_NOTES.md` | 人工核对 | 含 `build_id`、`content_hash`、`schema_version`、`param_set_version`、本版新增/修复清单、REF-01 性能登记值 |
| R-03 | 已知限制 | `dist/.../KNOWN_LIMITS.md` | 机器 + 人工 | 必须逐条列出计划书 §03「首版允许保留的简化」全部条目（不模拟商业银行与货币创造、不可直接操纵汇率、无逐企业 AI、固定汇率等），加上 `docs/13_open_questions.md` 中 `status == open` 的全部 OQ 编号；漏项数 `== 0` |
| R-04 | 操作指南 | `dist/.../GUIDE.md` | 由 `T-P-G-01` 的 5 名被试实测 | 被试**只读该指南**即可完成前 4 季，达成人数 `≥ 4` |
| R-05 | 样例存档 | `dist/.../saves/sample_q08/`、`sample_q20/` | 机器 | 两份存档读入后 `state_hash` 与档内值一致（`E_SAVE_CORRUPT` 触发数 `== 0`），且可继续推进 1 季无 `Fault` |
| R-06 | 反馈表 | `dist/.../FEEDBACK.md`（离线表单，纸面/文本，**不联网提交**） | 人工 | 字段限于计划书 §17 的七项记录项 + 可选联系方式；**不含**真实姓名、住址、设备指纹、IP、任何自动采集项；字段清单逐条核对，越界字段数 `== 0` |
| R-07 | 调试日志导出 | 游戏内「导出调试包」按钮 | 机器 | 导出目录含 `state.json`、`ledger_q.csv`、`physical_q.csv`、`step_hashes.json`、`commands.jsonl`、`build_id`；文件缺失数 `== 0`；导出是**玩家主动触发**，不在后台自动发生 |

### 12.2 必须不存在的东西（四条否定项，逐条可验）

| # | 要求 | 验收方式 | 判据 |
|---|---|---|---|
| N-01 | **无登录** | 静态 + 人工 | 发布包中要求输入账号/密码/邮箱/许可证密钥的界面数 `== 0`；首次启动到主菜单的必经步骤中无任何身份输入 |
| N-02 | **无在线依赖** | 机器 | ① 静态扫描发布包脚本：`HTTPRequest` / `HTTPClient` / `WebSocketPeer` / `UPNP` / `OS.shell_open` / `PacketPeerUDP` 的引用数 `== 0`；② **拔网线（或禁用网卡）后完整跑 40 季**，失败数 `== 0`；③ 在本机环回与网卡上抓包 10 分钟，本进程发起的外连尝试数 `== 0` |
| N-03 | **无默认遥测** | 机器 + 人工 | 同 N-02 的第 ①③ 项；另：发布包中不存在任何「使用数据上报」开关（即便默认关闭也不做——首版没有这个功能） |
| N-04 | **无 AI 订阅要求** | 静态 + 人工 | 发布包中对任何外部模型服务的引用数 `== 0`；报告文案 100% 来自规则模板（模板渲染函数之外的文案生成路径数 `== 0`）；生成式 AI 参与权威结算的代码路径数 `== 0`（计划书 §12） |

### 12.3 发布前的最后一次检查（顺序固定）

```
1. tools/gate.sh gate:p0          # P0 未清零 -> 立刻停止，不产出任何文件
2. tools/gate.sh gate:parse gate:layer gate:unit gate:replay gate:scenario gate:coverage
3. tools/bench_quarter.gd         # 在 REF-01 上重跑 3 轮，登记中位数与 P95
4. tests/stress 全量（夜间）      # T-X-E-11 的三档命令流
5. N-01..N-04 四条否定项逐条验收（含断网 40 季）
6. R-01..R-07 七件物件逐条验收
7. 独立复验人把 defects.jsonl 中 fixed -> verified
8. tools/package.sh               # 只有以上全过才会产出 dist/
```

> **发布口径**（计划书 §15）：这条路线的终点是「可信、可玩、可继续验证的首版」。
> 本清单全过 ≠ 游戏好玩，只 = **它没有在骗人**：账是对的，约束是真的，差异是可追溯的，
> 而且它没有偷偷联网、没有在后台收集任何东西。

---

*本文件为质量门与测试矩阵的唯一权威版本。任何与之冲突的草案内容一律作废。*
*矩阵新增或删除一行，必须同步更新 `tests/tools/test_registry.gd`，否则 `T-U-Z-02` 会红。*
