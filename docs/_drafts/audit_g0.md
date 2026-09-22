# G0 内容层计划书符合性审计（对抗性）

> 审计对象：`content/`（36 个 JSON）。基准：`docs/ref/plan_v1.0.txt` v1.0，及 `docs/10/11/12/13` 四份权威契约。
> 审计立场：不夸奖、不复述已写好的部分。只列**与计划书不符**、**看似合规实则空洞**、**跨文件互相矛盾**三类问题。
> 本文件是审计报告，不是契约。**不修改任何被审计文件**；每条给出最小修复方案，由对应负责人执行。
>
> 需要先承认的一点：内容层的自我登记质量很高——`io_table.json`、`world.json`、`P07`、`P08` 都主动登记了
> 自己发现的阻塞级缺口。本报告中若干条目与它们的自我登记重合，但**登记不等于修复**：
> 一个被诚实登记的阻塞问题，仍然是一个阻塞问题。以下按「这一版能不能跑、能不能对账」排序。

---

## 0 一页结论

| # | 判定 | 条数 |
|---|---|---:|
| P0 | 内容包**无法加载**或**基年账无法闭合** | 9 |
| P1 | 政策/事件**机制不可实现**或**跨文件矛盾** | 11 |
| P2 | 口径、可解释性与纪律问题 | 11 |

**一句话**：内容层的说理密度远超实现密度。12 项政策里有 3 项（P07、P08、P12）的效果落点
**没有任何结算步读取**；基年 100 U 在六个不同的跨文件口径上同时对不上；
`§5.15` 规定的 72 个首版必备参数**一张卡都没有**，而已建的 162 张卡全是政策局部参数。
这不是「还没写完」，是「把说明书写在了没有实现的位置上」。

---

## 1 P0 — 阻塞级

### P0-1 剧本根文件引用 5 个不存在的文件，内容包在第一步就加载失败

`content/scenarios/chengwan/scenario.json` `/includes`：

| includes 键 | 期望文件 | 磁盘实况 |
|---|---|---|
| `population_init` | `population_init.json` | **不存在**（有 `population.json`） |
| `cells_init` | `cells_init.json` | **不存在** |
| `pubserv_init` | `pubserv_init.json` | **不存在** |
| `politics_init` | `politics_init.json` | **不存在**（有 `politics.json`） |
| `assertions` | `assertions.json` | **不存在** |

同时目录里多出一个 `world.json`，既不在 `includes` 里，也不在 `11_data_contract.md §2` 的文件布局里。
`policies/` `events/` `shocks/` `parameters/` 四个目录的文件名也全部偏离 §2 布局
（`P01_personal_income_tax.json` vs `policy_P01.json`；`registry.json` vs `params_core.json`）。
`content/schemas/`、`id_aliases.json`、`tombstones.json` 三项 §2 要求的产物完全缺失。

**违反**：`11_data_contract.md §2`（文件布局）、§7（跨文件引用解析，悬空引用即失败）；
计划书 §12「数据协议：尽早固定」。

**最小修复**：把三个缺失文件补齐（`cells_init` / `pubserv_init` / `assertions`），把两个已存在的改名为
契约规定的名字；`world.json` 要么并入 `scenario.json#world_init` 与新的一等字段，要么先升
`content.schema_version` 把它登记进 §2 布局与 `includes`。在此之前**不要**放宽加载器去接受别名。

---

### P0-2 全经济现金总量对不上：实测 55 U，声明 80 U

`scenario.json` `/total_cash_uu = 80000000`，其 `_note_total_cash_uu` 给出分解
「gov 2 + invpool 9 + row 15 + 16 个 cell 合计 24 + 36 个 group 合计 30 + opening 0 = 80」。

实测：

| 主体 | 声明 | 文件实测 |
|---|---:|---:|
| `agent.gov` | 2 000 000 | 2 000 000（`government_init.json`） |
| `agent.invpool` | 9 000 000 | 9 000 000（`government_init.json`） |
| `agent.row` | 15 000 000 | 15 000 000（`scenario.json#world_init.cash_uu`） |
| 16 个 `agent.cell` | 24 000 000 | **20 000 000**（`io_table.json` `_note_base_year_accounting/sector_accounts[*].operating_cash_uu` 求和，且该文件 `interface_requirements` 明写「cell 现金合计 20 000 000」） |
| 36 个 `agent.group` | 30 000 000 | **9 000 000**（`population.json` `/groups[*].cash_uu` 求和） |
| **合计** | **80 000 000** | **55 000 000** |

差额 25 000 000 μU（25 U），其中群组一项独差 21 U。

**违反**：`INV-018`（全经济现金总量恒定）、`E_CASH_TOTAL`、`assert.cash_total`（容差 0）；
计划书 §07「融资必须有对手方」的整个前提——现金总量若不是一个可对账的常数，
「没有无来源资金」这条底座（§16 人工评审要点）就没有检验手段。

**最小修复**：以 `population.json` 与 `io_table.json` 的实测值为准重算
`scenario.total_cash_uu`（= 55 000 000），或反过来定死分配额度后改各初值文件；
**两者必须由 `assertions.json` 的 `assert.cash_total` 在载入期强制，且这条断言目前根本不存在**（见 P0-1）。

---

### P0-3 就业两侧交叉对账失败：差 803 146 人，能源部门差 3 倍

`V-POP-08` 要求群组侧就业按 (地区, 部门, 技能) 汇总 == `cells_init` / `pubserv_init` 侧在岗人数。
`cells_init` / `pubserv_init` 还不存在，但 `io_table.json` 的基年核算附录已经把这一侧的目标值定死了：

| 去向 | `population.json` 群组侧 | `io_table.json` 基年目标 | 差 |
|---|---:|---:|---:|
| `sector.agri` | 2 396 686 | 2 899 050 | −502 364 |
| `sector.manu` | 2 118 909 | 1 947 900 | +171 009 |
| `sector.energy` | **610 580** | **199 800** | **+410 780（3.06 倍）** |
| `sector.services` | 4 136 405 | 3 892 950 | +243 455 |
| `pubserv` | 1 480 266 | 1 000 000 | +480 266 |
| **合计** | **10 742 846** | **9 939 700** | **+803 146** |

分技能同样对不上：群组侧 low/mid/high = 4 577 518 / 4 433 186 / 1 732 142；
`io_table` 市场部门 = 4 763 575 / 3 254 500 / 921 625（mid 差 +36%，high 差 +88%）。
劳动力口径也不同：群组侧 11 677 007，`io_table` 11 804 022→10 804 022，差 872 985。
两边都反算出 80 000 ppm 的失业率——**这恰恰说明「反算出 8%」不足以证明就业结构正确**。

**违反**：`V-POP-08` / `E_EMPLOY_MISMATCH`、`INV-151`；
计划书 §17「人口与就业：就业人数不超过同口径劳动力」、§05「失业率由初始就业分配反算」。

**最小修复**：在 `cells_init.json` 落笔**之前**先裁定哪一侧是权威。建议以
`io_table` 的「产量 × 用工系数」为权威（因为它同时决定 `bound_labor` 与增加值），
反过来重写 `population.json` 的 `employed_persons`，再复核失业率仍落在 [79 500, 80 500] ppm。
能源部门 3 倍的差不是取整噪声，按现状写 `cells_init` 会让能源 cell 的工资支出是其增加值的数倍。

---

### P0-4 基年收入法在 μU 分辨率下无解：劳动报酬占比只能以约 7 个百分点跳变

`scenario.json` `/prices_init/wage_uu_per_person_q = [1, 2, 3]`（低/中/高，μU/人/季）。
`io_table.json` 基年目标：市场部门劳动报酬 51 900 000 μU/年，公共服务 9 000 000 μU/年。

用 `io_table` 自己的分技能就业（4 763 575 / 3 254 500 / 921 625）求解整数工资向量 (a, b, c)，
要求季度市场劳动报酬 == 12 975 000 μU：

```
4 763 575·a + 3 254 500·b + 921 625·c = 12 975 000
a=1: b=1 → c=5.379 ; b=2 → c=1.847      （均非整数）
a=2: b=1 → c=0.210  (< 1，不允许)
```
**无整数解。** 现取值 (1,2,3) 给出 14 037 450 μU/季 = 56 149 800 μU/年，比目标高 4 249 800 μU（+8.2%）。
换用 `population.json` 的就业则是 74 561 264 μU/年（劳动报酬占 GDP 74.6%）。
可达格点在 49.9 U (1,1,2) 与 56.8 U (1,1,3) 之间**没有任何取值**——
即劳动报酬占 GDP 的比重只能以约 **7 个百分点**为步长取值。

`scenario.json` 的 `_note_prices_init` 已如实登记了分辨率问题，但它把结论写成「取最保守的可行值」，
**低估了后果**：这不只是「工资动不了」，而是**基年收入法 GDP 落不到 100 U 的目标点上**，
而 `assert.base_year_gdp` 与 `INV-118` 的容差是 0。

连带失效的机制（全部是计划书明写要有的）：

- `param.wage_step_max_ppm = 20000`（±2%/季）作用在 1 μU 上 `floor` 后恒为 0 →
  计划书 §06「价格与工资作有界平滑调整」在工资侧**永远不产生任何变动**。
- `P03` 替代比例：`benefit = wage × replacement_ppm`，40% 与 45% 在单人量级上同为 0。
  P03 已用「先乘人数再缩放」规避（见其 `cost_model.arithmetic_order_zh`），但这是政策自救，不是系统解。
- `regions.json` `/migration_cost_uu` 只能取 2/3/4（其 `_note_regions` 自承「迁移成本只剩三档分辨率」）。
- `housing_rent_uu_per_unit_q = [1,1,1,1]`，全国住房成本的最小可表达步长约 7.93 U/季。
- `P10` 已被迫自创单位 `μQ_services/千人/季`（`registry.json` 把它判为 `E_UNIT_MISMATCH`）。

**违反**：计划书 §05（基年 GDP = 100 U 是锁定值）、§06（有界平滑的价格与工资调整）、
§14「先保证定义正确」；`INV-118`、`INV-067`。

**最小修复（须先改契约，再改数据）**：在 `13_open_questions.md` 新开一条，
把「按人计价量的记账分辨率」升级为 G0 阻塞问题，并在 `10_variable_dictionary.md §0.1` 增加一个
**按千人计价的派生单位**（例如 `_uu_per_kperson_q`，1 = μU/千人/季），
工资率、迁移成本、人均收入基准、住房租金全部改用该单位存储，
结算时以「人数 × 千人工资率 ÷ 1000（`idiv_floor`，登记余数）」换算。
这不动 `1 U = 1e6 μU` 这条锁定决策，只给人均量增加 3 个数量级的分辨率。
**不要**用「放宽 `assert.base_year_gdp` 的容差」解决——那正是计划书 §13 禁止的做法。

---

### P0-5 公共部门工资 8.4 U vs 需要的 9.0 U，基年生产法 GDP = 99.4 U

`government_init.json` `/annual_plan/expenditure_lines_uu/public_wages = 8400000`；
`io_table.json` `interface_requirements` 明写「必须等于 9 000 000（= 公共服务增加值 10 000 000 减折旧 1 000 000）」。

生产法：市场部门增加值 90 000 000 + 公共服务增加值（工资 + 折旧）。
按 `government_init` 实际取值 = 90 000 000 + 8 400 000 + 1 000 000 = **99 400 000 μU ≠ 100 000 000**。
差 600 000 μU（0.6 U），而 `assert.base_year_gdp` 的 `tolerance` 是 0。

同组还有：`procurement = 3 900 000` vs `io_table` 要求的公共服务中间投入 4 200 000（差 300 000）。

进一步的结构性困难：若把 `public_wages` 提到 9 000 000、`procurement` 提到 4 200 000，
则 9 000 000 + 3 600 000 + 4 200 000 + 1 800 000 + 1 680 000 + 400 000 + 2 033 700 = **22 713 700 > 22 000 000**，
在 `discretionary = 0` 之前就已经超出计划书 §05 锁定的年度支出总额。
也就是说「22 U 支出」「100 U GDP」「公共服务增加值 10 U」三者在当前分项结构下**不能同时成立**。

**违反**：计划书 §05（20 U / 22 U / 100 U 三个锁定值）；`INV-118`、`V-FIN-04`、`assert.base_year_gdp`。

**最小修复**：这是一次真正的三方求解，不能靠调一项。建议压缩 `procurement` 与 `discretionary`，
把 `public_wages` 提到 9 000 000，并把公共服务中间投入降到预算能承担的水平，
然后**同步重算 `io_table` 附录的 `government_nonmarket_output` 与三法对账**。
在 `tools/solve_base_year.gd`（OQ-203 指定）就绪前不要手改单项，否则只会把矛盾挪个位置。

---

### P0-6 服务作为中间投入 × 服务不可库存 ⇒ `bound_materials ≡ 0`，全国产量归零

`io_table.json` `/io_coeff_uqs_per_qs/sector.services` = {agri 95000, manu 150000, energy 90000, services 120000}，
全部 > 0。
`12_simulation_contract.md §5.3` 的材料约束写作 `for j in [agri, manu, services]`，
读 `state.cell.inventory_input_uqs[idx_inv(i, services)]`；
而 `V-CELL-02` 禁止 `inventory_input_uqs` 出现 `sector.services`（不可库存），该值恒为 0。
于是 `bound_materials = idiv_floor(0 × 1e6, a) = 0` → `q_actual = 0` → 四个部门全部停产。

`io_table.json` 的 `open_issues[0]` 已把这条登记为「阻塞级」并给出了正确的修法，
但**内容仍以服务系数非零的形态交付**，即：按现行契约执行 = 剧本跑不起来。

**违反**：计划书 §06「产量由最紧的约束决定」「电力当期使用，不跨季储存」；`INV-049`、`V-CELL-02`。

**最小修复**（采纳 `io_table` 自己的提案，与能源完全对称）：
在 `12_simulation_contract.md §5.3` 新增 `bound_services`，由**当期服务产量在市场闭合前的配给**决定；
材料循环改为 `for j in [agri, manu]`。该改动必须先改 12 号文件，再跑 `T-U-QACTUAL-TABLE` 的扩展用例。
在这条改动落地前，`io_table` 的服务列系数**不应被当作已定稿**。

---

### P0-7 46 个 `mech.*` 里 38 个不在 MechanismRegistry，`V-PD-08` 会拒绝全部 12 项政策

`17_api_skeleton.md:1164-1167` 的 `JWPolicyDef.MECHANISM_IDS` 只有 12 个：
`grid_capacity / project_queue / service_capacity / tax_rate / transfer_payment / investment_subsidy /
training_seats / housing_stock / irrigation_index / port_capacity / tax_capacity / admin_capacity`。

12 个政策文件共引用 **46** 个 `mech.*`，其中**只有 8 个**在注册表内；
注册表里的 `tax_rate / transfer_payment / training_seats / admin_capacity` 反而无人引用。

更要命的是它对「伪深度」的影响。`11_data_contract.md §5.12` 的裁定原话是：
「**机制注册表堵住计划书 §09 的伪深度：政策只能引用已有机制并给参数，不能自带逻辑；
两个政策的 `mechanism_ids` 与参数完全相同时 `tools/check_policy_dup.gd` 报警告**」。
现状是每个政策自带一批只有自己使用的机制名，于是**查重工具在结构上永远不会报警**。
而这些自造名里已经出现了明显的同物异名：

- `mech.service_opex` / `mech.service_opex_availability` / `mech.service_opex_funding`（三名，同一条 S04 付款 + S07 可用率）
- `mech.irrigation_index` / `mech.irrigation_availability`
- `mech.policy_eligibility_gate` / `mech.policy_precondition_gate`（都是 12 号 02.1 的同一条资格链）
- `mech.income_tax_base` / `mech.income_tax_schedule` / `mech.tax_capacity_gate` / `mech.tax_collection` / `mech.tax_capacity`

**违反**：`V-PD-08` / `E_MECH_UNKNOWN`；计划书 §09「不把同一个效果复制成十个名字」。

**最小修复**：先冻结一份机制清单（12 个不够，按 12 号文件八步实际存在的函数枚举，估计 20–25 个），
写进 `MechanismRegistry` 并在 `docs/15_module_map.md` 登记落点文件；
再回头把 46 个引用映射过去，**合并上面四组同物异名**。
合并后 `check_policy_dup.gd` 才可能有意义。

---

### P0-8 全部 27 个政策/事件/冲击文件都带 schema 未声明的键，`additionalProperties: false` 下无一可加载

逐文件统计（非 `_note_` 前缀的多余顶层键）：

| 文件类 | 多余顶层键数（范围） | 例 |
|---|---|---|
| 12 个政策 | 18–29 个 | `effect_chain`、`targets`、`cost_model`、`funding_requirement`、`lag_model`、`operating_cost`、`parameters`、`ui_copy`、`acceptance_tests_detail`、`open_questions_refs`、`new_open_questions_proposed` |
| 12 个事件 | 12–26 个 | `trigger_detail`、`evidence`、`consequences`、`player_options`、`political_reaction`、`copy`、`parameters`、`acceptance_tests_spec` |
| 3 个冲击 | 13 个 | `magnitude_distribution`、`arrival_rule`、`sampling_protocol`、`transmission`、`value_cards` |
| `population.json` | 2 个 | `derived_check`、`extensions` |
| `io_table.json` | — | `_note_base_year_accounting`（见 P1-3） |

`11_data_contract.md §3` 明写：「对象键必须是 schema 已声明的键（`additionalProperties: false`），
拼错字段名会被静默忽略 → `E_UNKNOWN_FIELD`」。`_note_<field>` 是唯一白名单，
而上述键都不是 `_note_` 前缀、也不是某个已声明字段的注释。
事件条件对象里还混进了裸 `_note_zh`（E09–E12 的每条 `all_of` 项）。

P08 自己把这条登记为 OQ-247，结论正确：「处置办法只有一个：扩展 schema 到 v2，不得删字段」。
但在 schema v2 落地前，**内容包的状态是「全部不可加载」**，而 `content/schemas/` 目录尚不存在。

**违反**：`11_data_contract.md §3`、`§5.12`、`§5.13`、`§5.14`、`§5.7`；
计划书 §12「数据协议：尽早固定」——协议固定的意思是先定后写，不是先写后追认。

**最小修复**：立刻做一次 schema v2：把 `effect_chain`、`targets`、`operating_cost`、
`funding_requirement`、`lag_model`、`parameters`、`failure_paths[].trigger_zh/observable_zh`、
`ui_copy` 升为一等字段（它们承载的正是计划书 §09/§10 的硬要求，删不得），
并把 `content/schemas/*.schema.json` 真正产出——**schema 本身就是第一道测试**（§1 立场），
现在这道测试根本没被写出来。

---

### P0-9 契约规定的 72 个首版必备参数，一张身份证都没有；`param.rng_salt` 缺失使重放无数据

`content/parameters/registry.json` `/contract_min_set_missing` 长度 = **72**，
与 `11_data_contract.md §5.15`「首版必备参数最小集」的条数**完全相等**——即**零覆盖**。
缺失的包括：

`price_step_max_ppm`、`price_gap_gain_ppm`、`wage_gain_ppm`、`wage_step_max_ppm`、
`demand_smooth_ppm`、`inventory_target_ppm`、`hiring_friction_ppm`、`wage_cash_share_ppm`、
`construction_share_cap_ppm`、`uu_to_construction_uqs_ppm`、`training_lag_q`、`student_teacher_ratio`、
`migration_*`（5 条）、`mpc_ppm`、`dissave_ppm`、`engel_weight_ppm`、`payout_ratio_ppm`、
`invest_propensity_ppm`、`market_rate_base_ppm`、`market_rate_slope_ppm`、`coupon_min/max_ppm`、
`household_bond_appetite_ppm`、`trust_drop_ppm`、`trust_recover_ppm`、`support_weight_ppm`、
`expectation_inertia_ppm`、`persons_per_housing_unit`、`bond_batch_cap`、`default_grace_q`、
`amount_max_uu`、`qty_max_uqs`、`rng_salt` ……

已建的 162 张卡**全部**是政策/事件局部参数（`param.p04_*`、`param.p11_*`、`param.e05_*`…）。
也就是说：**驱动整个模拟的行为系数一个都没有身份证，而每项政策的冷却时间都有。**
这是本次审计里最典型的一条「看似合规实则空洞」：
`14_parameter_registry.md` 的仪表盘显示「162 张身份证、observed = 0、V-PC-04 ✅ 通过」，
读起来像是计划书 §14 已经落实，实际上 §14 要管的那批参数一张也不在。

三条直接后果：

1. `param.rng_salt[6]` 缺失。`scenario.json` 的 `_note_root_seed` 明写「盐值在 `param.rng_salt[6]` 中声明，
   本文件不重复声明，避免出现第二处事实来源」——而那个唯一的事实来源不存在。
   `12_simulation_contract.md §0.4` 的 `draw_raw(stream,q,index) = splitmix64(root_seed ^ SALT[stream] ^ …)`
   没有 SALT 可读 ⇒ 计划书 §12「固定构建、固定种子、相同命令得到相同结果」与 §16 T08 没有数据基础。
2. `INV-122`（`trust_recover_ppm < trust_drop_ppm`）由「ParameterCard 交叉校验」落地（`§7.1` 映射表），
   两张卡都不存在 ⇒ 该不变量无物可校。
3. `scenario.json` `/param_set_ref = "paramset.baseline"` 是**悬空引用**：
   `registry.json` 的 `schema_kind` 是 `parameter_registry`（§5.15 要求 `parameter_set`），
   且没有 `param_set_id` / `param_set_version` 字段 ⇒ `manifest.param_set_version` 与 `INV-134` 无法工作。

另外 `registry.json` 是**工具扫描报告**（带 `generated`/`tool`/`files_scanned`/`findings`），不是参数集；
且已经**过期**：15 个文件（11 个事件 + P12 + 3 个冲击，约 133 张卡）不在 `files_scanned` 里。
它自己报了 5 条 ERROR（`param.io_table_set` 的 `value` 是字符串、`valid_range` 是散文、`unit` 非法；
`param.p10_*` 两条单位非法）。

**违反**：计划书 §14「每个参数都带一张身份证」；`V-PC-01`、`V-PC-02`、`V-PC-06`、`V-PC-07`、`INV-152`。

**最小修复**：新建 `content/parameters/params_core.json`，`schema_kind = "parameter_set"`，
`param_set_id = "paramset.baseline"`，把 §5.15 表里的 72 项逐条建卡（九字段齐全，
全部 `design_assumption`，取值直接用 §5.15 给的首版取值）。
`registry.json` 改名为 `docs` 侧的生成物或明确标注为报告，**不放在 `content/` 下冒充输入**。

---

## 2 P1 — 机制不可实现 / 跨文件矛盾

### P1-1 P07、P08、P12 的效果落点没有任何结算步读取 —— 三项空政策

对 `12_simulation_contract.md` 全文检索每个 `effect.target` 的**读**位置：

| 政策 | `effect.target` | 写它的步 | **读它的步** |
|---|---|---|---|
| P04 | `state.region.grid_capacity_pending_uqs_per_q` | S07→S01 | §5.2 电力配给（第 710 行）✔ |
| P05 | `state.group.education_cohort_persons` | S07 | §7 技能队列到期（第 1302/1350 行）✔ |
| P06 | `state.region.housing_pending_units` | S07→S01 | §7.5 迁移住房闸（第 1331 行）✔ |
| P10 | `state.pubserv.capacity_pending_uqs_per_q` | S07→S01 | §5.7 公共服务交付 ✔ |
| P11 | `state.gov.tax_capacity_ppm` | S07 | §6 征收（第 1103/1121 行）✔ |
| **P07** | `state.region.irrigation_index_pending_ppm` | S01 转入 | **无**（全文只出现在 §1 可写子集与 01.4 转入） |
| **P08** | `state.region.port_capacity_pending_uqs_per_q` | S01 转入、S06 折旧 | **无** |
| **P12** | `state.politics.admin_capacity_ppm` | S07、事件 | **无**（只出现在 INV-125 的「不得引用」句里） |

三项政策的完整链条是：花钱 → 排队 → 施工 → 完工 → 写一个**没有任何人读的状态变量**。
`P07` 的 `contract_gaps.irrigation_consumption_rule` 与 `world.json` 的 `port_gate.consequence_if_unfixed_zh`
都已逐字点明这一点，`politics.json` 的 `administrative_capacity.consumer_gap_note_zh` 同样点明
「行政能力现在只能被写、不能起作用」。三处独立发现同一类缺口，说明它是系统性的。

连带：事件 `E08` / `E11` / `E12` 对 `state.politics.admin_capacity_ppm` 的 `delta_ppm` 同样是空写入。

**违反**：计划书 §09「12 项政策，每项至少 1 条完整反馈链」、
§03「不可削减的底座：……因果说明……少一张地图可以；**少一条关键反馈链不可以**」。

**最小修复**（三条，都在 12 号文件补消费端，不改内容）：
1. **灌溉**：采纳 P07 的提案，在 §5.3 的 `bound_capacity` 上为 `sector.agri` 加一个乘子
   `mul_ppm(cap, min(irrigation_index_ppm, 1_000_000))`，并注册 `mech.irrigation_availability`。
2. **港口**：先按 `world.json` OQ 的保守读法把单位定为 `μQ_manu/季`（只覆盖制造品跨境流），
   在 §5.6 的出口成交与 §5.5 的设备到货前各加一道地区级上限。
3. **行政能力**：给它一个**唯一**消费点（建议：§2 02.7 的项目每季可推进上限，或 §5.5 的施工分配效率），
   否则就应当把 P12 的效果改到一个已被读取的落点上——**不能留一个只写不读的政治指标**。

---

### P1-2 出口基准量没有 schema 归宿；io_table 的 11 U 出口与 world.json 的 2 U 相差 5.5 倍

`12_simulation_contract.md §5.6` 的出口需求行是
`min(mul_ppm(基准出口量[s], world.export_demand_ppm[s]), world.delivery_capacity_uqs[s])`。
「基准出口量」在 `11_data_contract.md §5.4` 的 `world_init` 里**没有字段**，
在 `scenario.json` 里也没有。唯一给出它的是 `world.json`
（`/export_demand/export_baseline_uqs_per_q = [100000, 350000, 50000, 0]`），
而该文件不在 `includes` 里、不在 §2 布局里、`schema_kind = "world_init"` 不在契约的 `schema_kind` 集合里。
**结论：在可加载的内容里，出口需求没有定义。**

同时两份文件对基年外贸规模的说法差 5.5 倍：

| 口径 | 年出口 | 年进口 |
|---|---:|---:|
| `io_table.json` `final_use_uu` | 11 000 000（agri 1.5 / manu 5.2 / energy 2.3 / services 2.0） | 11 000 000 |
| `world.json` `export_baseline` | 2 000 000（500 000/季） | 仅设备线可用 |

且 `io_table` 的服务出口 2 000 000/年在结构上不可能：
`scenario.json` `/world_init/delivery_capacity_uqs[3] = 0`，`world.json` 明写服务跨境「closed_in_v1」。
若服务出口归零，基年支出法 GDP 掉到 98 000 000，`assert.base_year_gdp` 再度失败。

进一步的可持续性问题（用 `world.json` 自己的 `sustainability_budget` 方法复算 `io_table` 的数）：
`agent.row` 初始现金 15 U；按 `io_table` 的 11 U/年出口，而 `world.json` 说 agri/energy 进口线
「declared_no_sim_step_in_v1」（只有 manu 7.5 U/年可回流），则 row 现金年净减约 3.5 U，
**约第 17 季（q≈17）见底，出口此后静默归零**。这正是 `world.json` 警告的
「原因不在任何经济机制里，玩家无法解释」的情形。

**违反**：计划书 §07「外部世界：精简，但不能成为无限资金源」「不能仅靠『外汇充足』标签无限采购」；
`11_data_contract.md §5.4`；`INV-018`。

**最小修复**：在 `11_data_contract.md §5.4` 的 `world_init` 增加必填字段
`export_baseline_uqs_per_q: int[4]`，并加校验「`delivery_capacity_uqs[s] == 0` ⇒ `export_baseline[s] == 0`」；
把 `world.json` 的取值写进 `scenario.json`；然后**以该取值为准重算 `io_table` 附录的 `final_use_uu`**，
而不是反过来。另补一条 `assert.row_cash_nonneg`（`world.json` 已建议，但 §5.11 的表达式语言缺 `min_q`/`expect_ge`）。

---

### P1-3 基年核算表藏在 `_note_` 键里：不进 `content_hash`、无机器校验、与实际系数可以静默漂移

`io_table.json` `/_note_base_year_accounting` 是一个约 20 KB 的嵌套对象，
内含部门账户、投入产出矩阵、最终使用、三法对账、季度拆分、pubserv 账户、库存需求、
`param.io_table_set` 的参数卡镜像与 8 条 open issues。它是本次审计里信息量最大的单块内容。

问题在于它的**位置**：`11_data_contract.md §1.5`「`_note_*` 只供 Presentation 读取，
SimCore 的加载器不读它，`content_hash` 也不包含它」，§6.4 的规范化编码把它列入排除集合。
因此：

- 它对系数的任何约束（列和、能源自用、三法残差为 0）**没有任何机器校验**；
- 改了 `io_coeff` 而忘了改附录，`content_hash` 不变、测试不失败、没人会发现；
- §3 的 `_note_<field>` 约定要求它是某个同级字段的注释，而 `base_year_accounting` 这个字段并不存在；
- `test_u_note_consistency` 的设计是「解析 `_note_` 中的『N U』并断言与数值一致」，
  面对一个嵌套对象直接不适用。

该块自己的 `_status` 已如实说明了这一点并请求升为一等字段。审计确认这个请求是必要的、且是阻塞级的：
它同时是 P0-2（现金）、P0-3（就业）、P0-5（公共工资）三条对账的唯一对手方数据。

**违反**：计划书 §12「Content 层不得隐藏不可追溯的脚本副作用」、§14「数据和作者假设始终分开」；
`11_data_contract.md §1.5`、§6.4。

**最小修复**：schema v2 把它升为 `io_table.base_year_accounting` 一等字段，纳入 `content_hash`，
并新增 `V-IO-09`：附录的 `sector_accounts[*].gross_output_uu` 必须等于
`cells_init` 各 cell 基年产量之和 × 基年价；`accounting_checks` 的三个 `residual` 必须为 0（由加载器复算，不是抄写）。

---

### P1-4 `OQ-246..OQ-263` 共 18 个编号被并行产出的文件各自占用，同号不同义

`13_open_questions.md` 登记到 `OQ-245` 为止，且 §H 明写「编号一经登记不得复用」
「由 `tools/check_oq_refs.gd` 双向校验」。内容层实际使用了 18 个未登记编号，且互相冲突：

| 编号 | `world.json` 的含义 | `P08` 的含义 | `P11` / `politics.json` 的含义 |
|---|---|---|---|
| OQ-246 | `delivery_capacity` 是否拆成进/出两个数组 | 港口通行能力的计量单位与覆盖部门 | P11：征收乘数的分配效果；politics：席位并列判定矛盾 |
| OQ-247 | 出口价格弹性通道未入 §5.6 | PolicyDefinition schema 覆盖不足 | P11：进口涨价使交付进度到不了 100%；politics：admin_capacity 无消费者 |
| OQ-248 | `port_gate` 首版不启用 | 预算曲线只能平直 | P11：运行费与中州公共服务耦合；politics：`bloc.resource_uu` 不更新 |
| OQ-249 | `agent.row` 实物侧不做库存对账 | P04 示例施工金额与施工量差 2 倍 | P11：门槛可能永不生效；politics：隶属权重不随季重算 |
| OQ-250 | 进口交付时滞为 0 | 进口设备金额→数量换算未定义 | P11：冷却时长；politics：组织力否决闸门不采纳 |
| OQ-253 | 对外违约的额度收紧量 | `failure_paths[].code` 取值集合未定义 | P12：同 P08 |

`E09`–`E12` 这批事件已经发现了碰撞，改用 `OQ-PENDING-EV-xx` 占位并在
`open_question_refs_note_zh` 里写明「现有的 OQ-246 及以后的编号已被若干并行产出的内容文件各自占用且含义互相冲突」。
这是正确处置，但也证明该机制已经失效。

**违反**：`13_open_questions.md §H.1`（双向校验）与「编号不得复用」；
计划书 §13「每条变化附带实体 ID、来源操作」的可追溯原则。

**最小修复**：由 13 号文件负责人一次性收编：把 18 个编号按**首次出现的文件修改时间**重新分配为
`OQ-246 … OQ-27x`，逐条写进 `13_open_questions.md`（问题/影响面/临时取法/将来怎么验证四段齐全），
然后回改 9 个内容文件的引用。在收编完成前，**任何文件不得再自行占号**——这正是 E09–E12 的做法。

---

### P1-5 `preconditions` 与 `expr` 把表达式求值器又请了回来

`11_data_contract.md §1.1` 是本项目最硬的一条结构性承诺：
「内容包是只读数据，不是脚本。**只有 JSON，不允许内嵌表达式**、不允许 GDScript 回调、
**不存在表达式求值器**（事件触发只有六种比较运算）」。
`12_simulation_contract.md` 02.1 第 3 步同样写「前置条件逐条求值（**只有比较，无表达式器**）」。

实况：12 个政策共用了 **21 种** `precondition.kind`（契约示例只有 3 种），
其中 `ratio_compare`（带 `denominator`，即一次除法）、`membership`、`claim_ledger`、
`housing_headroom`、`opex_commitment`、`param_order`、`no_active_project`、`mask_single_bit`
都不是比较。并出现了 `value_ref`（指向另一个状态字段的间接引用）、
`scope: "qualifying_quarter"`、`metric: "qualifying_investment_q"` 这类非稳定 ID 的求值对象。

更直接的是字符串表达式：

- `P06_public_housing_construction.json` `/preconditions[*].expr` 共 **7 条**，例如
  `"(state.politics.legal_authority_mask >> 1) & 1 == 1 且 idiv_floor(state.politics.seats_gov × 1000000, state.politics.seats_total) >= 500000"`
  和 `"对每个 r：state.region.housing_capacity_units[r] − state.region.housing_stock_units[r] >= mul_ppm(param.p06_batch_units, scale_ppm)"`。
  这些是 P06 前置条件的**唯一**表述——中英混排的伪代码，没有任何机器可求值的等价字段。
- `P09` `/preconditions[*].claim_key_expr = "hash64(policy.P09, beneficiary_cell, q, qualifying_investment_id)"`。
- `P05` `/enrollment_rule/pseudocode`（21 行伪代码）、`P12` `/effect/formula_steps`、`P10` `/preconditions[*].expr_zh`。

这些块的内容质量很高（P05 的四闸取最紧、P12 的覆盖率公式都写得可直接实现），
问题是**它们住错了地方**：规格应当在 12 号文件里，内容包里只放参数。
现在的形态是「内容包携带逻辑」，而这正是 §1.1 用 schema 结构去禁止的东西。

**违反**：`11_data_contract.md §1.1`；`12_simulation_contract.md` 02.1；
计划书 §12（Content 层「不得隐藏不可追溯的脚本副作用」）。

**最小修复**：
(a) 把 21 种 `kind` 收敛成一个**封闭枚举**，每种给出机器可求值的字段组合
（建议保留 `state_compare` / `ratio_compare` / `membership` / `slot_available` / `authority` / `cooldown` / `budget`，
其余合并），写进 §5.12 并加 `V-PD-12` 校验枚举闭集；
(b) 把 `P06.expr`、`P05.pseudocode`、`P12.formula_steps`、`P10.expr_zh` 的内容**搬进 12 号文件**的对应小节，
内容包里只留字段与参数；
(c) 保留一条静态检查：内容包中出现 `expr` / `formula` / `pseudocode` 字样即 `E_EXPR_IN_CONTENT`。

---

### P1-6 P03 的法定转移在三处给出三个不同的数（4 U / 3.6 U / 实算 2.24 U）

- `P03_unemployment_benefit.json` `/cost` = `per_quarter_uu 1000000 × 4 = 4000000`，
  且 `/cost_model/provision_derivation/cross_check_zh` 声称「与 `government_init.annual_plan.
  expenditure_lines_uu.statutory_transfers`（4 U/年）在基年逐字相等」。
- `government_init.json` 实际写的是 `statutory_transfers = 3600000`（3.6 U）。
  P03 的参数卡 `param.p03_provision_uu_per_q` 的 `source_ref` 引用的是
  **`11_data_contract.md §5.9` 的示例值 4000000**，不是本剧本的实际值。
- 按默认拉杆值实算：`population.json` 的失业人数按技能档为
  low 543 131 / mid 315 211 / high 75 819；
  `wage_base = 543131×1 + 315211×2 + 75819×3 = 1 401 010 μU/季`；
  `due = mul_ppm(1401010, 400000) = 560 404 μU/季` ⇒ **全年约 2 241 616 μU（2.24 U）**。

即：预算行 3.6 U、政策计提 4 U、机制实际能花出去 2.24 U。
`government_init` 的 `_note_annual_plan` 声称「基线年赤字 2 U 如实现身」，按实算不成立。

**违反**：计划书 §05（基线年收入 20 U / 支出 22 U / 赤字 2 U 是锁定值，分项必须能对上）；
`V-FIN-04`、`INV-146`。

**最小修复**：先定 `government_init.statutory_transfers`，再由 P03 的默认拉杆值**反解**
`replacement_ppm` 或 `eligibility_rule`，使实算的基年四季支出落在该行的 ±10% 内
（P03 的 `param.p03_provision_uu_per_q` 的 `calibration_note` 已经写明了这条纪律，照做即可）；
同时把 P03 的 `source_ref` 从「契约示例值」改成「本剧本 `government_init.json` 的实际取值」——
**引用示例值当事实来源是一类独立的缺陷**，应在全部内容文件里做一次扫描。

---

### P1-7 `season_factor_ppm` 与 `annual_plan` 在 12 号文件里没有任何消费者

全文检索 `12_simulation_contract.md`：`annual_plan`、`season_factor` **零命中**。
即：

- `scenario.json` `/season_factor_ppm` 的三条数组（`gov_receipts` / `gov_primary` / `agri_output`）
  没有任何结算步读取；
- `government_init.json` `_note_annual_plan` 里推导出的四季收入
  `4600000 / 4900000 / 5000000 / 5500000` 与四季基本支出
  `4791912 / 4991575 / 5091407 / 5091406` 是纯注释，不进状态、不进账；
- `io_table.json` 的 `quarterly_split` 注释已经独立发现了 `agri_output` 一条无消费者。

计划书 §05 明写：「**季度财政由季节系数分配，初始四季合计与年计划一致**」。
这是一条对结算的要求，现在在契约与内容两侧都落空。

**违反**：计划书 §05；`INV-042` 变成一条只校验「四项和 == 1e6」的空断言。

**最小修复**：在 `12_simulation_contract.md` §2（S02）或 §4（S04）显式写出
「本季基本支出额度 = `split_largest_remainder(年度基本支出, season_factor_ppm.gov_primary)` 的第 `q mod 4` 项」，
并说明利息与还本不受季节系数支配（`government_init` 的注释已给出正确口径，把它升格为规则）。
若决定首版不做季度分配，则应当**删掉** `season_factor_ppm` 并在 13 号文件登记，
而不是留着一组没人读的系数假装满足了 §05。

---

### P1-8 灌溉指数初值 620 000–900 000 与「基年产能不是紧约束」互相排斥

`regions.json` 的 `irrigation_index_ppm` = 北原 620 000 / 中州 900 000 / 海岬 850 000 / 西岭 700 000，
全部低于基期 1 000 000。
`P07` 的 `contract_gaps.irrigation_consumption_rule.base_year_impact_zh` 已给出条件：
「若剧本按地区故事设为低于 1 000 000，**剧本作者必须在这个机制在位的前提下校准基年，不能两边各算各的**」。

而 `io_table.json` 的基年核算按**满产能**算：各部门产能利用率 86.7%–92.6%，
明写「基年产能不是任何部门的紧约束」。若 P07 的乘子落地，北原农业 cell 的 `bound_capacity`
要乘 0.62，`io_table` 的 6 275 000 μQ/季 农业产量与由此得出的 17.19 U 农业增加值立刻失效。

**两条路都不通**：装上乘子 ⇒ 基年 100 U 破；不装乘子 ⇒ P07 是空政策（P1-1）。

**违反**：计划书 §05（北原「灌溉与运输薄弱」必须是可结算的约束）、§06、`INV-118`。

**最小修复**：先裁定灌溉乘子（建议按 P07 提案落地），再把 `regions.json` 的四个指数值
与 `io_table` 的农业产量**一起**重解：要么把指数初值提到 1 000 000 并用别的字段表达北原的弱势
（例如更低的 `capacity_active`），要么保留低指数并按乘子后的有效产能重算基年农业增加值。

---

### P1-9 冲击文件里有为通过校验而填的死字段，以及配置好但不可执行的到达规则

- `S03_external_financing.json` `/targets` 与 `/target_weights_ppm = [250000,250000,250000,250000]`：
  S03 的通道是 `external_credit`，`12_simulation_contract.md` 01.7 对它的作用式是
  `sovereign_rate_ppm_per_q = clamp(base + mul_ppm(eff, param.rate_sensitivity_ppm), …)` 与
  `credit_limit_uu = mul_ppm(base, clamp(1e6 − eff, …))`，**两个标量，都不按部门加权**。
  这四个 250 000 唯一的作用是让 `V-SH-03`（Σ == 1e6）通过。**这是典型的为满足校验器而填数**。
- `min_gap_q`（S01/S02 = 4，S03 = 6）不可执行：01.6 的判据是 `q - last_end_q[k] < min_gap_q[k]`，
  而 `10_variable_dictionary.md` 里**没有 `state.world.last_end_q` 这个字段**
  （只有 `shock_active` / `shock_remaining_q` / `shock_magnitude_ppm`）。三个冲击文件已自行登记为 OQ-260。
- `arrival.max_active = 1` 同样没有对应的状态或判据。
- `S02_import_price.json` `/target_weights_ppm = [0, 1000000, 0, 0]`：
  能源与农产品权重为 0，因为 `world.json` 说这两条进口线「declared_no_sim_step_in_v1」。
  后果是计划书 §07 明确点名的三类冲击之一——「**进口能源**／设备价格变化」——
  在首版只剩「设备」半条。S02 自己的注释也承认「对能源供给没有传导……不要用调大冲击强度去掩盖」。

**违反**：计划书 §07「三类外生冲击足够开局：出口需求变化、进口能源／设备价格变化、外部融资收紧」；
`V-SH-03` 被降格为形式校验。

**最小修复**：
(a) 给 `ShockDefinition` 加 `channel_uses_target_weights: 0|1`，S03 置 0 并允许 `target_weights_ppm` 缺省，
    `V-SH-03` 只对置 1 的通道生效；
(b) 在 `10_variable_dictionary.md §7` 增加 `state.world.shock_last_end_q[]`（3 项，写者 S01），
    否则删掉 `min_gap_q` / `max_active` 两个字段；
(c) 能源进口通路（`world.json` 的 OQ-251）应当在 G3 之前补齐，否则 S02 应当**在文案中明说它只影响设备**。

---

### P1-10 `population.json` 携带 `derived_check` 与 `extensions` 两个影子命名空间

除 P0-8 的 schema 问题外，内容上还有更深的隐患：
`extensions.groups_ext[*]` 里放着 `base_income_lines_uu_per_q`、`base_equity_share_ppm`、
`cohort_rates_ppm_per_q`（含 `skill_up_ppm_per_q`、`age_out_target`）、`migration.relative_propensity_ppm`、
`housing.housing_burden_design_target_ppm` 等 SimCore 真正需要的量。
其中 `equity_share_ppm` 按 `11_data_contract.md §5.8` 应当住在 `cells_init.json`，
`age_out` / `death` 率按 §5.7 应当住在 `demography_rates`——
现在它们在两处各有一份，而 `cells_init.json` 还不存在。

`derived_check` 则是把 `assertions.json` 的职责搬进了数据文件：
它给出 `unemployment_ppm = 80000`、`employment_cross_check_for_cells_init` 等校验值。
`§5.11` 的立场是「**`assertions` 是断言，不是输入**，SimCore 绝不从这里读任何值（INV-143）」——
这条纪律的前提是断言住在**独立文件**里。放进 `population.json` 后，
「谁是输入、谁是校验」只剩注释在区分，加载器区分不了。

**违反**：`11_data_contract.md §5.7`、§5.8、§5.11、`INV-143`；
计划书 §14「数据和作者假设始终分开」。

**最小修复**：`derived_check` 整块搬进新建的 `assertions.json`；
`extensions.groups_ext` 里属于 `cells_init` 的字段（`base_equity_share_ppm`）搬过去，
属于人口学的（`cohort_rates_ppm_per_q`）合并进 `demography_rates`，
真正还没有归宿的（`relative_propensity_ppm`、`housing_burden_design_target_ppm`）
写进 13 号文件的待决登记，**不要留在数据文件里**。

---

### P1-11 损耗率全零，使「物资约束」底座的一个可观察项恒真

`io_table.json` `/spoilage_ppm = [0, 0, 0, 0]`（契约示例是 `[20000, 2000, 0, 0]`）。
后果：`12_simulation_contract.md §5.8` 的 `spoilage[i] = mul_ppm(inv, 0) = 0`，
库存恒等式 `inv_end == inv_start + produced + purchased − sold − used − spoilage` 的最后一项恒为 0，
`INV-053`（损耗计入中间消耗）恒真。于是**一个实现完全缺失的损耗模块，与一个实现正确的损耗模块，
在所有测试下表现相同**。

该文件的 `_note_spoilage_ppm` 已把理由写清（非零损耗让基年 GDP 与 `cells_init` 形成不动点），
理由成立。但这条简化的**代价**没有被登记：农业损耗为 0 直接削弱了
计划书 §05 北原「运输薄弱」与 P07「农业物流」的可观察性
（P07 自己的 `contract_gaps.logistics_channel` 承认「物流」只剩一半）。

**违反**：计划书 §03「不可削减的底座：……物资约束……」的可检验性；§06 的库存逐项对账。

**最小修复**：保留首版取 0，但**必须**补一条回归测试 `T-U-SPOILAGE-NONZERO`，
用夹具把 `spoilage_ppm` 置为非零并断言库存恒等式与中间消耗都随之变化——
否则这条代码路径在首版全程无人走过。同时把「损耗为 0 ⇒ P07 的物流效果只剩灌溉」
写进 13 号文件，避免将来被读成「P07 设计得薄」。

---

## 3 P2 — 口径、可解释性与纪律

### P2-1 12 个事件模板全部只建模失败，30 条群组级效果 100% 为负

逐条统计 `effects[].delta_ppm`：

- 群组级（`trust_ppm` / `expectation_ppm`）共 **30 条，全部为负**，范围 −8 000 至 −45 000；
- 集团级 `org_power_ppm` 共 13 条，**12 条为正**（反对方组织力增强），仅 E11 有一条 −15 000；
- 触发条件方面，12 个模板**没有一个由「成功状态」触发**：
  E01 限电、E02 歉收、E03 住房挤压、E04 环境事故、E05 培训错配、E06 港口拥堵、
  E07 到期墙、E08 征收争议、E09 运行费欠拨、E10 迁移潮、E11 采购丑闻、E12 预算冲突。

计划书 §08 的标题是「**成功的发展，也会带来新的反对者**」——它要的是「发展产生新诉求」，
而不是「只有搞砸了才会有事发生」。现状下，事件系统对「三条可描述路线」（§17 策略差异门槛）
的贡献为零：它只区分「出问题」和「没出问题」，不区分两条都成功的路线。

另一个结构性问题：`12_simulation_contract.md §8.1` 明写
「程序信任**只受「承诺兑现与否」驱动。失信事件是一个闭集合**」（欠付转移／欠拨运行费／项目取消／债券违约四项），
而 `11_data_contract.md §5.13` 的事件白名单允许事件直接写 `state.group.trust_ppm`。
E01（限电投诉）、E04（环境事故）、E05（培训错配）、E06（港口拥堵）四个**都不是失信**的事件
合计对信任写了最多 −188 000 ppm。两份契约在这一点上不自洽，内容层顺着宽的那一侧走了。

**违反**：计划书 §08、§17（策略差异）；`12_simulation_contract.md §8.1` 与
`11_data_contract.md §5.13` 的白名单不自洽。

**最小修复**：
(a) 把 `state.group.trust_ppm` 从事件可写白名单里**移除**，事件只能写 `expectation_ppm` / `support_ppm`
（信任仍由 §8.1 的闭集合驱动）；若不移除，则应改写 §8.1 的措辞，二选一，不能两边都留着；
(b) 至少把 2 个模板改成由成功状态触发（例如「新增供电投运后制造业扩产 ⇒ `bloc.business` 立场上升、
`bloc.labor_public` 因工时上升而 `org_power` 上升」），使事件层能区分不同的成功路线。

---

### P2-2 `V-PD-09` 对枚举型 `player_params` 不成立：P04 / P08 / P11 的 `funding_source` 无 `valid_range`

`V-PD-09` 要求每个 `player_params` 项都有 `valid_range` 与 `default` 且 `default ∈ valid_range`，
但 `valid_range` 是 `[min, max]` 整数对，对 `funding_source` 这种 `enum` 无意义。
契约自己的 P04 示例就是这么写的（只有 `values` + `default`），内容层照抄，于是 3 个文件必然违反 V-PD-09。
P08 已登记为其自造的 OQ-254。

另外 `player_params.type` 在内容层出现了 9 种（`ppm` / `int` / `enum` / `q` / `int_q` / `int_enum` /
`mask` / `uu` / `quarters`），其中 `q` 与 `int_q`、`enum` 与 `int_enum`、`q` 与 `quarters` 是同义异名。

**修复**：把 `V-PD-09` 改成「枚举用 `values`，数值用 `valid_range`」；
把 `type` 收敛成封闭枚举 `{ppm, int, uu, q, mask, enum}` 并加校验。

---

### P2-3 `state.bloc.stance_ppm` 的 scope 用了契约没定义的复合语法

E05/E06/E07/E08 的效果 scope 写作 `"bloc.labor_public.policy.P05"`、`"bloc.business.policy.P11"`。
`stance_ppm` 在 `politics.json` 里确实是 (集团 × 政策) 的二维映射，需要复合定位，
但 `11_data_contract.md §5.13` 的 `scope` 示例只有 `region.haijia` 这类单实体 ID，
§4 的 `id_pattern` 也没有为复合 scope 留位置。

**修复**：在 §5.13 增加 `scope_kind` 字段（`region` / `cell` / `group` / `bloc` / `bloc_policy` / `national`），
并为 `bloc_policy` 给出正则；或把效果拆成 `scope: "bloc.business"` + `policy_ref: "policy.P11"` 两个字段。

---

### P2-4 `rationing_priority` 是「内容配置」，但没有任何内容文件配置它

`12_simulation_contract.md §5.6` 写「第一级 —— 公开优先级（**内容配置 `rationing_priority`**，默认 0..4 的顺序）」，
`17_api_skeleton.md:2257` 也写「`rationing_priority` 来自内容配置」。
全内容包检索：**零命中**。`gov.ration_mode`（§5.6 与 S-13 裁定提到的全比例切换开关）
在 `10_variable_dictionary.md` 里也没有字段。

OQ-238 把配给顺序定死为「居民 > 公共服务 > 政府采购 > 企业投入与补库 > 出口」，
这是一条**对玩家可见、且会被质疑**的设计（「为什么国内缺货还在出口」），
它必须有数据归宿才能在报告里被解释。

**修复**：在 `scenario.json` 增加 `rationing_priority: int[5]` 与 `ration_mode: 0|1`，
加校验「必须是 0..4 的全排列」（与 `payment_priority` 同构）。

---

### P2-5 `credit_used_uu` 初值 0 使开局 16 U 外债不占额度，外部约束被悄悄放松

`scenario.json` `_note_world_init` 自承：「`credit_limit_uu` 取 12 000 000 μU，
低于开局外债余额 16 000 000 μU，用意是外部融资在开局即为稀缺资源；
注意 `state.world.credit_used_uu` 按 10 号文件初值为 0，即**存量外债不占用额度**」。
`world.json` 又补了一条：还本时**也不释放**额度。

两条叠加的净效果是：开局可新增外债 12 U，与历史 16 U 并存，外债总承受能力实为 28 U——
比「12 U 稀缺」的叙述宽了一倍以上。这不是错账（额度是表外 memo），
但它让「外部融资在开局即为稀缺资源」这句设计意图不成立。

**修复**：明确裁定一条并写进 13 号文件：要么 `credit_used_uu` 初值 = 开局外债余额（16 000 000）
并相应调高 `credit_limit_uu`，要么保留 0 但把注释里的「稀缺」改成准确的描述。
`world.json` 已把它登记为其自造的 OQ-252，收编时一并处理。

---

### P2-6 `region.beiyuan` ↔ `region.haijia` 的物流与迁移成本填了值但不相邻

`regions.json` 里北原与海岬互不在对方 `adjacency` 里（其 `_note_regions` 明确说明），
但 `logistics_cost_ppm` 填了 250 000、`migration_cost_uu` 填了 4。
注释说「填高值以免将来打开邻接时被当成便宜通道」——动机合理，
但 `V-REG-02` 只校验「对其它 3 区完备、自身为 0」，不校验「非邻接对是否应当为哨兵值」。
于是这两个数字是**不可达代码路径上的数据**：没有测试会走到它们，也没有断言保证它们保持高值。

**修复**：`V-REG-02` 增加一条：非邻接地区对的 `logistics_cost_ppm` 必须等于约定哨兵值
（建议 `-1` 或 `SENTINEL`），加载期展开时用它触发「不可直达」而不是「很贵」。

---

### P2-7 `spoilage`、`season_factor`、`S03.target_weights`、`port_capacity`、`admin_capacity`：
### 五处「字段存在、无人读取」的共同模式

把前文各条汇总，内容层目前至少有五个字段处于「写得出、校验得过、没人读」的状态：

| 字段 | 校验通过靠 | 谁也不读 |
|---|---|---|
| `spoilage_ppm` | V-IO-04（≥ 0） | 值为 0，§5.8 恒等变换 |
| `season_factor_ppm` | INV-042（Σ == 1e6） | 12 号文件零命中 |
| `S03.target_weights_ppm` | V-SH-03（Σ == 1e6） | 01.7 的 S03 公式不按部门加权 |
| `port_capacity_uqs_per_q` | 无 | 无结算步读 |
| `admin_capacity_ppm` | 无 | 无结算步读 |

这是一个**模式**，不是五次巧合：现有校验体系只检查「字段格式对不对」，
不检查「字段有没有消费者」。计划书 §03 的范围闸门第一问就是
「**它解决哪个已观察到的玩法问题？**」——一个没有消费者的字段答不出这一问。

**修复（工具级，建议进 G0 门槛）**：新增 `tools/check_field_consumers.gd`：
对 `10_variable_dictionary.md` 里每个 `state.*` / `content.*` 字段，
在 `12_simulation_contract.md` 中检索「作为读取方出现」的位置，零命中即 CI 警告，
并要求在 13 号文件里有一条显式登记才允许豁免。这条工具比再多写十个内容文件更值钱。

---

### P2-8 引用契约「示例值」当事实来源

已确认两处，建议全量扫描：

- `P03` 的 `param.p03_provision_uu_per_q` `source_ref` 引用
  「`11_data_contract.md §5.9` `annual_plan.expenditure_lines_uu.statutory_transfers = 4000000`」，
  而 §5.9 那一段是**占位示例**（该段自己写着「由 T03 剧本任务最终确定」），本剧本实际值是 3 600 000。
- `io_table.json` 的 `interface_requirements` 指出 `§5.4` 的 `delivery_capacity_uqs` 占位值
  `[0, 4000000, 2000000, 0]` 与平衡贸易账户冲突——这次是内容层正确地**拒绝**了示例值。

**修复**：在 `11_data_contract.md` 的所有示例块顶部统一加 `"_example_only": 1` 标记，
并加一条内容侧静态检查：`source_ref` 指向带该标记的段落即 `E_EXAMPLE_AS_SOURCE`。

---

### P2-9 `io_table` 的 `labor_coeff` 不做单格覆盖，与「地区差异」的剧本要求之间需要一条显式论证

`io_table.json` `_note_labor_coeff_persons_per_qs`：「首版只给 `"*"` 默认值，不做单格覆盖……
这是更保守的取法，避免凭空发明 16 组地区专属技术系数」。
这个取舍本身正确（§14「不能从相关性直接推出」）。
但它把**全部**地区差异压到了 `cells_init` 的资本/产能/在岗人数上，
而 `cells_init.json` 还不存在（P0-1）。也就是说：计划书 §05 的四条地区故事
（北原灌溉、中州住房、海岬电网、西岭环境）目前**只有三条**有落点
（灌溉在 `regions.json` 但无人读，住房在 `regions.json` 且被读，电网在 `regions.json` 且被读，
环境在 `regions.json` 但按 OQ-226 只记录不反馈），**第四条（西岭产业单一）完全没有落点**。

**修复**：写 `cells_init.json` 时必须逐条对照 §05 的四行「开局主要约束」，
在返回值里给出「这条故事落在哪个字段、由哪一步读取、由哪个测试断言」的三元组；
做不到的那一条，登记为待决问题，而不是写进文案。

---

### P2-10 `registry.json` 的仪表盘措辞会被误读为「§14 已落实」

`14_parameter_registry.md` §0 写着「162 张身份证中有 162 张（100%）没有任何外部证据支撑……
**这不是缺陷，是首版的真实状态**」。这句话是对的、也很好。
但同一页同时显示「**V-PC-04 闸门 ✅ 通过**」，而真正决定模拟行为的 72 个参数**一张卡都没有**
（`PR-019` 只被列为 WARN）。一个读者看完这页会得出「参数纪律已经建立」的结论，
这与实际状态相反。

**修复**：把 `PR-019`（契约最小集覆盖）从 WARN 升为 **ERROR**，
并把仪表盘首行改成「契约最小集覆盖：0 / 72」——**先显示缺口，再显示已有**。

---

### P2-11 范围闸门（计划书 §03）复查：未发现越界

按要求逐项核对「明确排除」的五项：

| 排除项 | 内容层是否越界 | 依据 |
|---|---|---|
| 多人联机 | 否 | 无任何网络/账号字段 |
| 战术战争 | 否 | 无军事实体 |
| 逐人模拟 | 否 | 最细粒度是 36 群组 + 16 cell；P03 的受益队列是「12 组 × 8 槽」的人数计数，不是个人 |
| 全球经济 | 否 | `agent.row` 是单一外部主体，固定汇率，无伙伴关系 |
| 生成式 AI 裁决 | 否 | 全部文案走 `report_template_id` / `ui_text_keys` 模板 |

另：`world.json` 的 `tightening_price_rule` 与 `default_penalty_rule_zh` 属于**补齐**契约留空处
（12 号 02.6 的「外部收紧冲击加成」确实无名无值），不是新增机制，不算越界；
但它们目前只住在一个不被加载的文件里（P0-1），等于既没越界也没生效。

---

## 4 建议的处置顺序

1. **先修加载**：P0-1（文件名与缺失文件）、P0-8（schema v2）、P0-9（72 张核心参数卡 + `rng_salt`）。
   在这三条完成前，后面任何数值工作都无法被验证。
2. **再修基年**：P0-2、P0-3、P0-4、P0-5、P0-6 必须**一次性联立求解**，
   由 `tools/solve_base_year.gd`（OQ-203）承担，不要逐项手调。
   特别提请注意 P0-4：它是单位制问题，不解决它，基年在整数上无解。
3. **再修反馈链**：P1-1 的三项空政策（P07/P08/P12）——
   计划书 §03 说「少一条关键反馈链不可以」，现在少了三条。
4. **再收编编号与纪律**：P1-4（OQ 收编）、P1-5（表达式清理）、P2-7（消费者检查工具）。
5. 其余 P2 条目在 G1 结束前清掉即可。

---

## 5 审计自身的边界

- 本审计**没有**运行任何 Godot 代码：`sim/`、`systems/` 下的实现未纳入范围，
  因此「某字段无人读取」的判定依据是 `12_simulation_contract.md` 的文本，不是实现。
  若实现中已有读取而契约漏写，属于另一类缺陷（实现超出契约），同样需要修。
- 三法对账、利息逐批次复核、失业率反算、现金求和、工资格点求解均由本次审计独立复算，
  数值可在 `content/` 上逐条复现。
- 本审计**没有**评价内容的叙事质量与平衡性；计划书 §14 明确这些要由原型验证决定，不由审计决定。
